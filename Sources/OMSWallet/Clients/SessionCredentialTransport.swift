import Foundation

/// Orders requests signed with the wallet session's credential: one at a time per signing
/// credential, in the order they arrive, the SDK's own expiry reads (`GetCredential`) included.
/// WaaS accepts a request only when its nonce exceeds the last one it accepted for the credential,
/// an atomic conditional write (`:nonce > LastNonce`, waas v1.2.0 data/credential.go:741,837,894).
/// Requests in flight together can reach it out of order and be rejected with 7206; one at a time,
/// each nonce is taken after the previous request completed, so none is. Nonces of different
/// credentials are independent, so a new sign-in's requests do not wait behind a request of the
/// credential it replaced. Other processes using the same credential are not covered, so the
/// transport still resends a 7206.
final class SignedRequestGate: @unchecked Sendable {
    private struct Queue {
        var isHeld = false
        /// Waiting acquirers in arrival order; a release hands the gate to the first.
        var waiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    }

    private let lock = NSLock()
    /// The queues in use, by credential ID (`nil` before the signer has a key); a queue no request
    /// holds or waits for is removed.
    private var queues: [String?: Queue] = [:]

    /// Waits for the request's turn among those of `credentialId`. Throws `CancellationError`,
    /// without holding the gate, when the task is cancelled first.
    func acquire(credentialId: String? = nil) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                // A cancellation before this point found no waiter to remove.
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                var queue = queues[credentialId] ?? Queue()
                guard queue.isHeld else {
                    queue.isHeld = true
                    queues[credentialId] = queue
                    lock.unlock()
                    continuation.resume()
                    return
                }
                queue.waiters.append((id, continuation))
                queues[credentialId] = queue
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let index = queues[credentialId]?.waiters.firstIndex { $0.id == id }
            let continuation = index.flatMap { queues[credentialId]?.waiters.remove(at: $0).continuation }
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Hands `credentialId`'s gate to its next waiter, or frees it.
    func release(credentialId: String? = nil) {
        lock.lock()
        guard var queue = queues[credentialId], !queue.waiters.isEmpty else {
            queues[credentialId] = nil
            lock.unlock()
            return
        }
        let next = queue.waiters.removeFirst()
        queues[credentialId] = queue
        lock.unlock()
        next.continuation.resume()
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

/// A transport that tells the request's `SignedRequestAttempt` when it is about to start the HTTP
/// request, after signing (see `SignedRequestAttempt.markSending()`).
protocol ReportsSendStart {}

/// Settles once whether a signed request was possibly sent or ran out of time before it could be.
/// It is possibly sent once its transport is about to start the HTTP request (for a transport that
/// does not report that, as soon as it gets its turn); a deadline before then means it is never
/// sent.
final class SignedRequestAttempt: @unchecked Sendable {
    /// The attempt of the signed request this task is sending, for its transport.
    @TaskLocal static var current: SignedRequestAttempt?

    private enum State {
        case waiting
        /// Got its turn and is being signed.
        case begun
        case sending
        case expired
    }

    private let lock = NSLock()
    private var state = State.waiting
    private let reportsSendStart: Bool

    init(reportsSendStart: Bool) {
        self.reportsSendStart = reportsSendStart
    }

    /// Whether the request may go on after getting its turn; false once its deadline has passed.
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .waiting else {
            return false
        }
        state = reportsSendStart ? .begun : .sending
        return true
    }

    /// Whether the HTTP request may start; false once its deadline has passed. A resend after a
    /// stale nonce is already sending.
    func markSending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state != .expired else {
            return false
        }
        state = .sending
        return true
    }

    /// Whether the request expired before it was possibly sent, so it never will be.
    func expire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state != .sending else {
            return false
        }
        state = .expired
        return true
    }
}

/// Resumes the caller once, with whichever settles first: its request, the request's deadline, or
/// the caller's cancellation. A result that arrives before the continuation is installed is kept
/// and delivered when it is.
private final class SignedRequestRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<WebRPCHTTPResponse, any Error>?
    private var result: Result<WebRPCHTTPResponse, any Error>?
    private var isResumed = false

    func install(_ continuation: CheckedContinuation<WebRPCHTTPResponse, any Error>) {
        lock.lock()
        guard let result else {
            self.continuation = continuation
            lock.unlock()
            return
        }
        isResumed = true
        lock.unlock()
        continuation.resume(with: result)
    }

    func settle(_ result: Result<WebRPCHTTPResponse, any Error>) {
        lock.lock()
        guard self.result == nil, !isResumed else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        if continuation != nil {
            isResumed = true
        }
        lock.unlock()
        continuation?.resume(with: result)
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
    let onResponse: @Sendable (_ response: WebRPCHTTPResponse, _ path: String, _ revision: UInt64) -> Void

    /// The most a signed request may take in all, from waiting for its turn through signing to its
    /// last response (resends included). URLSession's request timeout only limits the time between
    /// received bytes, and the gate wait has no limit of its own.
    static let requestDeadlineSeconds: TimeInterval = 30
    var deadlineSeconds = Self.requestDeadlineSeconds
    /// The credential the request will be signed with, which picks its queue in `gate`; `nil`
    /// before the signer has a key.
    var signingCredentialId: @Sendable () -> String? = { nil }

    func post(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String]
    ) async throws -> WebRPCHTTPResponse {
        let attempt = SignedRequestAttempt(reportsSendStart: base is ReportsSendStart)
        let sendRecord = RequestSendRecord.current
        // An unstructured task, so the caller gets its result at the deadline, or at once when it is
        // cancelled, even while a signer is still running; that task then ends on its own, holding
        // its turn in the gate until it does, and sends nothing (`markSending()` and the
        // cancellation check).
        let send = Task {
            try await SignedRequestAttempt.$current.withValue(attempt) {
                try await self.send(baseURL: baseURL, path: path, body: body, headers: headers, attempt: attempt)
            }
        }
        let deadlineSeconds = self.deadlineSeconds
        let race = SignedRequestRace()
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(deadlineSeconds * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            // Settled before the send is cancelled, so the caller gets the timeout and not the
            // cancellation it causes. An expired attempt is never sent: its transport's
            // `markSending()` refuses.
            if attempt.expire() {
                sendRecord?.recordFailedBeforeSending()
                race.settle(.failure(RequestNotSentError(underlying: URLError(.timedOut))))
            } else {
                // It may have reached WaaS; the caller cannot assume it did not.
                race.settle(.failure(URLError(.timedOut)))
            }
            send.cancel()
        }
        Task {
            let result = await send.result
            deadline.cancel()
            race.settle(result)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.install(continuation)
            }
        } onCancel: {
            // The caller gave up: it is answered now, and a signer still running never sends.
            _ = attempt.expire()
            race.settle(.failure(CancellationError()))
            deadline.cancel()
            send.cancel()
        }
    }

    private func send(
        baseURL: String,
        path: String,
        body: Data,
        headers: [String: String],
        attempt: SignedRequestAttempt
    ) async throws -> WebRPCHTTPResponse {
        // Read before queueing; a request signed with a key that replaced it meanwhile is ordered
        // with the old credential's, which WaaS no longer accepts anyway.
        let signingCredentialId = self.signingCredentialId
        let credentialId = try await SignerWork.run { signingCredentialId() }
        try await gate.acquire(credentialId: credentialId)
        guard attempt.begin() else {
            gate.release(credentialId: credentialId)
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
            gate.release(credentialId: credentialId)
            throw error
        }
        gate.release(credentialId: credentialId)
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
