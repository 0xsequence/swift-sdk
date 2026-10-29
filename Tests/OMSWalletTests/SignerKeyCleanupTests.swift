import Foundation
import Security
import Testing
@testable import OMSWallet

// An app and its extensions can share the keychain, and with it the signing key stored under one
// application tag. A session that ends on its own in one process must not delete a key another
// process's newer sign-in stored under that tag.

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

@Test func TestKeychainSignerDeletesItsOwnKeyAndKeepsTheSharedNonce() throws {
    let shared = SharedTag()
    defer { shared.cleanUp() }
    let signer = shared.signer()
    let credentialId = try signer.credentialId()
    let nonce = try signer.nextNonce()

    try signer.clear(ifCredentialId: credentialId.uppercased())

    #expect(try !signer.hasCredential())
    // A later key's nonces only need to keep increasing.
    #expect(try shared.nonces.string(forKey: shared.tag + ".nonce") == nonce)
}

@Test func TestKeychainSignerKeepsAKeyAnotherProcessStoredUnderTheSameTag() throws {
    let shared = SharedTag()
    defer { shared.cleanUp() }
    let app = shared.signer()
    let oldId = try app.credentialId()

    let extensionSigner = shared.signer()
    try extensionSigner.clear()
    let newId = try extensionSigner.credentialId()
    try app.clear(ifCredentialId: oldId)

    #expect(newId != oldId)
    #expect(try app.hasCredential())
    #expect(try shared.signer().credentialId() == newId)
}

@Test func TestKeychainSignerKeepsAKeyReplacedBetweenTheCheckAndTheDelete() throws {
    // The delete removes the item it checked, by reference, not whatever the tag holds by then.
    let shared = SharedTag()
    defer { shared.cleanUp() }
    let app = shared.signer()
    _ = try app.credentialId()
    let checkedKey = try #require(try app.storedKey())

    let extensionSigner = shared.signer()
    try extensionSigner.clear()
    let newId = try extensionSigner.credentialId()
    try AppleKeychainP256CredentialSigner.deleteKeyItem(checkedKey)

    #expect(try shared.signer().credentialId() == newId)
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
