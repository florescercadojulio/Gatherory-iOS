import Foundation

/// Builds an independent event from explicitly selected planning content.
/// Identity, people, responses, media, and sharing state are always new or empty.
@MainActor
enum PlanningWorkspaceDuplicateFactory {
    static func canDuplicate(
        from source: PlanningWorkspace,
        owner: UserAccount?,
        localGuest: LocalGuestProfile?
    ) -> Bool {
        guard !source.isInvitationProjection,
              !source.isMainEventDeleted,
              source.showsPlanningInterface,
              let actor = source.currentViewerMember(for: .main),
              actor.invitationStatus == .active,
              (actor.participantRole == .host
                || (actor.participantRole == .collaborator && actor.planningPermission == .manage)),
              belongsToCurrentActor(actor, owner: owner, localGuest: localGuest) else {
            return false
        }
        return true
    }

    static func makeDuplicate(
        from source: PlanningWorkspace,
        title: String,
        owner: UserAccount?,
        localGuest: LocalGuestProfile?
    ) -> PlanningWorkspace? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              canDuplicate(from: source, owner: owner, localGuest: localGuest),
              let actor = source.currentViewerMember(for: .main),
              belongsToCurrentActor(actor, owner: owner, localGuest: localGuest) else {
            return nil
        }

        let actorName = (localGuest?.displayName ?? owner?.displayName ?? actor.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hostName = actorName.isEmpty ? "You" : actorName
        let host = WorkspaceMember(
            userID: localGuest?.storageID ?? owner?.id,
            name: hostName,
            participantRole: .host,
            initials: initials(for: hostName),
            email: owner?.email,
            planningPermission: .manage
        )

        let newMainEventID = UUID()
        let sourceChildren = source.isScopedEvent ? [] : source.timeline.filter {
            $0.parentEventID == source.mainEventID && $0.status != .archived
        }
        let childIDs = Dictionary(uniqueKeysWithValues: sourceChildren.map { ($0.id, UUID()) })
        let sourceIdeas = source.ideas.filter {
            $0.status != .archived
                && belongsToCopiedEvent($0.eventID, sourceID: source.mainEventID, childIDs: childIDs)
        }
        let ideaIDs = Dictionary(uniqueKeysWithValues: sourceIdeas.map { ($0.id, UUID()) })

        let children = sourceChildren.map { child in
            TimelineItem(
                id: childIDs[child.id]!,
                title: child.title,
                category: child.category,
                purpose: child.purpose,
                scheduledAt: child.scheduledAt,
                schedulingState: child.schedulingState,
                eventLocation: child.eventLocation,
                endsAt: child.endsAt,
                isAllDay: child.isAllDay,
                timeZoneIdentifier: child.timeZoneIdentifier,
                participantIDs: [host.id],
                parentEventID: newMainEventID,
                status: .draft,
                completionStatus: .upcoming,
                linkedIdeaID: child.linkedIdeaID.flatMap { ideaIDs[$0] },
                eventDescription: child.eventDescription,
                dressCode: child.dressCode,
                budgetCap: child.budgetCap
            )
        }

        let ideas = sourceIdeas.map { idea in
            PlanningIdea(
                id: ideaIDs[idea.id]!,
                eventID: remapIdeaEvent(idea.eventID, sourceID: source.mainEventID, newID: newMainEventID, childIDs: childIDs),
                title: idea.title,
                note: idea.note,
                category: idea.category,
                submittedBy: hostName,
                submittedByUserID: owner?.id,
                estimatedCost: idea.estimatedCost,
                status: .new,
                submittedAt: .now,
                configuration: idea.configuration,
                invitationVisibility: idea.invitationVisibility
            )
        }

        let workspace = PlanningWorkspace(
            mainEventID: newMainEventID,
            title: trimmedTitle,
            mainEventStartsAt: source.mainEventStartsAt,
            mainEventEndsAt: source.mainEventEndsAt,
            mainEventIsAllDay: source.mainEventIsAllDay,
            mainEventTimeZoneIdentifier: source.mainEventTimeZoneIdentifier,
            mainEventLocation: source.mainEventLocation,
            venueName: source.venueName,
            location: source.location,
            dressCode: source.dressCode,
            eventMessage: source.eventMessage,
            planningMode: .openToIdeas,
            members: [host],
            mainEventParticipantIDs: [host.id],
            ideas: ideas,
            timeline: children,
            workspaceBudgetCap: source.isScopedEvent
                ? source.mainEventBudgetCap
                : source.workspaceBudgetCap,
            currencyCode: source.currencyCode,
            mainEventBudgetCap: source.mainEventBudgetCap,
            mainEventStatus: .draft,
            mainEventResponse: nil,
            guides: [],
            experienceConfiguration: nil,
            isMainEventDeleted: false,
            registry: [],
            isRegistryShared: false,
            isCollaboratorLinkEnabled: false,
            requiresCollaboratorApproval: true,
            defaultCollaboratorPermission: .contribute
        )
        workspace.configureViewer(owner)
        if let localGuest {
            workspace.configureLocalGuestViewer(localGuest)
        }
        return workspace
    }

    private static func belongsToCurrentActor(
        _ actor: WorkspaceMember,
        owner: UserAccount?,
        localGuest: LocalGuestProfile?
    ) -> Bool {
        if let owner {
            return actor.userID == owner.id
                || actor.email?.caseInsensitiveCompare(owner.email) == .orderedSame
        }
        if let localGuest {
            return actor.userID == localGuest.storageID
        }
        return false
    }

    private static func belongsToCopiedEvent(
        _ eventID: UUID?,
        sourceID: UUID,
        childIDs: [UUID: UUID]
    ) -> Bool {
        guard let eventID else { return true }
        return eventID == sourceID || childIDs[eventID] != nil
    }

    private static func remapIdeaEvent(
        _ eventID: UUID?,
        sourceID: UUID,
        newID: UUID,
        childIDs: [UUID: UUID]
    ) -> UUID {
        guard let eventID, eventID != sourceID else { return newID }
        return childIDs[eventID] ?? newID
    }

    private static func initials(for name: String) -> String {
        let result = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return result.isEmpty ? "Y" : result
    }
}
