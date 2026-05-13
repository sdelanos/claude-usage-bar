import Foundation

struct Usage: Equatable {
    struct Window: Equatable {
        let utilization: Double  // 0.0 - 1.0
        let resetAt: Date
        let status: String
    }

    let fiveHour: Window
    let sevenDay: Window
    let representative: RepresentativeClaim
    let overage: OverageStatus
    let overageDisabledReason: String?
    let fetchedAt: Date

    enum RepresentativeClaim: Equatable {
        case fiveHour
        case sevenDay
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "five_hour": self = .fiveHour
            case "seven_day": self = .sevenDay
            default: self = .other(rawValue)
            }
        }
    }

    enum OverageStatus: Equatable {
        case allowed
        case rejected
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "allowed": self = .allowed
            case "rejected": self = .rejected
            default: self = .other(rawValue)
            }
        }
    }

    /// Percent (0-100) following the representative claim.
    /// Unknown representative falls back to the 5-hour window.
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

    /// Human-readable reason why overage was refused. The API ships short
    /// snake_case codes; we translate the ones we've seen and humanize the rest.
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
