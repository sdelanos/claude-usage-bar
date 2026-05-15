import Testing
import Foundation
@testable import ClaudeUsageBar

@Suite("TokenFormat.looksValid")
struct TokenFormatTests {

    @Test("accepts a plausible long-lived token")
    func acceptsPlausibleToken() {
        #expect(TokenFormat.looksValid("sk-ant-oat01-" + String(repeating: "A", count: 100)))
    }

    @Test("rejects empty / whitespace-only input")
    func rejectsEmpty() {
        #expect(!TokenFormat.looksValid(""))
        #expect(!TokenFormat.looksValid("   \n\t  "))
    }

    @Test("rejects strings that include internal whitespace")
    func rejectsInternalWhitespace() {
        #expect(!TokenFormat.looksValid("sk-ant-oat01 with a space inside"))
        #expect(!TokenFormat.looksValid("sk-ant-\noat01-XXXX"))
    }

    @Test("rejects strings that don't start with sk-ant-")
    func rejectsWrongPrefix() {
        #expect(!TokenFormat.looksValid("Bearer sk-ant-oat01-XXXX"))
        #expect(!TokenFormat.looksValid("export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-…"))
        // A Console API key (`sk-` but not `sk-ant-`) is the most likely
        // paste mistake; explicitly reject it.
        #expect(!TokenFormat.looksValid("sk-" + String(repeating: "A", count: 80)))
    }

    @Test("boundary on length: minimum-length-minus-1 rejected, minimum accepted")
    func lengthBoundary() {
        let belowMin = "sk-ant-" + String(repeating: "x", count: TokenFormat.minimumLength - "sk-ant-".count - 1)
        let atMin    = "sk-ant-" + String(repeating: "x", count: TokenFormat.minimumLength - "sk-ant-".count)
        #expect(!TokenFormat.looksValid(belowMin))
        #expect(TokenFormat.looksValid(atMin))
    }

    @Test("rejects pathologically long input")
    func rejectsTooLong() {
        let huge = "sk-ant-" + String(repeating: "X", count: TokenFormat.maximumLength)
        #expect(!TokenFormat.looksValid(huge))
    }
}

/// Round-trip tests for `KeychainTokenStore`. Each test uses a unique
/// service name so suites run in parallel without clobbering each other,
/// and so a crash mid-test never leaves the user's real keychain dirty.
///
/// These tests hit the user's real login keychain (under random service
/// names). They're skipped automatically when `CUBAR_SKIP_KEYCHAIN_TESTS`
/// is set, which CI sets when its keychain isn't usefully unlocked.
@Suite("KeychainTokenStore round-trip",
       .disabled(if: ProcessInfo.processInfo.environment["CUBAR_SKIP_KEYCHAIN_TESTS"] != nil))
struct KeychainTokenStoreTests {

    private func makeStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "dev.claude-usage-bar.tests.\(UUID().uuidString)")
    }

    @Test("save then load returns the original token")
    func saveThenLoad() throws {
        let store = makeStore()
        defer { try? store.delete() }

        let token = "sk-ant-oat01-" + String(repeating: "Z", count: 80)
        try store.save(token)
        #expect(try store.load() == token)
    }

    @Test("save trims surrounding whitespace before persisting")
    func saveTrimsWhitespace() throws {
        let store = makeStore()
        defer { try? store.delete() }

        let raw = "sk-ant-oat01-" + String(repeating: "Q", count: 80)
        try store.save("  \(raw)\n  ")
        #expect(try store.load() == raw)
    }

    @Test("save then save replaces the previous value (no duplicate)")
    func saveReplacesPrevious() throws {
        let store = makeStore()
        defer { try? store.delete() }

        let first  = "sk-ant-oat01-" + String(repeating: "A", count: 80)
        let second = "sk-ant-oat01-" + String(repeating: "B", count: 80)
        try store.save(first)
        try store.save(second)
        #expect(try store.load() == second)
    }

    @Test("load returns nil when nothing has been saved")
    func loadEmptyReturnsNil() throws {
        let store = makeStore()
        #expect(try store.load() == nil)
    }

    @Test("delete is idempotent")
    func deleteIsIdempotent() throws {
        let store = makeStore()
        try store.delete()

        let token = "sk-ant-oat01-" + String(repeating: "X", count: 80)
        try store.save(token)
        try store.delete()
        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("save rejects malformed input before touching the keychain")
    func saveRejectsMalformed() throws {
        let store = makeStore()
        defer { try? store.delete() }

        #expect(throws: TokenStoreError.invalidFormat) {
            try store.save("nope")
        }
        #expect(try store.load() == nil)
    }
}

@Suite("InMemoryTokenStore")
struct InMemoryTokenStoreTests {

    @Test("round-trip via the in-memory store works without a keychain")
    func roundTrip() throws {
        let store = InMemoryTokenStore()
        #expect(try store.load() == nil)

        let token = "sk-ant-oat01-" + String(repeating: "M", count: 80)
        try store.save(token)
        #expect(try store.load() == token)

        try store.delete()
        #expect(try store.load() == nil)
    }

    @Test("save validates format")
    func saveValidates() {
        let store = InMemoryTokenStore()
        #expect(throws: TokenStoreError.invalidFormat) {
            try store.save("bad")
        }
    }
}
