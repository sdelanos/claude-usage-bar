import Foundation
import Security

enum KeychainReaderError: Error, CustomStringConvertible {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case malformedData
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

struct KeychainReader {
    static let service = "Claude Code-credentials"

    static func readAccessToken() throws -> String {
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
        let parsed = try? JSONSerialization.jsonObject(with: data)
        guard let root = parsed as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            throw KeychainReaderError.missingAccessToken
        }
        return token
    }
}
