import Foundation
import Security
import Testing
@testable import Gatherory

@MainActor
final class MemoryBlueprintShareLinkCredentialStore: BlueprintShareLinkCredentialStore {
    private(set) var credentials: [BlueprintShareLinkCredentialScope: BlueprintShareLinkCredential] = [:]
    var loadError: Error?
    var saveError: Error?
    var removeError: Error?

    func load(_ scope: BlueprintShareLinkCredentialScope) throws -> BlueprintShareLinkCredential? {
        if let loadError { throw loadError }
        return credentials[scope]
    }

    func save(_ credential: BlueprintShareLinkCredential, for scope: BlueprintShareLinkCredentialScope) throws {
        if let saveError { throw saveError }
        guard credential.isValid else { throw BlueprintShareLinkCredentialStoreError.invalidCredential }
        credentials[scope] = credential
    }

    func remove(_ scope: BlueprintShareLinkCredentialScope) throws {
        if let removeError { throw removeError }
        credentials.removeValue(forKey: scope)
    }
}

@Suite(.serialized)
@MainActor
struct BlueprintShareLinkCredentialStoreTests {
    private let eventID = UUID(uuidString: "6336EE7B-E8A0-48B5-9013-211F6AC8E197")!
    private let templateID = UUID(uuidString: "942B95FB-31FC-48CF-AE20-1A5379A92056")!
    private let token = String(repeating: "a1", count: 32)

