import Testing
import Foundation
@testable import ClaudeUsageBar

/// Round-trip tests for `TokenStore`. Each test uses a unique service name
/// so suites run in parallel without clobbering each other, and so a crash
/// mid-test never leaves the user's real keychain dirty.
@Suite("TokenStore")
struct TokenStoreTests {

    private static func makeServiceName() -> String {
        "dev.claude-usage-bar.tests.\(UUID().uuidString)"
    }

    // MARK: - Format validation

    @Suite("looksValid")
    struct LooksValidTests {

        @Test("accepts a plausible long-lived token")
        func acceptsPlausibleToken() {
            #expect(TokenStore.looksValid("sk-ant-oat01-" + String(repeating: "A", count: 100)))
        }

        @Test("rejects empty / whitespace-only input")
        func rejectsEmpty() {
            #expect(!TokenStore.looksValid(""))
            #expect(!TokenStore.looksValid("   \n\t  "))
        }

        @Test("rejects strings that include internal whitespace")
        func rejectsInternalWhitespace() {
            #expect(!TokenStore.looksValid("sk-ant-oat01 with a space inside"))
            #expect(!TokenStore.looksValid("sk-ant-\noat01-XXXX"))
        }

        @Test("rejects strings that don't start with sk-")
        func rejectsWrongPrefix() {
            #expect(!TokenStore.looksValid("Bearer sk-ant-oat01-XXXX"))
            #expect(!TokenStore.looksValid("export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-…"))
        }

        @Test("rejects strings that are too short to be a real token")
        func rejectsTooShort() {
            #expect(!TokenStore.looksValid("sk-ant-short"))
        }
    }

    // MARK: - Round-trip

    @Test("save then load returns the original token")
    func saveThenLoad() throws {
        let service = Self.makeServiceName()
        defer { try? TokenStore.delete(service: service) }

        let token = "sk-ant-oat01-" + String(repeating: "Z", count: 80)
        try TokenStore.save(token, service: service)
        #expect(try TokenStore.load(service: service) == token)
    }

    @Test("save trims surrounding whitespace before persisting")
    func saveTrimsWhitespace() throws {
        let service = Self.makeServiceName()
        defer { try? TokenStore.delete(service: service) }

        let raw = "sk-ant-oat01-" + String(repeating: "Q", count: 80)
        try TokenStore.save("  \(raw)\n  ", service: service)
        #expect(try TokenStore.load(service: service) == raw)
    }

    @Test("save then save replaces the previous value (no duplicate)")
    func saveReplacesPrevious() throws {
        let service = Self.makeServiceName()
        defer { try? TokenStore.delete(service: service) }

        let first  = "sk-ant-oat01-" + String(repeating: "A", count: 80)
        let second = "sk-ant-oat01-" + String(repeating: "B", count: 80)
        try TokenStore.save(first, service: service)
        try TokenStore.save(second, service: service)
        #expect(try TokenStore.load(service: service) == second)
    }

    @Test("load returns nil when nothing has been saved")
    func loadEmptyReturnsNil() throws {
        let service = Self.makeServiceName()
        #expect(try TokenStore.load(service: service) == nil)
    }

    @Test("delete is idempotent")
    func deleteIsIdempotent() throws {
        let service = Self.makeServiceName()
        // First delete with nothing saved must not throw.
        try TokenStore.delete(service: service)

        let token = "sk-ant-oat01-" + String(repeating: "X", count: 80)
        try TokenStore.save(token, service: service)
        try TokenStore.delete(service: service)
        try TokenStore.delete(service: service)
        #expect(try TokenStore.load(service: service) == nil)
    }

    @Test("save rejects malformed input before touching the keychain")
    func saveRejectsMalformed() throws {
        let service = Self.makeServiceName()
        defer { try? TokenStore.delete(service: service) }

        #expect(throws: TokenStoreError.invalidFormat) {
            try TokenStore.save("nope", service: service)
        }
        #expect(try TokenStore.load(service: service) == nil)
    }
}
