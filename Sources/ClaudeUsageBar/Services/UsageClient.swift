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
    /// truncated to 200 chars in the description so it stays readable in the
    /// UI.
    case httpError(Int, String)
    /// `URLSession` handed us a response object that isn't HTTP.
    case invalidResponse

    var description: String {
        switch self {
        case .missingHeaders(let names):
            return "Missing or unparseable headers: \(names.joined(separator: ", "))"
        case .unauthorized:
            return "Token rejected (401). Re-run `claude setup-token` and paste the new token."
        case .httpError(let code, let body):
            let trimmed = body.count > 200 ? String(body.prefix(200)) + "…" : body
            return "HTTP \(code): \(trimmed)"
        case .invalidResponse:
            return "Invalid HTTP response."
        }
    }
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
/// `parse(headers:at:)` is the pure logic and is unit-tested. `fetch(...)`
/// wires it to `URLSession`.
struct UsageClient {

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Header names

    static let h5hUtil         = "anthropic-ratelimit-unified-5h-utilization"
    static let h5hReset        = "anthropic-ratelimit-unified-5h-reset"
    static let h5hStatus       = "anthropic-ratelimit-unified-5h-status"
    static let h7dUtil         = "anthropic-ratelimit-unified-7d-utilization"
    static let h7dReset        = "anthropic-ratelimit-unified-7d-reset"
    static let h7dStatus       = "anthropic-ratelimit-unified-7d-status"
    static let hRepresentative = "anthropic-ratelimit-unified-representative-claim"
    static let hOverageStatus  = "anthropic-ratelimit-unified-overage-status"
    static let hOverageReason  = "anthropic-ratelimit-unified-overage-disabled-reason"

    // MARK: - Parsing

    /// Pure parser. Given an HTTP response, extracts a `Usage` snapshot or
    /// throws `.missingHeaders` listing every required header that was
    /// missing or unparseable.
    static func parse(headers response: HTTPURLResponse, at fetchedAt: Date) throws -> Usage {
        var missing: [String] = []

        func headerDouble(_ name: String) -> Double? {
            guard let raw = response.value(forHTTPHeaderField: name),
                  let value = Double(raw.trimmingCharacters(in: .whitespaces)) else {
                missing.append(name)
                return nil
            }
            return value
        }

        func headerString(_ name: String) -> String? {
            guard let raw = response.value(forHTTPHeaderField: name)?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else {
                missing.append(name)
                return nil
            }
            return raw
        }

        let util5            = headerDouble(h5hUtil)
        let reset5           = headerDouble(h5hReset)
        let status5          = headerString(h5hStatus)
        let util7            = headerDouble(h7dUtil)
        let reset7           = headerDouble(h7dReset)
        let status7          = headerString(h7dStatus)
        let representativeRaw = headerString(hRepresentative)
        let overageRaw       = headerString(hOverageStatus)

        if !missing.isEmpty {
            throw UsageClientError.missingHeaders(missing)
        }

        let overageReason = response
            .value(forHTTPHeaderField: hOverageReason)?
            .trimmingCharacters(in: .whitespaces)

        return Usage(
            fiveHour: .init(
                utilization: util5!,
                resetAt: Date(timeIntervalSince1970: reset5!),
                status: status5!
            ),
            sevenDay: .init(
                utilization: util7!,
                resetAt: Date(timeIntervalSince1970: reset7!),
                status: status7!
            ),
            representative: .init(rawValue: representativeRaw!),
            overage: .init(rawValue: overageRaw!),
            overageDisabledReason: (overageReason?.isEmpty ?? true) ? nil : overageReason,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Network

    /// Sends a 1-token completion to `claude-haiku-4-5` and parses the
    /// rate-limit headers from the response. Throws `UsageClientError` on
    /// transport / HTTP failures and the underlying parsing errors.
    ///
    /// - Parameters:
    ///   - accessToken: OAuth bearer token from the Claude Code Keychain entry.
    ///   - session: injection point for tests; defaults to `URLSession.shared`.
    func fetch(accessToken: String, session: URLSession = .shared) async throws -> Usage {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw UsageClientError.httpError(http.statusCode, text)
        }
        return try Self.parse(headers: http, at: Date())
    }
}
