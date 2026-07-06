# AGENTS.md

Single source of truth for agents working in this repo. `CLAUDE.md` imports this file via
`@AGENTS.md`, so Claude Code, Codex, and any other agent that reads `AGENTS.md` share the same
instructions.

---

## Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. (Adapted from Andrej Karpathy's
[CLAUDE.md](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md).)

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding
**Don't assume. Don't hide confusion. Surface tradeoffs.**
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First
**Minimum code that solves the problem. Nothing speculative.**
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes
**Touch only what you must. Clean up only your own mess.**
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- Remove imports/variables YOUR changes made unused; leave pre-existing dead code unless asked.

The test: every changed line should trace directly to the request.

### 4. Goal-Driven Execution
**Define success criteria. Loop until verified.**
- "Add validation" → "Write tests for invalid inputs, then make them pass."
- "Fix the bug" → "Write a test that reproduces it, then make it pass."

For multi-step tasks, state a brief plan with a verify step for each item.

---

## Third-Party Library Docs

For **any third-party library**, use the **context7** MCP to fetch up-to-date documentation rather
than relying on training data, which lags real library APIs. If the context7 MCP server is not
available, set it up: https://context7.com/install

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

## Common Commands

```sh
swift build
swift test
scripts/check-public-api-does-not-expose-generated-waas.sh
xcodebuild -list -project Examples/sdk-demo/oms-wallet-demo.xcodeproj
xcodebuild -project Examples/sdk-demo/oms-wallet-demo.xcodeproj -scheme oms-wallet-demo build CODE_SIGNING_ALLOWED=NO
xcodebuild -list -project Examples/trails-actions/trails-actions.xcodeproj
xcodebuild -project Examples/trails-actions/trails-actions.xcodeproj -scheme trails-actions build CODE_SIGNING_ALLOWED=NO
```

Run `swift test` for SDK changes. For demo app changes, also build the relevant
Xcode project with signing disabled when feasible.

## Testing

See **[TESTING.md](./TESTING.md)** for testing conventions, unit vs. integration boundaries, and
execution commands.

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

CI runs on every PR and push to `master` via `.github/workflows/ci.yml`:
`swift build`, `swift test`, `scripts/check-public-api-does-not-expose-generated-waas.sh`,
and the demo app Xcode builds are required to pass.
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

## Working Tree Notes

The demo app may contain local Xcode or macOS metadata changes. Do not revert
unrelated user changes, generated assets, or `.DS_Store` churn unless explicitly
asked.

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
| New third-party dependency added | `Package.swift`, `AGENTS.md` (note the lib), context7 setup |
| Demo app flows change | `README.md`, `Examples/` |
