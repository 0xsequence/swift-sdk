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
    /// Blocked acquirers; each is resumed with `false` on a release, or when its task is cancelled,
    /// and then retries or stops.
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    /// Waits for the request's turn. Throws `CancellationError`, without holding the gate, when the
    /// task is cancelled first.
    func acquire(isRefresh: Bool) async throws {
        var isPending = false
        while true {
            let id = UUID()
            let acquired = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    lock.lock()
                    // A cancellation before this point found no waiter to resume.
                    if Task.isCancelled {
                        lock.unlock()
                        continuation.resume(returning: false)
                        return
                    }
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
                    waiters[id] = continuation
                    lock.unlock()
                }
            } onCancel: {
                lock.lock()
                let continuation = waiters.removeValue(forKey: id)
                lock.unlock()
                continuation?.resume(returning: false)
            }
            if acquired {
                return
            }
            if Task.isCancelled {
                if isPending {
                    abandonPendingRefresh()
                }
                throw CancellationError()
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
        let waiters = takeWaitersLocked()
        lock.unlock()
        waiters.forEach { $0.resume(returning: false) }
    }

    /// A refresh that gives up no longer holds back the requests waiting behind it.
    private func abandonPendingRefresh() {
        lock.lock()
        pendingRefreshes -= 1
        let waiters = takeWaitersLocked()
        lock.unlock()
        waiters.forEach { $0.resume(returning: false) }
    }

    private func takeWaitersLocked() -> [CheckedContinuation<Bool, Never>] {
        let waiters = Array(self.waiters.values)
        self.waiters = [:]
        return waiters
    }
}

/// Thrown when a signed request failed before it was sent: signing failed, or its deadline passed
/// while it waited for its turn. WaaS never saw it.
struct RequestNotSentError: Error {
    let underlying: any Error
}

/// Tells the caller of a signed request whether it failed before being sent. The generated client
/// keeps only a description of a transport's error, so `RequestNotSentError` cannot reach the
/// caller as a type; `SessionCredentialTransport` records it here, in the caller's task.
final class RequestSendRecord: @unchecked Sendable {
    @TaskLocal static var current: RequestSendRecord?

    private let lock = NSLock()
    private var _failedBeforeSending = false

    var failedBeforeSending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _failedBeforeSending
    }

    func recordFailedBeforeSending() {
        lock.lock()
        defer { lock.unlock() }
        _failedBeforeSending = true
    }
}

/// Settles once whether a signed request began (got its turn, so it may be signed and sent) or
/// ran out of time first.
private final class SignedRequestAttempt: @unchecked Sendable {
    private enum State {
        case waiting
        case begun
        case expired
    }

    private let lock = NSLock()
    private var state = State.waiting

    /// Whether the request may go on; false once its deadline has passed.
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .waiting else {
            return false
        }
        state = .begun
        return true
    }

    /// Whether the request expired before it began, so it is never sent.
    func expire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .waiting else {
            return false
        }
        state = .expired
        return true
    }
}

/// Wraps the transport of a client that signs with the wallet session's credential (the signed
/// WaaS client and the wallet-import client, never the public client). It applies the
/// `SignedRequestGate`, resends a request WaaS rejected for a stale nonce, bounds the whole of it
/// by `requestDeadlineSeconds`, and reports each response to the session, which ends itself when
/// WaaS rejects its credential.
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
    /// Called once a request completes (its last response received or its error thrown), while the
    /// gate is still held: no `GetCredential` overlaps another request, so a request processed after
    /// a read completes after it.
    let onRequestCompleted: @Sendable (_ path: String) -> Void
    let onResponse: @Sendable (_ response: WebRPCHTTPResponse, _ path: String, _ revision: UInt64) -> Void

    /// The most a signed request may take in all, from waiting for its turn through signing to its
    /// last response (resends included). URLSession's request timeout only limits the time between
    /// received bytes, and the gate wait has no limit of its own.
    static let requestDeadlineSeconds: TimeInterval = 30
    var deadlineSeconds = Self.requestDeadlineSeconds

    func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let attempt = SignedRequestAttempt()
        return try await withThrowingTaskGroup(of: WebRPCHTTPResponse?.self) { group in
            group.addTask {
                try await send(baseURL: baseURL, path: path, body: body, headers: headers, attempt: attempt)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadlineSeconds * 1_000_000_000))
                return nil
            }
            // Cancelling stops the gate wait or the request, and the group waits for both to end,
            // so no late signer or wait can send anything after this returns.
            defer { group.cancelAll() }
            if case .some(.some(let response)) = try await group.next() {
                return response
            }
            if attempt.expire() {
                RequestSendRecord.current?.recordFailedBeforeSending()
                throw RequestNotSentError(underlying: URLError(.timedOut))
            }
            // It may have reached WaaS; the caller cannot assume it did not.
            throw URLError(.timedOut)
        }
    }

    private func send(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String],
        attempt: SignedRequestAttempt
    ) async throws -> WebRPCHTTPResponse {
        let isRefresh = path == WaasAPI.GetCredential.urlPath
        try await gate.acquire(isRefresh: isRefresh)
        guard attempt.begin() else {
            gate.release(isRefresh: isRefresh)
            throw CancellationError()
        }
        let revision = activeSessionRevision()
        var response: WebRPCHTTPResponse
        do {
            // The gate stays held across resends, so each fresh nonce is still taken in order.
            var retries = 0
            while true {
                response = try await base.post(baseURL: baseURL, path: path, body: body, headers: headers)
                guard retries < Self.maxStaleNonceRetries, Self.isStaleNonceRejection(response) else {
                    break
                }
                retries += 1
            }
        } catch {
            if error is RequestNotSentError {
                RequestSendRecord.current?.recordFailedBeforeSending()
            }
            onRequestCompleted(path)
            gate.release(isRefresh: isRefresh)
            throw error
        }
        onRequestCompleted(path)
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
