import Foundation

/// Formats a reset deadline the way claude.ai does it:
///   - "in 32 min" / "in 2h 15m" when the reset is less than 12 hours away
///   - "Tue 06:00" (localized weekday + time) when it's further out
///   - "imminently" if the deadline is already past
///
/// Callers add their own prefix ("Resets …", etc.).
enum ResetFormatter {

    private static let relativeThreshold: TimeInterval = 12 * 3600

    static func format(_ date: Date, now: Date = Date()) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "imminently"
        }
        if interval < relativeThreshold {
            return relative(interval)
        }
        return absoluteWeekdayTime(date)
    }

    private static func relative(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return "in \(formatter.string(from: interval) ?? "—")"
    }

    private static func absoluteWeekdayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("E HH:mm")
        return formatter.string(from: date)
    }
}
