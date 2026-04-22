@available(macOS 12.0, iOS 15.0, *)
public class OmsWallet {
    let wallet: WalletClient
    let indexer: IndexerClient
    
    public init(projectAccessKey: String, environment: OmsEnvironment = OmsEnvironment()) {
        self.wallet = WalletClient(projectAccessKey: projectAccessKey, environment: environment)
        self.indexer = IndexerClient(projectAccessKey: projectAccessKey, environment: environment)
    }
    
    /// Initiates email-based OTP authentication by sending a one-time code to the given address.
    ///
    /// This method generates a new session key pair and stores the verifier state internally.
    /// After this call returns, present your OTP entry UI and pass the user's code to
    /// `completeEmailSignIn(code:walletType:)`.
    ///
    /// - Parameter email: The email address to send the one-time passcode to.
    public func signInWithEmail(email: String) async {
        await wallet.signInWithEmail(email: email)
    }
    
    /// Completes the email OTP authentication flow by verifying the code the user received.
    ///
    /// Must be called after `signInWithEmail(email:)`. The challenge and verifier from the
    /// previous step are used automatically. On success, this method also provisions a wallet
    /// of `walletType` for the authenticated user: if one already exists on the account it is
    /// loaded, otherwise a new one is created. In both cases the wallet address and session key
    /// are persisted to the keychain.
    ///
    /// - Parameters:
    ///   - code: The one-time passcode string entered by the user.
    ///   - walletType: The wallet type to load or create for this user. Defaults to `.ethereumEoa`.
    public func completeEmailSignIn(code: String, walletType: WalletType = WalletType.ethereumEoa) async {
        await wallet.completeEmailSignIn(code: code, walletType: walletType)
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

    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, any attempt to restore the session on the next launch will fail
    /// and the user will need to sign in again via `signInWithEmail(email:)`. Navigate to your
    /// sign-in screen after calling this.
    public func clearSession() {
        wallet.clearSession()
    }
    
    /// Returns a list of credentials that currently have access to this wallet.
    ///
    /// Use this to display active sessions or integrations in your app's account
    /// management UI, or to check what credentials exist before revoking one.
    ///
    /// - Returns: An array of `CredentialInfo` values representing each credential
    ///   with access to this wallet.
    public func listAccess() async -> [CredentialInfo] {
        return await wallet.listAccess()
    }

    /// Revokes access for a specific credential, preventing it from interacting
    /// with this wallet going forward.
    ///
    /// Use `listAccess()` first to retrieve the credential IDs available to revoke.
    /// This action cannot be undone — the credential will need to be re-authorized
    /// to regain access.
    ///
    /// - Parameter targetCredentialId: The unique identifier of the credential to revoke.
    public func revokeAccess(targetCredentialId: String) async {
        await wallet.revokeAccess(targetCredentialId: targetCredentialId)
    }
    
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: String, message: String) async -> String {
        return await wallet.signMessage(network: network, message: message)
    }
    
    /// Sends a native token transfer to the specified address on the given network.
    ///
    /// The transaction is submitted via the Sequence relayer, so the user does not need
    /// to hold gas tokens to cover fees.
    ///
    /// - Parameters:
    ///   - network: The network to send the transaction on (e.g., `"mainnet"`, `"polygon"`).
    ///   - to: The recipient's wallet address.
    ///   - value: The amount to send, as a string in the network's smallest denomination (e.g., wei for Ethereum).
    /// - Returns: The transaction hash of the submitted transaction.
    public func sendTransaction(network: String, to: String, value: String) async -> String {
        return await wallet.sendTransaction(network: network, to: to, value: value)
    }

    /// Calls a smart contract function with the provided parameters.
    ///
    /// Use this for any contract interaction that writes state — token transfers, NFT mints,
    /// approvals, and so on. For read-only calls that don't require a transaction, query the
    /// contract directly without this method.
    ///
    /// - Parameter params: A `CallContractRequest` describing the target contract, function
    ///   selector, ABI-encoded arguments, network, and any value to attach to the call.
    /// - Returns: The transaction hash of the submitted transaction.
    public func callContract(params: CallContractRequest) async -> String {
        return await wallet.callContract(params: params)
    }
}
