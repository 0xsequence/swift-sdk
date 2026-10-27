import Foundation
import Testing
@testable import OMSWallet

// Claimable wallets are preallocated for the recipient's email. `CompleteAuth` lists the ones still
// unclaimed in `claimable`, separately from the owned `wallets`, and `ClaimWallet` transfers one.

private let ownedEthereumWallet = testWallet(id: "wallet-owned-evm", address: "0x1111111111111111111111111111111111111111")
private let claimableEthereumWallet = testWallet(id: "wallet-claimable-evm", address: "0x2222222222222222222222222222222222222222")
private let claimableSolanaWallet = testWallet(
    id: "wallet-claimable-sol",
    type: .solana,
    address: "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin"
)
private let claimableTronWallet = testWallet(
    id: "wallet-claimable-trx",
    type: .tron,
    address: "TNPeeaaFB7K9cmo4uQpcU32zGK8G1NYqeL"
)

/// The body WaaS returns for an allocation that is not claimable by the caller.
private let accountNotFoundBody = Data(
    #"{"error":"AccountNotFound","code":7301,"msg":"Account not found","cause":"","status":404}"#.utf8
)

private func expectAccountNotFound(_ error: Error, operation: OMSWalletOperation) {
    guard let error = error as? OMSWalletError else {
        Issue.record("Expected OMSWalletError, got \(error)")
        return
    }
    #expect(error.code == .requestFailed)
    #expect(error.operation == operation)
    #expect(error.status == 404)
    #expect(error.retryable == false)
    #expect(error.upstreamError == OMSWalletUpstreamError(
        service: .waas,
        name: "AccountNotFound",
        code: "7301",
        message: "Account not found",
        status: 404
    ))
}

@Test func TestAutomaticSignInClaimsClaimableWalletWhenNoOwnedWalletOfTypeExists() async throws {
    let fixture = makeMockWalletClient()
    let ownedSolanaWallet = testWallet(
        id: "wallet-owned-sol",
        type: .solana,
        address: "7EYnhQoR9YM3N7UoaKRoA44Uy8JeaZV3qyouov87awMs"
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [ownedSolanaWallet],
            claimable: [claimableEthereumWallet, claimableTronWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ClaimWalletResponse(wallet: claimableEthereumWallet),
        for: WaasAPI.ClaimWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(code: "123456")

    guard case .walletSelected(let wallet, let wallets, let claimableWallets, _) = result else {
        Issue.record("Expected an automatically selected wallet")
        return
    }
    #expect(try fixture.transport.requestObject(for: WaasAPI.ClaimWallet.urlPath) == [
        "walletId": claimableEthereumWallet.id
    ])
    #expect(fixture.transport.requestCount(for: WaasAPI.ClaimWallet.urlPath) == 1)
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.UseWallet.urlPath) == 0)
    #expect(wallet.id == claimableEthereumWallet.id)
    #expect(wallets.map(\.id) == [ownedSolanaWallet.id, claimableEthereumWallet.id])
    #expect(claimableWallets.map(\.id) == [claimableTronWallet.id])
    #expect(result.claimableWallets.map(\.id) == [claimableTronWallet.id])
    #expect(fixture.client.activeWallet?.id == claimableEthereumWallet.id)
    #expect(fixture.client.activeWallet?.address == claimableEthereumWallet.address)
    let storedCredentials = try fixture.storedCredentials()
    #expect(storedCredentials?.wallet.id == claimableEthereumWallet.id)
    #expect(storedCredentials?.wallet.address == claimableEthereumWallet.address)
    #expect(storedCredentials?.auth.email == "user@example.com")
}

