import Foundation
import Observation

enum BlueprintLibraryActionPolicy {
    static func blocksInlineInstall(isInstalled: Bool, explicitCreateWorkspace: Bool) -> Bool {
        isInstalled && !explicitCreateWorkspace
    }
}

nonisolated struct BlueprintUsedTemplate: Codable, Equatable, Identifiable, Sendable {
    let installationID: UUID
    let scopeID: UUID
    let catalogKey: String
    let revision: Int
    let templateName: String
    let eventName: String
    /// Kept as the server's RFC 3339 string so fractional seconds decode consistently.
    let installedAt: String
    /// Optional local source for offline reuse, including unlisted templates.
    var sourceDraftData: Data? = nil

    var id: UUID { installationID }

    var libraryTemplateKey: String { "\(catalogKey):\(revision)" }

    var installedDate: Date? {
        BlueprintLibraryDate.parse(installedAt)
    }

    func previewSource(ownerID: String) throws -> BlueprintSetupDraft? {
        guard let sourceDraftData else { return nil }
        let draft = try JSONDecoder().decode(BlueprintSetupDraft.self, from: sourceDraftData)
        guard draft.ownerUserID == ownerID else { throw BlueprintLibraryCache.StoreError.ownerMismatch }
        guard draft.entry.catalogKey == catalogKey, draft.entry.revision == revision else {
            throw BlueprintLibraryCache.StoreError.invalidResponse
        }
        return draft
    }

    /// Resolve at action time, not from the card's potentially stale snapshot.
    /// Installation receipts identify past copies; they never bind those copies to future edits.
    func workspaceDraft(ownerID: String, store: BlueprintSetupDraftStore) throws -> BlueprintSetupDraft? {
        guard let source = try previewSource(ownerID: ownerID) else { return nil }
        if let saved = try store.load(ownerUserID: ownerID, catalogKey: catalogKey) {
            return saved
        }
        if let token = source.shareToken,
           var saved = try store.load(ownerUserID: ownerID, catalogKey: catalogKey, shareToken: token) {
            saved.shareToken = nil
            try store.save(saved)
            try store.remove(ownerUserID: ownerID, catalogKey: catalogKey, requestID: saved.requestID, shareToken: token)
            return saved
        }
        var copy = try source.freshWorkspaceCopy(ownerID: ownerID)
        // Completed copies use their exact-source grant, not a revocable entry link.
        copy.shareToken = nil
        try store.save(copy)
        return copy
    }
}

nonisolated struct BlueprintLibraryResponse: Codable, Equatable, Sendable {
    let installations: [BlueprintUsedTemplate]
}

nonisolated private enum BlueprintLibraryDate {
    static func parse(_ value: String) -> Date? {
        guard value.unicodeScalars.count <= 29 else { return nil }
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if value.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
        return formatter.date(from: value)
    }
}

