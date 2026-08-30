import Foundation
import NIOMTProtoEncryption
import Security

final class KeychainStore: @unchecked Sendable {
    private let service = "ad.neko.player"
    private let lock = NSLock()

    private enum AccountKey {
        static let searchBots = "search-bots.v1"
        static let accountRegistry = "telegram.accounts.v1"

        static func primaryDC(accountID: String) -> String {
            "mtproto.primary-dc.\(accountID)"
        }
    }

    private struct StoredSession: Codable {
        var authKey: Data
        var serverSalt: Int64
        var expiresAt: Int32
    }

    private struct StoredAccountRegistry: Codable {
        var accounts: [TelegramAccount]
        var activeAccountID: String?
    }

    @discardableResult
    func saveSession(_ keys: MTProtoSessionKeys, dcID: Int32, accountID: String) -> Bool {
        let value = StoredSession(authKey: keys.authKey, serverSalt: keys.serverSalt, expiresAt: keys.expiresAt)
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return withLock {
            saveCloudPreferred(data, account: sessionKey(dcID: dcID, accountID: accountID))
        }
    }

    func loadSession(dcID: Int32, accountID: String) -> MTProtoStoredSession? {
        withLock {
            guard let data = loadCloudPreferred(account: sessionKey(dcID: dcID, accountID: accountID)),
                  let value = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
            return MTProtoStoredSession(
                authKey: value.authKey,
                serverSalt: value.serverSalt,
                expiresAt: value.expiresAt
            )
        }
    }

    func clearSessions(accountID: String) {
        withLock {
            for dcID in 1...5 {
                deleteAll(account: sessionKey(dcID: Int32(dcID), accountID: accountID))
                deleteAll(account: sessionKey(dcID: Int32(-dcID), accountID: accountID))
            }
            deleteAll(account: AccountKey.primaryDC(accountID: accountID))
        }
    }

    func deleteSession(dcID: Int32, accountID: String) {
        withLock {
            deleteAll(account: sessionKey(dcID: dcID, accountID: accountID))
        }
    }

    @discardableResult
    func savePrimaryDC(_ dcID: Int32, accountID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(dcID) else { return false }
        return withLock {
            saveCloudPreferred(data, account: AccountKey.primaryDC(accountID: accountID))
        }
    }

    func loadPrimaryDC(accountID: String) -> Int32? {
        withLock {
            guard let data = loadCloudPreferred(account: AccountKey.primaryDC(accountID: accountID)) else {
                return nil
            }
            return try? JSONDecoder().decode(Int32.self, from: data)
        }
    }

    @discardableResult
    func saveSearchBotConfigs(_ configs: [SearchBotConfig]) -> Bool {
        guard let data = try? JSONEncoder().encode(configs) else { return false }
        return withLock {
            saveCloudPreferred(data, account: AccountKey.searchBots)
        }
    }

    /// Returns `nil` when no configuration has ever been stored. An empty array is a
    /// deliberate user choice and is preserved across devices.
    func loadSearchBotConfigs() -> [SearchBotConfig]? {
        withLock {
            guard let data = loadCloudPreferred(account: AccountKey.searchBots) else { return nil }
            return try? JSONDecoder().decode([SearchBotConfig].self, from: data)
        }
    }

    @discardableResult
    func saveAccountRegistry(accounts: [TelegramAccount], activeAccountID: String?) -> Bool {
        guard let data = try? JSONEncoder().encode(
            StoredAccountRegistry(accounts: accounts, activeAccountID: activeAccountID)
        ) else { return false }
        return withLock {
            saveCloudPreferred(data, account: AccountKey.accountRegistry)
        }
    }

    func loadAccountRegistry() -> (accounts: [TelegramAccount], activeAccountID: String?)? {
        withLock {
            guard let data = loadCloudPreferred(account: AccountKey.accountRegistry),
                  let registry = try? JSONDecoder().decode(StoredAccountRegistry.self, from: data) else {
                return nil
            }
            return (registry.accounts, registry.activeAccountID)
        }
    }

    private func sessionKey(dcID: Int32, accountID: String) -> String {
        accountID == "legacy"
            ? "mtproto.session.\(dcID)"
            : "mtproto.session.\(accountID).\(dcID)"
    }

    /// iCloud Keychain is unavailable in some unsigned simulator/debug environments.
    /// Prefer a synchronizable item, then retain the same non-device-only item locally
    /// so login and playback never regress in those environments.
    @discardableResult
    private func saveCloudPreferred(_ data: Data, account: String) -> Bool {
        do {
            try save(data, account: account, synchronizable: true)
            delete(account: account, synchronizable: false)
            return true
        } catch {
            do {
                try save(data, account: account, synchronizable: false)
                return true
            } catch {
                return false
            }
        }
    }

    /// Local legacy/fallback data is authoritative. A successful read opportunistically
    /// migrates it to iCloud Keychain and only then removes the local copy.
    private func loadCloudPreferred(account: String) -> Data? {
        if let local = load(account: account, synchronizable: false) {
            do {
                try save(local, account: account, synchronizable: true)
                delete(account: account, synchronizable: false)
            } catch {
                // Keep the local value. A future signed/iCloud-enabled launch retries migration.
            }
            return local
        }
        return load(account: account, synchronizable: true)
    }

    private func save(_ data: Data, account: String, synchronizable: Bool) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
        let values: [CFString: Any] = [
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
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

    private func load(account: String, synchronizable: Bool) -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        return status == errSecSuccess ? result as? Data : nil
    }

    private func deleteAll(account: String) {
        delete(account: account, synchronizable: false)
        delete(account: account, synchronizable: true)
    }

    private func delete(account: String, synchronizable: Bool) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ] as CFDictionary)
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
