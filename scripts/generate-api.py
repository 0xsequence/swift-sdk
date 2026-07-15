#!/usr/bin/env python3
"""Render API.md from an OMSWallet Swift symbol graph."""

from __future__ import annotations

import argparse
import json
import re
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional
from urllib.parse import unquote, urlparse


EXPECTED_GROUPS = [
    "OMSWallet",
    "Authentication and sessions",
    "Transactions and signing",
    "Indexer",
    "Networks, types, and errors",
]
NOMINAL_KINDS = {
    "swift.actor": "actor",
    "swift.class": "class",
    "swift.enum": "enum",
    "swift.protocol": "protocol",
    "swift.struct": "struct",
}


class GenerationError(Exception):
    pass


@dataclass(frozen=True)
class PublicSymbol:
    identifier: str
    kind: str
    path: str
    declaration: str
    conformances: tuple[str, ...]
    summary: Optional[str]
    parent_identifier: Optional[str]
    sort_key: tuple[str, int, int, str, str]


@dataclass(frozen=True)
class PresentationEntry:
    anchor: PublicSymbol
    label: str
    symbols: tuple[PublicSymbol, ...]


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise GenerationError(f"Could not read {path}: {error}") from error


def source_summary(symbol: dict[str, Any]) -> Optional[str]:
    doc_comment = symbol.get("docComment")
    if not isinstance(doc_comment, dict) or doc_comment.get("module") != "OMSWallet":
        return None

    lines = doc_comment.get("lines")
    if not isinstance(lines, list):
        return None

    summary_lines: list[str] = []
    for line in lines:
        if not isinstance(line, dict) or not isinstance(line.get("text"), str):
            raise GenerationError(
                f"Malformed doc comment for {symbol.get('identifier', {}).get('precise', '<unknown>')}"
            )
        text = line["text"]
        if not text.strip():
            if summary_lines:
                break
            continue
        summary_lines.append(text)

    return "\n".join(summary_lines) if summary_lines else None


def source_path(uri: str, symbol_path: str) -> Path:
    parsed = urlparse(uri)
    if (
        parsed.scheme != "file"
        or parsed.netloc not in ("", "localhost")
        or parsed.params
        or parsed.query
        or parsed.fragment
    ):
        raise GenerationError(f"Public symbol has an unsupported source URI: {symbol_path}")

    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        raise GenerationError(f"Public symbol has a non-absolute source URI: {symbol_path}")
    parts = path.parts
    for index in range(len(parts) - 2):
        if parts[index : index + 3] == ("Sources", "OMSWallet", "Generated"):
            raise GenerationError(f"Generated source exposed a public symbol: {symbol_path}")
    return path


def read_source(path: Path, cache: dict[Path, str]) -> str:
    if path not in cache:
        try:
            cache[path] = path.read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise GenerationError(f"Could not read Swift source {path}: {error}") from error
    return cache[path]


def source_offset(
    source: str, line: int, character: int, symbol_path: str
) -> tuple[int, int]:
    lines = source.splitlines(keepends=True)
    if line < 0 or line >= len(lines) or character < 0:
        raise GenerationError(f"Public symbol has an out-of-range source location: {symbol_path}")

    source_line = lines[line]
    line_content = source_line.rstrip("\r\n")
    encoded_line = line_content.encode("utf-8")
    if character > len(encoded_line):
        raise GenerationError(f"Public symbol has an out-of-range source location: {symbol_path}")
    try:
        character_offset = len(encoded_line[:character].decode("utf-8"))
    except UnicodeDecodeError as error:
        raise GenerationError(
            f"Public symbol source location splits a UTF-8 scalar: {symbol_path}"
        ) from error

    line_start = sum(len(value) for value in lines[:line])
    return line_start, line_start + character_offset


def dedent_declaration(source: str, symbol_path: str) -> str:
    declaration = textwrap.dedent(source.rstrip()).strip("\n")
    if not declaration:
        raise GenerationError(f"Recovered an empty source declaration: {symbol_path}")
    return declaration


