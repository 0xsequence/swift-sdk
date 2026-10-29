import Foundation

/// The session's lifetime cap, learned at sign-in: WaaS never moves the session expiry past it,
/// so once it has passed the session has ended without asking.
struct SessionExpiryBounds: Equatable, Sendable {
    /// The cap N the server never moves the expiry past.
    let ceiling: Date

    /// Returns `nil` unless the value is finite.
    init?(ceilingEpochSeconds: TimeInterval?) {
        guard let ceilingEpochSeconds, ceilingEpochSeconds.isFinite else {
            return nil
        }
        self.ceiling = Date(timeIntervalSince1970: ceilingEpochSeconds)
    }

    /// Derives the cap from a `CompleteAuth` exchange: `sentAt` (C0) was taken right before the
    /// request, which asked for `requestedLifetimeSeconds` (R), and the response's credential
    /// expires at `expiresAt` (L0), so N = max(C0 + R, L0). Returns `nil` when L0 is unreadable or
    /// not after C0.
    init?(signInSentAt sentAt: Date, expiresAt: String, requestedLifetimeSeconds: UInt32) {
        guard let expiry = OMSWalletSession.parseDate(expiresAt), expiry > sentAt else {
            return nil
        }
        let ceiling = max(sentAt.addingTimeInterval(TimeInterval(requestedLifetimeSeconds)), expiry)
        self.init(ceilingEpochSeconds: ceiling.timeIntervalSince1970)
    }

    var ceilingEpochSeconds: TimeInterval {
        ceiling.timeIntervalSince1970
    }

    /// Whether the cap has passed at `now`: the session has ended, whatever WaaS would say.
    func hasPassed(at now: Date) -> Bool {
        now >= ceiling
    }
}
