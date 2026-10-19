import Foundation

@MainActor
protocol BlueprintSavedCopyTransport {
    func copyBlueprintSnapshot(requestID: UUID, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord
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
        let response = try await transport.copyBlueprintSnapshot(requestID: copyID, content: content)
        try Task.checkCancellation()
        guard currentOwnerID() == ownerID else { throw Failure.ownerChanged }
        guard try !hasPendingInstallation() else { throw Failure.installationPending }
        guard var latest = try store.load(ownerUserID: ownerID, catalogKey: draft.entry.catalogKey,
                                          shareToken: draft.shareToken), latest.requestID == saved.requestID,
              latest.copyRequestID == copyID, latest.entry.contentHash == saved.entry.contentHash,
              latest.entry.revision == saved.entry.revision else { throw Failure.draftChanged }
        guard response.listedRevision == nil, response.publishedRevision == response.catalogEntry.revision,
              response.catalogEntry.catalogKey != saved.entry.catalogKey,
              try BlueprintDraftContent.snapshot(of: response.catalogEntry) == content else { throw Failure.invalidCopy }
        latest.copyEntry = response.catalogEntry
        try store.save(latest)
        return latest
    }
}

extension BlueprintDraftContent {
    static func snapshot(of entry: BlueprintCatalogEntry) throws -> Self {
        guard entry.definition.supportsCurrentSchema else { throw BlueprintSavedCopyResolver.Failure.invalidCopy }
        let supported: [String: Int] = ["experience_tree": 2, "ideas": 2, "instructions": 1]
        guard entry.definition.modules.allSatisfy({ !$0.isRequired || supported[$0.type] == $0.version }) else {
            throw BlueprintSavedCopyResolver.Failure.invalidCopy
        }
        let effective = try BlueprintCustomization().applying(to: entry)
        let instructions = entry.definition.modules.filter { $0.type == "instructions" }.flatMap {
            $0.decodeConfiguration(BlueprintInstructionsConfig.self)?.sections ?? []
        }.map { BlueprintDraftInstruction(key: $0.key, title: $0.title, body: $0.body, audience: $0.audience, target: $0.target) }
        return Self(name: entry.definition.blueprint.name, description: entry.description ?? entry.discovery?.summary ?? "",
                    experienceType: entry.definition.experienceDefaults.type, children: effective.tree.children,
                    ideas: effective.ideas.ideas, instructions: instructions)
    }
}
