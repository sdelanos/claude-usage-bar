import Foundation

/// Formats a reset deadline the way claude.ai does it:
///   - "in 32 min" / "in 2h 15m" when the reset is less than 12 hours away
///   - "Tue 06:00" (localized weekday + time) when it's further out
///   - "imminently" if the deadline is already past
///
/// Callers add their own prefix ("Resets …", etc.). The `locale:` parameter
/// is exposed so tests can pin to `en_US_POSIX` and not depend on the CI
/// runner's locale.
///
/// Formatters are allocated per call. The cost (~50 µs each) is negligible
/// at our refresh cadence and the alternative — a per-locale cache —
/// requires either an `actor` (forces `await` at every call site) or a
/// `nonisolated(unsafe)` shared map (a hazard that's hard to justify for
/// something allocated twice every five minutes).
enum ResetFormatter {
    private static let relativeThreshold: TimeInterval = 12 * 3600

    static func format(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "imminently"
        }
        if interval < relativeThreshold {
            return relative(interval, locale: locale)
        }
        return absoluteWeekdayTime(date, locale: locale)
    }

    private static func relative(_ interval: TimeInterval, locale: Locale) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return "in \(formatter.string(from: interval) ?? "—")"
    }

    private static func absoluteWeekdayTime(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("E HH:mm")
        return formatter.string(from: date)
    }
}
