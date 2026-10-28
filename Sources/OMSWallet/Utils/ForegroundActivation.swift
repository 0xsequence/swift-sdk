import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Runs work once the app is in the foreground, without `UIApplication.shared`, so the SDK stays
/// safe to use in app extensions.
enum ForegroundActivation {
    /// Cancels work that has not run yet; does nothing once it has run.
    typealias Cancel = @Sendable () -> Void

    /// With UIKit, runs `body` soon when the app is already active, otherwise on the next
    /// `didBecomeActiveNotification`: a background launch waits for the user to open the app, and an
    /// app extension, which is never active, never runs it. Elsewhere it runs `body` now.
    @discardableResult
    static func runWhenActive(_ body: @escaping @Sendable () -> Void) -> Cancel {
        #if canImport(UIKit) && !os(watchOS)
        return runOnce(
            onNext: UIApplication.didBecomeActiveNotification,
            in: .default,
            orNowIf: isAppActive,
            body
        )
        #else
        body()
        return {}
        #endif
    }

    /// Runs `body` once: on the main actor right away when `isActive` holds there, otherwise on the
    /// next `name` posted to `center`. Cancelling stops observing without running it.
    @discardableResult
    static func runOnce(
        onNext name: Notification.Name,
        in center: NotificationCenter,
        orNowIf isActive: @escaping @MainActor @Sendable () -> Bool = { false },
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
        // The observer is registered first, so an activation in between is not missed, and
        // `take()` runs `body` only once.
        Task { @MainActor in
            guard isActive(), let token = observation.take() else {
                return
            }
            center.removeObserver(token)
            body()
        }
        return {
            if let token = observation.take() {
                center.removeObserver(token)
            }
        }
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Whether the app is in the foreground. `UIApplication.shared` is unavailable in app
    /// extensions, so the shared application is looked up by name; an extension is never active.
    @MainActor
    private static func isAppActive() -> Bool {
        guard Bundle.main.bundleURL.pathExtension != "appex",
              let application = UIApplication.value(forKey: "sharedApplication") as? UIApplication
        else {
            return false
        }
        return application.applicationState == .active
    }
    #endif

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
