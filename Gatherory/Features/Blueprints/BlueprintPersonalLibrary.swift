import Foundation

/// The editable content owned by an account. Its wire shape intentionally
/// matches the web API's BlueprintDraftContent object.
nonisolated struct BlueprintDraftContent: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var experienceType: String
    var children: [BlueprintCatalogChild]
    var ideas: [BlueprintCatalogIdea]
    var instructions: [BlueprintDraftInstruction]
}

nonisolated struct BlueprintDraftInstruction: Codable, Equatable, Identifiable, Sendable {
    var key: String
    var title: String
    var body: String
    var audience: ExperienceGuideVisibility
    var target: BlueprintTarget
    var id: String { key }
}

nonisolated struct BlueprintPersonalRecord: Codable, Identifiable, Sendable {
    let id: UUID
    var draftVersion: Int
    var publishedRevision: Int?
    var listedRevision: Int?
    var catalogEntry: BlueprintCatalogEntry
}

nonisolated struct BlueprintPersonalListResponse: Decodable, Sendable {
    let templates: [BlueprintPersonalRecord]
}

@MainActor protocol BlueprintPersonalLibraryTransport {
    func listPersonalBlueprints() async throws -> [BlueprintPersonalRecord]
    func savePersonalBlueprint(id: UUID, expectedVersion: Int, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord
    func deletePersonalBlueprint(id: UUID) async throws
    func publishPersonalBlueprint(id: UUID, expectedVersion: Int) async throws -> BlueprintPersonalRecord
}

nonisolated enum BlueprintPersonalLibraryError: Error, Equatable {
    case emptyOwner
    case ownerMismatch
    case invalidRecord
    case corruptCache
}

nonisolated final class BlueprintPersonalLibraryStore {
    private struct Envelope: Codable {
        let version: Int
        let ownerID: String
        let records: [BlueprintPersonalRecord]
    }
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        directory = directoryURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gatherory/BlueprintPersonalLibrary", isDirectory: true)
    }

    func load(ownerID: String) throws -> [BlueprintPersonalRecord] {
        guard !ownerID.isEmpty else { throw BlueprintPersonalLibraryError.emptyOwner }
        let url = fileURL(ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let envelope = try? decoder.decode(Envelope.self, from: Data(contentsOf: url)),
              envelope.version == 1, envelope.ownerID == ownerID,
              envelope.records.allSatisfy({ $0.draftVersion > 0 })
        else { throw BlueprintPersonalLibraryError.corruptCache }
        return envelope.records
    }

    func save(_ records: [BlueprintPersonalRecord], ownerID: String) throws {
        guard !ownerID.isEmpty else { throw BlueprintPersonalLibraryError.emptyOwner }
        guard records.allSatisfy({ $0.draftVersion > 0 }) else { throw BlueprintPersonalLibraryError.invalidRecord }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(Envelope(version: 1, ownerID: ownerID, records: records))
            .write(to: fileURL(ownerID), options: .atomic)
    }

    func upsert(_ record: BlueprintPersonalRecord, ownerID: String) throws {
        var rows = try load(ownerID: ownerID).filter { $0.id != record.id }
        rows.append(record)
        try save(rows, ownerID: ownerID)
    }

    func remove(id: UUID, ownerID: String) throws {
        try save(load(ownerID: ownerID).filter { $0.id != id }, ownerID: ownerID)
    }

    private func fileURL(_ ownerID: String) -> URL {
        directory.appendingPathComponent(ownerID.utf8.map { String(format: "%02x", $0) }.joined() + ".json")
    }
}

extension BlueprintPersonalRecord {
    @MainActor
    func editedContent(from session: BlueprintPreviewSession) throws -> BlueprintDraftContent {
        guard session.entry.catalogKey == catalogEntry.catalogKey, let content = session.content else {
            throw BlueprintPersonalLibraryError.invalidRecord
        }
        var result = draftContent
        result.name = session.mainEventValues.name
        result.children = content.children
        result.ideas = content.ideas
        return result
    }

    var draftContent: BlueprintDraftContent {
        let modules = catalogEntry.definition.modules
        let children = modules.first { $0.type == "experience_tree" }?.decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
        let ideas = modules.first { $0.type == "ideas" }?.decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
        let instructions = modules.first { $0.type == "instructions" }?.decodeConfiguration(BlueprintInstructionsConfig.self)?.sections.map {
            BlueprintDraftInstruction(key: $0.key, title: $0.title, body: $0.body, audience: $0.audience, target: $0.target)
        } ?? []
        return BlueprintDraftContent(name: catalogEntry.definition.blueprint.name, description: catalogEntry.description ?? catalogEntry.discovery?.summary ?? "",
            experienceType: catalogEntry.definition.experienceDefaults.type, children: children,
            ideas: ideas, instructions: instructions)
    }
}