    @Test("Credential scope accepts only exact HTTPS shared-template URLs")
    func scopeValidationAndIdentity() throws {
        let url = try #require(URL(string: "https://APP.Gatherory.com/templates/shared/\(token)"))
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: url
        ))
        #expect(scope.origin == "https://app.gatherory.com")

        let otherAccount = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-b", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let otherEvent = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: UUID(), templateID: templateID, shareURL: url
        ))
        let otherTemplate = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: UUID(), shareURL: url
        ))
        let otherOriginURL = try #require(URL(string: "https://preview.gatherory.com/templates/shared/\(token)"))
        let otherOrigin = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: otherOriginURL
        ))
        #expect(scope != otherAccount)
        #expect(scope != otherEvent)
        #expect(scope != otherTemplate)
        #expect(scope != otherOrigin)

        for string in [
            "gatherory://template/\(token)",
            "http://app.gatherory.com/templates/shared/\(token)",
            "https://app.gatherory.com/templates/shared/\(token)?source=qr",
            "https://app.gatherory.com/templates/shared/\(token)#fragment",
            "https://app.gatherory.com/templates/shared/\(token)/extra",
            "https://user:secret@app.gatherory.com/templates/shared/\(token)",
            "https://app.gatherory.com/templates/shared/\(String(repeating: "A", count: 64))",
            "https://app.gatherory.com/other/shared/\(token)"
        ] {
            let invalidURL = try #require(URL(string: string))
            #expect(BlueprintShareLinkCredentialScope.make(
                accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: invalidURL
            ) == nil)
        }
        #expect(BlueprintShareLinkCredentialScope.make(
            accountID: "", eventID: eventID, templateID: templateID, shareURL: url
        ) == nil)
    }

    @Test("Memory store isolates credentials by full scope and removes only the selected scope")
    func memoryStoreRoundTripAndIsolation() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let otherAccountScope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-b", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let credential = BlueprintShareLinkCredential(linkID: UUID(), revision: 4, token: token)
        let store = MemoryBlueprintShareLinkCredentialStore()

        #expect(try store.load(scope) == nil)
        try store.save(credential, for: scope)
        #expect(try store.load(scope) == credential)
        #expect(try store.load(otherAccountScope) == nil)

        try store.save(BlueprintShareLinkCredential(linkID: UUID(), revision: 5, token: token), for: otherAccountScope)
        try store.remove(scope)
        #expect(try store.load(scope) == nil)
        #expect(try store.load(otherAccountScope)?.revision == 5)
    }

    @Test("Stored record validates version, exact scope, revision, and token before returning a credential")
    func recordCodecValidation() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let otherScope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-b", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let credential = BlueprintShareLinkCredential(linkID: UUID(), revision: 4, token: token)
        let encoded = try BlueprintShareLinkCredentialRecordCodec.encode(credential, for: scope)

        #expect(try BlueprintShareLinkCredentialRecordCodec.decode(encoded, for: scope) == credential)
        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidRecord) {
            try BlueprintShareLinkCredentialRecordCodec.decode(encoded, for: otherScope)
        }

        var record = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        record["version"] = 2
        let unsupportedVersion = try JSONSerialization.data(withJSONObject: record)
        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidRecord) {
            try BlueprintShareLinkCredentialRecordCodec.decode(unsupportedVersion, for: scope)
        }

        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidCredential) {
            try BlueprintShareLinkCredentialRecordCodec.encode(
                BlueprintShareLinkCredential(linkID: UUID(), revision: 0, token: token), for: scope
            )
        }
        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidCredential) {
            try BlueprintShareLinkCredentialRecordCodec.encode(
                BlueprintShareLinkCredential(linkID: UUID(), revision: 4, token: "invalid"), for: scope
            )
        }
    }

    @Test("Keychain failures preserve credentials and duplicate adds retry with an update")
    func keychainErrorHandling() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let existing = BlueprintShareLinkCredential(linkID: UUID(), revision: 4, token: token)
        let replacement = BlueprintShareLinkCredential(linkID: existing.linkID, revision: 5, token: token)
        let fake = MemoryBlueprintCredentialKeychainClient()
        let store = KeychainBlueprintShareLinkCredentialStore(bundleIdentifier: "errors.gatherory", keychain: fake)
        try store.save(existing, for: scope)

        fake.nextCopyStatus = errSecInteractionNotAllowed
        #expect(throws: BlueprintShareLinkCredentialStoreError.keychain(errSecInteractionNotAllowed)) {
            try store.load(scope)
        }

        fake.nextUpdateStatus = errSecInteractionNotAllowed
        #expect(throws: BlueprintShareLinkCredentialStoreError.keychain(errSecInteractionNotAllowed)) {
            try store.save(replacement, for: scope)
        }
        #expect(try store.load(scope) == existing)

        fake.nextUpdateStatus = errSecItemNotFound
        fake.nextAddStatus = errSecDuplicateItem
        try store.save(replacement, for: scope)
        #expect(try store.load(scope) == replacement)
        #expect(fake.updateCount == 1)

        fake.nextDeleteStatus = errSecInteractionNotAllowed
        #expect(throws: BlueprintShareLinkCredentialStoreError.keychain(errSecInteractionNotAllowed)) {
            try store.remove(scope)
        }
        #expect(try store.load(scope) == replacement)
    }

    @Test("Keychain namespace isolates accounts and account deletion removes corrupt records too")
    func keychainAccountNamespaceAndRemoval() throws {
        let url = try #require(URL(string: "https://app.gatherory.com/templates/shared/\(token)"))
        let scopeA = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-a", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let scopeB = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner-b", eventID: eventID, templateID: templateID, shareURL: url
        ))
        let fake = MemoryBlueprintCredentialKeychainClient()
        let store = KeychainBlueprintShareLinkCredentialStore(bundleIdentifier: "tests.gatherory", keychain: fake)
        let credentialA = BlueprintShareLinkCredential(linkID: UUID(), revision: 4, token: token)
        let credentialB = BlueprintShareLinkCredential(linkID: UUID(), revision: 5, token: token)

        try store.save(credentialA, for: scopeA)
        try store.save(credentialB, for: scopeB)
        #expect(fake.itemCount == 2)
        #expect(try store.load(scopeA) == credentialA)
        #expect(try store.load(scopeB) == credentialB)
        #expect(fake.lastAddedAttributes?[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(fake.lastAddedAttributes?[kSecAttrSynchronizable as String] as? Bool == false)

        let replacement = BlueprintShareLinkCredential(linkID: credentialA.linkID, revision: 6, token: token)
        try store.save(replacement, for: scopeA)
        #expect(fake.itemCount == 2)
        #expect(try store.load(scopeA) == replacement)
        #expect(fake.updateCount == 1)

        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidScope) { try store.removeAll(accountID: "") }
        try store.removeAll(accountID: "owner-a")
        #expect(try store.load(scopeA) == nil)
        #expect(try store.load(scopeB) == credentialB)

        fake.corruptAllItems()
        #expect(throws: BlueprintShareLinkCredentialStoreError.invalidRecord) { try store.load(scopeB) }
        try store.removeAll(accountID: "owner-b")
        #expect(try store.load(scopeB) == nil)
        #expect(fake.itemCount == 0)
    }
}

