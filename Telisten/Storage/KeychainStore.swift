import Foundation
import NIOMTProtoEncryption
import Security

final class KeychainStore: @unchecked Sendable {
    private let service = "ad.neko.player"

    private struct StoredSession: Codable {
        var authKey: Data
        var serverSalt: Int64
        var expiresAt: Int32
    }

    @discardableResult
    func saveSession(_ keys: MTProtoSessionKeys, dcID: Int32, accountID: String) -> Bool {
        let value = StoredSession(authKey: keys.authKey, serverSalt: keys.serverSalt, expiresAt: keys.expiresAt)
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try save(data, account: sessionKey(dcID: dcID, accountID: accountID))
            return true
        } catch {
            return false
        }
    }

    func loadSession(dcID: Int32, accountID: String) -> MTProtoStoredSession? {
        guard let data = load(account: sessionKey(dcID: dcID, accountID: accountID)),
              let value = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
        return MTProtoStoredSession(
            authKey: value.authKey,
            serverSalt: value.serverSalt,
            expiresAt: value.expiresAt
        )
    }

    func clearSessions(accountID: String) {
        for dcID in 1...5 {
            delete(account: sessionKey(dcID: Int32(dcID), accountID: accountID))
            delete(account: sessionKey(dcID: Int32(-dcID), accountID: accountID))
        }
    }

    func deleteSession(dcID: Int32, accountID: String) {
        delete(account: sessionKey(dcID: dcID, accountID: accountID))
    }

    private func sessionKey(dcID: Int32, accountID: String) -> String {
        accountID == "legacy"
            ? "mtproto.session.\(dcID)"
            : "mtproto.session.\(accountID).\(dcID)"
    }

    private func save(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let values: [CFString: Any] = [
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        let status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func load(account: String) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private func delete(account: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ] as CFDictionary)
    }
}
