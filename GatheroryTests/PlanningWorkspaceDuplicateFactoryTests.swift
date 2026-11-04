import Foundation
import Testing
@testable import Gatherory

@MainActor
struct PlanningWorkspaceDuplicateFactoryTests {
    @Test("A newly initialized main event starts ongoing")
    func newWorkspaceStartsOngoing() {
        let workspace = PlanningWorkspace(
            title: "New Event",
            mainEventStartsAt: .now,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [],
            ideas: [],
            timeline: [],
            registry: []
        )

        #expect(workspace.mainEventStatus == .ongoing)
    }

    @Test("Main editor promotes legacy drafts and preserves terminal statuses")
    func editorValueNormalizesOnlyDraft() {
        #expect(MainEventStatus.draft.editorValue == .ongoing)
        #expect(MainEventStatus.ongoing.editorValue == .ongoing)
        #expect(MainEventStatus.finished.editorValue == .finished)
        #expect(MainEventStatus.cancelled.editorValue == .cancelled)
    }

    @Test("Duplicate copies event content and starts as a fresh host-only event")
    func defaultDuplicate() throws {
        let owner = makeOwner()
        let source = makeWorkspace(owner: owner)
        source.mainEventImageData = Data([0x01, 0x02])
        source.mainEventMediaAssetID = UUID()
        source.mainEventResponse = .going
        let idea = PlanningIdea(title: "Source idea", note: "", category: .other, submittedBy: "Guest")
        source.addIdea(idea)
        let child = makeChild(in: source)
        source.timeline.append(child)

        let duplicate = try #require(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: source,
            title: "  Copy of Family Picnic  ",
            owner: owner,
            localGuest: nil
        ))

        #expect(duplicate.mainEventID != source.mainEventID)
        #expect(duplicate.title == "Copy of Family Picnic")
        #expect(duplicate.mainEventStartsAt == source.mainEventStartsAt)
        #expect(duplicate.mainEventLocation == source.mainEventLocation)
        #expect(duplicate.mainEventStatus == .ongoing)
        #expect(duplicate.mainEventResponse == nil)
        #expect(duplicate.mainEventImageData == nil)
        #expect(duplicate.mainEventMediaAssetID == nil)
        #expect(duplicate.members.count == 1)
        #expect(duplicate.members[0].userID == owner.id)
        #expect(duplicate.members[0].participantRole == .host)
        #expect(duplicate.members[0].planningPermission == .manage)
        #expect(Set(duplicate.eventParticipations.map(\.memberID)) == Set(duplicate.members.map(\.id)))
        #expect(duplicate.timeline.count == 1)
        #expect(duplicate.timeline[0].id != child.id)
        #expect(duplicate.timeline[0].parentEventID == duplicate.mainEventID)
        #expect(duplicate.timeline[0].status == .approved)
        #expect(duplicate.ideas.count == 1)
        #expect(duplicate.ideas[0].id != idea.id)
        #expect(duplicate.ideas[0].eventID == duplicate.mainEventID)
        #expect(duplicate.ideas[0].status == .new)
        #expect(duplicate.ideaResponses.isEmpty)
        #expect(duplicate.todos.isEmpty)
        #expect(duplicate.notes.isEmpty)
        #expect(duplicate.eventExpenses.isEmpty)
        #expect(duplicate.eventMoments.isEmpty)
        #expect(duplicate.registry.isEmpty)
        #expect(!duplicate.isCollaboratorLinkEnabled)
        #expect(duplicate.experienceConfiguration == nil)
    }

    @Test("Confirmed schedule and ideas receive fresh IDs and remapped relationships without replies or media")
    func copiesScheduleAndIdeasSafely() throws {
        let owner = makeOwner()
        let source = makeWorkspace(owner: owner)
        let childID = UUID()
        let childStart = Date.now.addingTimeInterval(86_400)
        let childIdea = PlanningIdea(
            title: "Flowers for dinner", note: "Blue flowers", category: .flowers,
            submittedBy: "Guest", submittedByUserID: "someone-else", status: .chosen,
            imageData: Data([0x11]), mediaAssetID: UUID()
        )
        var child = TimelineItem(
            id: childID, title: "Dinner", category: .reception,
            scheduledAt: childStart, location: "Town Hall",
            participantIDs: source.members.map(\.id), parentEventID: source.mainEventID,
            status: .approved, completionStatus: .complete, response: .going,
            linkedIdeaID: childIdea.id, imageData: Data([0x22]), mediaAssetID: UUID()
        )
        child.eventDescription = "Dinner and music"
        source.timeline.append(child)
        let mainIdea = PlanningIdea(title: "Flowers", note: "Blue", category: .flowers, submittedBy: "Guest")
        source.addIdea(mainIdea)
        let sourceURLIdea = PlanningIdea(
            title: "Reception inspiration", note: "Pinterest reference", category: .link,
            submittedBy: "Guest",
            configuration: .link(LinkIdeaConfiguration(url: URL(string: "https://www.pinterest.com/pin/123/?source=event-plan")!))
        )
        source.addIdea(sourceURLIdea)
        var attachedChildIdea = childIdea
        attachedChildIdea.eventID = childID
        source.addIdea(attachedChildIdea)
        let approvedEventIdea = PlanningIdea(
            title: "Dinner proposal", note: "A seated dinner", category: .event,
            submittedBy: "Guest", status: .chosen,
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .planning,
                proposedDate: childStart, location: nil
            ))
        )
        source.addIdea(approvedEventIdea)
        source.decide(.love, on: mainIdea)
        #expect(!source.ideaResponses.isEmpty)

        let duplicate = try #require(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: source,
            title: "Picnic Copy",
            owner: owner,
            localGuest: nil
        ))
        let copiedChild = try #require(duplicate.timeline.first)
        let copiedMainIdea = try #require(duplicate.ideas.first { $0.title == mainIdea.title })
        let copiedChildIdea = try #require(duplicate.ideas.first { $0.title == childIdea.title })
        let copiedURLIdea = try #require(duplicate.ideas.first { $0.title == sourceURLIdea.title })
        let copiedEventIdea = try #require(duplicate.ideas.first { $0.title == approvedEventIdea.title })

        #expect(copiedChild.id != child.id)
        #expect(duplicate.timeline.count == source.timeline.count)
        #expect(copiedChild.parentEventID == duplicate.mainEventID)
        #expect(copiedChild.participantIDs == duplicate.members.map(\.id))
        #expect(copiedChild.status == .approved)
        #expect(copiedChild.completionStatus == .upcoming)
        #expect(copiedChild.response == nil)
        #expect(copiedChild.imageData == nil)
        #expect(copiedChild.mediaAssetID == nil)
        #expect(copiedChild.linkedIdeaID == copiedChildIdea.id)
        #expect(copiedMainIdea.id != mainIdea.id)
        #expect(copiedMainIdea.eventID == duplicate.mainEventID)
        #expect(copiedChildIdea.id != childIdea.id)
        #expect(copiedChildIdea.eventID == copiedChild.id)
        #expect(copiedChildIdea.submittedBy == duplicate.members[0].name)
        #expect(copiedChildIdea.submittedByUserID == owner.id)
        #expect(copiedChildIdea.status == .new)
        #expect(copiedChildIdea.imageData == nil)
        #expect(copiedChildIdea.mediaAssetID == nil)
        #expect(copiedURLIdea.linkConfiguration?.url == sourceURLIdea.linkConfiguration?.url)
        #expect(copiedEventIdea.id != approvedEventIdea.id)
        #expect(copiedEventIdea.eventID == duplicate.mainEventID)
        #expect(copiedEventIdea.status == .new)
        #expect(duplicate.timeline.contains { $0.linkedIdeaID == copiedEventIdea.id })
        #expect(duplicate.timeline.allSatisfy { $0.status == .approved && $0.completionStatus == .upcoming })
        #expect(duplicate.ideaResponses.isEmpty)
    }

    @Test("Duplicate requires current host or manage permission and an identified current actor")
    func permissionBoundary() {
        let owner = makeOwner()
        for (role, permission) in [
            (WorkspaceRole.guest, PlanningPermission.viewOnly),
            (.collaborator, .viewOnly),
            (.collaborator, .contribute)
        ] {
            let source = makeWorkspace(owner: owner, role: role, permission: permission)
            #expect(PlanningWorkspaceDuplicateFactory.makeDuplicate(
                from: source, title: "Copy",
                owner: owner, localGuest: nil
            ) == nil)
        }

        let manager = makeWorkspace(owner: owner, role: .collaborator, permission: .manage)
        #expect(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: manager, title: "Copy",
            owner: owner, localGuest: nil
        ) != nil)

        let otherOwner = UserAccount(
            id: "other-owner", email: "other@example.com", displayName: "Other",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        #expect(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: manager, title: "Copy",
            owner: otherOwner, localGuest: nil
        ) == nil)
        #expect(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: manager, title: "  ",
            owner: owner, localGuest: nil
        ) == nil)

        let pending = makeWorkspace(owner: owner, invitationStatus: .invited)
        #expect(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: pending, title: "Copy", owner: owner, localGuest: nil
        ) == nil)
    }

    @Test("Past and cancelled events can be copied as new ongoing events without changing the source")
    func closedEventsRemainReadOnly() throws {
        let owner = makeOwner()
        for status in [MainEventStatus.finished, .cancelled] {
            let source = makeWorkspace(owner: owner, status: status)
            let sourceID = source.mainEventID
            let sourceTitle = source.title
            let sourceStatus = source.mainEventStatus

            let duplicate = try #require(PlanningWorkspaceDuplicateFactory.makeDuplicate(
                from: source, title: "Copy of \(source.title)", owner: owner, localGuest: nil
            ))

            #expect(duplicate.mainEventID != sourceID)
            #expect(duplicate.title == "Copy of \(sourceTitle)")
            #expect(duplicate.mainEventStatus == .ongoing)
            #expect(source.mainEventID == sourceID)
            #expect(source.title == sourceTitle)
            #expect(source.mainEventStatus == sourceStatus)
            #expect(!source.isMainEventDeleted)
        }
    }

    @Test("A scoped event duplicate contains only that event’s content")
    func scopedEventIsolation() throws {
        let owner = makeOwner()
        let source = makeWorkspace(owner: owner, isScopedEvent: true)
        source.workspaceBudgetCap = 500
        source.mainEventBudgetCap = 80
        let hiddenParentID = UUID()
        source.timeline.append(makeChild(in: source))
        source.addIdea(PlanningIdea(
            eventID: hiddenParentID, title: "Parent-only idea", note: "", category: .other, submittedBy: "Host"
        ))
        source.addIdea(PlanningIdea(
            eventID: source.mainEventID, title: "Scoped idea", note: "", category: .other, submittedBy: "Host"
        ))

        let duplicate = try #require(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: source, title: "Scoped copy", owner: owner, localGuest: nil
        ))
        #expect(duplicate.timeline.isEmpty)
        #expect(duplicate.ideas.map(\.title) == ["Scoped idea"])
        #expect(duplicate.ideas[0].eventID == duplicate.mainEventID)
        #expect(!duplicate.isScopedEvent)
        #expect(duplicate.workspaceBudgetCap == 80)
    }

    @Test("A local guest host becomes the sole host of a device-local duplicate")
    func localGuestHost() throws {
        let guest = LocalGuestProfile(displayName: "Guest Planner")
        let member = WorkspaceMember(
            userID: guest.storageID, name: guest.displayName, participantRole: .host,
            initials: "GP", planningPermission: .manage
        )
        let source = PlanningWorkspace(
            title: "Guest Event", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [member], ideas: [], timeline: [], registry: []
        )
        source.configureLocalGuestViewer(guest)

        let duplicate = try #require(PlanningWorkspaceDuplicateFactory.makeDuplicate(
            from: source, title: "Guest Event Copy",
            owner: nil, localGuest: guest
        ))
        #expect(duplicate.members.count == 1)
        #expect(duplicate.members[0].participantRole == .host)
        #expect(duplicate.members[0].userID == guest.storageID)
        #expect(duplicate.localGuestProfileID == guest.id)
    }

    private func makeOwner() -> UserAccount {
        UserAccount(
            id: "event-owner", email: "owner@example.com", displayName: "Alex Owner",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
    }

    private func makeWorkspace(
        owner: UserAccount,
        role: WorkspaceRole = .host,
        permission: PlanningPermission = .manage,
        invitationStatus: CollaborationInvitationStatus = .active,
        status: MainEventStatus = .draft,
        isScopedEvent: Bool = false
    ) -> PlanningWorkspace {
        let host = WorkspaceMember(
            userID: owner.id, name: owner.displayName, participantRole: role,
            initials: "AO", email: owner.email, planningPermission: permission,
            invitationStatus: invitationStatus
        )
        let workspace = PlanningWorkspace(
            isScopedEvent: isScopedEvent,
            title: "Family Picnic",
            mainEventStartsAt: .now.addingTimeInterval(86_400),
            mainEventLocation: EventLocation(address: "Detroit", placeName: "Park", locationName: "Park"),
            venueName: "Park", location: "Detroit",
            eventMessage: "Bring a dish",
            planningMode: .openToIdeas,
            members: [host], ideas: [], timeline: [],
            mainEventStatus: status,
            registry: []
        )
        workspace.configureViewer(owner)
        return workspace
    }

    private func makeChild(in workspace: PlanningWorkspace) -> TimelineItem {
        TimelineItem(
            title: "Lunch", category: .foodTasting,
            scheduledAt: .now.addingTimeInterval(90_000), location: "Park",
            participantIDs: workspace.members.map(\.id), parentEventID: workspace.mainEventID
        )
    }
}
