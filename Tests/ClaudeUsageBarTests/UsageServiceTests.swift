@testable import ClaudeUsageBar
import Foundation
import Testing

/// State-machine tests for `UsageService`.
///
/// Both `TokenStoring` and `UsageFetching` are mocked, so these tests run
/// in a few milliseconds and never touch the keychain or the network.
@MainActor
@Suite("UsageService state machine")
struct UsageServiceTests {
    // MARK: - Fixtures

    private let validToken = "sk-ant-oat01-" + String(repeating: "A", count: 80)

    private let sampleUsage = Usage(
        fiveHour: .init(utilization: 0.42, resetAt: .distantFuture),
        sevenDay: .init(utilization: 0.71, resetAt: .distantFuture),
        overage: .allowed,
        overageDisabledReason: nil,
        fetchedAt: Date()
    )

    private func makeService(
        token: String? = nil,
        fetchResult: Result<Usage, Error> = .failure(URLError(.unknown))
    ) -> (UsageService, MockUsageFetcher) {
        let store = InMemoryTokenStore(token)
        let fetcher = MockUsageFetcher(result: fetchResult)
        let service = UsageService(
            tokenStore: store,
            usageFetcher: fetcher,
            bootstrapNotifications: {},
            evaluateNotifications: { _ in }
        )
        return (service, fetcher)
    }

    // MARK: - refresh()

    @Test("no token saved → needsSetup(.notConfigured)")
    func noTokenLandsInNeedsSetup() async {
        let (service, _) = makeService(token: nil, fetchResult: .success(sampleUsage))
        await service.refresh()
        #expect(service.state == .needsSetup(.notConfigured))
    }

    @Test("token + happy path → loaded(usage)")
    func happyPathLoadsUsage() async {
        let (service, _) = makeService(token: validToken, fetchResult: .success(sampleUsage))
        await service.refresh()
        #expect(service.state == .loaded(sampleUsage))
    }

    @Test("token + 401 → needsSetup(.tokenRejected)")
    func unauthorizedSwitchesToSetup() async {
        let (service, _) = makeService(
            token: validToken,
            fetchResult: .failure(UsageClientError.unauthorized)
        )
        await service.refresh()
        #expect(service.state == .needsSetup(.tokenRejected))
    }

    @Test("token + network error → .error with user-facing message")
    func networkErrorTranslatesUserFacing() async {
        let (service, _) = makeService(
            token: validToken,
            fetchResult: .failure(URLError(.notConnectedToInternet))
        )
        await service.refresh()
        guard case .error(let userFacing) = service.state else {
            Issue.record("expected .error, got \(service.state)")
            return
        }
        #expect(userFacing.message == "No internet connection.")
        #expect(userFacing.isRetryable)
    }

    @Test("token + HTTP 503 → .error, message does not leak the response body")
    func httpErrorDoesNotLeakBody() async {
        let (service, _) = makeService(
            token: validToken,
            fetchResult: .failure(UsageClientError.httpError(
                status: 503,
                debugBody: "ROBOT-LEAK-XYZ"
            ))
        )
        await service.refresh()
        guard case .error(let userFacing) = service.state else {
            Issue.record("expected .error, got \(service.state)")
            return
        }
        #expect(!userFacing.message.contains("ROBOT-LEAK-XYZ"))
    }

    @Test("loaded → loaded transition keeps the displayable state between cycles")
    func loadedStaysDuringRefresh() async {
        let (service, fetcher) = makeService(token: validToken, fetchResult: .success(sampleUsage))
        await service.refresh()
        #expect(service.state == .loaded(sampleUsage))
        // Second cycle: still loaded, same data.
        fetcher.result = .success(sampleUsage)
        await service.refresh()
        #expect(service.state == .loaded(sampleUsage))
    }

    // MARK: - saveToken / signOut

    @Test("saveToken with a valid token persists + triggers a successful refresh")
    func saveTokenHappyPath() async throws {
        let (service, _) = makeService(token: nil, fetchResult: .success(sampleUsage))
        try await service.saveToken(validToken)
        #expect(service.state == .loaded(sampleUsage))
    }

    @Test("saveToken with a malformed string throws and leaves state untouched")
    func saveTokenMalformedThrows() async {
        let (service, _) = makeService(token: nil, fetchResult: .success(sampleUsage))
        // Initial state before saveToken
        let initial = service.state
        await #expect(throws: TokenStoreError.invalidFormat) {
            try await service.saveToken("not-a-real-token")
        }
        #expect(service.state == initial)
    }

    @Test("signOut deletes the token and reverts to needsSetup(.notConfigured)")
    func signOutResetsState() async {
        let (service, _) = makeService(token: validToken, fetchResult: .success(sampleUsage))
        await service.refresh()
        #expect(service.state == .loaded(sampleUsage))
        service.signOut()
        #expect(service.state == .needsSetup(.notConfigured))
    }

    // MARK: - normalizedInterval

    @Test("normalizedInterval: nil → default, 0 → manualOnly, valid → clamped")
    func normalizedIntervalCases() {
        let normalize = UsageService.normalizedInterval(fromStoredValue:)
        #expect(normalize(nil) == UsageService.defaultInterval)
        #expect(normalize(0) == UsageService.manualOnly)
        #expect(normalize(10) == UsageService.minimumInterval)
        #expect(normalize(600) == 600)
        #expect(normalize(-5) == UsageService.defaultInterval)
        #expect(normalize(.nan) == UsageService.defaultInterval)
        #expect(normalize(.infinity) == UsageService.defaultInterval)
    }
}

// MARK: - Mocks

final class MockUsageFetcher: UsageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<Usage, Error>

    var result: Result<Usage, Error> {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    init(result: Result<Usage, Error>) {
        _result = result
    }

    func fetch(accessToken: SecretToken) async throws -> Usage {
        switch lock.withLock({ _result }) {
        case .success(let usage): return usage
        case .failure(let error): throw error
        }
    }
}