def nominal_declaration(
    source: str,
    line_start: int,
    location_offset: int,
    name: str,
    keyword: str,
    symbol_path: str,
) -> str:
    source_line_end = source.find("\n", line_start)
    if source_line_end == -1:
        source_line_end = len(source)
    line = source[line_start:source_line_end].rstrip("\r")
    line_location = location_offset - line_start
    if line[line_location : line_location + len(name)] != name:
        raise GenerationError(
            f"Source location does not point to {name!r}: {symbol_path}"
        )

    declaration_start = line_start + len(line) - len(line.lstrip(" \t"))
    prefix = source[declaration_start:location_offset]
    modifier = r"[A-Za-z_][A-Za-z0-9_]*"
    if re.fullmatch(rf"public(?:[ \t]+{modifier})*[ \t]+{keyword}[ \t]+", prefix) is None:
        raise GenerationError(
            f"Unsupported public {keyword} declaration layout: {symbol_path}"
        )

    paren_depth = 0
    bracket_depth = 0
    index = location_offset + len(name)
    while index < len(source):
        if source.startswith("//", index) or source.startswith("/*", index):
            raise GenerationError(
                f"Comments in public nominal headers are unsupported: {symbol_path}"
            )
        character = source[index]
        if character == '"':
            raise GenerationError(
                f"String literals in public nominal headers are unsupported: {symbol_path}"
            )
        if character == "(":
            paren_depth += 1
        elif character == ")":
            paren_depth -= 1
        elif character == "[":
            bracket_depth += 1
        elif character == "]":
            bracket_depth -= 1
        elif character == "{" and paren_depth == 0 and bracket_depth == 0:
            return dedent_declaration(source[line_start:index], symbol_path)
        elif character == "}" or paren_depth < 0 or bracket_depth < 0:
            raise GenerationError(f"Malformed public nominal header: {symbol_path}")
        index += 1

    raise GenerationError(f"Public nominal declaration has no body: {symbol_path}")


def swift_string_end(source: str, start: int, symbol_path: str) -> Optional[int]:
    hashes = 0
    index = start
    while index < len(source) and source[index] == "#":
        hashes += 1
        index += 1
    if index >= len(source) or source[index] != '"':
        return None

    quote_count = 3 if source.startswith('"""', index) else 1
    closing = '"' * quote_count + "#" * hashes
    index += quote_count
    while index < len(source):
        if source.startswith(closing, index):
            return index + len(closing)
        if quote_count == 1 and source[index] in "\r\n":
            break
        if hashes == 0 and source[index] == "\\":
            index += 2
        else:
            index += 1
    raise GenerationError(f"Unterminated string literal in enum case: {symbol_path}")


def enum_case_declaration(
    source: str,
    line_start: int,
    location_offset: int,
    name: str,
    symbol_path: str,
) -> str:
    source_line_end = source.find("\n", line_start)
    if source_line_end == -1:
        source_line_end = len(source)
    line = source[line_start:source_line_end].rstrip("\r")
    line_location = location_offset - line_start
    if line[line_location : line_location + len(name)] != name:
        raise GenerationError(
            f"Source location does not point to {name!r}: {symbol_path}"
        )

    declaration_start = line_start + len(line) - len(line.lstrip(" \t"))
    prefix = source[declaration_start:location_offset]
    if re.fullmatch(r"(?:indirect[ \t]+)?case[ \t]+", prefix) is None:
        raise GenerationError(f"Unsupported enum case declaration layout: {symbol_path}")

    paren_depth = 0
    bracket_depth = 0
    index = declaration_start
    while index < len(source):
        string_end = swift_string_end(source, index, symbol_path)
        if string_end is not None:
            index = string_end
            continue
        if source.startswith("/*", index):
            raise GenerationError(f"Block comments in enum cases are unsupported: {symbol_path}")
        if source.startswith("//", index):
            if paren_depth == 0 and bracket_depth == 0:
                return dedent_declaration(source[line_start:index], symbol_path)
            newline = source.find("\n", index)
            if newline == -1:
                raise GenerationError(f"Unterminated multiline enum case: {symbol_path}")
            index = newline
            continue

        character = source[index]
        if character == "(":
            paren_depth += 1
        elif character == ")":
            paren_depth -= 1
        elif character == "[":
            bracket_depth += 1
        elif character == "]":
            bracket_depth -= 1
        elif character == "," and paren_depth == 0 and bracket_depth == 0:
            raise GenerationError(f"Multiple enum cases per declaration are unsupported: {symbol_path}")
        elif character == ";" and paren_depth == 0 and bracket_depth == 0:
            return dedent_declaration(source[line_start:index], symbol_path)
        elif character in "\r\n" and paren_depth == 0 and bracket_depth == 0:
            return dedent_declaration(source[line_start:index], symbol_path)
        elif character in "{}" or paren_depth < 0 or bracket_depth < 0:
            raise GenerationError(f"Malformed enum case declaration: {symbol_path}")
        index += 1

    if paren_depth != 0 or bracket_depth != 0:
        raise GenerationError(f"Unterminated multiline enum case: {symbol_path}")
    return dedent_declaration(source[line_start:index], symbol_path)


