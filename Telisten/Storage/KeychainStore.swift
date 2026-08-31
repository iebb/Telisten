import Foundation
import NIOMTProtoEncryption
import Security

final class KeychainStore: @unchecked Sendable {
    private static let defaultService = "ad.neko.player"
    private static let primaryDCs = (1...5).map(Int32.init)
    private static let accessGroupPrefixInfoKey = "TelistenKeychainAccessGroupPrefix"

    private let service: String
    private let accessGroupPrefix: String?
    private let lock = NSLock()

    init(
        service: String = KeychainStore.defaultService,
        accessGroupPrefix: String? = nil
    ) {
        self.service = service
        let configuredPrefix = accessGroupPrefix
            ?? Bundle.main.object(forInfoDictionaryKey: Self.accessGroupPrefixInfoKey) as? String
        self.accessGroupPrefix = configuredPrefix.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
            return trimmed.hasSuffix(".") ? trimmed : "\(trimmed)."
        }
        purgeSynchronizedSessionArtifacts()
    }

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

    private struct SyncedValue: Codable {
        var payload: Data
        var modifiedAt: Date
    }

    private struct DecodedSyncedValue {
        var payload: Data
        var modifiedAt: Date
        var encoded: Data
    }

    func availableSessionDCs(accountID: String) -> [Int32] {
        withLock { availableSessionDCsUnlocked(accountID: accountID) }
    }

    func availableSessionAccountIDs() -> [String] {
        withLock {
            let accountIDs = Set(sessionItemAccounts().compactMap(sessionAccountID(from:)))
            return accountIDs
                .filter { !availableSessionDCsUnlocked(accountID: $0).isEmpty }
                .sorted()
        }
    }

    @discardableResult
    func saveSession(_ keys: MTProtoSessionKeys, dcID: Int32, accountID: String) -> Bool {
        let value = StoredSession(authKey: keys.authKey, serverSalt: keys.serverSalt, expiresAt: keys.expiresAt)
        guard let data = try? JSONEncoder().encode(value) else { return false }
        return withLock {
            let account = sessionKey(dcID: dcID, accountID: accountID)
            let saved = saveDeviceLocal(data, account: account)
            deleteSynchronizedSessionArtifact(account: account)
            return saved
        }
    }

    func loadSession(dcID: Int32, accountID: String) -> MTProtoStoredSession? {
        withLock {
            guard let data = loadDeviceLocal(account: sessionKey(dcID: dcID, accountID: accountID)),
                  let value = decodedSession(data) else { return nil }
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
                for signedDCID in [Int32(dcID), Int32(-dcID)] {
                    let account = sessionKey(dcID: signedDCID, accountID: accountID)
                    deleteDeviceLocal(account: account)
                    deleteSynchronizedSessionArtifact(account: account)
                }
            }
            let primaryDCAccount = AccountKey.primaryDC(accountID: accountID)
            deleteDeviceLocal(account: primaryDCAccount)
            deleteSynchronizedSessionArtifact(account: primaryDCAccount)
        }
    }

    func deleteSession(dcID: Int32, accountID: String) {
        withLock {
            let account = sessionKey(dcID: dcID, accountID: accountID)
            deleteDeviceLocal(account: account)
            deleteSynchronizedSessionArtifact(account: account)
        }
    }

    @discardableResult
    func savePrimaryDC(_ dcID: Int32, accountID: String) -> Bool {
        guard let data = try? JSONEncoder().encode(dcID) else { return false }
        return withLock {
            let account = AccountKey.primaryDC(accountID: accountID)
            let saved = saveDeviceLocal(data, account: account)
            deleteSynchronizedSessionArtifact(account: account)
            return saved
        }
    }

    func loadPrimaryDC(accountID: String) -> Int32? {
        withLock {
            guard let data = loadDeviceLocal(account: AccountKey.primaryDC(accountID: accountID)) else {
                return nil
            }
            return try? JSONDecoder().decode(Int32.self, from: data)
        }
    }

    /// Moves every device-local MTProto session and the primary-DC marker to a
    /// different account identifier. Synchronizable Keychain items are never used
    /// as session input; stale copies from older builds are purged after the move.
    ///
    /// Keychain has no multi-item transaction API, so this uses a recoverable
    /// two-phase move: replace and verify the destination first, then remove the
    /// source. Any failure restores the snapshots while retaining at least one
    /// complete copy of the source state.
    @discardableResult
    func moveDeviceLocalSessions(fromAccountID sourceAccountID: String, toAccountID destinationAccountID: String) -> Bool {
        guard !sourceAccountID.isEmpty, !destinationAccountID.isEmpty else { return false }
        guard sourceAccountID != destinationAccountID else { return true }

        return withLock {
            let sourceKeys = deviceLocalAccountItemKeys(accountID: sourceAccountID)
            let destinationKeys = deviceLocalAccountItemKeys(accountID: destinationAccountID)

            let sourceSnapshot: [Data?]
            let destinationSnapshot: [Data?]
            do {
                sourceSnapshot = try deviceLocalSnapshot(keys: sourceKeys)
                destinationSnapshot = try deviceLocalSnapshot(keys: destinationKeys)
            } catch {
                return false
            }
            guard sourceSnapshot.contains(where: { $0 != nil }) else { return false }

            do {
                try applyDeviceLocalSnapshot(sourceSnapshot, keys: destinationKeys)
                guard try deviceLocalSnapshot(keys: destinationKeys) == sourceSnapshot else {
                    throw CocoaError(.fileWriteUnknown)
                }
            } catch {
                try? applyDeviceLocalSnapshot(destinationSnapshot, keys: destinationKeys)
                return false
            }

            do {
                try applyDeviceLocalSnapshot(Array(repeating: nil, count: sourceKeys.count), keys: sourceKeys)
                guard try deviceLocalSnapshot(keys: sourceKeys).allSatisfy({ $0 == nil }) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                for key in sourceKeys + destinationKeys {
                    deleteSynchronizedSessionArtifact(account: key)
                }
                return true
            } catch {
                // Restore the source first. Only roll the destination back once
                // that succeeds, so a failed recovery can never discard the last
                // complete copy of the session state.
                do {
                    try applyDeviceLocalSnapshot(sourceSnapshot, keys: sourceKeys)
                    guard try deviceLocalSnapshot(keys: sourceKeys) == sourceSnapshot else {
                        return false
                    }
                    try? applyDeviceLocalSnapshot(destinationSnapshot, keys: destinationKeys)
                } catch {
                    // The verified destination still contains the complete source
                    // snapshot and remains recoverable by a later retry.
                }
                return false
            }
        }
    }

    @discardableResult
    func saveSearchBotConfigs(_ configs: [SearchBotConfig]) -> Bool {
        guard let data = try? JSONEncoder().encode(configs) else { return false }
        return withLock {
            saveSynced(data, account: AccountKey.searchBots)
        }
    }

    /// Returns `nil` when no configuration has ever been stored. An empty array is a
    /// deliberate user choice and is preserved across devices.
    func loadSearchBotConfigs() -> [SearchBotConfig]? {
        withLock {
            guard let data = loadSynced(account: AccountKey.searchBots) else { return nil }
            return try? JSONDecoder().decode([SearchBotConfig].self, from: data)
        }
    }

    @discardableResult
    func saveAccountRegistry(accounts: [TelegramAccount], activeAccountID: String?) -> Bool {
        guard let data = try? JSONEncoder().encode(
            StoredAccountRegistry(accounts: accounts, activeAccountID: activeAccountID)
        ) else { return false }
        return withLock {
            saveSynced(data, account: AccountKey.accountRegistry)
        }
    }

    func loadAccountRegistry() -> (accounts: [TelegramAccount], activeAccountID: String?)? {
        withLock {
            guard let data = loadSynced(account: AccountKey.accountRegistry),
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

    private func availableSessionDCsUnlocked(accountID: String) -> [Int32] {
        Self.primaryDCs.filter { dcID in
            let account = sessionKey(dcID: dcID, accountID: accountID)
            return decodedSession(loadDeviceLocal(account: account)) != nil
        }
    }

    private func deviceLocalAccountItemKeys(accountID: String) -> [String] {
        let sessionKeys = Self.primaryDCs.flatMap { dcID in
            [
                sessionKey(dcID: dcID, accountID: accountID),
                sessionKey(dcID: -dcID, accountID: accountID)
            ]
        }
        return sessionKeys + [AccountKey.primaryDC(accountID: accountID)]
    }

    private func deviceLocalSnapshot(keys: [String]) throws -> [Data?] {
        try keys.map { key in
            try loadThrowing(
                account: key,
                synchronizable: false,
                service: service
            )
        }
    }

    private func applyDeviceLocalSnapshot(_ snapshot: [Data?], keys: [String]) throws {
        guard snapshot.count == keys.count else {
            throw CocoaError(.coderInvalidValue)
        }
        for (data, key) in zip(snapshot, keys) {
            if let data {
                try save(data, account: key, synchronizable: false, service: service)
            } else {
                try deleteThrowing(account: key, synchronizable: false, service: service)
            }
        }
    }

    private func sessionItemAccounts() -> [String] {
        itemAccounts(synchronizable: false)
    }

    private func purgeSynchronizedSessionArtifacts() {
        withLock {
            for account in itemAccounts(synchronizable: true)
                where account.hasPrefix("mtproto.session.")
                    || account.hasPrefix("mtproto.primary-dc.") {
                deleteSynchronizedSessionArtifact(account: account)
            }
        }
    }

    private func itemAccounts(synchronizable: Bool) -> [String] {
        var result: CFTypeRef?
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]
        addAccessOptions(to: &query, service: service)
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return []
        }
        let items: [[CFString: Any]]
        if let many = result as? [[CFString: Any]] {
            items = many
        } else if let one = result as? [CFString: Any] {
            items = [one]
        } else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount] as? String }
    }

    private func sessionAccountID(from itemAccount: String) -> String? {
        let prefix = "mtproto.session."
        guard itemAccount.hasPrefix(prefix) else { return nil }
        let remainder = String(itemAccount.dropFirst(prefix.count))
        if let dcID = Int32(remainder), Self.primaryDCs.contains(dcID) {
            return "legacy"
        }
        guard let separator = remainder.lastIndex(of: "."),
              let dcID = Int32(remainder[remainder.index(after: separator)...]),
              Self.primaryDCs.contains(dcID) else { return nil }
        let accountID = String(remainder[..<separator])
        return accountID.isEmpty ? nil : accountID
    }

    private func decodedSession(_ data: Data?) -> StoredSession? {
        guard let data,
              let value = try? JSONDecoder().decode(StoredSession.self, from: data),
              value.authKey.count == 256 else { return nil }
        return value
    }

    /// Account descriptors and user configuration may follow the user through
    /// iCloud Keychain. Raw MTProto session keys deliberately use the device-local
    /// helpers instead: reusing one auth key on two active devices can make
    /// Telegram invalidate it as duplicated.
    @discardableResult
    private func saveSynced(_ data: Data, account: String) -> Bool {
        guard let encoded = try? JSONEncoder().encode(
            SyncedValue(payload: data, modifiedAt: Date())
        ) else { return false }
        do {
            try save(encoded, account: account, synchronizable: true)
            delete(account: account, synchronizable: false)
            return true
        } catch {
            do {
                try save(encoded, account: account, synchronizable: false)
                return true
            } catch {
                return false
            }
        }
    }

    private func loadSynced(account: String) -> Data? {
        let local = decodedSyncedValue(load(account: account, synchronizable: false, service: service))
        let cloud = decodedSyncedValue(load(account: account, synchronizable: true, service: service))
        let selected: DecodedSyncedValue
        switch (local, cloud) {
        case let (local?, cloud?):
            selected = local.modifiedAt > cloud.modifiedAt ? local : cloud
        case let (local?, nil):
            selected = local
        case let (nil, cloud?):
            selected = cloud
        case (nil, nil):
            return nil
        }

        if let local, selected.modifiedAt == local.modifiedAt,
           (cloud == nil || local.modifiedAt > cloud!.modifiedAt) {
            do {
                try save(selected.encoded, account: account, synchronizable: true, service: service)
                delete(account: account, synchronizable: false, service: service)
            } catch {
                // Keep the newer local fallback and retry when iCloud Keychain is available.
            }
        } else if cloud != nil {
            delete(account: account, synchronizable: false, service: service)
        }
        return selected.payload
    }

    private func decodedSyncedValue(_ data: Data?) -> DecodedSyncedValue? {
        guard let data else { return nil }
        if let value = try? JSONDecoder().decode(SyncedValue.self, from: data) {
            return DecodedSyncedValue(
                payload: value.payload,
                modifiedAt: value.modifiedAt,
                encoded: data
            )
        }
        // Values written by an earlier build of the current app remain readable.
        return DecodedSyncedValue(payload: data, modifiedAt: .distantPast, encoded: data)
    }

    @discardableResult
    private func saveDeviceLocal(_ data: Data, account: String) -> Bool {
        do {
            try save(data, account: account, synchronizable: false)
            return true
        } catch {
            return false
        }
    }

    private func loadDeviceLocal(account: String) -> Data? {
        load(account: account, synchronizable: false, service: service)
    }

    private func deleteDeviceLocal(account: String) {
        delete(account: account, synchronizable: false, service: service)
    }

    private func deleteSynchronizedSessionArtifact(account: String) {
        delete(account: account, synchronizable: true, service: service)
    }

    private func save(
        _ data: Data,
        account: String,
        synchronizable: Bool,
        service itemService: String? = nil
    ) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: itemService ?? service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
        addAccessOptions(to: &query, service: itemService ?? service)
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

    private func load(
        account: String,
        synchronizable: Bool,
        service itemService: String? = nil
    ) -> Data? {
        try? loadThrowing(
            account: account,
            synchronizable: synchronizable,
            service: itemService
        )
    }

    private func loadThrowing(
        account: String,
        synchronizable: Bool,
        service itemService: String? = nil
    ) throws -> Data? {
        var result: CFTypeRef?
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: itemService ?? service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        addAccessOptions(to: &query, service: itemService ?? service)
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }

    private func delete(
        account: String,
        synchronizable: Bool,
        service itemService: String? = nil
    ) {
        try? deleteThrowing(
            account: account,
            synchronizable: synchronizable,
            service: itemService
        )
    }

    private func deleteThrowing(
        account: String,
        synchronizable: Bool,
        service itemService: String? = nil
    ) throws {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: itemService ?? service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        ]
        addAccessOptions(to: &query, service: itemService ?? service)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func addAccessOptions(to query: inout [CFString: Any], service itemService: String) {
        if let accessGroupPrefix {
            query[kSecAttrAccessGroup] = "\(accessGroupPrefix)\(itemService)"
        }
        #if os(macOS)
        query[kSecUseDataProtectionKeychain] = true
        #endif
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
