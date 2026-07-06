import Foundation
import OMSWalletWaas

struct PendingWalletSelectionSession {
    let id: UUID
    let signerCredentialId: String
    let signerKeyType: SigningAlgorithm
    let metadata: SessionMetadata
}
