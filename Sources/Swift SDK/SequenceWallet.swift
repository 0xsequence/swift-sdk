@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceWallet {
    let signedClient: WaasWalletClient
    let intentSender: IntentSender = IntentSender()
    
    /// The on-chain address of this wallet.
    public var walletAddress: String
    
    var sessionPrivateKey: [UInt8]
    
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
    public func SignOut() {
        let keychain: KeychainManager = KeychainManager()
        try! keychain.delete(forKey: Constants.addressStorageKey)
        try! keychain.delete(forKey: Constants.signerStorageKey)
    }
    
    /// Signs an arbitrary message using the wallet's session key.
    ///
    /// - Parameters:
    ///   - network: The network identifier for the signing context (e.g. `"mainnet"`, `"polygon"`).
    ///   - message: The plaintext message to sign.
    /// - Returns: A hex-encoded signature string.
    public func SignMessage(network: String, message: String) async -> String {
        let params = SignMessageRequest(
            network: network,
            wallet: self.walletAddress,
            message: message
        )
        
        let response = await try! signedClient.signMessage(params)
        return response.signature
    }
    
    public func SendTransaction(network: String, to: String, value: String) async -> String {
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
    
    public func CallContract(params: CallContractRequest) async -> String {
        let response = await try! signedClient.callContract(params)
        return response.txHash
    }
}
