import Foundation

/// How far WaaS can slide the session expiry, learned at sign-in. Each request signed with the
/// session credential at time t moves the server's expiry toward min(t + idle window, ceiling)
/// and never past it, so after a last request sent at A the server's expiry is at most
/// max(current expiry, min(A + idle window, ceiling)).
struct SessionExpiryBounds: Equatable, Sendable {
    /// The server's idle window I: how far past a request the server moves the expiry.
    let idleWindowSeconds: TimeInterval
    /// The hard ceiling N the server never moves the expiry past.
    let ceiling: Date

    /// Returns `nil` unless the idle window is positive and both values are finite.
    init?(idleWindowSeconds: TimeInterval?, ceilingEpochSeconds: TimeInterval?) {
        guard let idleWindowSeconds, let ceilingEpochSeconds,
              idleWindowSeconds.isFinite, idleWindowSeconds > 0,
              ceilingEpochSeconds.isFinite else {
            return nil
        }
        self.idleWindowSeconds = idleWindowSeconds
        self.ceiling = Date(timeIntervalSince1970: ceilingEpochSeconds)
    }

    /// Derives the bounds from a `CompleteAuth` exchange: `sentAt` (C0) was taken right before the
    /// request, which asked for `requestedLifetimeSeconds` (R), and the response's credential
    /// expires at `expiresAt` (L0). Sign-in sets the expiry to exactly min(C0 + I, N), so
    /// I = L0 - C0 and N = max(C0 + R, L0). Returns `nil` when L0 is unreadable or I is not
    /// positive.
    init?(signInSentAt sentAt: Date, expiresAt: String, requestedLifetimeSeconds: UInt32) {
        guard let expiry = OMSWalletSession.parseDate(expiresAt) else {
            return nil
        }
        let ceiling = max(sentAt.addingTimeInterval(TimeInterval(requestedLifetimeSeconds)), expiry)
        self.init(
            idleWindowSeconds: expiry.timeIntervalSince(sentAt),
            ceilingEpochSeconds: ceiling.timeIntervalSince1970
        )
    }

    var ceilingEpochSeconds: TimeInterval {
        ceiling.timeIntervalSince1970
    }
}
