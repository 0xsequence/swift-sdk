@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceWallet {
    let intentSender: IntentSender = IntentSender()
    
    /// The on-chain address of this wallet.
    public var walletAddress: String
    
    var sessionPrivateKey: [UInt8]
    
    internal init(walletAddress: String, sessionPrivateKey: [UInt8]) {
        self.walletAddress = walletAddress
        self.sessionPrivateKey = sessionPrivateKey
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
        let params = SignMessageParams(
            message: message,
            network: network,
            wallet: self.walletAddress
        )
        
        let response = await self.intentSender.SignAndSend(endpoint: "/SignMessage", signer: self.sessionPrivateKey, params: params)
        let data = try! SignMessageReturn.from(jsonString: response)
        
        return data.signature
    }
    
    public func SendTransaction(network: String, to: String, value: String) async -> String {
        let params = SendTransactionParams(
            network: network,
            to: to,
            value: value
        )
        
        let response = await self.intentSender.SignAndSend(endpoint: "/SendTransaction", signer: self.sessionPrivateKey, params: params)
        let data = try! SendTransactionReturn.from(jsonString: response)
        
        return data.txHash
    }
}
