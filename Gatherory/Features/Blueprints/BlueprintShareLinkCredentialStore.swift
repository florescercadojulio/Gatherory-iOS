import CryptoKit
import Foundation
import Security

nonisolated struct BlueprintShareLinkCredential: Codable, Equatable, Sendable {
    let linkID: UUID
    let revision: Int
    let token: String

    var isValid: Bool {
        revision > 0 && BlueprintSharedTemplateLink.isValidToken(token)
    }
}

nonisolated struct BlueprintShareLinkCredentialScope: Codable, Equatable, Hashable, Sendable {
    let accountID: String
    let eventID: UUID
    let templateID: UUID
    let origin: String

    private init(accountID: String, eventID: UUID, templateID: UUID, origin: String) {
        self.accountID = accountID
        self.eventID = eventID
        self.templateID = templateID
        self.origin = origin
    }

    static func make(accountID: String, eventID: UUID, templateID: UUID, shareURL: URL) -> Self? {
        guard !accountID.isEmpty,
              let components = URLComponents(url: shareURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        var originComponents = URLComponents()
        originComponents.scheme = "https"
        originComponents.host = host.lowercased()
        originComponents.port = components.port
        guard let originURL = originComponents.url,
              BlueprintSharedTemplateLink.token(from: shareURL, baseURL: originURL) != nil,
              let origin = originComponents.string else { return nil }

        return Self(accountID: accountID, eventID: eventID, templateID: templateID, origin: origin)
    }

    private enum CodingKeys: String, CodingKey {
        case accountID
        case eventID
        case templateID
        case origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accountID = try container.decode(String.self, forKey: .accountID)
        let eventID = try container.decode(UUID.self, forKey: .eventID)
        let templateID = try container.decode(UUID.self, forKey: .templateID)
        let origin = try container.decode(String.self, forKey: .origin)
        guard !accountID.isEmpty,
              let url = URL(string: "\(origin)/templates/shared/\(String(repeating: "0", count: 64))"),
              let rebuilt = Self.make(accountID: accountID, eventID: eventID, templateID: templateID, shareURL: url),
              rebuilt.origin == origin else {
            throw BlueprintShareLinkCredentialStoreError.invalidRecord
        }
        self = rebuilt
    }
}

@MainActor
protocol BlueprintShareLinkCredentialStore {
    func load(_ scope: BlueprintShareLinkCredentialScope) throws -> BlueprintShareLinkCredential?
    func save(_ credential: BlueprintShareLinkCredential, for scope: BlueprintShareLinkCredentialScope) throws
    func remove(_ scope: BlueprintShareLinkCredentialScope) throws
}

@MainActor
protocol BlueprintShareLinkKeychainClient {
    func copyMatching(_ query: CFDictionary) -> (OSStatus, Data?)
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func add(_ query: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

@MainActor
private struct SystemBlueprintShareLinkKeychainClient: BlueprintShareLinkKeychainClient {
    func copyMatching(_ query: CFDictionary) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query, &result)
        return (status, result as? Data)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func add(_ query: CFDictionary) -> OSStatus {
        SecItemAdd(query, nil)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

@MainActor
struct KeychainBlueprintShareLinkCredentialStore: BlueprintShareLinkCredentialStore {
    private let servicePrefix: String
    private let keychain: any BlueprintShareLinkKeychainClient

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.guide-systems.gatherory") {
        self.init(bundleIdentifier: bundleIdentifier, keychain: SystemBlueprintShareLinkKeychainClient())
    }

    init(bundleIdentifier: String, keychain: any BlueprintShareLinkKeychainClient) {
        servicePrefix = "\(bundleIdentifier).blueprint-share-link-credential.v1"
        self.keychain = keychain
    }

    func load(_ scope: BlueprintShareLinkCredentialScope) throws -> BlueprintShareLinkCredential? {
        var query = try baseQuery(for: scope)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = keychain.copyMatching(query as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw BlueprintShareLinkCredentialStoreError.keychain(status)
        }
        guard let data else { throw BlueprintShareLinkCredentialStoreError.invalidRecord }
        return try BlueprintShareLinkCredentialRecordCodec.decode(data, for: scope)
    }

    func save(_ credential: BlueprintShareLinkCredential, for scope: BlueprintShareLinkCredentialScope) throws {
        let data = try BlueprintShareLinkCredentialRecordCodec.encode(credential, for: scope)
        let query = try baseQuery(for: scope)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = keychain.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw BlueprintShareLinkCredentialStoreError.keychain(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = keychain.add(addQuery as CFDictionary)
        if addStatus == errSecSuccess { return }
        if addStatus == errSecDuplicateItem {
            let retryStatus = keychain.update(query as CFDictionary, attributes: attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw BlueprintShareLinkCredentialStoreError.keychain(retryStatus)
            }
            return
        }
        throw BlueprintShareLinkCredentialStoreError.keychain(addStatus)
    }

    func remove(_ scope: BlueprintShareLinkCredentialScope) throws {
        let status = keychain.delete(try baseQuery(for: scope) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BlueprintShareLinkCredentialStoreError.keychain(status)
        }
    }

    func removeAll(accountID: String) throws {
        guard !accountID.isEmpty else { throw BlueprintShareLinkCredentialStoreError.invalidScope }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: accountID),
            kSecAttrSynchronizable as String: false
        ]
        let status = keychain.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BlueprintShareLinkCredentialStoreError.keychain(status)
        }
    }

    private func baseQuery(for scope: BlueprintShareLinkCredentialScope) throws -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(for: scope.accountID),
            kSecAttrAccount as String: try Self.accountKey(for: scope),
            kSecAttrSynchronizable as String: false
        ]
    }

    private func service(for accountID: String) -> String {
        "\(servicePrefix).\(Self.digest(Data(accountID.utf8)))"
    }

    private static func accountKey(for scope: BlueprintShareLinkCredentialScope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return digest(try encoder.encode(scope))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum BlueprintShareLinkCredentialStoreError: LocalizedError, Equatable {
    case invalidCredential
    case invalidScope
    case invalidRecord
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredential, .invalidScope, .invalidRecord:
            "Gatherory couldn’t use the saved share link."
        case .keychain:
            "Gatherory couldn’t access the secure saved share link."
        }
    }
}

enum BlueprintShareLinkCredentialRecordCodec {
    private struct Record: Codable {
        let version: Int
        let scope: BlueprintShareLinkCredentialScope
        let credential: BlueprintShareLinkCredential
    }

    static func encode(
        _ credential: BlueprintShareLinkCredential,
        for scope: BlueprintShareLinkCredentialScope
    ) throws -> Data {
        guard credential.isValid else { throw BlueprintShareLinkCredentialStoreError.invalidCredential }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Record(version: 1, scope: scope, credential: credential))
    }

    static func decode(_ data: Data, for expectedScope: BlueprintShareLinkCredentialScope) throws -> BlueprintShareLinkCredential {
        guard let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == 1,
              record.scope == expectedScope,
              record.credential.isValid else {
            throw BlueprintShareLinkCredentialStoreError.invalidRecord
        }
        return record.credential
    }
}
