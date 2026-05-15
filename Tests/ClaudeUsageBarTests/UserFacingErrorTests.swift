import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("UserFacingError.translate")
struct UserFacingErrorTests {

    @Test("URLError(.notConnectedToInternet) yields 'No internet connection.'")
    func noInternet() {
        let translated = UserFacingError.translate(URLError(.notConnectedToInternet))
        #expect(translated.message == "No internet connection.")
        #expect(translated.isRetryable)
    }

    @Test("URLError(.timedOut) yields a 'try again' message")
    func timedOut() {
        let translated = UserFacingError.translate(URLError(.timedOut))
        #expect(translated.message.lowercased().contains("try again"))
        #expect(translated.isRetryable)
    }

    @Test("UsageClientError.httpError doesn't leak the body bytes")
    func httpErrorDoesNotLeakBody() {
        let raw = UsageClientError.httpError(status: 503, debugBody: "secret-or-token-bearing-body")
        let translated = UserFacingError.translate(raw)
        #expect(!translated.message.contains("secret-or-token-bearing-body"))
        #expect(translated.message.contains("503"))
    }

    @Test("UsageClientError.invalidResponse maps to a stable user-facing message")
    func invalidResponseMapped() {
        let translated = UserFacingError.translate(UsageClientError.invalidResponse)
        #expect(translated.message.contains("Anthropic"))
        #expect(translated.isRetryable)
    }

    @Test("TokenStoreError.malformedData maps to a re-setup hint")
    func tokenStoreMalformed() {
        let translated = UserFacingError.translate(TokenStoreError.malformedData)
        #expect(translated.message.contains("setup-token"))
        #expect(!translated.isRetryable)
    }

    @Test("CancellationError surfaces as 'cancelled'")
    func cancellation() {
        let translated = UserFacingError.translate(CancellationError())
        #expect(translated.message.lowercased().contains("cancelled"))
    }
}

@Suite("SecretToken")
struct SecretTokenTests {

    @Test("description and debugDescription both redact the value")
    func descriptionsRedact() {
        let token = SecretToken("sk-ant-oat01-AAAAAA")
        #expect(token.description == "sk-ant-***")
        #expect(token.debugDescription == "sk-ant-***")
        // String interpolation also goes through description.
        #expect("\(token)" == "sk-ant-***")
    }

    @Test("reveal() returns the underlying string verbatim")
    func revealReturnsValue() {
        let raw = "sk-ant-oat01-AAAAAA"
        #expect(SecretToken(raw).reveal() == raw)
    }

    @Test("equality respects the wrapped value")
    func equality() {
        #expect(SecretToken("a") == SecretToken("a"))
        #expect(SecretToken("a") != SecretToken("b"))
    }
}
