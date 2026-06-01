# Repository Guidelines

## Project Overview

This repository is a Swift 6 package for the OMS SDK. It exposes the `OMS_SDK`
module and supports iOS 15+ and macOS 12+. The SDK covers wallet auth, Keychain
request signing and session persistence, OIDC flows, transactions, message and
typed-data signing, signature verification, token balances, and unit formatting.

The package, product, target, and several directories contain spaces. Quote paths
and target names in shell commands, for example `"Sources/Swift SDK"` and
`"OMS SDK"`.

## Repository Layout

- `Package.swift` defines the Swift package, the `"OMS SDK"` library target, and
  the `"OMS SDKTests"` test target.
- `Sources/Swift SDK/` contains the SDK implementation.
- `Sources/Swift SDK/Clients/` contains `WalletClient` and `IndexerClient`.
- `Sources/Swift SDK/Signer/` contains Keychain/P-256 signing and credential
  session code.
- `Sources/Swift SDK/Models/` contains public model types and auth/session
  state.
- `Sources/Swift SDK/Utils/` contains encoding, hashing, request, time, byte, and
  unit helpers.
- `Sources/Swift SDK/Generated/waas.gen.swift` is generated WebRPC client code.
  Do not edit it by hand unless the user explicitly asks for a generated-code
  patch.
- `Tests/Swift SDKTests/` contains Swift Testing tests using `@Test` and
  `#expect`.
- `Examples/sdk-demo/oms-sdk-demo.xcodeproj` and
  `Examples/sdk-demo/oms-sdk-demo/` contain the SwiftUI demo app.
- `README.md` is the user-facing guide; `API.md` is the detailed API reference.

## Common Commands

```sh
swift build
swift test
xcodebuild -list -project Examples/sdk-demo/oms-sdk-demo.xcodeproj
xcodebuild -project Examples/sdk-demo/oms-sdk-demo.xcodeproj -scheme oms-sdk-demo build
```

Run `swift test` for SDK changes. For demo app changes, also build the Xcode
project with the `oms-sdk-demo` scheme when feasible.

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
- When editing paths with spaces, keep command examples quoted and prefer
  `rg --files`, `rg`, `swift build`, and `swift test` from the repository root.

## Tests

Tests use the Swift Testing framework:

```swift
import Testing
@testable import OMS_SDK

@Test func TestExample() throws {
    #expect(actual == expected)
}
```

Name new tests in the existing `Test...` style and keep fixtures deterministic.
Prefer mocked transport, Keychain, and indexer tests over live services so the
suite stays reliable.

For auth, signing, pagination, and transaction behavior, add focused tests under
`Tests/Swift SDKTests/`. Split tests into separate files for each category, such
as authentication and indexer tests.

## Documentation

Update `README.md` when user-facing setup or flow examples change. Update
`API.md` when public methods, parameters, models, or behavior change. Keep docs
aligned with the actual Swift names, labels, return types, and the `OMS_SDK`
import name. Avoid adding method descriptions in source code.

## Demo App

The demo app should handle OMS SDK errors and open an error window when that
happens.

## Working Tree Notes

The demo app may contain local Xcode or macOS metadata changes. Do not revert
unrelated user changes, generated assets, or `.DS_Store` churn unless explicitly
asked.
