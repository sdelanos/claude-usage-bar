import Foundation

enum UsageClientError: Error, CustomStringConvertible, Equatable {
    case missingHeaders([String])
    case httpError(Int, String)
    case invalidResponse

    var description: String {
        switch self {
        case .missingHeaders(let names):
            return "Missing or unparseable headers: \(names.joined(separator: ", "))"
        case .httpError(let code, let body):
            let trimmed = body.count > 200 ? String(body.prefix(200)) + "…" : body
            return "HTTP \(code): \(trimmed)"
        case .invalidResponse:
            return "Invalid HTTP response."
        }
    }
}

struct UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // Header names
    static let h5hUtil = "anthropic-ratelimit-unified-5h-utilization"
    static let h5hReset = "anthropic-ratelimit-unified-5h-reset"
    static let h5hStatus = "anthropic-ratelimit-unified-5h-status"
    static let h7dUtil = "anthropic-ratelimit-unified-7d-utilization"
    static let h7dReset = "anthropic-ratelimit-unified-7d-reset"
    static let h7dStatus = "anthropic-ratelimit-unified-7d-status"
    static let hRepresentative = "anthropic-ratelimit-unified-representative-claim"
    static let hOverageStatus = "anthropic-ratelimit-unified-overage-status"
    static let hOverageReason = "anthropic-ratelimit-unified-overage-disabled-reason"

    /// Pure parser — testable without network. Throws `.missingHeaders` listing every required header that
    /// was absent or unparseable, so failures are diagnosable in one shot.
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

        let util5 = headerDouble(h5hUtil)
        let reset5 = headerDouble(h5hReset)
        let status5 = headerString(h5hStatus)
        let util7 = headerDouble(h7dUtil)
        let reset7 = headerDouble(h7dReset)
        let status7 = headerString(h7dStatus)

        // The representative claim and overage status are required to render meaningfully.
        let representativeRaw = headerString(hRepresentative)
        let overageRaw = headerString(hOverageStatus)

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

    /// Sends the cheapest possible message (1-token completion) and parses the rate-limit headers.
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
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw UsageClientError.httpError(http.statusCode, text)
        }
        return try Self.parse(headers: http, at: Date())
    }
}
