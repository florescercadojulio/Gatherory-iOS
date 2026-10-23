#if DEBUG
import Foundation

/// In-memory fixture data for the unified Yours library UI tests.
/// This type deliberately does not use any of the per-account library stores.
@MainActor
struct BlueprintLibraryVisualFixture {
    enum Mode: String {
        case empty
        case mixed
        case pending
    }

    struct State {
        let personalRecords: [BlueprintPersonalRecord]
        let installations: [BlueprintUsedTemplate]
        let recovery: BlueprintSetupRecovery
    }

    static let personalRecordID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    static let recoveryRequestID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    static let installationID = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!

    static func load(ownerID: String) -> State? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-BlueprintLibraryVisualFixture"),
              AppRuntimeConfiguration.usesEphemeralDataStore,
              AppRuntimeConfiguration.seedsDevelopmentData,
              AppRuntimeConfiguration.skipsAuthentication,
              !ownerID.isEmpty,
              let modeIndex = arguments.firstIndex(of: "-BlueprintLibraryFixtureState"),
              arguments.indices.contains(modeIndex + 1),
              let mode = Mode(rawValue: arguments[modeIndex + 1])
        else { return nil }

        switch mode {
        case .empty:
            return State(
                personalRecords: [],
                installations: [],
                recovery: BlueprintSetupRecovery(drafts: [], hasPendingInstallation: false, loadFailed: false)
            )
        case .mixed, .pending:
            guard let source = bundledCatalogEntry() else { return nil }
            let personalEntry = copy(source, catalogKey: "visual_personal")
            let recoveryEntry = copy(source, catalogKey: "visual_recovery")
            let receiptEntry = copy(source, catalogKey: "visual_used")

            let record = BlueprintPersonalRecord(
                id: personalRecordID,
                draftVersion: 3,
                publishedRevision: personalEntry.revision,
                listedRevision: nil,
                creatorName: "You",
                activeShareLinkCount: 0,
                catalogEntry: personalEntry
            )
            let changedChild = source.definition.modules
                .first(where: { $0.type == "experience_tree" })?
                .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children.first.map {
                    BlueprintCatalogChild(
                        key: $0.key,
                        title: "A recovery edit",
                        purpose: $0.purpose,
                        category: $0.category,
                        scheduleProposal: $0.scheduleProposal
                    )
                }
            let draft = BlueprintSetupDraft(
                ownerUserID: ownerID,
                entry: recoveryEntry,
                requestID: recoveryRequestID,
                eventName: "Garden celebration",
                startsAt: Date(timeIntervalSince1970: 1_798_200_000),
                timeZoneIdentifier: "America/Detroit",
                selectedChildren: Set(recoveryEntry.definition.modules
                    .first(where: { $0.type == "experience_tree" })?
                    .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children.prefix(1).map(\.key) ?? []),
                selectedIdeas: Set(recoveryEntry.definition.modules
                    .first(where: { $0.type == "ideas" })?
                    .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas.prefix(1).map(\.key) ?? []),
                confirmedDates: [:],
                customizations: BlueprintCustomization(children: changedChild.map { [$0] } ?? []),
                mainDateConfirmed: true
            )
            let receipt = BlueprintUsedTemplate(
                installationID: installationID,
                scopeID: UUID(uuidString: "40000000-0000-4000-8000-000000000004")!,
                catalogKey: receiptEntry.catalogKey,
                revision: receiptEntry.revision,
                templateName: receiptEntry.definition.blueprint.name,
                eventName: "Autumn dinner",
                installedAt: "2026-10-15T12:30:45Z"
            )
            return State(
                personalRecords: [record],
                installations: [receipt],
                recovery: BlueprintSetupRecovery(
                    drafts: [draft],
                    hasPendingInstallation: mode == .pending,
                    loadFailed: false
                )
            )
        }
#else
        return nil
#endif
    }

    private static func bundledCatalogEntry() -> BlueprintCatalogEntry? {
        guard let url = Bundle.main.url(forResource: "blueprint-search-visual-catalog.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(BlueprintCatalogResponse.self, from: data)
        else { return nil }
        return response.entries.first
    }

    private static func copy(_ source: BlueprintCatalogEntry, catalogKey: String) -> BlueprintCatalogEntry {
        BlueprintCatalogEntry(
            catalogKey: catalogKey,
            revision: source.revision,
            contentHash: source.contentHash,
            definition: source.definition,
            discovery: source.discovery,
            description: source.description,
            creator: source.creator,
            viewerState: nil,
            discoveryContext: nil
        )
    }
}
#endif
