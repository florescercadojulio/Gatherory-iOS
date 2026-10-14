import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct ManageNavigationTests {
    @Test("Manage destinations include the main event and every live child, including unscheduled children")
    func referencesIncludeMainAndUnscheduledChildren() throws {
        let workspace = makeWorkspace()
        let scheduled = makeChild("Scheduled", parentEventID: workspace.mainEventID)
        let unscheduled = makeChild("Unscheduled", parentEventID: workspace.mainEventID,
                                    schedulingState: .unscheduled)
        let archived = makeChild("Archived", parentEventID: workspace.mainEventID, status: .archived)
        workspace.timeline = [scheduled, unscheduled, archived]

        #expect(Set(ManageEventSummary.references(in: workspace)) == Set([
            .main, .subevent(scheduled.id), .subevent(unscheduled.id)
        ]))

        workspace.isMainEventDeleted = true
        #expect(Set(ManageEventSummary.references(in: workspace)) == Set([
            .subevent(scheduled.id), .subevent(unscheduled.id)
        ]))
    }

    @Test("Scoped Manage navigation contains only its main event and rejects injected sibling references")
    func scopedReferencesAreIsolated() throws {
        let workspace = makeWorkspace(isScoped: true)
        let injectedChild = makeChild("Injected sibling", parentEventID: workspace.mainEventID)
        workspace.timeline = [injectedChild]

        #expect(ManageEventSummary.references(in: workspace) == [.main])
        #expect(ManageEventSummary(workspace: workspace, reference: .main) != nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(injectedChild.id)) == nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(UUID())) == nil)
    }

    @Test("Summary resolves only valid main and child events, not ideas or unknown identifiers")
    func summaryRejectsInvalidReferences() throws {
        let workspace = makeWorkspace()
        let child = makeChild("Dinner", parentEventID: workspace.mainEventID)
        workspace.timeline = [child]

        let main = try #require(ManageEventSummary(workspace: workspace, reference: .main))
        #expect(main.reference == .main)
        #expect(main.eventID == workspace.mainEventID)
        #expect(main.title == workspace.title)

        let childSummary = try #require(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)))
        #expect(childSummary.reference == .subevent(child.id))
        #expect(childSummary.eventID == child.id)
        #expect(childSummary.title == child.title)

        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(UUID())) == nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .idea(UUID())) == nil)

        workspace.timeline[0].status = .archived
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)) == nil)
        workspace.isMainEventDeleted = true
        #expect(ManageEventSummary(workspace: workspace, reference: .main) == nil)
    }

    @Test("Summary counts RSVP and planning roles independently and reports invitation permission per event")
    func countsAndExactEventPermissions() throws {
        let host = WorkspaceMember(userID: "host", name: "Host", participantRole: .host,
                                   initials: "H", attendance: .going, planningPermission: .manage)
        let contributor = WorkspaceMember(userID: "contributor", name: "Contributor",
                                          participantRole: .collaborator, initials: "C",
                                          attendance: .invited, planningPermission: .contribute)
        let manager = WorkspaceMember(userID: "manager", name: "Manager", participantRole: .collaborator,
                                      initials: "M", attendance: .declined, planningPermission: .manage)
        let guest = WorkspaceMember(userID: "guest", name: "Guest", participantRole: .guest,
                                    initials: "G", attendance: .going, planningPermission: .viewOnly)
        let reader = WorkspaceMember(userID: "reader", name: "Reader", participantRole: .collaborator,
                                     initials: "R", attendance: .invited, planningPermission: .viewOnly)
        let mainID = UUID()
        let child = makeChild("Dinner", parentEventID: mainID)
        let workspace = makeWorkspace(
            mainEventID: mainID,
            members: [host, contributor, manager, guest, reader],
            participations: [
                participation(host, eventID: mainID, role: .host, permission: .manage, attendance: .going),
                participation(contributor, eventID: mainID, role: .collaborator, permission: .contribute, attendance: .invited),
                participation(manager, eventID: mainID, role: .collaborator, permission: .manage, attendance: .declined),
                participation(guest, eventID: mainID, role: .guest, permission: .viewOnly, attendance: .going),
                participation(reader, eventID: mainID, role: .collaborator, permission: .viewOnly, attendance: .invited),
                participation(host, eventID: child.id, role: .collaborator, permission: .contribute, attendance: .invited),
                participation(contributor, eventID: child.id, role: .collaborator, permission: .manage, attendance: .going),
                participation(manager, eventID: child.id, role: .guest, permission: .viewOnly, attendance: .going),
                participation(reader, eventID: child.id, role: .collaborator, permission: .manage, attendance: .invited)
            ],
            expenses: [
                EventExpense(eventID: mainID, title: "Main cost", amount: 125, status: .paid),
                EventExpense(eventID: child.id, title: "Child cost", amount: 40, status: .estimated)
            ],
            timeline: [child]
        )
        workspace.configureViewer(account("host"))

        let main = try #require(ManageEventSummary(workspace: workspace, reference: .main))
        #expect(main.spent == 125)
        #expect(main.budget == workspace.mainEventBudgetCap)
        #expect(main.goingCount == 2)
        #expect(main.awaitingRSVPCount == 2)
        #expect(main.collaboratorCount == 4)
        #expect(main.canManageInvitations)

        let childSummary = try #require(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)))
        #expect(childSummary.spent == 40)
        #expect(childSummary.goingCount == 2)
        #expect(childSummary.awaitingRSVPCount == 2)
        #expect(childSummary.collaboratorCount == 3)
        #expect(!childSummary.canManageInvitations)

        workspace.configureViewer(account("contributor"))
        #expect(ManageEventSummary(workspace: workspace, reference: .main)?.canManageInvitations == false)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(child.id))?.canManageInvitations == true)
        workspace.configureViewer(account("manager"))
        #expect(ManageEventSummary(workspace: workspace, reference: .main)?.canManageInvitations == true)
        workspace.configureViewer(account("reader"))
        #expect(ManageEventSummary(workspace: workspace, reference: .main)?.canManageInvitations == false)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(child.id))?.canManageInvitations == true)
    }

    @Test("Guest and invitation projection viewers cannot get Manage summaries")
    func guestAndProjectionDenied() {
        let guest = WorkspaceMember(userID: "guest", name: "Guest", participantRole: .guest,
                                    initials: "G", planningPermission: .viewOnly)
        let workspace = makeWorkspace(members: [guest])
        let child = makeChild("Dinner", parentEventID: workspace.mainEventID)
        workspace.timeline = [child]
        workspace.configureViewer(account("guest"))

        #expect(!workspace.showsPlanningInterface)
        #expect(ManageEventSummary.references(in: workspace).isEmpty)
        #expect(ManageEventSummary(workspace: workspace, reference: .main) == nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)) == nil)

        workspace.isInvitationProjection = true
        #expect(ManageEventSummary.references(in: workspace).isEmpty)
        #expect(ManageEventSummary(workspace: workspace, reference: .main) == nil)
    }

    @Test("Switching configured viewers does not leak Manage access across accounts")
    func accountSwitchDoesNotLeak() throws {
        let first = WorkspaceMember(userID: "first-account", name: "First", participantRole: .host,
                                    initials: "F", planningPermission: .manage)
        let second = WorkspaceMember(userID: "second-account", name: "Second", participantRole: .guest,
                                     initials: "S", planningPermission: .viewOnly)
        let workspace = makeWorkspace(members: [first, second])

        workspace.configureViewer(account("first-account"))
        #expect(ManageEventSummary.references(in: workspace) == [.main])
        #expect(ManageEventSummary(workspace: workspace, reference: .main)?.canManageInvitations == true)

        workspace.configureViewer(account("second-account"))
        #expect(ManageEventSummary.references(in: workspace).isEmpty)
        #expect(ManageEventSummary(workspace: workspace, reference: .main) == nil)

        workspace.configureViewer(account("unrelated-account"))
        #expect(ManageEventSummary.references(in: workspace).isEmpty)
    }

    @Test("Querying summaries and selecting a destination leaves sync entities and outbox unchanged")
    func navigationQueriesDoNotMutateSyncState() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "manage-owner")
        let workspace = makeWorkspace()
        let child = makeChild("Scheduled", parentEventID: workspace.mainEventID,
                              schedulingState: .scheduled)
        workspace.timeline = [child]
        library.add(workspace)
        try persistence.saveChanges(in: library)

        let beforeEntities = try WorkspaceArchiveV1(workspace: workspace)
            .syncEntities(using: WorkspaceArchiveCodec())
        let beforeOutbox = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init)
        let beforeArchive = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace))
        var pendingNotifications = 0
        defer { persistence.onPendingMutations = nil }
        persistence.onPendingMutations = { pendingNotifications += 1 }
        persistence.startObserving(library)

        var localSelection: EventReference = .main
        #expect(ManageEventSummary.references(in: workspace) == [.main, .subevent(child.id)])
        localSelection = .subevent(child.id)
        #expect(ManageEventSummary(workspace: workspace, reference: localSelection)?.eventID == child.id)
        #expect(workspace.selectedEventReference == .main)
        localSelection = .main
        #expect(ManageEventSummary(workspace: workspace, reference: localSelection)?.eventID == workspace.mainEventID)

        let afterEntities = try WorkspaceArchiveV1(workspace: workspace)
            .syncEntities(using: WorkspaceArchiveCodec())
        #expect(afterEntities == beforeEntities)
        #expect(try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace)) == beforeArchive)
        #expect(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init) == beforeOutbox)
        try await Task.sleep(for: .milliseconds(600))
        #expect(pendingNotifications == 0)
        #expect(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(PendingMutationSnapshot.init) == beforeOutbox)
    }

    private func makeWorkspace(
        isScoped: Bool = false,
        mainEventID: UUID = UUID(),
        members: [WorkspaceMember]? = nil,
        participations: [EventParticipation]? = nil,
        expenses: [EventExpense] = [],
        timeline: [TimelineItem] = []
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            mainEventID: mainEventID,
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            venueName: "Venue",
            location: "Address",
            planningMode: .openToIdeas,
            members: members ?? [WorkspaceMember(userID: "host", name: "Host", participantRole: .host,
                                                  initials: "H", planningPermission: .manage)],
            eventParticipations: participations,
            ideas: [],
            timeline: timeline,
            eventExpenses: expenses,
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 300,
            registry: []
        )
    }

    private func makeChild(
        _ title: String,
        parentEventID: UUID? = nil,
        schedulingState: EventSchedulingState = .scheduled,
        status: EventStatus = .approved
    ) -> TimelineItem {
        TimelineItem(title: title, category: .other, scheduledAt: .now,
                     schedulingState: schedulingState, location: "", participantIDs: [],
                     parentEventID: parentEventID,
                     status: status)
    }

    private func participation(
        _ member: WorkspaceMember,
        eventID: UUID,
        role: WorkspaceRole,
        permission: PlanningPermission,
        attendance: AttendanceStatus
    ) -> EventParticipation {
        EventParticipation(eventID: eventID, memberID: member.id, role: role,
                           planningPermission: permission, attendance: attendance,
                           invitationStatus: .active)
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id,
                    role: .planner, authenticationProvider: .password, createdAt: .now)
    }
}
