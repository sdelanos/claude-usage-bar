import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("Usage.humanOverageReason")
struct UsageHumanOverageReasonTests {

    private func usage(reason: String?) -> Usage {
        Usage(
            fiveHour: .init(utilization: 0.5, resetAt: .distantFuture),
            sevenDay: .init(utilization: 0.5, resetAt: .distantFuture),
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

    @Test("unknown codes fall back to the generic plan message (no leakage of raw codes)")
    func unknownCodeFallsBack() {
        #expect(usage(reason: "future_unseen_code").humanOverageReason ==
                "Overage isn't allowed on your current plan.")
    }
}
