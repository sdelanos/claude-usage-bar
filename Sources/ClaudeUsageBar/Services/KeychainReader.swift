import Foundation
import Security

/// Failure modes for reading the Claude Code OAuth token out of the macOS
/// Keychain. The descriptions are surfaced verbatim in the menu-bar dropdown
/// when something goes wrong, so they aim to tell the user what to do.
enum KeychainReaderError: Error, Equatable, CustomStringConvertible {
    /// No entry in the user's login keychain for service `Claude Code-credentials`.
    case itemNotFound
    /// `SecItemCopyMatching` returned an unexpected status code.
    case unexpectedStatus(OSStatus)
    /// The keychain entry is present but its payload isn't valid JSON.
    case malformedData
    /// The JSON is valid but doesn't contain `claudeAiOauth.accessToken`.
    case missingAccessToken

    var description: String {
        switch self {
        case .itemNotFound:
            return "No Claude Code credentials found in Keychain (service 'Claude Code-credentials'). Make sure Claude Code is installed and you're signed in."
        case .unexpectedStatus(let status):
            return "Keychain read failed (OSStatus \(status))."
        case .malformedData:
            return "Keychain entry is not valid JSON."
        case .missingAccessToken:
            return "Keychain JSON is missing claudeAiOauth.accessToken."
        }
    }
}

/// Reads the OAuth access token Claude Code stores in the user's login
/// keychain under service `Claude Code-credentials`. The token is the bearer
/// credential the app sends to `api.anthropic.com` to fetch rate-limit
/// headers; reusing it is what avoids a second sign-in.
///
/// The token is never copied to disk, never logged, and never sent anywhere
/// other than `api.anthropic.com`.
enum KeychainReader {

    /// Keychain service name set by Claude Code when it stores the OAuth token.
    static let service = "Claude Code-credentials"

    /// Fetches the access token from the user's login keychain.
    ///
    /// Throws `KeychainReaderError` if the entry is missing, the user denied
    /// access, or the JSON payload is malformed.
    static func readAccessToken() throws -> String {
        let data = try fetchKeychainData()
        return try parseAccessToken(from: data)
    }

    /// Parses the JSON blob Claude Code stores in the keychain and extracts
    /// the access token. Exposed (internal) so the parser can be tested
    /// without ever touching the real keychain.
    static func parseAccessToken(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KeychainReaderError.malformedData
        }
        guard let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            throw KeychainReaderError.missingAccessToken
        }
        return token
    }

    // MARK: - Private

    private static func fetchKeychainData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainReaderError.itemNotFound
        default:
            throw KeychainReaderError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainReaderError.malformedData
        }
        return data
    }
}
