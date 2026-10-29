import Foundation
import Testing
@testable import OMSWallet

// `addSessionChangeObserver` reports every change of `activeWallet` or `session` once, on the main
// actor, in order, with the state right after it.

private let firstWallet = activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-1")
private let secondWallet = activeTestWallet("0x2222222222222222222222222222222222222222", id: "wallet-2")
private let auth = OMSWalletSessionAuth.email(OMSWalletEmailSessionAuth(email: "user@example.com"))

/// Activates `wallet` in the client's session, as a sign-in or a wallet switch does.
private func activate(_ wallet: Wallet, in fixture: MockWalletClientFixture) throws {
    try fixture.client.createSequenceWallet(
        wallet: wallet,
        sessionMetadata: SessionMetadata(expiresAt: "2099-01-01T00:00:00Z", auth: auth, expiryBounds: testExpiryBounds),
        requiredSessionRevision: fixture.client.sessionRevisionSnapshot()
    )
}

/// Records the changes an observer receives.
@MainActor
private final class ChangeRecorder {
    var changes: [OMSWalletSessionChangeEvent] = []
    var observation: OMSWalletSessionChangeObservation?

    init(_ client: WalletClient, onChange: @escaping @MainActor (OMSWalletSessionChangeEvent) -> Void = { _ in }) {
        observation = client.addSessionChangeObserver { [weak self] event in
            self?.changes.append(event)
            onChange(event)
        }
    }

    var names: [String] { changes.map(\.name) }

    /// Waits until the changes are `names`.
    func waitFor(_ names: [String]) async throws {
        for _ in 0..<40 where self.names != names {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(self.names == names)
    }
}

@Test @MainActor func TestSessionChangesReportEachChangeOnceWithTheStateAfterIt() async throws {
    let fixture = makeMockWalletClient()
    let recorder = ChangeRecorder(fixture.client)

    try activate(firstWallet, in: fixture)
    try activate(secondWallet, in: fixture)
    // Activating the active wallet again changes nothing.
    try activate(secondWallet, in: fixture)
    try fixture.client.signOut()
    try fixture.client.signOut()

    try await recorder.waitFor(["signedIn", "walletChanged", "signedOut"])
    let session = OMSWalletSession(expiresAt: "2099-01-01T00:00:00Z", auth: auth)
    #expect(recorder.changes == [
        .signedIn(wallet: firstWallet, session: session),
        .walletChanged(wallet: secondWallet, session: session),
        .signedOut
    ])
}

@Test @MainActor func TestSessionChangesReportTheEndOfTheSessionWhenAnotherSignInStarts() async throws {
    let fixture = makeMockWalletClient()
    try activate(firstWallet, in: fixture)
    let recorder = ChangeRecorder(fixture.client)
    try fixture.transport.enqueue(
        CommitVerifierResponse(verifier: "verifier", loginHint: "other@example.com", challenge: "challenge"),
        for: WaasAPI.CommitVerifier.urlPath
    )

    try await fixture.client.startEmailAuth(email: "other@example.com")

    try await recorder.waitFor(["signedOut"])
}

@Test @MainActor func TestSessionChangesArriveInOrderIncludingOnesAnObserverCauses() async throws {
    let fixture = makeMockWalletClient()
    try activate(firstWallet, in: fixture)
    let signingOut = ChangeRecorder(fixture.client) { event in
        if case .walletChanged = event {
            try? fixture.client.signOut()
        }
    }
    let second = ChangeRecorder(fixture.client)

    try activate(secondWallet, in: fixture)

    try await second.waitFor(["walletChanged", "signedOut"])
    #expect(signingOut.names == ["walletChanged", "signedOut"])
    #expect(fixture.client.activeWallet == nil)
}

@Test @MainActor func TestSessionChangesAreNotDeliveredDuringTheCallThatMadeThem() async throws {
    let fixture = makeMockWalletClient()
    let recorder = ChangeRecorder(fixture.client)

    try activate(firstWallet, in: fixture)
    // Still on the main actor, inside the same synchronous stretch: nothing delivered yet.
    #expect(recorder.changes.isEmpty)

    try await recorder.waitFor(["signedIn"])
}

@Test @MainActor func TestCancellingAnObservationDropsChangesNotDeliveredYet() async throws {
    let fixture = makeMockWalletClient()
    try activate(firstWallet, in: fixture)
    let recorder = ChangeRecorder(fixture.client)

    try fixture.client.signOut()
    recorder.observation?.cancel()
    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(recorder.changes.isEmpty)
}

@Test @MainActor func TestAnObserverAddedInsideAnotherReceivesAnExpiryOnceThroughReplay() async throws {
    let fixture = makeMockWalletClient(currentDate: { Date(timeIntervalSince1970: 4_102_444_800 + 60) })
    try activate(firstWallet, in: fixture)
    var late: ChangeRecorder?
    let first = ChangeRecorder(fixture.client) { event in
        if case .expired = event, late == nil {
            late = ChangeRecorder(fixture.client)
        }
    }

    // The session's expiry (2099) has passed by the fixture's clock.
    #expect(fixture.client.expireCurrentSessionIfNeeded())

    try await first.waitFor(["expired"])
    try await late?.waitFor(["expired"])
    #expect(late?.changes.count == 1)
}
