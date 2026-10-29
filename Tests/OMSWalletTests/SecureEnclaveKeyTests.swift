import Foundation
import Security
import Testing
@testable import OMSWallet

// On an iOS device session keys are generated in the Secure Enclave, so the private key can sign
// but never be exported (Tests/DeviceTests proves that on a device). A software key saved before
// that cannot be moved there: its session ends as expired and the user signs in again, which
// creates a Secure Enclave key.

private let auth = OMSWalletSessionAuth.email(OMSWalletEmailSessionAuth(email: "user@example.com"))
private let restoredAt = Date(timeIntervalSince1970: 1_767_225_600)

/// A client restoring an unexpired session whose stored key is `signer`'s.
private func restore(
    keychain: InMemoryKeychain,
    signer: MockCredentialSigner,
    projectId: String,
    storedCredentials: StorableCredentials? = nil
) -> MockWalletClientFixture {
    makeMockWalletClient(
        projectId: projectId,
        keychain: keychain,
        signer: signer,
        currentDate: { restoredAt },
        storedCredentials: storedCredentials
    )
}

private func record(_ signer: MockCredentialSigner) throws -> StorableCredentials {
    StorableCredentials(
        wallet: activeTestWallet("0x1111111111111111111111111111111111111111", id: "wallet-main"),
        signerCredentialId: try signer.credentialId(),
        alg: signer.alg,
        expiresAt: "2099-01-01T00:00:00Z",
        auth: auth,
        expiryBounds: testExpiryBounds
    )
}

@MainActor
private func replayedExpiry(_ client: WalletClient) async throws -> OMSWalletExpiredSession? {
    var replayed: OMSWalletExpiredSession?
    let observation = client.addSessionChangeObserver { replayed = $0.expiredSession }
    defer { observation.cancel() }
    for _ in 0..<40 where replayed == nil {
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    return replayed
}

@Test @MainActor func TestSessionSignedByASoftwareKeyOnADeviceEndsAsExpiredAndKeepsItsHint() async throws {
    let keychain = InMemoryKeychain()
    let signer = MockCredentialSigner()
    let projectId = "proj_\(UUID().uuidString)"
    let stored = try record(signer)
    signer.holdOnlyUnusableKey()

    let fixture = restore(keychain: keychain, signer: signer, projectId: projectId, storedCredentials: stored)

    #expect(fixture.client.session == nil)
    let expired = try #require(try await replayedExpiry(fixture.client))
    #expect(expired.expiredAt == "2026-01-01T00:00:00Z")
    #expect(expired.wallet?.id == "wallet-main")
    #expect(expired.session.auth == auth)
    #expect(signer.unusableKeyCredentialId == nil)
    // The record stays as the sign-in hint, now expired, so later launches replay the expiry too.
    #expect(try fixture.storedCredentials()?.expiresAt == "2026-01-01T00:00:00Z")
    #expect(fixture.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)

    let relaunched = restore(keychain: keychain, signer: signer, projectId: projectId)
    #expect(relaunched.client.session == nil)
    #expect(try await replayedExpiry(relaunched.client)?.expiredAt == "2026-01-01T00:00:00Z")
    #expect(relaunched.transport.requestCount(for: WaasAPI.GetCredential.urlPath) == 0)
}

@Test func TestLeftoverSoftwareKeyIsDeletedWithoutEndingTheSessionItDoesNotSign() throws {
    let signer = MockCredentialSigner()
    let stored = try record(signer)
    signer.unusableKeyCredentialId = "0xold-software-key"

    let fixture = restore(
        keychain: InMemoryKeychain(),
        signer: signer,
        projectId: "proj_\(UUID().uuidString)",
        storedCredentials: stored
    )

    #expect(fixture.client.activeWallet?.id == "wallet-main")
    #expect(try fixture.storedCredentials()?.expiresAt == "2099-01-01T00:00:00Z")
    #expect(signer.unusableKeyCredentialId == nil)
}

/// Signers for one tag in the real keychain, removed afterwards by the tag alone.
private struct KeychainTag {
    let tag = "oms.test.\(UUID().uuidString)"
    let nonces = InMemoryKeychain()

    func signer(_ keyStorage: AppleKeychainP256CredentialSigner.KeyStorage) -> AppleKeychainP256CredentialSigner {
        AppleKeychainP256CredentialSigner(
            applicationTag: tag,
            nonceStorageKey: tag + ".nonce",
            keychain: nonces,
            keyStorage: keyStorage
        )
    }

    func cleanUp() {
        try? signer(.software).clear()
    }
}

@Test func TestSecureEnclaveSignerNeverUsesASoftwareKeyStoredUnderItsTag() throws {
    let keys = KeychainTag()
    defer { keys.cleanUp() }
    let softwareId = try keys.signer(.software).credentialId()
    let enclave = keys.signer(.secureEnclave)

    #expect(try enclave.unusableKeyCredentialIds() == [softwareId])
    #expect(try !enclave.hasCredential())
    #expect(try enclave.storedKey() == nil)
    #expect(try keys.signer(.software).unusableKeyCredentialIds().isEmpty)

    try enclave.deleteUnusableKeys()

    #expect(try enclave.unusableKeyCredentialIds().isEmpty)
    #expect(try !keys.signer(.software).hasCredential())
}