def source_declaration(
    kind: str,
    path_components: list[str],
    uri: str,
    line: int,
    character: int,
    cache: dict[Path, str],
) -> str:
    symbol_path = ".".join(path_components)
    path = source_path(uri, symbol_path)
    source = read_source(path, cache)
    line_start, location_offset = source_offset(source, line, character, symbol_path)
    name = path_components[-1].split("(", 1)[0]

    if kind in NOMINAL_KINDS:
        return nominal_declaration(
            source,
            line_start,
            location_offset,
            name,
            NOMINAL_KINDS[kind],
            symbol_path,
        )
    if kind == "swift.enum.case":
        return enum_case_declaration(
            source, line_start, location_offset, name, symbol_path
        )
    raise GenerationError(f"Unsupported source-backed symbol kind: {kind}")


def restricted_setter_access(
    kind: str,
    path_components: list[str],
    uri: str,
    line: int,
    character: int,
    cache: dict[Path, str],
) -> Optional[str]:
    if kind not in {"swift.property", "swift.type.property"} or not uri:
        return None

    symbol_path = ".".join(path_components)
    path = source_path(uri, symbol_path)
    source = read_source(path, cache)
    line_start, location_offset = source_offset(source, line, character, symbol_path)
    prefix = source[line_start:location_offset]
    match = re.search(
        r"\bpublic[ \t]+((?:internal|private|fileprivate|package)\(set\))"
        r"[ \t]+[^\r\n]*\bvar[ \t]+$",
        prefix,
    )
    return match.group(1) if match is not None else None


def public_declaration(declaration: str, setter_access: Optional[str] = None) -> str:
    access = "public" if setter_access is None else f"public {setter_access}"
    index = 0
    while index < len(declaration) and declaration[index] == "@":
        index += 1
        while index < len(declaration) and (
            declaration[index].isalnum() or declaration[index] in "_."
        ):
            index += 1
        if index < len(declaration) and declaration[index] == "(":
            depth = 1
            index += 1
            while index < len(declaration) and depth > 0:
                if declaration[index] == "(":
                    depth += 1
                elif declaration[index] == ")":
                    depth -= 1
                index += 1
            if depth != 0:
                raise GenerationError("Public declaration has an unterminated attribute")
        while index < len(declaration) and declaration[index].isspace():
            index += 1
    return f"{declaration[:index]}{access} {declaration[index:]}"