nonisolated final class BlueprintLibraryCache {
    enum StoreError: Error, Equatable {
        case emptyOwner
        case ownerMismatch
        case unsupportedVersion(Int)
        case invalidResponse
        case corruptData
    }

    private struct Envelope: Codable {
        let formatVersion: Int
        let ownerID: String
        let installations: [BlueprintUsedTemplate]
    }

    private static let formatVersion = 1
    private static let maximumRows = 200
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
                .appendingPathComponent("BlueprintLibrary", isDirectory: true)
        }
    }

    func load(ownerID: String) throws -> [BlueprintUsedTemplate] {
        try validateOwner(ownerID)
        let fileURL = fileURL(ownerID: ownerID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        } catch {
            throw StoreError.corruptData
        }
        guard envelope.formatVersion == Self.formatVersion else {
            throw StoreError.unsupportedVersion(envelope.formatVersion)
        }
        guard envelope.ownerID == ownerID else { throw StoreError.ownerMismatch }
        guard let valid = Self.validated(envelope.installations), valid == envelope.installations else {
            throw StoreError.invalidResponse
        }
        return valid
    }

    /// Merges a successfully imported installation into the durable history cache.
    /// Re-recording an installation replaces its metadata and moves it to the front.
    func record(_ installation: BlueprintUsedTemplate, ownerID: String) throws {
        try validateOwner(ownerID)
        guard Self.validated([installation]) != nil else { throw StoreError.invalidResponse }
        var installations = try load(ownerID: ownerID)
        installations.removeAll { $0.installationID == installation.installationID }
        installations.insert(installation, at: 0)
        try save(Array(installations.prefix(Self.maximumRows)), ownerID: ownerID)
    }

    /// Edits the reusable local blueprint only; receipt/scope IDs never change.
    func updateSource(_ draft: BlueprintSetupDraft, installationID: UUID, ownerID: String) throws {
        guard draft.ownerUserID == ownerID else { throw StoreError.ownerMismatch }
        var rows = try load(ownerID: ownerID)
        guard let index = rows.firstIndex(where: { $0.id == installationID }),
              rows[index].catalogKey == draft.entry.catalogKey,
              rows[index].revision == draft.entry.revision else { throw StoreError.invalidResponse }
        rows[index].sourceDraftData = try JSONEncoder().encode(draft)
        try save(rows, ownerID: ownerID)
    }

    func save(_ installations: [BlueprintUsedTemplate], ownerID: String) throws {
        try validateOwner(ownerID)
        guard let valid = Self.validated(installations), valid == installations else {
            throw StoreError.invalidResponse
        }
        let url = fileURL(ownerID: ownerID)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(Envelope(
                formatVersion: Self.formatVersion,
                ownerID: ownerID,
                installations: valid
            ))
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.corruptData
        }
    }

    static func validated(_ installations: [BlueprintUsedTemplate]) -> [BlueprintUsedTemplate]? {
        guard installations.count <= maximumRows else { return nil }
        var seen: [UUID: BlueprintUsedTemplate] = [:]
        var rows: [BlueprintUsedTemplate] = []
        rows.reserveCapacity(installations.count)
        for row in installations {
            guard isValid(row) else { return nil }
            if let prior = seen[row.installationID] {
                // Exact retries can repeat a stable installation; conflicting values are malformed.
                guard prior == row else { return nil }
                continue
            }
            seen[row.installationID] = row
            rows.append(row)
        }
        return rows
    }

    private static func isValid(_ row: BlueprintUsedTemplate) -> Bool {
        row.revision > 0 &&
            validCatalogKey(row.catalogKey) &&
            boundedScalars(row.templateName, maximum: 160) &&
            boundedScalars(row.eventName, maximum: 120) &&
            BlueprintLibraryDate.parse(row.installedAt) != nil
    }

    private static func validCatalogKey(_ value: String) -> Bool {
        guard value.unicodeScalars.count <= 100 else { return false }
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first, (97...122).contains(first.value) else { return false }
        return scalars.dropFirst().allSatisfy { scalar in
            (97...122).contains(scalar.value) || (48...57).contains(scalar.value) || scalar.value == 95
        }
    }

    private static func boundedScalars(_ value: String, maximum: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && value.unicodeScalars.count <= maximum
    }

    private func validateOwner(_ ownerID: String) throws {
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.emptyOwner
        }
    }

    private func fileURL(ownerID: String) -> URL {
        // Base64-url encoding prevents account IDs from becoming path components.
        let component = Data(ownerID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appendingPathComponent(component + ".json", isDirectory: false)
    }
}

/// Library visibility is local metadata, not deletion of receipts or workspaces.
struct BlueprintLibraryVisibilityStore {
    var defaults: UserDefaults = .standard

    private func key(_ ownerID: String) -> String {
        "blueprint.library.hidden.v1." + Data(ownerID.utf8).base64EncodedString()
    }