@Test func TestOidcIdTokenSignInClaimsClaimableWalletOfRequestedType() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        CommitVerifierResponse(verifier: "oidc-verifier", loginHint: "user@example.com", challenge: ""),
        for: WaasAPI.CommitVerifier.urlPath
    )
    try fixture.transport.enqueue(
        completeAuthResponse(
            identity: Identity(type: .oidc, iss: "https://accounts.google.com", sub: "google-sub-123"),
            wallets: [],
            claimable: [claimableEthereumWallet, claimableSolanaWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ClaimWalletResponse(wallet: claimableSolanaWallet),
        for: WaasAPI.ClaimWallet.urlPath
    )

    let result = try await fixture.client.signInWithOidcIdToken(
        idToken: try fakeOidcIdToken(),
        issuer: "https://accounts.google.com",
        audience: "demo-web-client-id",
        walletType: .solana
    )

    #expect(try fixture.transport.requestObject(for: WaasAPI.ClaimWallet.urlPath) == [
        "walletId": claimableSolanaWallet.id
    ])
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
    #expect(result.wallet?.id == claimableSolanaWallet.id)
    #expect(result.claimableWallets.map(\.id) == [claimableEthereumWallet.id])
    #expect(fixture.client.activeWallet?.id == claimableSolanaWallet.id)
    #expect(try fixture.storedCredentials()?.wallet.id == claimableSolanaWallet.id)
}

@Test func TestAutomaticSignInPrefersOwnedWalletOverClaimableWallet() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [ownedEthereumWallet], claimable: [claimableEthereumWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: ownedEthereumWallet),
        for: WaasAPI.UseWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(code: "123456")

    #expect(fixture.transport.requestCount(for: WaasAPI.ClaimWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
    #expect(try fixture.transport.decodedRequest(UseWalletRequest.self, for: WaasAPI.UseWallet.urlPath).walletId
        == ownedEthereumWallet.id)
    #expect(result.wallet?.id == ownedEthereumWallet.id)
    #expect(result.claimableWallets.map(\.id) == [claimableEthereumWallet.id])
    #expect(fixture.client.activeWallet?.id == ownedEthereumWallet.id)
}

@Test func TestAutomaticSignInCreatesWalletWhenOnlyAnotherTypeIsClaimable() async throws {
    let fixture = makeMockWalletClient()
    let createdWallet = testWallet(id: "wallet-created-evm", address: "0x3333333333333333333333333333333333333333")
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [], claimable: [claimableSolanaWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        CreateWalletResponse(wallet: createdWallet),
        for: WaasAPI.CreateWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(code: "123456")

    #expect(fixture.transport.requestCount(for: WaasAPI.ClaimWallet.urlPath) == 0)
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 1)
    #expect(result.wallet?.id == createdWallet.id)
    #expect(result.claimableWallets.map(\.id) == [claimableSolanaWallet.id])
    #expect(fixture.client.activeWallet?.id == createdWallet.id)
}

@Test func TestAutomaticSignInFailsWithoutCreatingWhenClaimFails() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [], claimable: [claimableEthereumWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    fixture.transport.enqueueRawHTTPError(
        statusCode: 404,
        body: accountNotFoundBody,
        for: WaasAPI.ClaimWallet.urlPath
    )

    do {
        _ = try await fixture.client.completeEmailAuth(code: "123456")
        Issue.record("Expected the claim failure to fail sign-in")
    } catch {
        expectAccountNotFound(error, operation: .walletCompleteEmailAuth)
    }
    #expect(fixture.transport.requestCount(for: WaasAPI.CreateWallet.urlPath) == 0)
    #expect(fixture.client.activeWallet == nil)
    #expect(fixture.client.session == nil)
    #expect(try fixture.storedCredentials() == nil)
}

@Test func TestManualSelectionExposesClaimableWalletsAndClaimWalletCompletesIt() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        completeAuthResponse(
            wallets: [ownedEthereumWallet],
            claimable: [claimableEthereumWallet, claimableSolanaWallet]
        ),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        ClaimWalletResponse(wallet: claimableEthereumWallet),
        for: WaasAPI.ClaimWallet.urlPath
    )

    let result = try await fixture.client.completeEmailAuth(code: "123456", walletSelection: .manual)
    guard case .walletSelection(let pendingSelection) = result else {
        Issue.record("Expected a pending wallet selection")
        return
    }
    #expect(pendingSelection.wallets.map(\.id) == [ownedEthereumWallet.id])
    #expect(pendingSelection.claimableWallets.map(\.id) == [claimableEthereumWallet.id])
    #expect(result.claimableWallets.map(\.id) == [claimableEthereumWallet.id])
    #expect(fixture.transport.requestCount(for: WaasAPI.ClaimWallet.urlPath) == 0)
    #expect(fixture.client.activeWallet == nil)

    let claimed = try await fixture.client.claimWallet(walletId: claimableEthereumWallet.id)

    #expect(try fixture.transport.requestObject(for: WaasAPI.ClaimWallet.urlPath) == [
        "walletId": claimableEthereumWallet.id
    ])
    #expect(claimed.wallet.id == claimableEthereumWallet.id)
    #expect(fixture.client.activeWallet?.id == claimableEthereumWallet.id)
    let storedCredentials = try fixture.storedCredentials()
    #expect(storedCredentials?.wallet.id == claimableEthereumWallet.id)
    #expect(storedCredentials?.auth.email == "user@example.com")
}

