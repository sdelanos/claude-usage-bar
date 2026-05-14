import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("KeychainReader.parseAccessToken")
struct KeychainReaderParseAccessTokenTests {

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test("valid JSON with a token returns it verbatim")
    func validJSONReturnsToken() throws {
        let token = try KeychainReader.parseAccessToken(from: data(#"""
        {"claudeAiOauth": {"accessToken": "sk-ant-test-token", "refreshToken": "rk-..."}}
        """#))
        #expect(token == "sk-ant-test-token")
    }

    @Test("extra siblings on the root object are ignored")
    func extraSiblingsIgnored() throws {
        let token = try KeychainReader.parseAccessToken(from: data(#"""
        {"claudeAiOauth": {"accessToken": "tok"}, "organizationUuid": "uuid", "_v": 2}
        """#))
        #expect(token == "tok")
    }

    @Test("malformed JSON throws .malformedData")
    func malformedJSONThrows() {
        #expect(throws: KeychainReaderError.malformedData) {
            try KeychainReader.parseAccessToken(from: data("not even close to JSON"))
        }
    }

    @Test("missing claudeAiOauth throws .missingAccessToken")
    func missingClaudeAiOauthThrows() {
        #expect(throws: KeychainReaderError.missingAccessToken) {
            try KeychainReader.parseAccessToken(from: data(#"{"other": "value"}"#))
        }
    }

    @Test("missing accessToken throws .missingAccessToken")
    func missingAccessTokenKeyThrows() {
        #expect(throws: KeychainReaderError.missingAccessToken) {
            try KeychainReader.parseAccessToken(from: data(#"""
            {"claudeAiOauth": {"refreshToken": "rk-..."}}
            """#))
        }
    }

    @Test("empty accessToken throws .missingAccessToken")
    func emptyAccessTokenThrows() {
        #expect(throws: KeychainReaderError.missingAccessToken) {
            try KeychainReader.parseAccessToken(from: data(#"""
            {"claudeAiOauth": {"accessToken": ""}}
            """#))
        }
    }

    @Test("root is a JSON array (not an object) throws .malformedData")
    func nonObjectRootThrows() {
        #expect(throws: KeychainReaderError.malformedData) {
            try KeychainReader.parseAccessToken(from: data("[1, 2, 3]"))
        }
    }
}