    func hiddenIDs(ownerID: String) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key(ownerID)) ?? []).compactMap(UUID.init(uuidString:)))
    }

    func hide(_ id: UUID, ownerID: String) {
        guard !ownerID.isEmpty else { return }
        var ids = hiddenIDs(ownerID: ownerID)
        ids.insert(id)
        defaults.set(ids.map(\.uuidString).sorted(), forKey: key(ownerID))
    }

    func visible(_ rows: [BlueprintUsedTemplate], ownerID: String) -> [BlueprintUsedTemplate] {
        let hidden = hiddenIDs(ownerID: ownerID)
        // Receipts describe workspace copies, not new blueprints. Keep the original
        // library identity/source when another copy changes only its setup dates.
        let groups = Dictionary(grouping: rows, by: \.libraryTemplateKey)
        let representatives = groups.values.compactMap { group -> BlueprintUsedTemplate? in
            guard !group.contains(where: { hidden.contains($0.id) }) else { return nil }
            return group.min {
                if $0.installedDate != $1.installedDate {
                    return ($0.installedDate ?? .distantPast) < ($1.installedDate ?? .distantPast)
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        let ids = Set(representatives.map(\.id))
        return rows.filter { ids.contains($0.id) }
    }
}

@MainActor @Observable
final class BlueprintLibraryModel {
    private(set) var installations: [BlueprintUsedTemplate] = []
    private(set) var loading = false
    private(set) var refreshFailed = false
    private(set) var cacheFailed = false

    let ownerID: String

    @ObservationIgnored private let cache: BlueprintLibraryCache
    @ObservationIgnored private let visibility: BlueprintLibraryVisibilityStore
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isInvalidated = false

    init(ownerID: String, cache: BlueprintLibraryCache = BlueprintLibraryCache(),
         visibility: BlueprintLibraryVisibilityStore? = nil) {
        // Default arguments are evaluated outside this initializer's actor.
        // Create the actor-isolated store here, on the model's main actor.
        let visibility = visibility ?? BlueprintLibraryVisibilityStore()
        self.ownerID = ownerID
        self.cache = cache
        self.visibility = visibility
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cacheFailed = true
            return
        }
        do {
            installations = visibility.visible(try cache.load(ownerID: ownerID), ownerID: ownerID)
        } catch {
            cacheFailed = true
        }
    }

    func load(fetch: () async throws -> BlueprintLibraryResponse) async {
        guard !isInvalidated, !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let requestGeneration = UUID()
        generation = requestGeneration
        loading = true
        refreshFailed = false
        do {
            installations = visibility.visible(try cache.load(ownerID: ownerID), ownerID: ownerID)
            cacheFailed = false
        } catch {
            // A failed reread must not erase rows already visible in memory.
            cacheFailed = true
        }
        defer {
            if isCurrent(requestGeneration) { loading = false }
        }

        do {
            let response = try await fetch()
            guard isCurrent(requestGeneration), !Task.isCancelled,
                  var valid = BlueprintLibraryCache.validated(response.installations)
            else {
                if isCurrent(requestGeneration), !Task.isCancelled { refreshFailed = true }
                return
            }
            let cached = (try? cache.load(ownerID: ownerID)) ?? []
            for index in valid.indices where valid[index].sourceDraftData == nil {
                valid[index].sourceDraftData = cached.first { $0.id == valid[index].id }?.sourceDraftData
            }
            installations = visibility.visible(valid, ownerID: ownerID)
            do {
                try cache.save(valid, ownerID: ownerID)
                cacheFailed = false
            } catch {
                cacheFailed = true
            }
        } catch {
            guard isCurrent(requestGeneration), !Task.isCancelled else { return }
            refreshFailed = true
        }
    }

    /// Hide only this history entry. The receipt cache and workspace outbox are untouched.
    func removeFromLibrary(_ installation: BlueprintUsedTemplate) {
        guard !isInvalidated, installations.contains(where: { $0.id == installation.id }) else { return }
        visibility.hide(installation.id, ownerID: ownerID)
        installations.removeAll { $0.id == installation.id }
    }

    /// Prevents any in-flight response from updating a model whose account context ended.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        generation = UUID()
        installations = []
        loading = false
    }

    private func isCurrent(_ requestGeneration: UUID) -> Bool {
        !isInvalidated && generation == requestGeneration
    }
}