def public_symbols(graph: dict[str, Any]) -> list[PublicSymbol]:
    module = graph.get("module")
    if not isinstance(module, dict) or module.get("name") != "OMSWallet":
        raise GenerationError("Expected an OMSWallet symbol graph")

    raw_symbols = graph.get("symbols")
    relationships = graph.get("relationships", [])
    if not isinstance(raw_symbols, list) or not isinstance(relationships, list):
        raise GenerationError("Symbol graph has no symbols or relationships array")

    kind_by_identifier = {
        symbol.get("identifier", {}).get("precise"): symbol.get("kind", {}).get("identifier")
        for symbol in raw_symbols
        if isinstance(symbol, dict)
        and isinstance(symbol.get("identifier"), dict)
        and isinstance(symbol.get("kind"), dict)
    }

    public_identifiers = {
        symbol.get("identifier", {}).get("precise")
        for symbol in raw_symbols
        if isinstance(symbol, dict) and symbol.get("accessLevel") == "public"
    }
    readable_targets: dict[str, str] = {}
    for raw_symbol in raw_symbols:
        if not isinstance(raw_symbol, dict):
            continue
        identifier = raw_symbol.get("identifier", {}).get("precise")
        path_components = raw_symbol.get("pathComponents")
        if (
            isinstance(identifier, str)
            and identifier
            and isinstance(path_components, list)
            and path_components
            and all(isinstance(component, str) for component in path_components)
        ):
            readable_targets[identifier] = ".".join(path_components)

    parent_by_identifier: dict[str, str] = {}
    conformances_by_identifier: dict[str, set[str]] = {}
    for relationship in relationships:
        if not isinstance(relationship, dict):
            raise GenerationError("Malformed symbol relationship")
        kind = relationship.get("kind")
        if kind == "conformsTo":
            source = relationship.get("source")
            if source not in public_identifiers:
                continue
            if "swiftConstraints" in relationship:
                raise GenerationError(
                    f"Conditional public conformance is unsupported: {source}"
                )

            target_fallback = relationship.get("targetFallback")
            if target_fallback is None:
                target_identifier = relationship.get("target")
                target = (
                    readable_targets.get(target_identifier)
                    if isinstance(target_identifier, str)
                    else None
                )
            else:
                target = target_fallback
            if not isinstance(target, str) or not target:
                raise GenerationError(f"Public conformance has no readable target: {source}")
            if target == "Swift.SendableMetatype":
                continue
            conformances_by_identifier.setdefault(source, set()).add(target)
            continue
        if kind != "memberOf":
            continue
        source = relationship.get("source")
        target = relationship.get("target")
        if not isinstance(source, str) or not isinstance(target, str):
            raise GenerationError("Malformed memberOf relationship")
        existing = parent_by_identifier.get(source)
        if existing is not None and existing != target:
            raise GenerationError(f"Symbol has multiple memberOf parents: {source}")
        parent_by_identifier[source] = target

    symbols: list[PublicSymbol] = []
    identifiers: set[str] = set()
    source_cache: dict[Path, str] = {}
    for raw_symbol in raw_symbols:
        if not isinstance(raw_symbol, dict) or raw_symbol.get("accessLevel") != "public":
            continue

        identifier = raw_symbol.get("identifier", {}).get("precise")
        kind_value = raw_symbol.get("kind")
        kind = kind_value.get("identifier") if isinstance(kind_value, dict) else None
        path_components = raw_symbol.get("pathComponents")
        fragments = raw_symbol.get("declarationFragments")
        if not isinstance(identifier, str) or not identifier:
            raise GenerationError("Public symbol has no precise identifier")
        if not isinstance(kind, str) or not kind:
            raise GenerationError(f"Public symbol {identifier} has no valid kind")
        if identifier in identifiers:
            raise GenerationError(f"Duplicate public symbol identifier: {identifier}")
        if (
            not isinstance(path_components, list)
            or not path_components
            or not all(isinstance(component, str) for component in path_components)
        ):
            raise GenerationError(f"Public symbol {identifier} has no valid path")
        if not isinstance(fragments, list) or not fragments:
            raise GenerationError(f"Public symbol {identifier} has no declaration fragments")

        spellings: list[str] = []
        for fragment in fragments:
            if not isinstance(fragment, dict) or not isinstance(fragment.get("spelling"), str):
                raise GenerationError(f"Public symbol {identifier} has malformed declaration fragments")
            spellings.append(fragment["spelling"])

        location = raw_symbol.get("location")
        if location is None:
            uri = ""
            line = -1
            character = -1
        elif isinstance(location, dict):
            position = location.get("position")
            uri = location.get("uri")
            line = position.get("line") if isinstance(position, dict) else None
            character = position.get("character") if isinstance(position, dict) else None
            if (
                not isinstance(uri, str)
                or not uri
                or not isinstance(line, int)
                or line < 0
                or not isinstance(character, int)
                or character < 0
            ):
                raise GenerationError(f"Public symbol {identifier} has malformed source location")
            source_path(uri, ".".join(path_components))
        else:
            raise GenerationError(f"Public symbol {identifier} has malformed source location")

        path = ".".join(path_components)
        declaration = "".join(spellings)
        if kind in NOMINAL_KINDS or kind == "swift.enum.case":
            if not uri:
                raise GenerationError(f"Source-backed public symbol has no location: {path}")
            declaration = source_declaration(
                kind, path_components, uri, line, character, source_cache
            )
        elif kind_by_identifier.get(parent_by_identifier.get(identifier)) != "swift.protocol":
            declaration = public_declaration(
                declaration,
                restricted_setter_access(
                    kind, path_components, uri, line, character, source_cache
                ),
            )
        identifiers.add(identifier)
        symbols.append(
            PublicSymbol(
                identifier=identifier,
                kind=kind,
                path=path,
                declaration=declaration,
                conformances=tuple(sorted(conformances_by_identifier.get(identifier, set()))),
                summary=source_summary(raw_symbol),
                parent_identifier=parent_by_identifier.get(identifier),
                sort_key=(uri, line, character, path, identifier),
            )
        )

    if not symbols:
        raise GenerationError("OMSWallet symbol graph has no public symbols")

    public_identifiers = {symbol.identifier for symbol in symbols}
    for symbol in symbols:
        if symbol.parent_identifier is not None and symbol.parent_identifier not in public_identifiers:
            raise GenerationError(
                f"Public symbol has a non-public or missing parent: {symbol.path}"
            )
    return symbols


