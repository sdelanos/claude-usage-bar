import Foundation
import UserNotifications

/// Fires a local notification each time the 5-hour or 7-day utilization crosses
/// a configured threshold (every 25 % for the session, every 10 % for the week).
///
/// State (the highest threshold already fired and the reset timestamp that
/// state belongs to) lives in UserDefaults so we don't re-notify on every
/// poll — or after a relaunch — for the same crossing. When the API reports a
/// new reset timestamp we wipe the threshold so the next window starts fresh.
enum NotificationService {

    static let fiveHourStep = 25
    static let sevenDayStep = 10
    static let fiveHourStart = 25  // smallest threshold worth notifying about
    static let sevenDayStart = 10

    /// Asks the user once for permission to display notifications. No-op on subsequent calls.
    static func bootstrap() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Inspects the latest usage snapshot and posts one notification per newly
    /// crossed threshold. Safe to call on every refresh.
    static func evaluate(usage: Usage) async {
        await evaluateWindow(
            label: "5-hour session",
            utilization: usage.fiveHour.utilization,
            resetAt: usage.fiveHour.resetAt,
            step: fiveHourStep,
            start: fiveHourStart,
            keyThreshold: Keys.fiveHourThreshold,
            keyResetStamp: Keys.fiveHourResetStamp
        )
        await evaluateWindow(
            label: "7-day window",
            utilization: usage.sevenDay.utilization,
            resetAt: usage.sevenDay.resetAt,
            step: sevenDayStep,
            start: sevenDayStart,
            keyThreshold: Keys.sevenDayThreshold,
            keyResetStamp: Keys.sevenDayResetStamp
        )
    }

    // MARK: - Internals

    private enum Keys {
        static let fiveHourThreshold = "notif.fiveHour.lastThreshold"
        static let fiveHourResetStamp = "notif.fiveHour.lastResetStamp"
        static let sevenDayThreshold = "notif.sevenDay.lastThreshold"
        static let sevenDayResetStamp = "notif.sevenDay.lastResetStamp"
    }

    private static func evaluateWindow(
        label: String,
        utilization: Double,
        resetAt: Date,
        step: Int,
        start: Int,
        keyThreshold: String,
        keyResetStamp: String
    ) async {
        let defaults = UserDefaults.standard
        let resetStamp = resetAt.timeIntervalSince1970

        // Reset the threshold whenever the API hands us a new window.
        let previousResetStamp = defaults.double(forKey: keyResetStamp)
        if abs(previousResetStamp - resetStamp) > 1.0 {
            defaults.set(resetStamp, forKey: keyResetStamp)
            defaults.set(0, forKey: keyThreshold)
        }

        let percent = Int((max(0, min(1, utilization)) * 100).rounded(.down))
        let crossed = (percent / step) * step
        let last = defaults.integer(forKey: keyThreshold)

        guard crossed >= start, crossed > last else { return }
        defaults.set(crossed, forKey: keyThreshold)

        await post(
            title: "\(label) at \(crossed)%",
            body: "Resets \(ResetFormatter.format(resetAt))."
        )
    }

    private static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
