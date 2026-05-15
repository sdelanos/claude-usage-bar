@testable import ClaudeUsageBar
import Foundation
import Testing

/// Tests pin to `en_US_POSIX` so assertions on the relative-formatter
/// prefix ("in …") and on the abbreviated-units shape are deterministic
/// regardless of the CI runner's system locale.
@Suite("ResetFormatter.format")
struct ResetFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_715_000_000)
    private let locale = Locale(identifier: "en_US_POSIX")

    @Test("past dates render as imminent")
    func pastIsImminent() {
        let past = now.addingTimeInterval(-60)
        #expect(ResetFormatter.format(past, now: now, locale: locale) == "imminently")
    }

    @Test("dates exactly at now render as imminent")
    func nowIsImminent() {
        #expect(ResetFormatter.format(now, now: now, locale: locale) == "imminently")
    }

    @Test("sub-hour deadlines use minutes")
    func subHourUsesMinutes() {
        let in32Min = now.addingTimeInterval(32 * 60)
        let out = ResetFormatter.format(in32Min, now: now, locale: locale)
        #expect(out.hasPrefix("in "))
        #expect(out.contains("32"))
        #expect(!out.contains(":")) // not the absolute branch
    }

    @Test("a few hours away uses hours + minutes")
    func fewHoursAwayUsesHoursAndMinutes() {
        let in2h15 = now.addingTimeInterval(2 * 3600 + 15 * 60)
        let out = ResetFormatter.format(in2h15, now: now, locale: locale)
        #expect(out.contains("in "))
        #expect(out.contains("2"))
        #expect(out.contains("15"))
    }

    @Test("≥12 hours switches to absolute weekday + time")
    func farFutureUsesWeekdayTime() {
        let in13h = now.addingTimeInterval(13 * 3600)
        let out = ResetFormatter.format(in13h, now: now, locale: locale)
        #expect(!out.hasPrefix("in "))
        #expect(
            out.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil,
            "expected an HH:MM fragment, got '\(out)'"
        )
    }

    @Test("days-away reset still uses weekday + time")
    func daysAwayUsesWeekdayTime() {
        let in5d = now.addingTimeInterval(5 * 24 * 3600)
        let out = ResetFormatter.format(in5d, now: now, locale: locale)
        #expect(!out.hasPrefix("in "))
        #expect(out.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil)
    }
}
