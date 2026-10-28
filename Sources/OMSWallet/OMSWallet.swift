import Foundation

@available(macOS 12.0, iOS 15.0, *)
public final class OMSWallet: Sendable {
    public let wallet: WalletClient
    public let indexer: IndexerClient

    /// Creating `OMSWallet` again for the same project and environment returns the same `wallet`:
    /// one session, active wallet, expiry timer, and set of observers per project in the process,
    /// so instances cannot drift apart. A publishable key with another key ID for the same project
    /// (a rotated key) keeps that session and is used for later requests. Another project or
    /// environment is a separate session.
    public convenience init(publishableKey: String) throws {
        let parsedKey = try parsePublishableKey(publishableKey)
        self.init(
            publishableKey: publishableKey,
            parsedKey: parsedKey,
            environment: parsedKey.environment()
        )
    }

    init(
        publishableKey: String,
        parsedKey: ParsedPublishableKey,
        environment: OMSWalletEnvironment,
        registry: WalletClientRegistry = .shared
    ) {
        let wallet = registry.client(
            scope: Constants.sessionScopeKey(environment: environment, scope: parsedKey.projectId),
            publishableKey: publishableKey
        ) {
            WalletClient(
                publishableKey: publishableKey,
                projectId: parsedKey.projectId,
                environment: environment,
                walletImportTrustedPcr0s: parsedKey.walletImportTrustedPcr0s
            )
        }
        self.wallet = wallet
        // Shares the wallet's publishable key, so it follows a rotated key too.
        self.indexer = wallet.indexerClient
    }

}

/// The process's `WalletClient`s, one per session scope (`Constants.sessionScopeKey`). Entries live
/// as long as the process, as the session they hold does; there is one per project and
/// environment the app uses.
@available(macOS 12.0, iOS 15.0, *)
final class WalletClientRegistry: @unchecked Sendable {
    static let shared = WalletClientRegistry()

    private let lock = NSLock()
    private var clients: [String: WalletClient] = [:]

    /// The client for `scope`, made with `makeClient` the first time. A later caller's
    /// `publishableKey` replaces the client's for later requests. The client is made under the
    /// lock, so concurrent callers for one scope get one client and one restore.
    func client(
        scope: String,
        publishableKey: String,
        makeClient: () -> WalletClient
    ) -> WalletClient {
        lock.lock()
        defer { lock.unlock() }
        if let client = clients[scope] {
            client.adoptPublishableKey(publishableKey)
            return client
        }
        let client = makeClient()
        clients[scope] = client
        return client
    }
}
