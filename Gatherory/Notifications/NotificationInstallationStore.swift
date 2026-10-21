import Foundation
import Security

@MainActor protocol NotificationInstallationStoring {
    func loadIfExists() throws -> NotificationInstallation?
    func loadOrCreate() throws -> NotificationInstallation
    func nextRevision(minimum: Int) throws -> NotificationInstallation
    func markMayBeBound() throws
    func markDetached() throws
}

@MainActor struct KeychainNotificationInstallationStore: NotificationInstallationStoring {
    private let service: String
    private let account = "notification-installation"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.guide-systems.gatherory") {
        service = "\(bundleIdentifier).notifications"
    }

    func loadOrCreate() throws -> NotificationInstallation {
        if let existing = try loadIfExists() { return existing }
        let installation = NotificationInstallation(installationID: UUID(), secret: LocalGuestCredentialToken.make())
        var add = baseQuery
        add[kSecValueData as String] = try JSONEncoder().encode(installation)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw LocalGuestCredentialStoreError.keychain(addStatus) }
        return installation
    }

    func loadIfExists() throws -> NotificationInstallation? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw LocalGuestCredentialStoreError.keychain(status)
        }
        guard let installation = try? JSONDecoder().decode(NotificationInstallation.self, from: data),
              LocalGuestCredentialToken.isValid(installation.secret) else {
            throw LocalGuestCredentialStoreError.invalidSecret
        }
        return installation
    }

    func nextRevision(minimum: Int) throws -> NotificationInstallation {
        var installation = try loadOrCreate()
        installation.revision = max(installation.revision + 1, minimum)
        var changes: [String: Any] = [:]
        changes[kSecValueData as String] = try JSONEncoder().encode(installation)
        let status = SecItemUpdate(baseQuery as CFDictionary, changes as CFDictionary)
        guard status == errSecSuccess else { throw LocalGuestCredentialStoreError.keychain(status) }
        return installation
    }

    func markMayBeBound() throws { try updateBindingState(true) }
    func markDetached() throws { try updateBindingState(false) }

    private func updateBindingState(_ mayBeBound: Bool) throws {
        var installation = try loadOrCreate()
        installation.mayBeBound = mayBeBound
        var changes: [String: Any] = [:]
        changes[kSecValueData as String] = try JSONEncoder().encode(installation)
        let status = SecItemUpdate(baseQuery as CFDictionary, changes as CFDictionary)
        guard status == errSecSuccess else { throw LocalGuestCredentialStoreError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
