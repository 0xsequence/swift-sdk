@available(macOS 12.0, iOS 15.0, *)
public class OMSClient {
    public let wallet: WalletClient
    public let indexer: IndexerClient
    public let utils: OMSClientUtils

    public init(projectAccessKey: String, environment: OMSClientEnvironment = OMSClientEnvironment()) {
        self.wallet = WalletClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )

        self.indexer = IndexerClient(
            projectAccessKey: projectAccessKey,
            environment: environment
        )
        self.utils = OMSClientUtils()
    }

    public func startEmailAuth(email: String) async {
        await wallet.startEmailAuth(email: email)
    }

    public func completeEmailAuth(code: String, walletType: WalletType = WalletType.ethereum) async {
        await wallet.completeEmailAuth(code: code, walletType: walletType)
    }

    public func signInWithEmail(email: String) async {
        await startEmailAuth(email: email)
    }

    public func completeEmailSignIn(code: String, walletType: WalletType = WalletType.ethereum) async {
        await completeEmailAuth(code: code, walletType: walletType)
    }

    public func getTokenBalances(
        chainId: String,
        contractAddress: String,
        walletAddress: String,
        includeMetadata: Bool
    )
    async throws -> TokenBalancesResult {
        return try await indexer.getTokenBalances(
            chainId: chainId,
            contractAddress: contractAddress,
            walletAddress: walletAddress,
            includeMetadata: includeMetadata
        )
    }

    public func signOut() {
        wallet.signOut()
    }

    public func listAccess() async -> [CredentialInfo] {
        return await wallet.listAccess()
    }

    public func revokeAccess(targetCredentialId: String) async {
        await wallet.revokeAccess(targetCredentialId: targetCredentialId)
    }

    public func signMessage(network: String, message: String) async -> String {
        return await wallet.signMessage(network: network, message: message)
    }

    public func sendTransaction(
        network: String,
        to: String,
        value: String,
        feeOptionSelector: FeeOptionSelector = .first
    ) async throws -> String {
        return try await wallet.sendTransaction(
            network: network,
            to: to,
            value: value,
            feeOptionSelector: feeOptionSelector
        )
    }

    public func sendTransaction(
        network: String,
        request: SendTransactionRequest,
        feeOptionSelector: FeeOptionSelector = .first
    ) async throws -> String {
        return try await wallet.sendTransaction(
            network: network,
            request: request,
            feeOptionSelector: feeOptionSelector
        )
    }

    public func callContract(
        network: String,
        contract: String,
        method: String,
        args: [AbiArg]?,
        feeOptionSelector: FeeOptionSelector = .first
    ) async throws -> String {
        return try await wallet.callContract(
            network: network,
            contract: contract,
            method: method,
            args: args,
            feeOptionSelector: feeOptionSelector
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
public typealias OmsWallet = OMSClient

public typealias OmsEnvironment = OMSClientEnvironment
