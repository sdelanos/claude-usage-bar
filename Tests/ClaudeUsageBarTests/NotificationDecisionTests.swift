import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("NotificationService.decide")
struct NotificationDecisionTests {

    private let fiveHour = NotificationService.fiveHour    // 25 % step, start 25
    private let sevenDay = NotificationService.sevenDay    // 10 % step, start 10

    @Test("below the start threshold never fires")
    func belowStartDoesNotFire() {
        let d = NotificationService.decide(
            utilization: 0.20,        // 20 %
            config: fiveHour,         // start = 25
            lastThreshold: 0,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 0)
        #expect(d.shouldNotify == false)
        #expect(d.didWindowReset == false)
    }

    @Test("crossing the first threshold fires")
    func crossingFirstThresholdFires() {
        let d = NotificationService.decide(
            utilization: 0.25,
            config: fiveHour,
            lastThreshold: 0,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 25)
        #expect(d.shouldNotify == true)
    }

    @Test("staying inside the same band doesn't refire")
    func sameBandDoesNotRefire() {
        let d = NotificationService.decide(
            utilization: 0.48,        // still in [25, 50)
            config: fiveHour,
            lastThreshold: 25,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 25)
        #expect(d.shouldNotify == false)
    }

    @Test("jumping two bands fires for the higher one only")
    func jumpFiresOnceOnTheHigherBand() {
        // 5h step is 25, so going from 0 → 60 % crosses both 25 and 50.
        // We only fire once, for the highest crossed band.
        let d = NotificationService.decide(
            utilization: 0.60,
            config: fiveHour,
            lastThreshold: 0,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 50)
        #expect(d.shouldNotify == true)
    }

    @Test("new reset stamp wipes the threshold counter")
    func newResetStampWipesThreshold() {
        // Last we saw was 75 % (last threshold band), then the API gave us a
        // new window (different resetStamp). We're now at 30 % in the new
        // window, which should fire 25 % even though 75 was just "remembered".
        let d = NotificationService.decide(
            utilization: 0.30,
            config: fiveHour,
            lastThreshold: 75,
            previousResetStamp: 1_000,
            currentResetStamp: 5_000
        )
        #expect(d.didWindowReset == true)
        #expect(d.crossed == 25)
        #expect(d.shouldNotify == true)
    }

    @Test("7-day window honors its smaller step (10)")
    func sevenDayUsesTenPercentStep() {
        let d = NotificationService.decide(
            utilization: 0.10,
            config: sevenDay,
            lastThreshold: 0,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 10)
        #expect(d.shouldNotify == true)
    }

    @Test("utilization is clamped before bucketing")
    func clampsOverOne() {
        let d = NotificationService.decide(
            utilization: 1.6,         // shouldn't happen, but defensive
            config: fiveHour,
            lastThreshold: 99,
            previousResetStamp: 1_000,
            currentResetStamp: 1_000
        )
        #expect(d.crossed == 100)
        #expect(d.shouldNotify == true)
    }
}
