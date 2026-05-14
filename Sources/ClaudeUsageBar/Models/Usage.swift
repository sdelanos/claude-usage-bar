import Foundation

/// A point-in-time snapshot of the caller's Claude API rate-limit usage,
/// decoded from the `anthropic-ratelimit-unified-*` response headers.
///
/// This is a pure value type — no SwiftUI dependencies, no I/O. The actual
/// decoding lives in `UsageClient.parse(headers:at:)`.
struct Usage: Equatable {

    /// One rolling-window slice — either the 5-hour session or the 7-day total.
    struct Window: Equatable {
        /// Fraction of the limit already consumed, clamped by the API to `[0, 1]`.
        let utilization: Double
        /// Wall-clock moment the window resets and `utilization` returns to 0.
        let resetAt: Date
        /// Raw status string from the API (`allowed`, `allowed_warning`, …) —
        /// reserved for future per-window UX, currently displayed only on the
        /// dropdown in passing.
        let status: String
    }

    /// Which window the API currently considers the binding constraint.
    /// Useful when only one number can fit (the menu-bar label *used* to
    /// surface this; the UI now shows both, but the field is still part of
    /// the snapshot for completeness).
    enum RepresentativeClaim: Equatable {
        case fiveHour
        case sevenDay
        /// Any other value the API might add in the future; kept as a raw
        /// string so the app doesn't break when Anthropic ships a new enum.
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "five_hour": self = .fiveHour
            case "seven_day": self = .sevenDay
            default:          self = .other(rawValue)
            }
        }
    }

    /// Whether the account is currently allowed to spend beyond the quota.
    enum OverageStatus: Equatable {
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
    let representative: RepresentativeClaim
    let overage: OverageStatus
    /// API-supplied code explaining why overage was refused (e.g. `group_zero_credit_limit`).
    /// `nil` when the field is absent or when overage is `.allowed`.
    let overageDisabledReason: String?
    /// When the snapshot was captured client-side — used for "Last updated" in the UI.
    let fetchedAt: Date

    /// Percent (0-100) following the representative claim. Falls back to the
    /// 5-hour window when the API reports an unknown representative.
    var displayPercent: Int {
        let frac: Double
        switch representative {
        case .sevenDay:
            frac = sevenDay.utilization
        case .fiveHour, .other:
            frac = fiveHour.utilization
        }
        return Int((max(0, min(1, frac)) * 100).rounded())
    }

    /// Plain-English version of `overageDisabledReason`. Known codes are
    /// hand-translated; unknown codes are humanized by replacing underscores
    /// with spaces and capitalizing — so a never-before-seen reason still
    /// reads acceptably in the overage banner.
    var humanOverageReason: String {
        switch overageDisabledReason {
        case "group_zero_credit_limit":
            return "Your organization hasn't enabled overage credits."
        case "personal_zero_credit_limit", "user_zero_credit_limit":
            return "You haven't enabled overage credits on your account."
        case .some(let raw) where !raw.isEmpty:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return "Overage isn't allowed on your current plan."
        }
    }
}
