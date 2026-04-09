@available(macOS 12.0, *)
public class SequenceWallet {
    let intentSender: IntentSender = IntentSender()
    
    var walletAddress: String
    var sessionPrivateKey: [UInt8]
    
    public init(walletAddress: String, sessionPrivateKey: [UInt8]) {
        self.walletAddress = walletAddress
        self.sessionPrivateKey = sessionPrivateKey
    }
    
    public func SignOut() {
        let keychain: KeychainManager = KeychainManager()
        try! keychain.delete(forKey: Constants.addressStorageKey)
        try! keychain.delete(forKey: Constants.signerStorageKey)
    }
    
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
}
