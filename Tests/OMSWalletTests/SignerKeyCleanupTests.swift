import Foundation
import Security
import Testing
@testable import OMSWallet

// An app and its extensions can share the keychain, and with it the signing key stored under one
// application tag. A session that ends on its own in one process must not delete a key another
// process's newer sign-in stored under that tag.

/// Runs blocking keychain calls off Swift's cooperative thread pool, as the SDK does (`SignerWork`).
/// The real keychain can take over a second per call on CI; blocking the pool's few threads that
/// long delays the tasks of tests running alongside, such as a request deadline's timer.
func keychainWork<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await SignerWork.run(body)
}

/// Two signers for one tag, as an app and an extension sharing the keychain would have.
private struct SharedTag {
    let tag = "oms.test.\(UUID().uuidString)"
    let nonces = InMemoryKeychain()

    func signer() -> AppleKeychainP256CredentialSigner {
        AppleKeychainP256CredentialSigner(applicationTag: tag, nonceStorageKey: tag + ".nonce", keychain: nonces)
    }

    func cleanUp() {
        try? signer().clear()
    }
}

@Test func TestKeychainSignerDeletesItsOwnKeyAndKeepsTheSharedNonce() async throws {
    let (hasCredential, storedNonce, nonce) = try await keychainWork {
        let shared = SharedTag()
        defer { shared.cleanUp() }
        let signer = shared.signer()
        let credentialId = try signer.credentialId()
        let nonce = try signer.nextNonce()

        try signer.clear(ifCredentialId: credentialId.uppercased())

        return (try signer.hasCredential(), try shared.nonces.string(forKey: shared.tag + ".nonce"), nonce)
    }

    #expect(!hasCredential)
    // A later key's nonces only need to keep increasing.
    #expect(storedNonce == nonce)
}

@Test func TestKeychainSignerKeepsAKeyAnotherProcessStoredUnderTheSameTag() async throws {
    let (oldId, newId, appHasCredential, storedId) = try await keychainWork {
        let shared = SharedTag()
        defer { shared.cleanUp() }
        let app = shared.signer()
        let oldId = try app.credentialId()

        let extensionSigner = shared.signer()
        try extensionSigner.clear()
        let newId = try extensionSigner.credentialId()
        try app.clear(ifCredentialId: oldId)

        return (oldId, newId, try app.hasCredential(), try shared.signer().credentialId())
    }

    #expect(newId != oldId)
    #expect(appHasCredential)
    #expect(storedId == newId)
}

@Test func TestKeychainSignerKeepsAKeyReplacedBetweenTheCheckAndTheDelete() async throws {
    // The delete removes the item it checked, by reference, not whatever the tag holds by then.
    let (newId, storedId) = try await keychainWork {
        let shared = SharedTag()
        defer { shared.cleanUp() }
        let app = shared.signer()
        _ = try app.credentialId()
        guard let checkedKey = try app.storedKey() else {
            throw AppleKeychainP256CredentialSigner.SignerError.publicKeyUnavailable
        }

        let extensionSigner = shared.signer()
        try extensionSigner.clear()
        let newId = try extensionSigner.credentialId()
        try AppleKeychainP256CredentialSigner.deleteKeyItem(checkedKey)

        return (newId, try shared.signer().credentialId())
    }

    #expect(storedId == newId)
}

@Test @MainActor func TestServerRejectedCredentialKeepsAKeyAnotherProcessStored() async throws {
    let fixture = makeMockWalletClient()
    activateTestSession(
        fixture,
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main")
    )
    var changes: [OMSWalletSessionChangeEvent] = []
    let observation = fixture.client.addSessionChangeObserver { changes.append($0) }
    defer { observation.cancel() }
    let revision = fixture.client.withSessionLock { fixture.client._sessionRevision }

    // While this session's request was in flight, another process signed in with a new key.
    fixture.signer.replaceKey(credentialId: "0xnewer-sign-in")
    fixture.client.endSessionRejectedByServer(revision: revision)
    for _ in 0..<40 where changes.last?.name != "expired" {
        try await Task.sleep(nanoseconds: 25_000_000)
    }

    #expect(changes.map(\.name) == ["expired"])
    #expect(fixture.client.session == nil)
    #expect(fixture.signer.hasStoredCredential)
    #expect(fixture.signer.clearCallCount == 0)
}
