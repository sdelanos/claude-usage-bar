import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("Usage.humanOverageReason")
struct UsageHumanOverageReasonTests {

    private func usage(reason: String?) -> Usage {
        Usage(
            fiveHour: .init(utilization: 0.5, resetAt: .distantFuture, status: "allowed"),
            sevenDay: .init(utilization: 0.5, resetAt: .distantFuture, status: "allowed"),
            representative: .fiveHour,
            overage: .rejected,
            overageDisabledReason: reason,
            fetchedAt: Date()
        )
    }

    @Test("group_zero_credit_limit maps to organization-level message")
    func groupZeroMapsToOrgMessage() {
        #expect(usage(reason: "group_zero_credit_limit").humanOverageReason ==
                "Your organization hasn't enabled overage credits.")
    }

    @Test("personal_zero_credit_limit maps to account-level message")
    func personalZeroMapsToAccountMessage() {
        #expect(usage(reason: "personal_zero_credit_limit").humanOverageReason ==
                "You haven't enabled overage credits on your account.")
    }

    @Test("user_zero_credit_limit maps to account-level message")
    func userZeroMapsToAccountMessage() {
        #expect(usage(reason: "user_zero_credit_limit").humanOverageReason ==
                "You haven't enabled overage credits on your account.")
    }

    @Test("nil reason falls back to a generic plan message")
    func nilReasonFallsBack() {
        #expect(usage(reason: nil).humanOverageReason ==
                "Overage isn't allowed on your current plan.")
    }

    @Test("empty string is treated like nil")
    func emptyStringTreatedAsNil() {
        #expect(usage(reason: "").humanOverageReason ==
                "Overage isn't allowed on your current plan.")
    }

    @Test("unknown codes are humanized (snake_case → Title Case)")
    func unknownCodeIsHumanized() {
        #expect(usage(reason: "future_unseen_code").humanOverageReason ==
                "Future Unseen Code")
    }
}

@Suite("Usage.displayPercent")
struct UsageDisplayPercentTests {

    private func usage(representative: Usage.RepresentativeClaim,
                       five: Double,
                       seven: Double) -> Usage {
        Usage(
            fiveHour: .init(utilization: five, resetAt: .distantFuture, status: "allowed"),
            sevenDay: .init(utilization: seven, resetAt: .distantFuture, status: "allowed"),
            representative: representative,
            overage: .allowed,
            overageDisabledReason: nil,
            fetchedAt: Date()
        )
    }

    @Test("representative .fiveHour returns the 5h percentage")
    func fiveHourRepresentativeUsesFiveHour() {
        #expect(usage(representative: .fiveHour, five: 0.42, seven: 0.71).displayPercent == 42)
    }

    @Test("representative .sevenDay returns the 7d percentage")
    func sevenDayRepresentativeUsesSevenDay() {
        #expect(usage(representative: .sevenDay, five: 0.42, seven: 0.71).displayPercent == 71)
    }

    @Test("unknown representative falls back to the 5h window")
    func otherFallsBackToFiveHour() {
        #expect(usage(representative: .other("lunar_cycle"), five: 0.42, seven: 0.71).displayPercent == 42)
    }

    @Test("over-1 utilization is clamped to 100 %")
    func clampsAbove() {
        #expect(usage(representative: .fiveHour, five: 1.5, seven: 0).displayPercent == 100)
    }

    @Test("negative utilization is clamped to 0 %")
    func clampsBelow() {
        #expect(usage(representative: .fiveHour, five: -0.2, seven: 0).displayPercent == 0)
    }
}
