# AGENTS.md

Single source of truth for agents working in this repo. `CLAUDE.md` imports this file via
`@AGENTS.md`, so Claude Code, Codex, and any other agent that reads `AGENTS.md` share the same
instructions.

---

## Working Principles

- State assumptions when ambiguity affects implementation, public API, security, or release behavior.
- Keep changes surgical and traceable to the request. Avoid speculative abstractions, broad refactors, and formatting churn.
- Preserve user work in the tree and match the local style of the files you touch.
- Define success criteria for non-trivial work and choose verification proportional to the risk.

---

## Third-Party Library Docs

For non-trivial or version-sensitive third-party library questions, prefer context7 or official
documentation over training-data recall. If context7 is unavailable, use official docs or local
package sources and note the fallback; do not block ordinary repo work just to install extra
tooling.

---

## Project Overview

This repository is a Swift 6 package for the OMS Wallet. It exposes the `OMSWallet`
module and supports iOS 15+ and macOS 12+. The SDK covers wallet auth, Keychain
request signing and session persistence, OIDC flows, transactions, message and
typed-data signing, signature verification, token balances, and unit formatting.

## Repository Layout

- `Package.swift` defines the Swift package, the `"OMSWallet"` library target, and
  the `"OMSWalletTests"` test target.
- `Sources/OMSWallet/` contains the SDK implementation.
- `Sources/OMSWallet/Clients/` contains `WalletClient` and `IndexerClient`.
- `Sources/OMSWallet/Signer/` contains Keychain/P-256 signing and credential
  session code.
- `Sources/OMSWallet/Models/` contains public model types and auth/session
  state.
- `Sources/OMSWallet/Utils/` contains encoding, hashing, request, time, byte, and
  unit helpers.
- `Sources/OMSWallet/Generated/waas.gen.swift` is generated WebRPC client code.
  Do not edit it by hand unless the user explicitly asks for a generated-code
  patch.
- `Tests/OMSWalletTests/` contains Swift Testing tests using `@Test` and
  `#expect`.
- `Examples/sdk-demo/oms-wallet-demo.xcodeproj` and
  `Examples/sdk-demo/oms-wallet-demo/` contain the SwiftUI demo app.
- `Examples/trails-actions/trails-actions.xcodeproj` and
  `Examples/trails-actions/trails-actions/` contain the Trails Actions demo app.
- `README.md` is the user-facing guide; `API.md` is the detailed API reference.
- `docs/error-contracts.md` is the public error contract matrix and expectation
  source for error behavior changes.

## Common Commands

```sh
swift build
swift test
scripts/verify.sh
scripts/check-public-api-does-not-expose-generated-waas.sh
xcodebuild -list -project Examples/sdk-demo/oms-wallet-demo.xcodeproj
xcodebuild -project Examples/sdk-demo/oms-wallet-demo.xcodeproj -scheme oms-wallet-demo build CODE_SIGNING_ALLOWED=NO
xcodebuild -list -project Examples/trails-actions/trails-actions.xcodeproj
xcodebuild -project Examples/trails-actions/trails-actions.xcodeproj -scheme trails-actions build CODE_SIGNING_ALLOWED=NO
```

For README/API/docs-only edits, use source-backed spot checks plus
`git diff --check`; run Swift or Xcode builds only when the docs claim changed
source behavior, public API shape, or runnable example code.

Run `swift test` for SDK changes. Run
`scripts/check-public-api-does-not-expose-generated-waas.sh` when public API
surfaces may be affected; it verifies the checked-in interface baseline,
external compile probes, and generated-WaaS isolation. For demo app changes,
also build the relevant Xcode project with signing disabled when feasible.

## Testing

See **[TESTING.md](./TESTING.md)** for testing conventions, unit vs. integration boundaries, and
execution commands.

- Use `TESTING.md` as the source of truth for test boundaries and public error
  contract rules.
- Prefer tests through public SDK behavior or stable internal boundaries that
  callers actually exercise.
- Add focused regression tests for auth, signing, session, transaction, indexer,
  unit-formatting, and public error behavior changes.

## Coding Conventions

- Prefer the existing public API style: `async throws` SDK methods, explicit
  public model types, and Foundation-native data handling.
- Preserve platform availability requirements with `@available(macOS 12.0, iOS
  15.0, *)` on public SDK surfaces that need it.
- Keep wallet/session/security changes conservative. The Keychain-backed P-256
  credential is intentionally non-extractable; do not introduce code paths that
  persist private key material in SDK session storage.
- Keep OIDC redirect state separate from completed wallet session state. Invalid
  or unrelated callbacks should not clear pending redirect auth.
- Verification APIs require an explicit `walletAddress`. Public wallet methods
  should validate active `walletId` and credential state before building signed
  requests.
- Avoid floating-point math for token amounts. Use or extend `parseUnits` and
  `formatUnits` for base-unit conversions.
- Prefer `rg --files`, `rg`, `swift build`, and `swift test` from the repository root.
- Commit messages and PR titles follow Conventional Commits.

## CI/CD

CI runs `scripts/verify.sh` on every PR and push to `master` via
`.github/workflows/ci.yml`. It builds and tests the Swift package, checks the
public API, validates the podspec, and builds both demo apps.
Claude review automation is defined in `.github/workflows/claude-review.yml`; it runs once
when a non-Dependabot PR is opened or marked ready for review, and can be
requested later with `@claude review` in a PR comment.

## Documentation

Update `README.md` when user-facing setup or flow examples change. Update
`API.md` when public methods, parameters, models, or behavior change. Keep docs
aligned with the actual Swift names, labels, return types, and the `OMSWallet`
import name. Avoid adding method descriptions in source code.

## Demo App

The demo app should handle OMS Wallet errors and open an error window when that
happens.

## Security and Configuration

- Do not commit secrets, signing keys, provisioning credentials, local build
  settings, or user-specific Xcode state.
- Publishable keys used by SDK examples are public project identifiers, not
  secrets. Concrete sandbox publishable keys may be checked into demo app configs
  when intentionally provided for runnable examples; do not flag or replace them
  solely because they are concrete values.

## Agent Workflow Rules

- Inspect relevant code, tests, docs, package configuration, and example project
  files before editing.
- Keep changes narrowly scoped to the requested behavior.
- Preserve user changes in the working tree; never revert unrelated edits,
  generated assets, or local Xcode/macOS metadata unless explicitly asked.
- Prefer existing package structure, model names, request helpers,
  session/signing abstractions, and test fixtures.
- Update tests and docs when behavior or public API changes.
- Ask before making product, architecture, or security trade-offs that are not
  answered by the request or existing docs.
- Run the relevant verification commands before reporting completion.

## Common Pitfalls

- `waas.gen.swift` is generated; do not edit by hand unless explicitly asked.
- Never persist private key material in session storage — the P-256 credential is intentionally non-extractable.
- Do not use floating-point for token amounts; use `parseUnits`/`formatUnits`.

## Maintenance Matrix

| When this changes… | Also update… |
|---|---|
| Public API methods or models | `API.md`, `README.md` (if user-facing), tests |
| Test commands | `TESTING.md`, `ci.yml`, `AGENTS.md` Common Commands |
| Repository structure | `AGENTS.md` Repository Layout |
| Swift version or platform targets | `Package.swift`, `ci.yml`, `README.md` |
| New third-party dependency added | `Package.swift`, `AGENTS.md` third-party docs guidance |
| Demo app flows change | `README.md`, `Examples/` |
