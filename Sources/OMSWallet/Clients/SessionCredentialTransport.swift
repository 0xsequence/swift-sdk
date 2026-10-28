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
/// `SignedRequestGate`, resends a request WaaS rejected for a stale nonce, and reports each
/// response to the session, which ends itself when WaaS rejects its credential.
struct SessionCredentialTransport: WebRPCTransport {
    /// How many times a request that WaaS rejected with `PreconditionFailed` (7206, its nonce was
    /// not above the last one accepted) is signed again with a fresh nonce and resent. WaaS rejects
    /// it in its credential middleware before any handler runs, so even a rejected `Execute` had
    /// no effect.
    static let maxStaleNonceRetries = 2

    /// Signs and sends one request; each call takes a fresh nonce.
    let base: any WebRPCTransport
    let gate: SignedRequestGate
    /// The session revision when a wallet session is active, or `nil` (for example during sign-in).
    let activeSessionRevision: @Sendable () -> UInt64?
    /// Called each time a request is about to be sent, including a resend.
    let onRequestSent: @Sendable (_ path: String) -> Void
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
        var response: WebRPCHTTPResponse
        do {
            // The gate stays held across resends, so each fresh nonce is still taken in order.
            var retries = 0
            while true {
                onRequestSent(path)
                response = try await base.post(baseURL: baseURL, path: path, body: body, headers: headers)
                guard retries < Self.maxStaleNonceRetries, Self.isStaleNonceRejection(response) else {
                    break
                }
                retries += 1
            }
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

    private static func isStaleNonceRejection(_ response: WebRPCHTTPResponse) -> Bool {
        guard response.statusCode == 412 else {
            return false
        }
        let error = WaasGenerated.decodeWebRPCError(statusCode: response.statusCode, data: response.body)
        return error.code == WebRPCErrorKind.preconditionFailed.code
    }
}
