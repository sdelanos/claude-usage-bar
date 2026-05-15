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
            return "Keychain operation failed (OSStatus \(status))."
        case .malformedData:
            return "Stored token is not valid UTF-8 — re-run setup."
        case .invalidFormat:
            return "That doesn't look like a Claude long-lived token."
        }
    }
}

/// Persists the user's long-lived `claude setup-token` in a keychain item
/// that we own (`dev.claude-usage-bar.oauth-token`).
///
/// Why a separate item, not Claude Code's `Claude Code-credentials`?
/// Claude Code rewrites its keychain entry on every OAuth token refresh, which
/// resets the ACL — every rewrite re-triggers the "Always Allow" prompt on
/// our side. Tokens minted by `claude setup-token` are not stored by Claude
/// Code at all; they are 1-year bearers that the user pastes in once. Storing
/// them under our own service name means nothing else ever touches the item.
///
/// The token never leaves the keychain on disk, is never logged, and is only
/// sent to `api.anthropic.com` as a `Bearer` credential.
enum TokenStore {

    /// Keychain service identifier. Distinct from Claude Code's so the two
    /// items can coexist on the same machine.
    static let service = "dev.claude-usage-bar.oauth-token"
    /// Single-account app — we never need more than one token at a time.
    static let account = "default"

    // MARK: - Public API

    /// Returns the stored token, or `nil` if none has been saved yet.
    static func load() throws -> String? {
        try load(service: service)
    }

    /// Persists `token` after a format check. Replaces any existing entry.
    static func save(_ token: String) throws {
        try save(token, service: service)
    }

    /// Removes the stored token, if any. No-op if nothing was saved.
    static func delete() throws {
        try delete(service: service)
    }

    /// Loose syntactic check on a pasted token. Catches the common paste
    /// mistakes (empty field, whole `export …` line, trailing newline) without
    /// hard-coding a specific prefix that Anthropic could change later.
    static func looksValid(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40, trimmed.count <= 4096 else { return false }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        // setup-token currently mints `sk-ant-…`. Accept anything starting
        // with `sk-` so a future prefix doesn't break paste.
        return trimmed.hasPrefix("sk-")
    }

    // MARK: - Service-parameterised core (for tests)

    static func load(service: String, account: String = TokenStore.account) throws -> String? {
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
                  !token.isEmpty else {
                throw TokenStoreError.malformedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychainStatus(status)
        }
    }

    static func save(_ token: String, service: String, account: String = TokenStore.account) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksValid(trimmed) else { throw TokenStoreError.invalidFormat }

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
            for (key, value) in attributes { addAttributes[key] = value }
            let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw TokenStoreError.keychainStatus(addStatus)
            }
        default:
            throw TokenStoreError.keychainStatus(updateStatus)
        }
    }

    static func delete(service: String, account: String = TokenStore.account) throws {
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