@Test func TestClaimWalletSwitchesTheActiveWallet() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [ownedEthereumWallet], claimable: [claimableTronWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: ownedEthereumWallet),
        for: WaasAPI.UseWallet.urlPath
    )
    try fixture.transport.enqueue(
        ClaimWalletResponse(wallet: claimableTronWallet),
        for: WaasAPI.ClaimWallet.urlPath
    )
    let signIn = try await fixture.client.completeEmailAuth(code: "123456")
    #expect(signIn.claimableWallets.map(\.id) == [claimableTronWallet.id])
    let expiresAt = fixture.client.session?.expiresAt

    let claimed = try await fixture.client.claimWallet(walletId: claimableTronWallet.id)

    #expect(try fixture.transport.requestObject(for: WaasAPI.ClaimWallet.urlPath) == [
        "walletId": claimableTronWallet.id
    ])
    #expect(claimed.wallet.id == claimableTronWallet.id)
    #expect(claimed.wallet.type == .tron)
    #expect(fixture.client.activeWallet?.id == claimableTronWallet.id)
    #expect(fixture.client.session?.expiresAt == expiresAt)
    let storedCredentials = try fixture.storedCredentials()
    #expect(storedCredentials?.wallet.id == claimableTronWallet.id)
    #expect(storedCredentials?.wallet.address == claimableTronWallet.address)
}

@Test func TestClaimWalletFailureSurfacesRequestErrorAndKeepsState() async throws {
    let fixture = makeMockWalletClient()
    try fixture.transport.enqueue(
        completeAuthResponse(wallets: [ownedEthereumWallet]),
        for: WaasAPI.CompleteAuth.urlPath
    )
    try fixture.transport.enqueue(
        UseWalletResponse(wallet: ownedEthereumWallet),
        for: WaasAPI.UseWallet.urlPath
    )
    fixture.transport.enqueueRawHTTPError(
        statusCode: 404,
        body: accountNotFoundBody,
        for: WaasAPI.ClaimWallet.urlPath
    )
    _ = try await fixture.client.completeEmailAuth(code: "123456")
    let sessionBefore = fixture.client.session
    let storedBefore = try fixture.storedCredentials()

    do {
        _ = try await fixture.client.claimWallet(walletId: claimableEthereumWallet.id)
        Issue.record("Expected the claim to fail")
    } catch {
        expectAccountNotFound(error, operation: .walletClaimWallet)
    }

    #expect(fixture.client.activeWallet?.id == ownedEthereumWallet.id)
    #expect(fixture.client.session == sessionBefore)
    let storedAfter = try fixture.storedCredentials()
    #expect(storedBefore?.wallet.id == ownedEthereumWallet.id)
    #expect(storedAfter?.wallet == storedBefore?.wallet)
    #expect(storedAfter?.expiresAt == storedBefore?.expiresAt)
    #expect(storedAfter?.signerCredentialId == storedBefore?.signerCredentialId)
}

@Test func TestClaimWalletRequiresSession() async throws {
    let fixture = makeMockWalletClient()

    do {
        _ = try await fixture.client.claimWallet(walletId: claimableEthereumWallet.id)
        Issue.record("Expected a missing session error")
    } catch let error as OMSWalletError {
        #expect(error.code == .sessionMissing)
        #expect(error.operation == .walletClaimWallet)
    }
    #expect(fixture.transport.requestCount(for: WaasAPI.ClaimWallet.urlPath) == 0)
}