def ordered_symbols(
    symbols: list[PublicSymbol], config: Any
) -> list[tuple[str, list[PresentationEntry]]]:
    if not isinstance(config, list) or not config:
        raise GenerationError("Presentation config must be a non-empty array of groups")
    labels = [group.get("label") if isinstance(group, dict) else None for group in config]
    if labels != EXPECTED_GROUPS:
        raise GenerationError(
            "Presentation groups must be exactly: " + "; ".join(EXPECTED_GROUPS)
        )

    by_identifier = {symbol.identifier: symbol for symbol in symbols}
    by_path: dict[str, list[PublicSymbol]] = {}
    for symbol in symbols:
        by_path.setdefault(symbol.path, []).append(symbol)

    configured: dict[str, tuple[int, int, str]] = {}
    group_entries: list[list[tuple[PublicSymbol, str]]] = []
    for group_index, group in enumerate(config):
        if not isinstance(group, dict) or set(group) != {"label", "symbols"}:
            raise GenerationError(
                f"Group {group_index + 1} must contain only label and symbols"
            )
        label = group["label"]
        entries = group["symbols"]
        if not isinstance(entries, list):
            raise GenerationError(f"Group {label!r} has no symbol entries")

        resolved: list[tuple[PublicSymbol, str]] = []
        for entry_index, entry in enumerate(entries):
            if (
                not isinstance(entry, dict)
                or not set(entry).issubset({"path", "id", "label"})
                or "path" not in entry
            ):
                raise GenerationError(
                    f"Entry {entry_index + 1} in {label!r} may contain only path, id, and label"
                )
            path = entry["path"]
            identifier = entry.get("id")
            display_label = entry.get("label", path)
            if not isinstance(path, str) or not path:
                raise GenerationError(f"Entry {entry_index + 1} in {label!r} has no path")
            if identifier is not None and (not isinstance(identifier, str) or not identifier):
                raise GenerationError(f"Configured ID for {path} must be a non-empty string")
            if not isinstance(display_label, str) or not display_label:
                raise GenerationError(f"Configured label for {path} must be a non-empty string")

            candidates = by_path.get(path, [])
            if identifier is not None:
                candidates = [symbol for symbol in candidates if symbol.identifier == identifier]
            if not candidates:
                suffix = f" with ID {identifier}" if identifier else ""
                raise GenerationError(f"Configured symbol is missing: {path}{suffix}")
            if len(candidates) > 1:
                ids = ", ".join(sorted(symbol.identifier for symbol in candidates))
                raise GenerationError(
                    f"Configured path is ambiguous and requires an ID: {path} ({ids})"
                )

            symbol = candidates[0]
            if symbol.identifier in configured:
                raise GenerationError(f"Configured symbol is assigned more than once: {path}")
            configured[symbol.identifier] = (group_index, entry_index, display_label)
            resolved.append((symbol, display_label))
        group_entries.append(resolved)

    split_roots: set[str] = set()
    for symbol_id in configured:
        current = by_identifier[symbol_id].parent_identifier
        while current is not None:
            if current in configured and by_identifier[current].parent_identifier is None:
                split_roots.add(current)
                break
            current = by_identifier[current].parent_identifier

    owned: dict[str, list[PublicSymbol]] = {symbol_id: [] for symbol_id in configured}
    unassigned: list[PublicSymbol] = []
    for symbol in symbols:
        if symbol.identifier in configured:
            owned[symbol.identifier].append(symbol)
            continue

        current = symbol.parent_identifier
        owner: Optional[str] = None
        while current is not None:
            if current in configured:
                owner = current
                break
            current = by_identifier[current].parent_identifier

        if owner is None or owner in split_roots:
            unassigned.append(symbol)
        else:
            owned[owner].append(symbol)

    if unassigned:
        details = "\n".join(
            f"  {symbol.path}\t{symbol.identifier}"
            for symbol in sorted(unassigned, key=lambda item: (item.path, item.identifier))
        )
        raise GenerationError(f"Public symbols are unassigned:\n{details}")

    groups: list[tuple[str, list[PresentationEntry]]] = []
    if len(config) != len(group_entries):
        raise GenerationError("Presentation group resolution is incomplete")
    for group, resolved in zip(config, group_entries):
        entries = [
            PresentationEntry(
                anchor=anchor,
                label=display_label,
                symbols=tuple(owned[anchor.identifier]),
            )
            for anchor, display_label in resolved
        ]
        groups.append((group["label"], entries))
    return groups


