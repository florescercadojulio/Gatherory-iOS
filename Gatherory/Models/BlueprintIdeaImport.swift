import Foundation

/// Public catalog metadata needed to turn one portable idea into a local event
/// proposal. The cover bytes must come from the validated public cover URL;
/// private media IDs from the source Blueprint are never copied.
struct BlueprintIdeaImportSource {
    let idea: BlueprintCatalogIdea
    let blueprintKey: String
    let blueprintRevision: Int
    let blueprintTitle: String
    let creatorName: String?
    let publicCoverURL: URL?

    init(
        idea: BlueprintCatalogIdea,
        blueprintKey: String,
        blueprintRevision: Int,
        blueprintTitle: String,
        creatorName: String?,
        publicCoverURL: URL? = nil
    ) {
        self.idea = idea
        self.blueprintKey = blueprintKey
        self.blueprintRevision = blueprintRevision
        self.blueprintTitle = blueprintTitle
        self.creatorName = creatorName
        self.publicCoverURL = publicCoverURL.flatMap {
            BlueprintPublicCoverURL.validated($0.absoluteString)
        }
    }

    init(entry: IdeaDiscoveryEntry) {
        self.init(
            idea: entry.idea,
            blueprintKey: entry.sourceBlueprintId,
            blueprintRevision: entry.sourceVersion,
            blueprintTitle: entry.sourceTitle,
            creatorName: entry.creator?.displayName,
            publicCoverURL: entry.coverImageURL.flatMap { URL(string: $0) }
        )
    }
}

enum BlueprintIdeaImportResult: Equatable {
    case added(PlanningIdea)
    case alreadyAdded(PlanningIdea)
    case unavailable
    case invalidSource
    case persistenceFailed
}

enum BlueprintIdeaImport {
    /// Adds are permitted for active hosts and collaborators who can contribute
    /// or manage planning in the exact destination event.
    static func canAdd(to destination: EventReference, in workspace: PlanningWorkspace) -> Bool {
        guard !workspace.isInvitationProjection,
              !workspace.isMainEventDeleted,
              !workspace.currentMainEventStatus.isReadOnly,
              workspace.showsPlanningInterface,
              workspace.canManageEvent(destination),
              let member = workspace.currentViewerMember(for: destination),
              member.invitationStatus == .active else { return false }

        switch member.participantRole {
        case .host:
            return true
        case .collaborator:
            return member.planningPermission == .manage || member.planningPermission == .contribute
        case .guest:
            return false
        }
    }

    /// Uses the request's stable idea UUID as its retry key. A later intentional
    /// copy gets a new UUID and is therefore allowed.
    @discardableResult
    static func add(
        _ source: BlueprintIdeaImportSource,
        to destination: EventReference,
        in workspace: PlanningWorkspace,
        ideaID: UUID,
        imageData: Data? = nil,
        submittedAt: Date = .now,
        persist: (() throws -> Void)? = nil
    ) -> BlueprintIdeaImportResult {
        guard canAdd(to: destination, in: workspace) else { return .unavailable }

        guard !source.blueprintKey.isEmpty,
              source.blueprintRevision > 0,
              !source.blueprintTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.idea.key.isEmpty,
              !source.idea.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.hasSupportedPortableConfiguration(source.idea.configuration),
              let category = IdeaCategory(rawValue: source.idea.category) else {
            return .invalidSource
        }

        let eventID: UUID
        switch destination {
        case .main:
            eventID = workspace.mainEventID
        case .subevent(let id):
            guard source.idea.category != IdeaCategory.event.rawValue else { return .unavailable }
            eventID = id
        case .idea(_):
            return .unavailable
        }

        guard let member = workspace.currentViewerMember(for: destination) else { return .unavailable }
        let creator = source.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceCredit: String
        if let creator, !creator.isEmpty {
            sourceCredit = String(
                localized: "ideaDiscovery.sourceCredit",
                defaultValue: "From \(source.blueprintTitle) · \(creator)"
            )
        } else {
            sourceCredit = String(
                localized: "ideaDiscovery.sourceCreditWithoutCreator",
                defaultValue: "From \(source.blueprintTitle)"
            )
        }
        let description = source.idea.notes ?? ""
        let note = description.isEmpty ? sourceCredit : "\(description)\n\n\(sourceCredit)"
        let idea = PlanningIdea(
            id: ideaID,
            eventID: eventID,
            title: source.idea.title,
            note: note,
            category: category,
            submittedBy: member.name,
            submittedByUserID: member.userID,
            estimatedCost: nil,
            status: .new,
            submittedAt: submittedAt,
            imageData: imageData,
            mediaAssetID: nil,
            configuration: nil
        )

        if let existing = workspace.ideas.first(where: { $0.id == ideaID }) {
            return Self.sameImport(existing, idea) ? .alreadyAdded(existing) : .unavailable
        }

        let previousExpenses = workspace.eventExpenses
        guard workspace.insertBlueprintIdea(idea) else {
            return .unavailable
        }
        if let persist {
            do {
                try persist()
            } catch {
                workspace.rollbackBlueprintIdeaImport(id: idea.id, previousExpenses: previousExpenses)
                return .persistenceFailed
            }
        }
        return .added(idea)
    }

    private static func sameImport(_ existing: PlanningIdea, _ candidate: PlanningIdea) -> Bool {
        existing.id == candidate.id
            && existing.eventID == candidate.eventID
            && existing.title == candidate.title
            && existing.note == candidate.note
            && existing.category == candidate.category
            && existing.submittedBy == candidate.submittedBy
            && existing.estimatedCost == nil
            && existing.status == .new
            && existing.imageData == candidate.imageData
            && existing.mediaAssetID == nil
    }

    private static func hasSupportedPortableConfiguration(
        _ configuration: [String: ExperienceJSONValue]
    ) -> Bool {
        guard configuration.count == 1,
              let version = configuration["version"] else { return false }
        return switch version {
        case .integer(let value): value == 1
        case .number(let value): value == 1
        default: false
        }
    }
}
