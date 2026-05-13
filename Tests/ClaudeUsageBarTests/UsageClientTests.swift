import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("UsageClient.parse")
struct UsageClientTests {

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

    static func nominalHeaders(representative: String = "five_hour",
                               overage: String = "allowed") -> [String: String] {
        [
            "anthropic-ratelimit-unified-5h-utilization": "0.42",
            "anthropic-ratelimit-unified-5h-reset": String(format: "%.0f", reset5h),
            "anthropic-ratelimit-unified-5h-status": "allowed",
            "anthropic-ratelimit-unified-7d-utilization": "0.71",
            "anthropic-ratelimit-unified-7d-reset": String(format: "%.0f", reset7d),
            "anthropic-ratelimit-unified-7d-status": "allowed_warning",
            "anthropic-ratelimit-unified-representative-claim": representative,
            "anthropic-ratelimit-unified-overage-status": overage
        ]
    }

    @Test("nominal headers decode and displayPercent follows 5h when representative=five_hour")
    func parseNominalFiveHourRepresentative() throws {
        let now = Date(timeIntervalSince1970: 1_714_000_000)
        let response = Self.makeResponse(Self.nominalHeaders())
        let usage = try UsageClient.parse(headers: response, at: now)

        #expect(abs(usage.fiveHour.utilization - 0.42) < 1e-9)
        #expect(abs(usage.sevenDay.utilization - 0.71) < 1e-9)
        #expect(usage.fiveHour.resetAt == Date(timeIntervalSince1970: Self.reset5h))
        #expect(usage.sevenDay.resetAt == Date(timeIntervalSince1970: Self.reset7d))
        #expect(usage.fiveHour.status == "allowed")
        #expect(usage.sevenDay.status == "allowed_warning")
        #expect(usage.representative == .fiveHour)
        #expect(usage.overage == .allowed)
        #expect(usage.overageDisabledReason == nil)
        #expect(usage.fetchedAt == now)
        #expect(usage.displayPercent == 42)
    }

    @Test("missing headers lists every required name")
    func parseMissingHeadersListsAllSixRequired() {
        let response = Self.makeResponse([:])
        let expected: Set<String> = [
            UsageClient.h5hUtil,
            UsageClient.h5hReset,
            UsageClient.h5hStatus,
            UsageClient.h7dUtil,
            UsageClient.h7dReset,
            UsageClient.h7dStatus,
            UsageClient.hRepresentative,
            UsageClient.hOverageStatus
        ]
        do {
            _ = try UsageClient.parse(headers: response, at: Date())
            Issue.record("expected missingHeaders error, got success")
        } catch let UsageClientError.missingHeaders(names) {
            #expect(Set(names) == expected,
                    "expected every required header to be reported as missing; got \(names)")
        } catch {
            Issue.record("expected UsageClientError.missingHeaders, got \(error)")
        }
    }

    @Test("representative=seven_day drives displayPercent off the 7d window")
    func parseSevenDayRepresentativeDrivesDisplayPercent() throws {
        let response = Self.makeResponse(Self.nominalHeaders(representative: "seven_day"))
        let usage = try UsageClient.parse(headers: response, at: Date())
        #expect(usage.representative == .sevenDay)
        #expect(usage.displayPercent == 71)
    }

    @Test("unknown representative falls back to the 5h window")
    func parseUnknownRepresentativeFallsBackToFiveHour() throws {
        let response = Self.makeResponse(Self.nominalHeaders(representative: "lunar_cycle"))
        let usage = try UsageClient.parse(headers: response, at: Date())
        #expect(usage.representative == .other("lunar_cycle"))
        #expect(usage.displayPercent == 42)
    }
}