def compound_declaration(entry: PresentationEntry) -> str:
    by_identifier = {symbol.identifier: symbol for symbol in entry.symbols}
    children: dict[str, list[PublicSymbol]] = {
        symbol.identifier: [] for symbol in entry.symbols
    }
    for symbol in entry.symbols:
        if symbol.identifier == entry.anchor.identifier:
            continue
        parent = symbol.parent_identifier
        if parent not in by_identifier:
            raise GenerationError(
                f"Owned symbol is detached from configured parent: {symbol.path}"
            )
        children[parent].append(symbol)
    for parent_identifier, siblings in children.items():
        parent_uri = by_identifier[parent_identifier].sort_key[0]

        def sibling_key(symbol: PublicSymbol) -> tuple[int, str, int, int, str, str]:
            uri, line, character, path, identifier = symbol.sort_key
            if uri and uri == parent_uri:
                source_tier = 0
            elif uri:
                source_tier = 1
            else:
                source_tier = 2
            return (source_tier, uri, line, character, path, identifier)

        siblings.sort(key=sibling_key)

    def render_symbol(symbol: PublicSymbol, depth: int, is_anchor: bool) -> list[str]:
        indent = "    " * depth
        lines: list[str] = []
        if not is_anchor and symbol.summary is not None:
            lines.extend(f"{indent}/// {line}" for line in symbol.summary.splitlines())

        declaration = symbol.declaration
        if symbol.conformances and symbol.kind not in NOMINAL_KINDS:
            names = [conformance.rsplit(".", 1)[-1] for conformance in symbol.conformances]
            declaration += ": " + ", ".join(names)
        declaration_lines = declaration.splitlines() or [""]
        lines.extend(f"{indent}{line}" for line in declaration_lines)
        symbol_children = children[symbol.identifier]
        if symbol_children:
            lines[-1] += " {"
            for child in symbol_children:
                lines.extend(render_symbol(child, depth + 1, False))
            lines.append(f"{indent}}}")
        return lines

    return "\n".join(render_symbol(entry.anchor, 0, True))


def render(groups: list[tuple[str, list[PresentationEntry]]]) -> str:
    lines = [
        "<!-- Generated by scripts/generate-api.sh. Do not edit directly. -->",
        "",
        "# Swift API reference",
    ]
    for group_label, entries in groups:
        lines.extend(["", f"## {group_label}"])
        for entry in entries:
            lines.extend(
                [
                    "",
                    f"### `{entry.label}`",
                    "",
                    "```swift",
                    compound_declaration(entry),
                    "```",
                ]
            )
            if entry.anchor.summary is not None:
                lines.extend(["", entry.anchor.summary])
    return "\n".join(lines) + "\n"


def generate(symbol_graph_path: Path, config_path: Path) -> str:
    graph = load_json(symbol_graph_path)
    if not isinstance(graph, dict):
        raise GenerationError("Symbol graph root must be an object")
    return render(ordered_symbols(public_symbols(graph), load_json(config_path)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbol-graph", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    try:
        output = generate(args.symbol_graph, args.config)
        if args.check:
            try:
                current = args.output.read_text(encoding="utf-8")
            except OSError as error:
                raise GenerationError(f"Could not read {args.output}: {error}") from error
            if current != output:
                print(
                    f"{args.output} is out of date. Regenerate it with scripts/generate-api.sh.",
                    file=sys.stderr,
                )
                return 1
        else:
            args.output.write_text(output, encoding="utf-8")
    except GenerationError as error:
        print(f"API generation failed: {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
