import Foundation
import Security

/// Failure modes for the local token cache.
enum TokenStoreError: Error, Equatable, CustomStringConvertible {
    /// `SecItem*` returned a non-success status.
    case keychainStatus(OSStatus)
    /// The stored keychain entry is present but isn't valid UTF-8.
    case malformedData
    /// The caller passed a string that doesn't look like a valid token.
    case invalidFormat

    var description: String {
        switch self {
        case .keychainStatus(let status):
            "Keychain operation failed (OSStatus \(status))."
        case .malformedData:
            "Stored token is not valid UTF-8 — re-run setup."
        case .invalidFormat:
            "That doesn't look like a Claude long-lived token."
        }
    }

    /// User-facing translation. See `UserFacingError`.
    var userFacing: UserFacingError {
        switch self {
        case .invalidFormat:
            .init(
                message: "That doesn't look like a token. Paste the full `sk-ant-…` string from `claude setup-token`.",
                isRetryable: false
            )
        case .malformedData:
            .init(
                message: "The stored token is corrupted. Re-run `claude setup-token` and paste the new token.",
                isRetryable: false
            )
        case .keychainStatus(errSecAuthFailed):
            .init(
                message: "Couldn't unlock the keychain. Sign in to macOS and try again.",
                isRetryable: true
            )
        case .keychainStatus:
            .init(
                message: "Couldn't save the token. Try again.",
                isRetryable: true
            )
        }
    }
}

/// Persists the user's long-lived `claude setup-token` in a keychain item
/// the app owns (service `dev.claude-usage-bar.oauth-token`).
///
/// Behind a protocol so `UsageService` can be unit-tested without ever
/// touching the real keychain.
protocol TokenStoring: Sendable {
    /// Returns the stored token, or `nil` if none has been saved yet.
    func load() throws -> String?
    /// Persists `token` after a format check. Replaces any existing entry.
    func save(_ token: String) throws
    /// Removes the stored token, if any. No-op if nothing was saved.
    func delete() throws
}

/// Loose syntactic check on a pasted token.
///
/// Catches the common paste mistakes (empty field, whole `export …` line,
/// trailing newline) without hard-coding a specific suffix Anthropic might
/// change later. The `sk-ant-` prefix is documented; relaxing further would
/// let a Console API key (`sk-…`) through validation, then 401, with no
/// nicer guidance than "Anthropic rejected that token."
enum TokenFormat {
    /// Minimum length we'll accept after trimming whitespace. setup-token
    /// currently mints ~108-char tokens; 40 is the safety floor below which
    /// nothing real fits.
    static let minimumLength = 40
    /// Sanity ceiling to bail out of pathological pastes early.
    static let maximumLength = 4096

    static func looksValid(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minimumLength ... maximumLength).contains(trimmed.count) else { return false }
        guard !trimmed.contains(where: \.isWhitespace) else { return false }
        return trimmed.hasPrefix("sk-ant-")
    }
}

/// Keychain-backed implementation of `TokenStoring`. Stores a single entry
/// under a configurable service name (`Self.defaultService` in production,
/// per-test names in `TokenStoreTests`).
///
/// The token never leaves the keychain on disk, is never logged, and is only
/// sent to `api.anthropic.com` as a `Bearer` credential.
struct KeychainTokenStore: TokenStoring {
    static let defaultService = "dev.claude-usage-bar.oauth-token"
    static let defaultAccount = "default"

    let service: String
    let account: String

    init(
        service: String = KeychainTokenStore.defaultService,
        account: String = KeychainTokenStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let token = String(data: data, encoding: .utf8),
                  !token.isEmpty
            else {
                throw TokenStoreError.malformedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychainStatus(status)
        }
    }

    func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokenFormat.looksValid(trimmed) else { throw TokenStoreError.invalidFormat }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addAttributes = query
            for (key, value) in attributes {
                addAttributes[key] = value
            }
            let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TokenStoreError.keychainStatus(addStatus)
            }
        default:
            throw TokenStoreError.keychainStatus(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainStatus(status)
        }
    }
}

/// In-memory store for tests. Not exposed in production paths.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(_ initial: String? = nil) {
        stored = initial
    }

    func load() throws -> String? {
        lock.withLock { stored }
    }

    func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TokenFormat.looksValid(trimmed) else { throw TokenStoreError.invalidFormat }
        lock.withLock { stored = trimmed }
    }

    func delete() throws {
        lock.withLock { stored = nil }
    }
}
