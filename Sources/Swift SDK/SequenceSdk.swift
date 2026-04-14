@available(macOS 12.0, *)
@available(iOS 15.0, *)
public class SequenceSdk {
    public let wallet: SequenceWalletClient
    
    public init(projectAccessKey: String) {
        self.wallet = SequenceWalletClient(projectAccessKey: projectAccessKey)
    }
}
