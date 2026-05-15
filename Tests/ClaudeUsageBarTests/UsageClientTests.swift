import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("UsageClient.parse")
struct UsageClientParseTests {

    static let reset5h: TimeInterval = 1_715_000_000
    static let reset7d: TimeInterval = 1_715_500_000

    static func makeResponse(_ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    static func nominalHeaders(overage: String = "allowed") -> [String: String] {
        [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-5h-reset": String(format: "%.0f", reset5h),
            "anthropic-ratelimit-unified-7d-utilization": "0.71",
            "anthropic-ratelimit-unified-7d-reset": String(format: "%.0f", reset7d),
            "anthropic-ratelimit-unified-overage-status": overage
        ]
    }

    @Test("nominal headers decode into a Usage snapshot")
    func parseNominalHeaders() throws {
        let now = Date(timeIntervalSince1970: 1_714_000_000)
        let response = Self.makeResponse(Self.nominalHeaders())
        let usage = try UsageClient.parse(headers: response, at: now)

        #expect(abs(usage.fiveHour.utilization - 0.42) < 1e-9)
        #expect(abs(usage.sevenDay.utilization - 0.71) < 1e-9)
        #expect(usage.fiveHour.resetAt == Date(timeIntervalSince1970: Self.reset5h))
        #expect(usage.sevenDay.resetAt == Date(timeIntervalSince1970: Self.reset7d))
        #expect(usage.fiveHour.percent == 42)
        #expect(usage.sevenDay.percent == 71)
        #expect(usage.overage == .allowed)
        #expect(usage.overageDisabledReason == nil)
        #expect(usage.fetchedAt == now)
    }

    @Test("missing headers lists every required name")
    func parseMissingHeadersListsRequired() {
        let response = Self.makeResponse([:])
        let required: Set<String> = [
            UsageClient.h5hUtil,
            UsageClient.h5hReset,
            UsageClient.h7dUtil,
            UsageClient.h7dReset,
            UsageClient.hOverageStatus
        ]
        do {
            _ = try UsageClient.parse(headers: response, at: Date())
            Issue.record("expected missingHeaders error, got success")
        } catch let UsageClientError.missingHeaders(names) {
            #expect(Set(names) == required,
                    "expected every required header to be reported as missing; got \(names)")
        } catch {
            Issue.record("expected UsageClientError.missingHeaders, got \(error)")
        }
    }

    @Test("overage rejected with disabled-reason is surfaced")
    func parseOverageRejected() throws {
        var headers = Self.nominalHeaders(overage: "rejected")
        headers["anthropic-ratelimit-unified-overage-disabled-reason"] = "group_zero_credit_limit"
        let usage = try UsageClient.parse(headers: Self.makeResponse(headers), at: Date())
        #expect(usage.overage == .rejected)
        #expect(usage.overageDisabledReason == "group_zero_credit_limit")
        #expect(usage.humanOverageReason == "Your organization hasn't enabled overage credits.")
    }

    @Test("unknown overage value is captured as .other(raw) for forward-compat")
    func parseUnknownOverage() throws {
        let response = Self.makeResponse(Self.nominalHeaders(overage: "metered_pay_per_use"))
        let usage = try UsageClient.parse(headers: response, at: Date())
        #expect(usage.overage == .other("metered_pay_per_use"))
    }

    @Test("utilization percent is clamped to [0, 100]")
    func percentClamped() {
        let above = Usage.Window(utilization: 1.5, resetAt: .distantFuture)
        #expect(above.percent == 100)
        let below = Usage.Window(utilization: -0.2, resetAt: .distantFuture)
        #expect(below.percent == 0)
    }
}

// MARK: - UsageClient.fetch (URLProtocol-based)

/// `URLProtocol` stub so we can drive `UsageClient.fetch` end-to-end without
/// touching the network. Each test installs a closure that returns the
/// response shape it wants, then makes a single request through a session
/// configured to use this protocol.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// `URLProtocol`-based fetch tests share a global handler, so we run them
/// serially to keep concurrent suites from clobbering each other's handler.
@Suite("UsageClient.fetch", .serialized)
struct UsageClientFetchTests {

    private func makeClient() -> (UsageClient, URLSession) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return (UsageClient(session: session, userAgent: "tests"), session)
    }

    @Test("happy path: 200 with nominal headers yields a Usage")
    func happyPath() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: UsageClient.endpoint,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: UsageClientParseTests.nominalHeaders()
            )!
            return (response, Data(#"{"id":"msg_test"}"#.utf8))
        }
        let usage = try await client.fetch(accessToken: SecretToken("sk-ant-test"))
        #expect(usage.fiveHour.percent == 42)
        #expect(usage.sevenDay.percent == 71)
    }

    @Test("401 maps to .unauthorized")
    func unauthorized() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: UsageClient.endpoint,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"{"error":"unauthenticated"}"#.utf8))
        }
        await #expect(throws: UsageClientError.unauthorized) {
            _ = try await client.fetch(accessToken: SecretToken("sk-ant-test"))
        }
    }

    @Test("non-2xx, non-401 maps to .httpError")
    func httpError() async throws {
        let (client, _) = makeClient()
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: UsageClient.endpoint,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (response, Data(#"{"error":"overloaded"}"#.utf8))
        }
        do {
            _ = try await client.fetch(accessToken: SecretToken("sk-ant-test"))
            Issue.record("expected UsageClientError.httpError")
        } catch let UsageClientError.httpError(status, body) {
            #expect(status == 503)
            #expect(body.contains("overloaded"))
        } catch {
            Issue.record("got unexpected \(error)")
        }
    }

    @Test("description for .httpError does not leak the response body")
    func httpErrorDescriptionHidesBody() {
        let error = UsageClientError.httpError(status: 500, debugBody: "secret-or-token-bearing-body")
        #expect(!error.description.contains("secret-or-token-bearing-body"))
    }
}
