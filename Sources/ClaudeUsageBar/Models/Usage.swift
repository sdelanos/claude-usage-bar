import Foundation

/// A point-in-time snapshot of the caller's Claude API rate-limit usage,
/// decoded from the `anthropic-ratelimit-unified-*` response headers.
///
/// Pure value type — no SwiftUI dependencies, no I/O. The actual decoding
/// lives in `UsageClient.parse(headers:at:)`.
struct Usage: Equatable, Sendable {

    /// One rolling-window slice — either the 5-hour session or the 7-day total.
    struct Window: Equatable, Sendable {
        /// Fraction of the limit already consumed, clamped by the API to `[0, 1]`.
        let utilization: Double
        /// Wall-clock moment the window resets and `utilization` returns to 0.
        let resetAt: Date

        /// Utilization rendered as an integer percent in `[0, 100]`. Clamps
        /// out-of-range API values so the UI never displays "-5 %" or "103 %".
        var percent: Int {
            Int((max(0, min(1, utilization)) * 100).rounded())
        }
    }

    /// Whether the account is currently allowed to spend beyond the quota.
    enum OverageStatus: Equatable, Sendable {
        case allowed
        case rejected
        /// Forward-compat for future API values.
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "allowed":  self = .allowed
            case "rejected": self = .rejected
            default:         self = .other(rawValue)
            }
        }
    }

    let fiveHour: Window
    let sevenDay: Window
    let overage: OverageStatus
    /// API-supplied code explaining why overage was refused
    /// (e.g. `group_zero_credit_limit`). `nil` when the field is absent or
    /// when overage is `.allowed`.
    let overageDisabledReason: String?
    /// When the snapshot was captured client-side — used for "Last updated"
    /// in the UI.
    let fetchedAt: Date

    /// Plain-English version of `overageDisabledReason`. Known codes are
    /// hand-translated; anything else falls back to a generic message
    /// (we don't humanize the raw code to avoid exposing internal Anthropic
    /// taxonomy if it changes unexpectedly).
    var humanOverageReason: String {
        switch overageDisabledReason {
        case "group_zero_credit_limit":
            return "Your organization hasn't enabled overage credits."
        case "personal_zero_credit_limit", "user_zero_credit_limit":
            return "You haven't enabled overage credits on your account."
        default:
            return "Overage isn't allowed on your current plan."
        }
    }
}
