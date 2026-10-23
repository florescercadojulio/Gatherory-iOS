import Foundation

@MainActor
protocol BlueprintSavedCopyTransport {
    func copyBlueprintSnapshot(requestID: UUID, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord
    func copyBlueprintSnapshot(
        requestID: UUID, content: BlueprintDraftContent, source: BlueprintCopySource
    ) async throws -> BlueprintPersonalRecord
}

extension BlueprintSavedCopyTransport {
    func copyBlueprintSnapshot(
        requestID: UUID, content: BlueprintDraftContent, source: BlueprintCopySource
    ) async throws -> BlueprintPersonalRecord {
        try await copyBlueprintSnapshot(requestID: requestID, content: content)
    }
}

struct BlueprintCopySource: Codable, Sendable {
    let catalogKey: String
    let revision: Int
    let shareToken: String?
    var discoveryExposureId: String? = nil
}

/// A saved portable snapshot is user content, not continuing access to its source.
/// Publication and installation remain distinct operations with separate retry IDs.
@MainActor
struct BlueprintSavedCopyResolver {
    enum Failure: Error { case ownerChanged, draftChanged, installationPending, invalidCopy }

    static func resolve(
        draft: BlueprintSetupDraft, ownerID: String, store: BlueprintSetupDraftStore,
        transport: any BlueprintSavedCopyTransport,
        currentOwnerID: @MainActor () -> String?,
        hasPendingInstallation: @MainActor () throws -> Bool
    ) async throws -> BlueprintSetupDraft {
        guard !ownerID.isEmpty, draft.ownerUserID == ownerID, currentOwnerID() == ownerID else {
            throw Failure.ownerChanged
        }
        guard try !hasPendingInstallation() else { throw Failure.installationPending }
        guard var saved = try store.load(ownerUserID: ownerID, catalogKey: draft.entry.catalogKey,
                                         shareToken: draft.shareToken), saved.requestID == draft.requestID,
              saved.entry.contentHash == draft.entry.contentHash,
              saved.entry.revision == draft.entry.revision else { throw Failure.draftChanged }
        if saved.copyEntry != nil { return saved }
        if saved.copyRequestID == nil {
            saved.copyRequestID = UUID()
            try store.save(saved)
        }
        guard let copyID = saved.copyRequestID else { throw Failure.invalidCopy }
        // Snapshot the full original portable document. Decisions, edited dates,
        // and overlays remain local and do not change the idempotent copy body.
        let content = try BlueprintDraftContent.snapshot(of: saved.entry)
        let response = try await transport.copyBlueprintSnapshot(
            requestID: copyID,
            content: content,
            source: BlueprintCopySource(
                catalogKey: saved.entry.catalogKey,
                revision: saved.entry.revision,
                shareToken: saved.shareToken,
                discoveryExposureId: saved.entry.discoveryContext.flatMap { $0.expiresAt > Date() ? $0.exposureId : nil }
            )
        )
        try Task.checkCancellation()
        guard currentOwnerID() == ownerID else { throw Failure.ownerChanged }
        guard try !hasPendingInstallation() else { throw Failure.installationPending }
        guard var latest = try store.load(ownerUserID: ownerID, catalogKey: draft.entry.catalogKey,
                                          shareToken: draft.shareToken), latest.requestID == saved.requestID,
              latest.copyRequestID == copyID, latest.entry.contentHash == saved.entry.contentHash,
              latest.entry.revision == saved.entry.revision else { throw Failure.draftChanged }
        guard response.listedRevision == nil, response.publishedRevision == response.catalogEntry.revision,
              response.catalogEntry.catalogKey != saved.entry.catalogKey,
              try copiedSnapshotMatches(
                content,
                sourceEntry: saved.entry,
                entry: response.catalogEntry
              ) else { throw Failure.invalidCopy }
        latest.customizations = remapCoverOverrides(
            latest.customizations,
            from: saved.entry,
            to: response.catalogEntry
        )
        latest.copyEntry = response.catalogEntry
        try store.save(latest)
        return latest
    }
}

private func remapCoverOverrides(
    _ customizations: BlueprintCustomization?,
    from source: BlueprintCatalogEntry,
    to copied: BlueprintCatalogEntry
) -> BlueprintCustomization? {
    guard var value = customizations else { return nil }
    var mapping: [UUID: UUID] = [:]
    if let oldID = source.definition.presentation?.coverAssetID,
       let newID = copied.definition.presentation?.coverAssetID {
        mapping[oldID] = newID
    }
    let sourceTree = source.definition.modules.first { $0.type == "experience_tree" }?
        .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
    let copiedTree = copied.definition.modules.first { $0.type == "experience_tree" }?
        .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
    let copiedChildren = Dictionary(uniqueKeysWithValues: copiedTree.map { ($0.key, $0) })
    for child in sourceTree {
        if let oldID = child.coverAssetId, let newID = copiedChildren[child.key]?.coverAssetId {
            mapping[oldID] = newID
        }
    }
    let sourceIdeas = source.definition.modules.first { $0.type == "ideas" }?
        .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
    let copiedIdeas = copied.definition.modules.first { $0.type == "ideas" }?
        .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
    let copiedIdeasByKey = Dictionary(uniqueKeysWithValues: copiedIdeas.map { ($0.key, $0) })
    for idea in sourceIdeas {
        if let oldID = idea.coverAssetId, let newID = copiedIdeasByKey[idea.key]?.coverAssetId {
            mapping[oldID] = newID
        }
    }
    if value.overridesCover, let coverAssetId = value.coverAssetId {
        value.coverAssetId = mapping[coverAssetId] ?? coverAssetId
    }
    value.children = value.children.map { child in
        var child = child
        if let id = child.coverAssetId { child.coverAssetId = mapping[id] ?? id }
        return child
    }
    value.ideas = value.ideas.map { idea in
        var idea = idea
        if let id = idea.coverAssetId { idea.coverAssetId = mapping[id] ?? id }
        return idea
    }
    return value
}

func copiedSnapshotMatches(
    _ source: BlueprintDraftContent,
    sourceEntry: BlueprintCatalogEntry,
    entry: BlueprintCatalogEntry
) throws -> Bool {
    let copied = try BlueprintDraftContent.snapshot(of: entry)
    var expected = source
    guard source.children.count == copied.children.count, source.ideas.count == copied.ideas.count else { return false }
    expected.coverAssetId = copied.coverAssetId
    expected.children = zip(source.children, copied.children).map { original, current in
        var value = original
        value.coverAssetId = current.coverAssetId
        value.coverAssetIdWasProvided = current.coverAssetIdWasProvided
        return value
    }
    expected.ideas = zip(source.ideas, copied.ideas).map { original, current in
        var value = original
        value.coverAssetId = current.coverAssetId
        value.coverAssetIdWasProvided = current.coverAssetIdWasProvided
        return value
    }
    guard expected == copied else { return false }

    let allowsCuratedMainCoverImport = sourceEntry.definition.presentation?.coverAssetID == nil
        && BlueprintPublicCoverURL.validated(sourceEntry.discovery?.coverImageURL) != nil
    var copiedCoverBySource: [UUID: UUID] = [:]
    let sourceChildren = Dictionary(uniqueKeysWithValues: sourceEntry.definition.modules
        .first(where: { $0.type == "experience_tree" })?
        .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children.map { ($0.key, $0) } ?? [])
    let sourceIdeas = Dictionary(uniqueKeysWithValues: sourceEntry.definition.modules
        .first(where: { $0.type == "ideas" })?
        .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas.map { ($0.key, $0) } ?? [])
    let copyPairs: [(UUID?, UUID?, Bool)] = [
        (source.coverAssetId, copied.coverAssetId, allowsCuratedMainCoverImport)
    ] + zip(source.children, copied.children).map { original, current in
        let allowsImport = sourceChildren[original.key]?.coverAssetId == nil
            && BlueprintPublicCoverURL.validated(sourceEntry.discovery?.coverImages?.children[original.key]) != nil
        return (original.coverAssetId, current.coverAssetId, allowsImport)
    } + zip(source.ideas, copied.ideas).map { original, current in
        let allowsImport = sourceIdeas[original.key]?.coverAssetId == nil
            && BlueprintPublicCoverURL.validated(sourceEntry.discovery?.coverImages?.ideas[original.key]) != nil
        return (original.coverAssetId, current.coverAssetId, allowsImport)
    }
    for (oldID, newID, allowsImport) in copyPairs {
        guard let oldID else {
            if newID != nil && !allowsImport { return false }
            continue
        }
        guard let newID, oldID != newID else { return false }
        if let existing = copiedCoverBySource[oldID], existing != newID { return false }
        copiedCoverBySource[oldID] = newID
    }
    return true
}

extension BlueprintDraftContent {
    static func snapshot(of entry: BlueprintCatalogEntry) throws -> Self {
        guard entry.definition.supportsCurrentSchema else { throw BlueprintSavedCopyResolver.Failure.invalidCopy }
        let supported: [String: Int] = ["experience_tree": 2, "ideas": 2, "instructions": 1, "todos": 1]
        guard entry.definition.modules.allSatisfy({ !$0.isRequired || supported[$0.type] == $0.version }) else {
            throw BlueprintSavedCopyResolver.Failure.invalidCopy
        }
        let effective = try BlueprintCustomization().applying(to: entry)
        let todosModule = entry.definition.modules.first { $0.type == "todos" }
        let todos: [BlueprintTodoDefinition]
        if let todosModule {
            guard todosModule.version == 1,
                  let config = todosModule.decodeConfiguration(BlueprintTodosConfig.self) else {
                throw BlueprintSavedCopyResolver.Failure.invalidCopy
            }
            let childKeys = Set(effective.tree.children.map(\.key))
            guard config.todos.allSatisfy({ todo in
                if case .main = todo.target { return true }
                if case let .child(key) = todo.target { return childKeys.contains(key) }
                return false
            }) else { throw BlueprintSavedCopyResolver.Failure.invalidCopy }
            todos = config.todos
        } else {
            todos = []
        }
        let instructions = entry.definition.modules.filter { $0.type == "instructions" }.flatMap {
            $0.decodeConfiguration(BlueprintInstructionsConfig.self)?.sections ?? []
        }.map { BlueprintDraftInstruction(key: $0.key, title: $0.title, body: $0.body, audience: $0.audience, target: $0.target) }
        return Self(name: entry.definition.blueprint.name, description: entry.description ?? entry.discovery?.summary ?? "",
                    experienceType: entry.definition.experienceDefaults.type, children: effective.tree.children,
                    ideas: effective.ideas.ideas, instructions: instructions, todos: todos,
                    coverAssetId: entry.definition.presentation?.coverAssetID)
    }
}
