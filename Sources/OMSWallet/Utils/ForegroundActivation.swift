import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Runs work once the app is in the foreground, without `UIApplication.shared`, so the SDK stays
/// safe to use in app extensions.
enum ForegroundActivation {
    /// Cancels work that has not run yet; does nothing once it has run.
    typealias Cancel = @Sendable () -> Void

    /// With UIKit, runs `body` on the next `didBecomeActiveNotification`: a background launch
    /// waits for the user to open the app, and an app extension, which never receives it, never
    /// runs it. Elsewhere it runs `body` now.
    @discardableResult
    static func runWhenActive(_ body: @escaping @Sendable () -> Void) -> Cancel {
        #if canImport(UIKit) && !os(watchOS)
        return runOnce(onNext: UIApplication.didBecomeActiveNotification, in: .default, body)
        #else
        body()
        return {}
        #endif
    }

    /// Runs `body` once, on the next `name` posted to `center`, then stops observing. Cancelling
    /// stops observing without running it.
    @discardableResult
    static func runOnce(
        onNext name: Notification.Name,
        in center: NotificationCenter,
        _ body: @escaping @Sendable () -> Void
    ) -> Cancel {
        let observation = Observation()
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            guard let token = observation.take() else {
                return
            }
            center.removeObserver(token)
            body()
        }
        observation.set(token)
        return {
            if let token = observation.take() {
                center.removeObserver(token)
            }
        }
    }

    /// Holds the observer token until the first notification takes it. A notification that
    /// arrives before the token is stored leaves the work for the next one.
    private final class Observation: @unchecked Sendable {
        private let lock = NSLock()
        private var token: (any NSObjectProtocol)?
        private var isTaken = false

        func set(_ token: any NSObjectProtocol) {
            lock.lock()
            defer { lock.unlock() }
            if !isTaken {
                self.token = token
            }
        }

        func take() -> (any NSObjectProtocol)? {
            lock.lock()
            defer { lock.unlock() }
            guard !isTaken, let token else {
                return nil
            }
            isTaken = true
            self.token = nil
            return token
        }
    }
}
