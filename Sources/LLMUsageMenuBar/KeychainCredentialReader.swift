import Foundation
import Security
import UsageCore

/// Reads Claude Code's generic password item from the login keychain.
/// Read-only: the app never adds, updates, or deletes keychain items.
struct KeychainCredentialReader: CredentialReader {
    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String {
            let text = SecCopyErrorMessageString(status, nil).map { String($0) } ?? "unknown"
            return "keychain error \(status) (\(text))"
        }
    }

    let paths: Paths

    init(paths: Paths = Paths()) {
        self.paths = paths
    }

    func read(configDirectory: String) throws -> OAuthCredential? {
        let service = KeychainServiceName.for(configDirectory: configDirectory, paths: paths)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try OAuthCredential.decode(keychainJSON: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// True when the default directory has a stored credential. Used for the
    /// first-launch default configuration (FR-034).
    func hasDefaultCredential() -> Bool {
        (try? read(configDirectory: Paths.defaultClaudeDirectory)) != nil
    }
}
