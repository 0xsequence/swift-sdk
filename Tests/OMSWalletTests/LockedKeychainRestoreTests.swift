import Foundation
import Testing
@testable import OMSWallet

// A background launch while the device is locked cannot read `WhenUnlocked` keychain items. The
// restore must wait for the keychain instead of treating the session as absent, because the
// shared client made during that launch is the one the app keeps using after the user unlocks.

/// Records each wait for protected data and runs them when the test says it became available.
private final class ProtectedDataTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [UUID: @Sendable () -> Void] = [:]
    private var checks: [Bool] = []

    /// For each wait, whether it asked for an immediate check.
    var immediateChecks: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return checks
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    func run(checkNow: Bool, _ body: @escaping @Sendable () -> Void) -> ForegroundActivation.Cancel {
        let id = UUID()
        lock.lock()
        checks.append(checkNow)
        pending[id] = body
        lock.unlock()
        return { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            self.pending[id] = nil
            self.lock.unlock()
        }
    }

    /// Runs every pending wait, as `protectedDataDidBecomeAvailableNotification` would.
    func fire() {
        lock.lock()
        let bodies = Array(pending.values)
        pending = [:]
        lock.unlock()
        bodies.forEach { $0() }
    }
}

private let wallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-restored")

private func credentialResponse(expiresAt: String) -> WaasAPI.GetCredential.Response {
    WaasAPI.GetCredential.Response(
        credential: WaasCredentialInfo(
            credentialId: "0xmock-credential",
            type: .direct,
            expiresAt: expiresAt,
            isCaller: true
        )
    )
}

private struct LockedLaunch {
    let fixture: MockWalletClientFixture
    let keychain: InMemoryKeychain
    let signer: MockCredentialSigner
    let trigger: ProtectedDataTrigger
    let changes: LockedBox<[OMSWalletSessionChangeEvent]>
    let observation: OMSWalletSessionChangeObservation

    var storedRecord: String? {
        get throws {
            try keychain.string(forKey: Constants.credentialsStorageKey(environment: testEnvironment, scope: projectId))
        }
    }

    func unlock() {
        keychain.isLocked = false
        signer.isLocked = false
    }
}

private let projectId = "proj_locked_launch"

/// Saves a session expiring at `expiresAt`, locks the device (keychain and key) as `locked` says,
/// and launches a client at `now`.
@MainActor
private func launch(
    expiresAt: String = "2099-01-01T00:00:00Z",
    now: Date = Date(),
    lockRecord: Bool = true,
    lockKey: Bool = true,
    storeSession: Bool = true,
    prepareTransport: (MockWaasTransport) throws -> Void = { _ in }
) throws -> LockedLaunch {
    let keychain = InMemoryKeychain()
    let signer = MockCredentialSigner()
    if storeSession {
        _ = try keychain.set(
            StorableCredentials(
                wallet: wallet,
                signerCredentialId: try signer.credentialId(),
                alg: signer.alg,
                expiresAt: expiresAt,
                auth: .email(OMSWalletEmailSessionAuth(email: "user@example.com")),
                expiryBounds: testExpiryBounds
            ).jsonString(),
            forKey: Constants.credentialsStorageKey(environment: testEnvironment, scope: projectId)
        )
    }
    keychain.isLocked = lockRecord
    signer.isLocked = lockKey
    let trigger = ProtectedDataTrigger()
    let fixture = makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { now },
        runWhenProtectedDataAvailable: trigger.run,
        prepareTransport: prepareTransport
    )
    let events = LockedBox<[OMSWalletSessionChangeEvent]>([])
    let observation = fixture.client.addSessionChangeObserver { event in
        events.withValue { $0.append(event) }
    }
    return LockedLaunch(
        fixture: fixture,
        keychain: keychain,
        signer: signer,
        trigger: trigger,
        changes: events,
        observation: observation
    )
}

/// The client's restored wallet without the retry a public `activeWallet` read makes.
private func restoredWallet(_ client: WalletClient) -> Wallet? {
    client.withSessionLock { client._activeWallet }
}

@Test @MainActor func TestLockedLaunchRestoresTheSameClientOnceProtectedDataIsAvailable() async throws {
    let launched = try launch { transport in
        try transport.enqueue(credentialResponse(expiresAt: "2099-01-01T00:00:00Z"), for: WaasAPI.GetCredential.urlPath)
    }
    defer { launched.observation.cancel() }

    // Locked: nothing restored, nothing reported, and one wait registered.
    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(launched.changes.withValue { $0.map(\.name) } == [])
    #expect(launched.trigger.immediateChecks == [true])

    // Nothing was deleted either.
    launched.unlock()
    #expect(try launched.storedRecord != nil)
    #expect(launched.signer.hasStoredCredential)
    #expect(launched.signer.clearCallCount == 0)

    launched.trigger.fire()

    #expect(launched.fixture.client.activeWallet?.id == wallet.id)
    #expect(launched.fixture.client.session?.expiresAt == "2099-01-01T00:00:00Z")
    #expect(launched.trigger.pendingCount == 0)
    // The observer, added after init, learns of the restore; nothing expired.
    try await waitForChanges(launched, ["restored"])
}

