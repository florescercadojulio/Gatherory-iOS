import Foundation

/// Creates the local setup plan only after the person explicitly chooses Use.
@MainActor
enum BlueprintPreviewWorkingCopy {
    enum PrepareError: Error, Equatable {
        case emptyOwner
        case installationPending
        case missingSavedDraft
    }

    static func prepare(
        ownerID: String,
        entry: BlueprintCatalogEntry,
        shareToken: String?,
        defaultEventName: String,
        store: BlueprintSetupDraftStore,
        hasPendingInstallation: Bool
    ) throws -> BlueprintSetupDraft {
        guard !ownerID.isEmpty else { throw PrepareError.emptyOwner }
        guard !hasPendingInstallation else { throw PrepareError.installationPending }

        if let existing = try store.load(
            ownerUserID: ownerID,
            catalogKey: entry.catalogKey,
            shareToken: shareToken
        ) {
            return existing
        }

        var session = BlueprintPreviewSession(
            ownerID: ownerID,
            entry: entry,
            shareToken: shareToken,
            savedDraft: nil,
            defaultEventName: defaultEventName
        )
        // With no saved selection to preserve, saving the new draft selects all
        // authored content. Selection is independent of preview Decide responses.
        try session.save(to: store, hasPendingInstallation: hasPendingInstallation)
        guard let savedDraft = session.draft else { throw PrepareError.missingSavedDraft }
        return savedDraft
    }
}
