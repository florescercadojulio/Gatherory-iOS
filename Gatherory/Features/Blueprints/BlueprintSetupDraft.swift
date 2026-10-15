import Foundation
import CryptoKit

nonisolated struct BlueprintSetupDraft: Codable, Sendable {
    var schemaVersion: Int = 1
    var ownerUserID: String
    var entry: BlueprintCatalogEntry
    var requestID: UUID
    var eventName: String
    var startsAt: Date
    var timeZoneIdentifier: String
    var selectedChildren: Set<String>
    var selectedIdeas: Set<String>
    var confirmedDates: [String: Date]
    var shareToken: String? = nil
}

nonisolated final class BlueprintSetupDraftStore {
    enum StoreError: Error, Equatable {
        case emptyIdentity
        case unsupportedSchemaVersion(Int)
        case ownerMismatch
        case catalogMismatch
        case invalidRevision
        case invalidContentHash
        case invalidTimeZone
        case invalidDate
        case invalidSelectionIdentifier
        case invalidShareToken
        case corruptData
    }

    private struct Envelope: Codable {
        let formatVersion: Int
        let draft: BlueprintSetupDraft
    }

    private static let formatVersion = 1
    private static let fileName = "draft.json"
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
            self.directoryURL = supportURL
                .appendingPathComponent("Gatherory", isDirectory: true)
                .appendingPathComponent("BlueprintSetupDrafts", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    func load(ownerUserID: String, catalogKey: String, shareToken: String? = nil) throws -> BlueprintSetupDraft? {
        try validateIdentity(ownerUserID, catalogKey)
        let fileURL = draftURL(ownerUserID: ownerUserID, catalogKey: catalogKey, shareToken: shareToken)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try readDraft(at: fileURL, ownerUserID: ownerUserID, catalogKey: catalogKey, shareToken: shareToken)
    }

    func load(ownerUserID: String, shareToken: String) throws -> BlueprintSetupDraft? {
        guard !ownerUserID.isEmpty, BlueprintSharedTemplateLink.isValidToken(shareToken) else {
            throw StoreError.emptyIdentity
        }
        let fileURL = directoryURL
            .appendingPathComponent(Self.pathComponent(ownerUserID), isDirectory: true)
            .appendingPathComponent(Self.directoryComponent(catalogKey: "", shareToken: shareToken), isDirectory: true)
            .appendingPathComponent(Self.fileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try readDraft(at: fileURL, ownerUserID: ownerUserID, catalogKey: nil, shareToken: shareToken)
    }

    func all(ownerUserID: String) throws -> [BlueprintSetupDraft] {
        guard !ownerUserID.isEmpty else { throw StoreError.emptyIdentity }
        let ownerDirectoryURL = directoryURL.appendingPathComponent(Self.pathComponent(ownerUserID), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: ownerDirectoryURL.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { throw StoreError.corruptData }

        let catalogDirectories = try FileManager.default.contentsOfDirectory(
            at: ownerDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        var drafts: [BlueprintSetupDraft] = []
        drafts.reserveCapacity(catalogDirectories.count)
        for catalogDirectoryURL in catalogDirectories {
            let values = try catalogDirectoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { throw StoreError.corruptData }
            let contents = try FileManager.default.contentsOfDirectory(atPath: catalogDirectoryURL.path)
            if contents.isEmpty { continue }
            guard contents == [Self.fileName] else { throw StoreError.corruptData }
            let fileURL = catalogDirectoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
            let draft = try readDraft(at: fileURL, ownerUserID: ownerUserID, catalogKey: nil)
            guard catalogDirectoryURL.lastPathComponent == Self.directoryComponent(
                catalogKey: draft.entry.catalogKey,
                shareToken: draft.shareToken
            ) else {
                throw StoreError.catalogMismatch
            }
            drafts.append(draft)
        }

        return drafts.sorted { $0.entry.catalogKey < $1.entry.catalogKey }
    }

    func save(_ draft: BlueprintSetupDraft) throws {
        try validate(draft, expectedOwnerUserID: draft.ownerUserID, expectedCatalogKey: draft.entry.catalogKey)
        let fileURL = draftURL(
            ownerUserID: draft.ownerUserID,
            catalogKey: draft.entry.catalogKey,
            shareToken: draft.shareToken
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encode(Envelope(formatVersion: Self.formatVersion, draft: draft))
        try data.write(to: fileURL, options: .atomic)
    }

    func remove(ownerUserID: String, catalogKey: String, requestID: UUID, shareToken: String? = nil) throws {
        try validateIdentity(ownerUserID, catalogKey)
        let fileURL = draftURL(ownerUserID: ownerUserID, catalogKey: catalogKey, shareToken: shareToken)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let draft = try readDraft(at: fileURL, ownerUserID: ownerUserID, catalogKey: catalogKey, shareToken: shareToken)
        guard draft.requestID == requestID else { return }
        try FileManager.default.removeItem(at: fileURL)

        let catalogDirectoryURL = fileURL.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: catalogDirectoryURL.path).isEmpty) == true {
            try? FileManager.default.removeItem(at: catalogDirectoryURL)
        }
    }

    private func readDraft(
        at fileURL: URL,
        ownerUserID: String,
        catalogKey: String?,
        shareToken: String? = nil
    ) throws -> BlueprintSetupDraft {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StoreError.corruptData
        }

        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw StoreError.corruptData
        }
        guard envelope.formatVersion == Self.formatVersion else {
            throw StoreError.unsupportedSchemaVersion(envelope.formatVersion)
        }
        try validate(
            envelope.draft,
            expectedOwnerUserID: ownerUserID,
            expectedCatalogKey: catalogKey,
            expectedShareToken: shareToken
        )
        return envelope.draft
    }

    private func validate(
        _ draft: BlueprintSetupDraft,
        expectedOwnerUserID: String,
        expectedCatalogKey: String?,
        expectedShareToken: String? = nil
    ) throws {
        guard !draft.ownerUserID.isEmpty,
              !draft.entry.catalogKey.isEmpty,
              !expectedOwnerUserID.isEmpty,
              expectedCatalogKey.map({ !$0.isEmpty }) ?? true
        else { throw StoreError.emptyIdentity }
        guard draft.schemaVersion == 1 else { throw StoreError.unsupportedSchemaVersion(draft.schemaVersion) }
        guard draft.ownerUserID == expectedOwnerUserID else { throw StoreError.ownerMismatch }
        if let expectedCatalogKey, draft.entry.catalogKey != expectedCatalogKey {
            throw StoreError.catalogMismatch
        }
        if let expectedShareToken, draft.shareToken != expectedShareToken {
            throw StoreError.catalogMismatch
        }
        if let shareToken = draft.shareToken, !BlueprintSharedTemplateLink.isValidToken(shareToken) {
            throw StoreError.invalidShareToken
        }
        guard draft.entry.revision > 0 else { throw StoreError.invalidRevision }
        let hash = draft.entry.contentHash
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else {
            throw StoreError.invalidContentHash
        }
        guard TimeZone(identifier: draft.timeZoneIdentifier) != nil else { throw StoreError.invalidTimeZone }
        guard draft.startsAt.timeIntervalSince1970.isFinite,
              draft.confirmedDates.values.allSatisfy({ $0.timeIntervalSince1970.isFinite })
        else { throw StoreError.invalidDate }
        guard draft.selectedChildren.allSatisfy({ !$0.isEmpty }),
              draft.selectedIdeas.allSatisfy({ !$0.isEmpty }),
              draft.confirmedDates.keys.allSatisfy({ !$0.isEmpty })
        else { throw StoreError.invalidSelectionIdentifier }
    }

    private func validateIdentity(_ ownerUserID: String, _ catalogKey: String) throws {
        guard !ownerUserID.isEmpty, !catalogKey.isEmpty else { throw StoreError.emptyIdentity }
    }

    private func encode(_ envelope: Envelope) throws -> Data {
        do {
            return try encoder.encode(envelope)
        } catch {
            throw StoreError.corruptData
        }
    }

    private func draftURL(ownerUserID: String, catalogKey: String, shareToken: String?) -> URL {
        directoryURL
            .appendingPathComponent(Self.pathComponent(ownerUserID), isDirectory: true)
            .appendingPathComponent(Self.directoryComponent(catalogKey: catalogKey, shareToken: shareToken), isDirectory: true)
            .appendingPathComponent(Self.fileName, isDirectory: false)
    }

    private static func directoryComponent(catalogKey: String, shareToken: String?) -> String {
        guard let shareToken else { return pathComponent(catalogKey) }
        let digest = SHA256.hash(data: Data(shareToken.utf8)).map { String(format: "%02x", $0) }.joined()
        return "shared-" + digest
    }

    private static func pathComponent(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
