# TESTING.md

How testing works in this repo. `AGENTS.md` points here so agents know how to verify changes.

## Frameworks & tools

- **Swift Testing** — the native Swift testing framework (`import Testing`). Uses `@Test` for test
  functions and `#expect` for assertions.
- No external test dependencies; tests are part of the `"OMS SDKTests"` target in `Package.swift`.

## Unit tests

- **Scope:** Tests for individual SDK components with mocked transport, Keychain, and indexer
  dependencies. No live network calls or real Keychain access.
- **Location:** `Tests/Swift SDKTests/`
- **Run:** `swift test`

Current test files:
- `RequestsTests.swift` — HTTP request building and signing
- `MockWalletTests.swift` — wallet auth and session logic with mocked dependencies
- `IndexerTests.swift` — indexer client pagination and response handling
- `WaasRequestSigningTests.swift` — generated WaaS request payload signing
- `PublicErrorContractsTests.swift` — public `OmsSdkError` field, upstream, and recovery contracts

## Public error contract tests

`PublicErrorContractsTests.swift` is the centralized owner for app-facing SDK
error behavior. It serializes `OmsSdkError` into stable public fields:
`code`, `operation`, `message`, `status`, nullable `retryable`, `txnId`, and
`upstreamError`.

When a public SDK method gains, removes, or intentionally changes error
behavior, update the test, [docs/error-contracts.md](docs/error-contracts.md),
`API.md`, and user-facing README examples together. Keep the tests
representative by covering each backend/transport/local failure family through
real public methods rather than duplicating the same assertion for every method.

## Integration tests

There is currently no separate integration test suite. All tests in `Tests/Swift SDKTests/` are
unit-style with mocked dependencies. If integration tests (live network, real Keychain) are added,
place them in `Tests/Swift SDKIntegrationTests/` and document prerequisites here.

## Conventions

- Test function names use the `Test...` style matching existing tests (e.g. `TestWalletAuth`).
- Every bugfix should include a regression test that reproduces the failure before the fix.
- Fixtures must be deterministic — no timestamps, random data, or live service calls.
- Use mocked transport, Keychain, and indexer stubs rather than live services to keep the suite
  fast and reliable in CI.
- Split tests into separate files by category (e.g. authentication, indexer, signing).
- Quote paths and target names with spaces in any shell commands.

## Execution summary

| Goal | Command |
|---|---|
| Run all tests | `swift test` |
| Build without running tests | `swift build` |
| Run tests matching a filter | `swift test --filter <TestNamePattern>` |
| Verbose output | `swift test --verbose` |
| Build SDK demo app | `xcodebuild -project Examples/sdk-demo/oms-sdk-demo.xcodeproj -scheme oms-sdk-demo build CODE_SIGNING_ALLOWED=NO` |
| Build Trails Actions demo app | `xcodebuild -project Examples/trails-actions/trails-actions.xcodeproj -scheme trails-actions build CODE_SIGNING_ALLOWED=NO` |
