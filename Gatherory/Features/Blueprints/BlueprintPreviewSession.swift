import Foundation

/// Staged preview choices. No method writes until save(to:) is explicitly called.
@MainActor
struct BlueprintPreviewSession {
    enum SaveError: Error { case accountRequired, draftChanged, installationPending, invalidMainEvent }

    struct MainEventValues: Equatable {
        var name: String
        var startsAt: Date
        var timeZoneIdentifier: String
    }

    let ownerID: String
    let entry: BlueprintCatalogEntry
    let shareToken: String?
    private(set) var draft: BlueprintSetupDraft?
    private(set) var responses: [String: DecisionChoice]
    private var savedResponses: [String: DecisionChoice]
    private let defaultEventName: String
    private let initialDateContext: BlueprintSetupDateContext
    private let sourceDraft: BlueprintSetupDraft?
    private(set) var customizations: BlueprintCustomization
    private var editedMainEvent: MainEventValues?
    private var confirmsMainDate = false
    private var editedChildren: Set<String> = []
    private var editedIdeas: Set<String> = []

    init(ownerID: String, entry: BlueprintCatalogEntry, shareToken: String?,
         savedDraft: BlueprintSetupDraft?, defaultEventName: String,
         dateContext: BlueprintSetupDateContext? = nil, sourceDraft: BlueprintSetupDraft? = nil) {
        self.ownerID = ownerID
        self.shareToken = shareToken
        // A saved setup stays pinned instead of silently upgrading to a newer publication.
        let saved = savedDraft.flatMap {
            $0.ownerUserID == ownerID && $0.entry.catalogKey == entry.catalogKey && $0.shareToken == shareToken ? $0 : nil
        }
        let source = sourceDraft.flatMap {
            $0.ownerUserID == ownerID && $0.entry.catalogKey == entry.catalogKey && $0.shareToken == shareToken ? $0 : nil
        }
        self.sourceDraft = source
        let baseline = saved ?? source
        let activeEntry = baseline?.entry ?? entry
        self.entry = activeEntry
        self.draft = saved
        self.defaultEventName = source?.eventName ?? defaultEventName
        self.initialDateContext = dateContext ?? source.map {
            BlueprintSetupDateContext(startsAt: $0.startsAt,
                                      timeZone: TimeZone(identifier: $0.timeZoneIdentifier) ?? .autoupdatingCurrent)
        } ?? BlueprintSetupDateContext()
        self.customizations = baseline?.customizations ?? BlueprintCustomization()
        let keys = Set((try? BlueprintCustomization().applying(to: activeEntry).ideas.ideas.map(\.key)) ?? [])
            .union(baseline?.customizations?.ideas.map(\.key) ?? [])
        self.responses = (baseline?.previewDecisions ?? [:]).filter { keys.contains($0.key) }
        self.savedResponses = self.responses
    }

    var isDirty: Bool {
        responses != savedResponses || editedMainEvent != nil
            || customizations != (draft?.customizations ?? sourceDraft?.customizations ?? BlueprintCustomization())
    }

    var mainEventValues: MainEventValues {
        editedMainEvent ?? MainEventValues(
            name: draft?.eventName ?? defaultEventName,
            startsAt: draft?.startsAt ?? initialDateContext.startsAt,
            timeZoneIdentifier: draft?.timeZoneIdentifier ?? initialDateContext.timeZoneIdentifier
        )
    }

    var content: BlueprintPreviewContent? {
        BlueprintPreviewContent(entry: entry, customizations: customizations,
                                eventName: editedMainEvent?.name ?? draft?.eventName ?? sourceDraft?.eventName)
    }

    mutating func decide(_ choice: DecisionChoice, key: String) {
        guard content?.ideas.contains(where: { $0.key == key }) == true else { return }
        responses[key] = choice
    }

    mutating func editMainEvent(_ values: MainEventValues, confirmsDate: Bool = false) throws {
        var values = values
        values.name = values.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !values.name.isEmpty, values.name.unicodeScalars.count <= 120,
              values.startsAt.timeIntervalSince1970.isFinite,
              TimeZone(identifier: values.timeZoneIdentifier) != nil else { throw SaveError.invalidMainEvent }
        editedMainEvent = values
        confirmsMainDate = confirmsDate || confirmsMainDate
    }

    mutating func editChild(_ child: BlueprintCatalogChild) throws {
        var candidate = customizations
        try candidate.upsert(child)
        _ = try candidate.applying(to: entry)
        customizations = candidate
        editedChildren.insert(child.key)
    }

    mutating func editIdea(_ idea: BlueprintCatalogIdea) throws {
        var candidate = customizations
        try candidate.upsert(idea)
        _ = try candidate.applying(to: entry)
        customizations = candidate
        editedIdeas.insert(idea.key)
        responses.removeValue(forKey: idea.key)
    }

    mutating func discardChanges() {
        responses = savedResponses
        customizations = draft?.customizations ?? sourceDraft?.customizations ?? BlueprintCustomization()
        resetContentChanges()
    }

    private mutating func resetContentChanges() {
        editedMainEvent = nil
        confirmsMainDate = false
        editedChildren.removeAll()
        editedIdeas.removeAll()
    }

    mutating func save(to store: BlueprintSetupDraftStore, hasPendingInstallation: Bool) throws {
        guard !ownerID.isEmpty else { throw SaveError.accountRequired }
        guard !hasPendingInstallation else { throw SaveError.installationPending }
        let existing = try store.load(ownerUserID: ownerID, catalogKey: entry.catalogKey, shareToken: shareToken)
        guard existing?.requestID == draft?.requestID,
              existing.map({ $0.entry.revision == entry.revision && $0.entry.contentHash == entry.contentHash }) ?? true
        else { throw SaveError.draftChanged }
        var saved = existing ?? BlueprintSetupDraft(
            ownerUserID: ownerID, entry: entry, requestID: UUID(),
            eventName: defaultEventName,
            startsAt: initialDateContext.startsAt,
            timeZoneIdentifier: initialDateContext.timeZoneIdentifier,
            selectedChildren: Set(content?.children.map(\.key) ?? []), selectedIdeas: [], confirmedDates: [:], shareToken: shareToken
        )
        let plan = content?.homeContent(responses: responses)
        saved.selectedIdeas = Set(plan?.ideas.map(\.key) ?? [])
        saved.selectedChildren = Set(plan?.children.map(\.key) ?? [])
        var merged = existing?.customizations ?? sourceDraft?.customizations ?? BlueprintCustomization()
        for child in customizations.children where editedChildren.contains(child.key) { try merged.upsert(child) }
        for idea in customizations.ideas where editedIdeas.contains(idea.key) { try merged.upsert(idea) }
        _ = try merged.applying(to: entry)
        saved.customizations = merged.isEmpty ? nil : merged
        if let editedMainEvent {
            let dateChanged = saved.startsAt != editedMainEvent.startsAt
                || saved.timeZoneIdentifier != editedMainEvent.timeZoneIdentifier
            saved.eventName = editedMainEvent.name
            saved.startsAt = editedMainEvent.startsAt
            saved.timeZoneIdentifier = editedMainEvent.timeZoneIdentifier
            if confirmsMainDate { saved.mainDateConfirmed = true }
            else if dateChanged { saved.mainDateConfirmed = false }
        }
        saved.previewDecisions = responses.isEmpty ? nil : responses
        try store.save(saved)
        draft = saved
        savedResponses = responses
        customizations = merged
        resetContentChanges()
    }
}
