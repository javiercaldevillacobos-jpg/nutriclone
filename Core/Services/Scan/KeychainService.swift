import Foundation
import Security

/// Guarda textos pequeños (la clave de Gemini) en el Llavero del iPhone.
/// Solo en este dispositivo, accesible con el iPhone desbloqueado y sin copia en iCloud.
struct KeychainService {
    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case invalidData
    }

    static let geminiAPIKeyAccount = "gemini-api-key"
    static let shared = KeychainService(service: "com.nutriclone.app.secrets")

    let service: String

    func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

extension KeychainService {
    /// Clave de Gemini guardada, sin espacios; nil si no hay o está vacía.
    var geminiAPIKey: String? {
        let key = (try? read(account: Self.geminiAPIKeyAccount))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty ?? true) ? nil : key
    }
}
