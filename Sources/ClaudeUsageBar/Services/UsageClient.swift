import Foundation

/// Reasons a `UsageClient` call can fail.
enum UsageClientError: Error, Equatable, CustomStringConvertible {
    /// One or more required rate-limit headers were absent or unparseable.
    /// The associated value lists every header that contributed to the
    /// failure, so the user gets one diagnostic instead of N round-trips.
    case missingHeaders([String])
    /// 401 from Anthropic — the token is expired, revoked, or wrong.
    /// Surfaced as its own case so the caller can drop straight into the
    /// re-setup flow without parsing a body.
    case unauthorized
    /// The Anthropic API returned a non-2xx, non-401 response. The body is
    /// intentionally not surfaced to the user — it can echo headers /
    /// request IDs / occasionally token-bearing context; we keep the raw
    /// body only for `debugDescription` so logs can capture it without it
    /// reaching the UI.
    case httpError(status: Int, debugBody: String)
    /// `URLSession` handed us a response object that isn't HTTP.
    case invalidResponse

    var description: String {
        switch self {
        case .missingHeaders(let names):
            "Missing or unparseable headers: \(names.joined(separator: ", "))"
        case .unauthorized:
            "Token rejected (401). Re-run `claude setup-token` and paste the new token."
        case .httpError(let code, _):
            "Anthropic returned HTTP \(code). Try again in a moment."
        case .invalidResponse:
            "Anthropic returned an unexpected response shape."
        }
    }

    /// User-facing translation. See `UserFacingError`.
    var userFacing: UserFacingError {
        switch self {
        case .missingHeaders(let names):
            .init(
                message: "Anthropic didn't return the expected rate-limit headers (\(names.count) missing). Try again.",
                isRetryable: true
            )
        case .unauthorized:
            // Should never reach the .error state — UsageService catches this
            // and transitions to .needsSetup(.tokenRejected). Included for
            // completeness only.
            .init(
                message: "Token rejected. Re-run `claude setup-token`.",
                isRetryable: false
            )
        case .httpError(let code, _):
            .init(
                message: "Anthropic returned HTTP \(code). Try again in a moment.",
                isRetryable: true
            )
        case .invalidResponse:
            .init(
                message: "Unexpected response from Anthropic. Try again, or file an issue if it persists.",
                isRetryable: true
            )
        }
    }
}

/// The abstraction the rest of the app depends on. `UsageClient` is the
/// production implementation; tests inject mocks.
protocol UsageFetching: Sendable {
    func fetch(accessToken: SecretToken) async throws -> Usage
}

/// Fetches Claude API rate-limit information by sending the cheapest possible
/// `POST /v1/messages` request and parsing the response headers.
///
/// The API doesn't expose a dedicated usage endpoint, but every messages
/// response includes `anthropic-ratelimit-unified-*` headers describing the
/// caller's 5-hour and 7-day utilization. A 1-token completion against
/// `claude-haiku-4-5` costs a few tokens — negligible compared to a single
/// chat interaction.
///
/// `parse(headers:at:)` is the pure logic and is unit-tested.
/// `fetch(accessToken:)` wires it to `URLSession`.
struct UsageClient: UsageFetching {
    /// Hard-coded URL; failing this at first launch would be a build-time
    /// bug we want to catch in tests, not a runtime crash. We use an
    /// `_unsafelyUnwrapped`-equivalent guard and fall back to a sentinel
    /// rather than `!` so the binary doesn't crash if someone breaks the
    /// constant in a refactor.
    static let endpoint: URL = {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            assertionFailure("UsageClient.endpoint constant is malformed")
            return URL(fileURLWithPath: "/dev/null")
        }
        return url
    }()

    /// Per-request timeout. 15 s is long enough for a single API round-trip
    /// over flaky Wi-Fi, short enough that the menu-bar doesn't sit on `…`
    /// for the full URLSession default of 60 s.
    static let requestTimeout: TimeInterval = 15

    // MARK: - Header names

    static let h5hUtil = "anthropic-ratelimit-unified-5h-utilization"
    static let h5hReset = "anthropic-ratelimit-unified-5h-reset"
    static let h7dUtil = "anthropic-ratelimit-unified-7d-utilization"
    static let h7dReset = "anthropic-ratelimit-unified-7d-reset"
    static let hOverageStatus = "anthropic-ratelimit-unified-overage-status"
    static let hOverageReason = "anthropic-ratelimit-unified-overage-disabled-reason"

    private let session: URLSession
    private let userAgent: String

    init(session: URLSession = .shared, userAgent: String = UsageClient.defaultUserAgent) {
        self.session = session
        self.userAgent = userAgent
    }

    /// Defaults to `ClaudeUsageBar/<CFBundleShortVersionString>` so Anthropic
    /// can identify the polling client if they ever start segmenting traffic.
    static let defaultUserAgent: String = {
        let version = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "ClaudeUsageBar/\(version) (+https://github.com/sdelanos/claude-usage-bar)"
    }()

    // MARK: - Parsing

    /// Pure parser. Given an HTTP response, extracts a `Usage` snapshot or
    /// throws `.missingHeaders` listing every required header that was
    /// missing or unparseable.
    static func parse(headers response: HTTPURLResponse, at fetchedAt: Date) throws -> Usage {
        var missing: [String] = []

        func headerDouble(_ name: String) -> Double? {
            guard let raw = response.value(forHTTPHeaderField: name),
                  let value = Double(raw.trimmingCharacters(in: .whitespaces))
            else {
                missing.append(name)
                return nil
            }
            return value
        }

        func headerString(_ name: String) -> String? {
            guard let raw = response.value(forHTTPHeaderField: name)?
                .trimmingCharacters(in: .whitespaces),
                !raw.isEmpty
            else {
                missing.append(name)
                return nil
            }
            return raw
        }

        let util5 = headerDouble(h5hUtil)
        let reset5 = headerDouble(h5hReset)
        let util7 = headerDouble(h7dUtil)
        let reset7 = headerDouble(h7dReset)
        let overageRaw = headerString(hOverageStatus)

        guard let util5, let reset5, let util7, let reset7, let overageRaw else {
            throw UsageClientError.missingHeaders(missing)
        }

        let overageReason = response
            .value(forHTTPHeaderField: hOverageReason)?
            .trimmingCharacters(in: .whitespaces)

        return Usage(
            fiveHour: .init(utilization: util5, resetAt: Date(timeIntervalSince1970: reset5)),
            sevenDay: .init(utilization: util7, resetAt: Date(timeIntervalSince1970: reset7)),
            overage: .init(rawValue: overageRaw),
            overageDisabledReason: (overageReason?.isEmpty ?? true) ? nil : overageReason,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Network

    /// Sends a 1-token completion to `claude-haiku-4-5` and parses the
    /// rate-limit headers from the response. Throws `UsageClientError` on
    /// transport / HTTP failures and the underlying parsing errors.
    func fetch(accessToken: SecretToken) async throws -> Usage {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken.reveal())", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.invalidResponse
        }
        if http.statusCode == 401 {
            throw UsageClientError.unauthorized
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            // Body is kept for debugDescription / Logger, not for UI.
            let debugBody = String(data: data.prefix(2048), encoding: .utf8) ?? ""
            throw UsageClientError.httpError(status: http.statusCode, debugBody: debugBody)
        }
        return try Self.parse(headers: http, at: Date())
    }
}
