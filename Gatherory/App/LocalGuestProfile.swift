import Foundation
import Security

/// A device-only identity for local planning and guest participation. It is
/// deliberately separate from `UserAccount` and never authenticates to Gatherory.
nonisolated struct LocalGuestProfile: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let displayName: String

    var storageID: String { "device-guest:\(id.uuidString.lowercased())" }
    var hasValidDisplayName: Bool {
        let count = displayName.unicodeScalars.count
        return (1...80).contains(count)
            && displayName == displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(id: UUID = UUID(), displayName: String) {
        self.id = id
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = normalized
    }
}

enum LocalGuestProfileStoreError: Error, Equatable {
    case invalidProfile
}

@MainActor protocol LocalGuestProfileStore {
    func load() throws -> LocalGuestProfile?
    func save(_ profile: LocalGuestProfile) throws
    func remove() throws
}

/// Stores only the non-secret display identity in an app-private file. The
/// separate guest credential remains in Keychain.
@MainActor struct DeviceLocalGuestProfileStore: LocalGuestProfileStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = URL.applicationSupportDirectory
                .appending(path: "LocalGuest/profile.json")
        }
    }

    func load() throws -> LocalGuestProfile? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let profile = try JSONDecoder().decode(LocalGuestProfile.self, from: Data(contentsOf: fileURL))
        guard profile.storageID == "device-guest:\(profile.id.uuidString.lowercased())",
              profile.hasValidDisplayName else {
            throw LocalGuestProfileStoreError.invalidProfile
        }
        return profile
    }

    func save(_ profile: LocalGuestProfile) throws {
        guard profile.hasValidDisplayName else { throw LocalGuestProfileStoreError.invalidProfile }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(profile)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}

enum LocalGuestCredentialStoreError: Error, Equatable {
    case keychain(OSStatus)
    case invalidSecret
}

enum LocalGuestCredentialToken {
    static func isValid(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        guard bytes.count == 43,
              bytes.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0)
                      || (48...57).contains($0) || $0 == 45 || $0 == 95
              }) else { return false }
        let base64 = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + "="
        guard let decoded = Data(base64Encoded: base64), decoded.count == 32 else { return false }
        return base64URL(decoded) == token
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }
}

@MainActor protocol LocalGuestCredentialStore {
    func loadOrCreateToken(profileID: UUID) throws -> String
    func removeSecret(profileID: UUID) throws
}

/// Device-only secret storage for event-only guest grants. This credential is
/// intentionally unrelated to Better Auth sessions and cannot create a planner
/// account.
@MainActor struct KeychainLocalGuestCredentialStore: LocalGuestCredentialStore {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier.map { "\($0).local-guest" } ?? "Gatherory.local-guest") {
        self.service = service
    }

    func loadOrCreateToken(profileID: UUID) throws -> String {
        let account = profileID.uuidString.lowercased()
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let secret = result as? Data,
                  let token = String(data: secret, encoding: .utf8),
                  LocalGuestCredentialToken.isValid(token) else {
                throw LocalGuestCredentialStoreError.invalidSecret
            }
            return token
        }
        guard status == errSecItemNotFound else {
            throw LocalGuestCredentialStoreError.keychain(status)
        }

        let token = LocalGuestCredentialToken.make()
        var add = baseQuery(account: account)
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return try loadOrCreateToken(profileID: profileID)
        }
        guard addStatus == errSecSuccess else {
            throw LocalGuestCredentialStoreError.keychain(addStatus)
        }
        return token
    }

    func removeSecret(profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(account: profileID.uuidString.lowercased()) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalGuestCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

@MainActor final class MemoryLocalGuestProfileStore: LocalGuestProfileStore {
    private(set) var profile: LocalGuestProfile?
    var failSave = false
    var failRemove = false

    func load() throws -> LocalGuestProfile? { profile }
    func save(_ profile: LocalGuestProfile) throws {
        guard !failSave else { throw CocoaError(.fileWriteUnknown) }
        self.profile = profile
    }
    func remove() throws {
        guard !failRemove else { throw CocoaError(.fileWriteUnknown) }
        profile = nil
    }
}

@MainActor final class MemoryLocalGuestCredentialStore: LocalGuestCredentialStore {
    private(set) var tokens: [UUID: String] = [:]

    func loadOrCreateToken(profileID: UUID) throws -> String {
        if let token = tokens[profileID] { return token }
        let token = LocalGuestCredentialToken.make()
        tokens[profileID] = token
        return token
    }

    func removeSecret(profileID: UUID) throws { tokens.removeValue(forKey: profileID) }
}
