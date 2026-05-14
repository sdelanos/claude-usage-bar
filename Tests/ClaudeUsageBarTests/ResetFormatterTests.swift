import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("ResetFormatter.format")
struct ResetFormatterTests {

    private let now = Date(timeIntervalSince1970: 1_715_000_000)

    @Test("past dates render as imminent")
    func pastIsImminent() {
        let past = now.addingTimeInterval(-60)
        #expect(ResetFormatter.format(past, now: now) == "imminently")
    }

    @Test("dates exactly at now render as imminent")
    func nowIsImminent() {
        #expect(ResetFormatter.format(now, now: now) == "imminently")
    }

    @Test("sub-hour deadlines use minutes")
    func subHourUsesMinutes() {
        let in32Min = now.addingTimeInterval(32 * 60)
        let out = ResetFormatter.format(in32Min, now: now)
        // Abbreviated style varies by macOS version ("32m" / "32 min") so we
        // only assert the surrounding shape and the magnitude.
        #expect(out.hasPrefix("in "))
        #expect(out.contains("32"))
        #expect(!out.contains(":"))   // not the absolute branch
    }

    @Test("a few hours away uses hours + minutes")
    func fewHoursAwayUsesHoursAndMinutes() {
        let in2h15 = now.addingTimeInterval(2 * 3600 + 15 * 60)
        // DateComponentsFormatter punctuation/casing depends on locale, so
        // we assert the two numeric parts rather than the exact string.
        let out = ResetFormatter.format(in2h15, now: now)
        #expect(out.contains("in "))
        #expect(out.contains("2"))
        #expect(out.contains("15"))
    }

    @Test("≥12 hours switches to absolute weekday + time")
    func farFutureUsesWeekdayTime() {
        let in13h = now.addingTimeInterval(13 * 3600)
        let out = ResetFormatter.format(in13h, now: now)
        // No "in " prefix on the absolute branch.
        #expect(!out.hasPrefix("in "))
        // We don't pin the exact string (locale-dependent) but it should
        // contain a digit-pair colon-digit-pair time fragment.
        #expect(out.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil,
                "expected an HH:MM fragment, got '\(out)'")
    }

    @Test("days-away reset still uses weekday + time")
    func daysAwayUsesWeekdayTime() {
        let in5d = now.addingTimeInterval(5 * 24 * 3600)
        let out = ResetFormatter.format(in5d, now: now)
        #expect(!out.hasPrefix("in "))
        #expect(out.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil)
    }
}
