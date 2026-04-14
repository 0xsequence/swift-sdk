@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceWallet {
    let signedClient: WaasWalletClient
    
    /// The on-chain address of this wallet.
    public let walletAddress: String
    
    let sessionPrivateKey: [UInt8]
    
    internal init(walletAddress: String, sessionPrivateKey: [UInt8]) {
        self.walletAddress = walletAddress
        self.sessionPrivateKey = sessionPrivateKey
        self.signedClient = WaasWalletClient(
            baseURL: Constants.apiUrl,
            transport: SignedWaasTransport(privateKey: sessionPrivateKey),
            headers: { [:] }
        )
    }
    
    /// Clears the wallet session from the device keychain.
    ///
    /// After calling this, `SequenceConnector.RestoreSession()` will return `nil` and
    /// the user will need to sign in again. Navigate to your sign-in screen after calling this.
    public func signOut() {
        let keychain: KeychainManager = KeychainManager()
        try! keychain.delete(forKey: Constants.addressStorageKey)
        try! keychain.delete(forKey: Constants.signerStorageKey)
    }
    
    /// Returns a list of credentials that currently have access to this wallet.
    ///
    /// Use this to display active sessions or integrations in your app's account
    /// management UI, or to check what credentials exist before revoking one.
    ///
    /// - Returns: An array of `CredentialInfo` values representing each credential
    ///   with access to this wallet.
    public func listAccess() async -> [CredentialInfo] {
        let params = ListAccessRequest(
            walletAddress: self.walletAddress
        )
        
        let response = try! await signedClient.listAccess(params)
        return response.credentials
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
        let params = RevokeAccessRequest(
            targetCredentialId: targetCredentialId,
            walletAddress: self.walletAddress
        )
        
        try! await signedClient.revokeAccess(params)
    }
    
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func signMessage(network: String, message: String) async -> String {
        let params = SignMessageRequest(
            network: network,
            wallet: self.walletAddress,
            message: message
        )
        
        let response = await try! signedClient.signMessage(params)
        return response.signature
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
        let params = SendTransactionRequest(
            network: network,
            wallet: self.walletAddress,
            to: to,
            value: value,
            mode: TransactionMode.relayer
        )
        
        let response = await try! signedClient.sendTransaction(params)
        return response.txHash
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
        let response = await try! signedClient.callContract(params)
        return response.txHash
    }
}
