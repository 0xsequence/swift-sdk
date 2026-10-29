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

    /// With UIKit, runs `body` once protected data (the keychain) may be readable: on the main actor
    /// right away when `checkNow` is set and protected data is available, otherwise on the next
    /// `protectedDataDidBecomeAvailableNotification` or `didBecomeActiveNotification`, whichever
    /// comes first. Both are hints, not proof: the caller reads the keychain again and waits again if
    /// it still cannot. Pass `checkNow: false` right after a failed read, so a keychain that keeps
    /// failing while protected data is available is not retried in a loop. Elsewhere `body` never
    /// runs; the client retries when the session is next read.
    @discardableResult
    static func runWhenProtectedDataAvailable(
        checkNow: Bool,
        _ body: @escaping @Sendable () -> Void
    ) -> Cancel {
        #if canImport(UIKit) && !os(watchOS)
        let once = RunOnceFlag()
        let run: @Sendable () -> Void = {
            if once.claim() {
                body()
            }
        }
        let isAvailableNow: @MainActor @Sendable () -> Bool
        if checkNow {
            isAvailableNow = { @MainActor @Sendable in isProtectedDataAvailable() }
        } else {
            isAvailableNow = { @MainActor @Sendable in false }
        }
        let cancelProtectedData = runOnce(
            onNext: UIApplication.protectedDataDidBecomeAvailableNotification,
            in: .default,
            orNowIf: isAvailableNow,
            run
        )
        let cancelActivation = runOnce(onNext: UIApplication.didBecomeActiveNotification, in: .default, run)
        return {
            cancelProtectedData()
            cancelActivation()
        }
        #else
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
    /// Whether protected data is available. An app extension cannot reach the shared application,
    /// so it reports `false` and waits for the client's next session read instead.
    @MainActor
    private static func isProtectedDataAvailable() -> Bool {
        guard Bundle.main.bundleURL.pathExtension != "appex",
              let application = UIApplication.value(forKey: "sharedApplication") as? UIApplication
        else {
            return false
        }
        return application.isProtectedDataAvailable
    }

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

    /// Lets only the first of several triggers run.
    private final class RunOnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !claimed else {
                return false
            }
            claimed = true
            return true
        }
    }
}
