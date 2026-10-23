import Foundation

/// Orders requests signed with the wallet session's credential. WaaS requires each request's nonce
/// to exceed the last one it accepted, so the SDK's own expiry refresh (`GetCredential`) must not
/// overlap an app request: a refresh starts only once no other signed request is in flight, and
/// signed requests that start while a refresh is pending or in flight wait for it to finish.
final class SignedRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequests = 0
    private var isRefreshActive = false
    private var pendingRefreshes = 0
    /// Blocked acquirers; each is resumed with `false` on a release and then retries.
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func acquire(isRefresh: Bool) async {
        var isPending = false
        while true {
            let acquired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                lock.lock()
                let canAcquire = isRefresh
                    ? !isRefreshActive && activeRequests == 0
                    : !isRefreshActive && pendingRefreshes == 0
                if canAcquire {
                    if isRefresh {
                        isRefreshActive = true
                        if isPending {
                            pendingRefreshes -= 1
                        }
                    } else {
                        activeRequests += 1
                    }
                    lock.unlock()
                    continuation.resume(returning: true)
                    return
                }
                if isRefresh && !isPending {
                    isPending = true
                    pendingRefreshes += 1
                }
                waiters.append(continuation)
                lock.unlock()
            }
            if acquired {
                return
            }
        }
    }

    func release(isRefresh: Bool) {
        lock.lock()
        if isRefresh {
            isRefreshActive = false
        } else {
            activeRequests -= 1
        }
        let waiters = self.waiters
        self.waiters = []
        lock.unlock()
        waiters.forEach { $0.resume(returning: false) }
    }
}

/// Wraps the transport of a client that signs with the wallet session's credential (the signed
/// WaaS client and the wallet-import client, never the public client). It applies the
/// `SignedRequestGate` and reports each response to the session, which ends itself when WaaS
/// rejects its credential.
struct SessionCredentialTransport: WebRPCTransport {
    let base: any WebRPCTransport
    let gate: SignedRequestGate
    /// The session revision when a wallet session is active, or `nil` (for example during sign-in).
    let activeSessionRevision: @Sendable () -> UInt64?
    let onResponse: @Sendable (_ response: WebRPCHTTPResponse, _ path: String, _ revision: UInt64) -> Void

    func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let isRefresh = path == WaasAPI.GetCredential.urlPath
        await gate.acquire(isRefresh: isRefresh)
        let revision = activeSessionRevision()
        let response: WebRPCHTTPResponse
        do {
            response = try await base.post(baseURL: baseURL, path: path, body: body, headers: headers)
        } catch {
            gate.release(isRefresh: isRefresh)
            throw error
        }
        gate.release(isRefresh: isRefresh)
        if let revision {
            onResponse(response, path, revision)
        }
        return response
    }
}