@MainActor
private final class MemoryBlueprintCredentialKeychainClient: BlueprintShareLinkKeychainClient {
    private struct ItemKey: Hashable {
        let service: String
        let account: String
    }

    private var items: [ItemKey: Data] = [:]
    private(set) var lastAddedAttributes: [String: Any]?
    private(set) var updateCount = 0
    var nextCopyStatus: OSStatus?
    var nextUpdateStatus: OSStatus?
    var nextAddStatus: OSStatus?
    var nextDeleteStatus: OSStatus?
    var itemCount: Int { items.count }

    func copyMatching(_ query: CFDictionary) -> (OSStatus, Data?) {
        if let nextCopyStatus {
            self.nextCopyStatus = nil
            return (nextCopyStatus, nil)
        }
        let values = dictionary(query)
        guard let key = itemKey(values), let data = items[key] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        if let nextUpdateStatus {
            self.nextUpdateStatus = nil
            if nextUpdateStatus != errSecSuccess { return nextUpdateStatus }
        }
        guard let key = itemKey(dictionary(query)), items[key] != nil else { return errSecItemNotFound }
        let values = dictionary(attributes)
        if let data = values[kSecValueData as String] as? Data { items[key] = data }
        updateCount += 1
        return errSecSuccess
    }

    func add(_ query: CFDictionary) -> OSStatus {
        if let nextAddStatus {
            self.nextAddStatus = nil
            if nextAddStatus != errSecSuccess { return nextAddStatus }
        }
        let values = dictionary(query)
        guard let key = itemKey(values), let data = values[kSecValueData as String] as? Data else { return errSecParam }
        guard items[key] == nil else { return errSecDuplicateItem }
        items[key] = data
        lastAddedAttributes = values
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        if let nextDeleteStatus {
            self.nextDeleteStatus = nil
            if nextDeleteStatus != errSecSuccess { return nextDeleteStatus }
        }
        let values = dictionary(query)
        guard let service = values[kSecAttrService as String] as? String else { return errSecParam }
        if let key = itemKey(values) {
            return items.removeValue(forKey: key) == nil ? errSecItemNotFound : errSecSuccess
        }
        let matching = items.keys.filter { $0.service == service }
        guard !matching.isEmpty else { return errSecItemNotFound }
        for key in matching { items.removeValue(forKey: key) }
        return errSecSuccess
    }

    func corruptAllItems() {
        for key in Array(items.keys) { items[key] = Data("corrupt".utf8) }
    }

    private func itemKey(_ values: [String: Any]) -> ItemKey? {
        guard let service = values[kSecAttrService as String] as? String,
              let account = values[kSecAttrAccount as String] as? String else { return nil }
        return ItemKey(service: service, account: account)
    }

    private func dictionary(_ dictionary: CFDictionary) -> [String: Any] {
        (dictionary as NSDictionary) as? [String: Any] ?? [:]
    }
}
