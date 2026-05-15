import Foundation
import OSLog
import UserNotifications

/// Posts a local notification each time the 5-hour or 7-day utilization
/// crosses a configured threshold (every 25 % for the session, every 10 % for
/// the week).
///
/// Threshold-crossing state (the highest level already announced and the
/// reset timestamp that state belongs to) is persisted in `UserDefaults` so
/// the app doesn't re-notify on every poll — or after a relaunch — for the
/// same crossing. When the API reports a new reset timestamp the threshold
/// counter resets so the next window starts fresh.
///
/// The pure decision logic lives in `decide(...)` and is unit-tested; the
/// `evaluate(usage:)` entry point only wires it up to `UserDefaults` and
/// `UNUserNotificationCenter`.
///
/// Pinned to `@MainActor` so the `UserDefaults` read/write pair and the
/// authorization-state cache stay coherent under Swift 6 strict concurrency.
@MainActor
enum NotificationService {
    // MARK: - Public configuration

    /// Window-specific thresholds.
    struct WindowConfig {
        /// Smallest crossing worth notifying about.
        let start: Int
        /// Distance between consecutive notifications.
        let step: Int
        /// Label used in the notification title.
        let label: String
        /// Stable identifier prefix used so notifications de-duplicate
        /// on the macOS Notification Center side.
        let identifierPrefix: String
    }

    nonisolated static let fiveHour = WindowConfig(
        start: 25, step: 25,
        label: "5-hour session",
        identifierPrefix: "threshold.five-hour"
    )
    nonisolated static let sevenDay = WindowConfig(
        start: 10, step: 10,
        label: "7-day window",
        identifierPrefix: "threshold.seven-day"
    )

    // MARK: - Lifecycle

    private static let log = Logger(subsystem: "dev.claude-usage-bar.app", category: "notify")
    /// Cached authorization grant — set by `bootstrap()`. We gate every
    /// `post` on this so we don't fire `add(_:)` 200 times a day for a
    /// silent permission.
    private static var isAuthorized: Bool = false

    /// Asks the user once for permission to display notifications. macOS
    /// only shows the prompt the first time; subsequent calls just read
    /// back the cached grant.
    static func bootstrap() async {
        do {
            isAuthorized = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            log.debug("notif authorization: \(isAuthorized, privacy: .public)")
        } catch {
            log.error("notif auth request failed: \(error.localizedDescription, privacy: .public)")
            isAuthorized = false
        }
    }

    /// Inspects the latest usage snapshot and posts one notification per
    /// newly crossed threshold. Safe to call on every refresh.
    static func evaluate(usage: Usage) async {
        await evaluateWindow(
            config: fiveHour,
            utilization: usage.fiveHour.utilization,
            resetAt: usage.fiveHour.resetAt,
            keys: Keys.fiveHour
        )
        await evaluateWindow(
            config: sevenDay,
            utilization: usage.sevenDay.utilization,
            resetAt: usage.sevenDay.resetAt,
            keys: Keys.sevenDay
        )
    }

    // MARK: - Pure decision logic (unit-tested)

    /// What `evaluate` should do for a single window given its current state.
    struct Decision: Equatable {
        /// Highest threshold the current utilization crosses, rounded down
        /// to the nearest `step` (0, 25, 50, … or 0, 10, 20, …).
        let crossed: Int
        /// `true` when we should post a notification now.
        let shouldNotify: Bool
        /// `true` when the API reset timestamp changed, meaning the persisted
        /// threshold counter should be cleared before storing `crossed`.
        let didWindowReset: Bool
    }

    /// Pure function — given the inputs, returns what to do. No side
    /// effects, so the threshold-crossing rules can be tested exhaustively.
    /// `nonisolated` so tests can call it synchronously from non-MainActor
    /// contexts.
    nonisolated static func decide(
        utilization: Double,
        config: WindowConfig,
        lastThreshold: Int,
        previousResetStamp: TimeInterval,
        currentResetStamp: TimeInterval
    ) -> Decision {
        let didWindowReset = abs(previousResetStamp - currentResetStamp) > 1.0
        let effectiveLast = didWindowReset ? 0 : lastThreshold

        let clamped = max(0, min(1, utilization))
        let percent = Int((clamped * 100).rounded(.down))
        let crossed = (percent / config.step) * config.step

        let shouldNotify = crossed >= config.start && crossed > effectiveLast

        return Decision(
            crossed: crossed,
            shouldNotify: shouldNotify,
            didWindowReset: didWindowReset
        )
    }

    // MARK: - Internals

    private struct WindowKeys {
        let threshold: String
        let resetStamp: String
    }

    private enum Keys {
        static let fiveHour = WindowKeys(
            threshold: "notif.fiveHour.lastThreshold",
            resetStamp: "notif.fiveHour.lastResetStamp"
        )
        static let sevenDay = WindowKeys(
            threshold: "notif.sevenDay.lastThreshold",
            resetStamp: "notif.sevenDay.lastResetStamp"
        )
    }

    private static func evaluateWindow(
        config: WindowConfig,
        utilization: Double,
        resetAt: Date,
        keys: WindowKeys
    ) async {
        let defaults = UserDefaults.standard
        let decision = decide(
            utilization: utilization,
            config: config,
            lastThreshold: defaults.integer(forKey: keys.threshold),
            previousResetStamp: defaults.double(forKey: keys.resetStamp),
            currentResetStamp: resetAt.timeIntervalSince1970
        )

        if decision.didWindowReset {
            defaults.set(resetAt.timeIntervalSince1970, forKey: keys.resetStamp)
            defaults.set(0, forKey: keys.threshold)
        }

        guard decision.shouldNotify else { return }

        defaults.set(decision.crossed, forKey: keys.threshold)
        await post(
            identifier: "\(config.identifierPrefix).\(decision.crossed)",
            title: "\(config.label) at \(decision.crossed)%",
            body: "Resets \(ResetFormatter.format(resetAt))."
        )
    }

    private static func post(identifier: String, title: String, body: String) async {
        guard isAuthorized else {
            log.debug("skipping post (not authorized): \(identifier, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            log.error("notif add failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