@Test @MainActor func TestLockedLaunchKeepsWaitingWithoutALoopUntilTheKeychainIsReadable() async throws {
    let launched = try launch { transport in
        try transport.enqueue(credentialResponse(expiresAt: "2099-01-01T00:00:00Z"), for: WaasAPI.GetCredential.urlPath)
    }
    defer { launched.observation.cancel() }

    // A hint while still locked: the retry fails and waits again, without an immediate recheck.
    launched.trigger.fire()
    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(launched.trigger.immediateChecks == [true, false])
    #expect(launched.trigger.pendingCount == 1)

    launched.unlock()
    // Several hints at once restore once.
    launched.trigger.fire()
    launched.trigger.fire()
    launched.fixture.client.retryDeferredRestore()

    #expect(restoredWallet(launched.fixture.client)?.id == wallet.id)
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(launched.fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 1)
}

@Test @MainActor func TestReadingTheSessionRetriesADeferredRestore() async throws {
    // An app extension gets no protected-data notifications; reading the session retries instead.
    let launched = try launch { transport in
        try transport.enqueue(credentialResponse(expiresAt: "2099-01-01T00:00:00Z"), for: WaasAPI.GetCredential.urlPath)
    }
    defer { launched.observation.cancel() }
    #expect(launched.fixture.client.activeWallet == nil)

    launched.unlock()
    // Reads retry at most once a second.
    try await Task.sleep(nanoseconds: 1_100_000_000)

    #expect(launched.fixture.client.activeWallet?.id == wallet.id)
}

@Test @MainActor func TestSignOutBeforeTheKeychainIsReadableCancelsTheDeferredRestore() async throws {
    let launched = try launch()
    defer { launched.observation.cancel() }
    launched.unlock()

    try launched.fixture.client.signOut()
    // Signing out stops the wait, so a later unlock does not resurrect the session.
    #expect(launched.trigger.pendingCount == 0)
    launched.trigger.fire()

    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(try launched.storedRecord == nil)
}

@Test @MainActor func TestDeferredRestoreDoesNotRunAfterTheSessionChanged() async throws {
    // A sign-out or sign-in between the trigger's claim and the restore bumps the revision first.
    let launched = try launch()
    defer { launched.observation.cancel() }
    launched.unlock()
    let staleRevision = launched.fixture.client.withSessionLock { launched.fixture.client._sessionRevision }
    launched.fixture.client.withSessionLock { launched.fixture.client._sessionRevision += 1 }

    launched.fixture.client.restoreStoredWalletSession(expectedRevision: staleRevision)

    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(try launched.storedRecord != nil)
    #expect(launched.signer.clearCallCount == 0)
}

@Test @MainActor func TestMissingSessionDoesNotWaitForTheKeychain() async throws {
    let launched = try launch(lockRecord: false, lockKey: false, storeSession: false)
    defer { launched.observation.cancel() }

    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(launched.trigger.immediateChecks.isEmpty)
}

@Test @MainActor func TestUnreadableKeyInTheRestoreWindowWaitsInsteadOfExpiring() async throws {
    // The saved expiry passed 4 hours ago, so restore checks the key; a key that cannot be read is
    // not a key an earlier expiry cleared.
    let launched = try launch(
        expiresAt: "2026-01-01T00:00:00Z",
        now: Date(timeIntervalSince1970: 1_767_225_600 + 4 * 3_600),
        lockRecord: false,
        lockKey: true
    ) { transport in
        try transport.enqueue(credentialResponse(expiresAt: "2026-01-11T04:00:00.000Z"), for: WaasAPI.GetCredential.urlPath)
    }
    defer { launched.observation.cancel() }

    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(launched.changes.withValue { $0.map(\.name) } == [])
    #expect(launched.signer.clearCallCount == 0)
    #expect(try launched.storedRecord != nil)

    launched.unlock()
    launched.trigger.fire()

    #expect(restoredWallet(launched.fixture.client)?.id == wallet.id)
    try await waitForSessionExpiry(launched.fixture.client, "2026-01-11T04:00:00.000Z")
    // Restored once readable, then the restore read moved its expiry; never expired.
    try await waitForChanges(launched, ["restored", "expiryUpdated"])
}

/// Waits until the observer has received changes named `names`, then expects exactly those.
@MainActor
private func waitForChanges(_ launched: LockedLaunch, _ names: [String]) async throws {
    for _ in 0..<40 where launched.changes.withValue({ $0.map(\.name) }) != names {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(launched.changes.withValue { $0.map(\.name) } == names)
}

@MainActor
private func waitForSessionExpiry(_ client: WalletClient, _ expiresAt: String) async throws {
    for _ in 0..<40 where client.session?.expiresAt != expiresAt {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(client.session?.expiresAt == expiresAt)
}

@Test @MainActor func TestUnreadableKeyForAnUnexpiredSessionWaitsAndKeepsTheRecord() async throws {
    // The record is readable but the key is not: restore keeps both and waits.
    let launched = try launch(lockRecord: false, lockKey: true) { transport in
        try transport.enqueue(credentialResponse(expiresAt: "2099-01-01T00:00:00Z"), for: WaasAPI.GetCredential.urlPath)
    }
    defer { launched.observation.cancel() }

    #expect(restoredWallet(launched.fixture.client) == nil)
    #expect(try launched.storedRecord != nil)
    #expect(launched.trigger.immediateChecks == [true])

    launched.unlock()
    launched.trigger.fire()

    #expect(restoredWallet(launched.fixture.client)?.id == wallet.id)
}
