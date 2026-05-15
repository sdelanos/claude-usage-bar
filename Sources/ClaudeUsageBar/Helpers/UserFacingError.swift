import Foundation

/// A pre-translated, view-ready error.
///
/// Every error reachable from the menu-bar UI passes through `translate(_:)`
/// before it lands in `UsageService.State.error`. That guarantees:
///
/// - The user never sees raw `Error Domain=NSURLErrorDomain Code=-1009` text.
/// - No raw API response bodies (which can include `request_id` or echoed
///   headers) end up in the dropdown — only sanitized messages we wrote.
/// - The view layer can render different affordances per error class
///   without re-introspecting the underlying type (a "retry" button on
///   transient failures, a "re-auth" handoff on `unauthorized`, etc.).
///
/// New error types added to the codebase must extend `translate(_:)` to map
/// themselves; the default `default:` branch fires `assertionFailure` in
/// DEBUG so missing mappings show up under test, not under production.
struct UserFacingError: Equatable, Hashable, Sendable {
    /// Short, sentence-cased text displayed verbatim in the dropdown.
    let message: String
    /// Whether a "Retry" affordance makes sense for this error.
    let isRetryable: Bool

    init(message: String, isRetryable: Bool) {
        self.message = message
        self.isRetryable = isRetryable
    }

    /// Maps any `Error` thrown by the app into a user-ready message.
    /// Unknown types fall back to a generic message and fire
    /// `assertionFailure` in DEBUG so the gap is visible in tests.
    static func translate(_ error: Error) -> UserFacingError {
        switch error {
        case let e as UsageClientError:
            return e.userFacing
        case let e as TokenStoreError:
            return e.userFacing
        case let e as URLError:
            return translate(urlError: e)
        case is CancellationError:
            return .init(message: "Request was cancelled.", isRetryable: true)
        default:
            assertionFailure("UserFacingError.translate missing mapping for \(type(of: error)): \(error)")
            return .init(message: "Something went wrong. Try again.", isRetryable: true)
        }
    }

    private static func translate(urlError: URLError) -> UserFacingError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed:
            return .init(message: "No internet connection.", isRetryable: true)
        case .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return .init(message: "Couldn't reach Anthropic. Try again.", isRetryable: true)
        case .cancelled:
            return .init(message: "Request was cancelled.", isRetryable: true)
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return .init(message: "Couldn't verify the TLS certificate for api.anthropic.com.",
                         isRetryable: true)
        default:
            return .init(message: "Network error. Try again.", isRetryable: true)
        }
    }
}

extension UserFacingError: CustomStringConvertible {
    var description: String { message }
}
