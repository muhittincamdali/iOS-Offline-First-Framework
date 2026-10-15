import Foundation
import Security

/// Small values in the Keychain, such as the encryption key of a store.
///
/// ```swift
/// let keychain = KeychainStore(service: "com.example.notes")
/// try keychain.save(tokenData, for: "auth-token")
/// let token = try keychain.load("auth-token")
/// ```
///
/// Items are generic passwords identified by ``service`` and the account name you pass.
public struct KeychainStore: Sendable {
    /// When the Keychain releases an item.
    public enum Accessibility: Sendable {
        /// After the first unlock following a restart, and only on this device (the item is not
        /// restored to another device from a backup). The default; background tasks can read it.
        case afterFirstUnlockThisDeviceOnly
        /// After the first unlock following a restart; included in encrypted backups.
        case afterFirstUnlock
        /// Only while the device is unlocked, and only on this device.
        case whenUnlockedThisDeviceOnly
        /// Only while the device is unlocked; included in encrypted backups.
        case whenUnlocked

        var attribute: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
            case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
            }
        }
    }

    /// The Keychain service that groups the items of this store.
    public let service: String

    /// The Keychain access group shared with other apps, or `nil` for the app's own group.
    public let accessGroup: String?

    /// When the Keychain releases items saved by this store.
    public let accessibility: Accessibility

    /// Creates a store for one Keychain service.
    public init(service: String, accessGroup: String? = nil, accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }

    /// Saves `data` for `account`, replacing an existing item.
    public func save(_ data: Data, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.attribute
        ]
        let updateStatus = SecItemUpdate(query(for: account) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw OfflineFirstError.keychain(status: updateStatus) }

        var item = query(for: account)
        item.merge(attributes) { $1 }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw OfflineFirstError.keychain(status: addStatus) }
    }

    /// Adds `data` for `account` only if there is no item yet, and returns the stored data:
    /// `data` when it was added, or the existing item when another caller was first.
    public func saveIfAbsent(_ data: Data, for account: String) throws -> Data {
        var item = query(for: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessibility.attribute
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess { return data }
        guard status == errSecDuplicateItem else { throw OfflineFirstError.keychain(status: status) }
        guard let existing = try load(account) else { throw OfflineFirstError.keychain(status: errSecItemNotFound) }
        return existing
    }

    /// The data saved for `account`, or `nil` when there is none.
    public func load(_ account: String) throws -> Data? {
        var request = query(for: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw OfflineFirstError.keychain(status: status)
        }
        return data
    }

    /// Deletes the item for `account`. Deleting a missing item is not an error.
    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OfflineFirstError.keychain(status: status)
        }
    }

    private func query(for account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
