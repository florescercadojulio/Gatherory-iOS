import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Gatherory

@MainActor
struct ManageDashboardTests {
    @Test("Dashboard columns stay flush when collaborator content needs more space")
    func columnsShareBottomEdge() {
        for collaborators: CGFloat in [200, 300, 420] {
            let heights = ManageDashboardLayoutPolicy.columnHeights(
                budget: 180, guests: 90, collaborators: collaborators, spacing: 12)
            #expect(heights.budget >= 180)
            #expect(heights.total >= collaborators)
            #expect(heights.budget + 12 + 90 == heights.total)
        }
    }

    @Test("Dashboard uses columns only for finite widths of at least 360 outside accessibility sizes")
    func columnLayoutThreshold() {
        for (width, expected) in [
            (CGFloat(359), false),
            (CGFloat(360), true),
            (CGFloat(390), true),
            (.nan, false),
            (-1, false),
            (.infinity, false)
        ] {
            #expect(ManageDashboardLayoutPolicy.usesColumns(
                availableWidth: width,
                isAccessibilitySize: false
            ) == expected)
        }

        #expect(!ManageDashboardLayoutPolicy.usesColumns(availableWidth: 360, isAccessibilitySize: true))
        #expect(!ManageDashboardLayoutPolicy.usesColumns(availableWidth: 390, isAccessibilitySize: true))
    }

    @Test("Changing dashboard summary references leaves workspace selection and outbox unchanged")
    func summariesAreReadOnly() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "manage-dashboard")
        let child = makeChild("Dinner")
        let workspace = makeWorkspace(timeline: [child])
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let context = ModelContext(persistence.container)
        let beforeOutbox = try context.fetch(FetchDescriptor<PendingMutation>())
            .map(PendingMutationSnapshot.init)
        var pendingNotifications = 0
        defer { persistence.onPendingMutations = nil }
        persistence.onPendingMutations = { pendingNotifications += 1 }
        persistence.startObserving(library)

        var dashboardReference: EventReference = .main
        let mainSummary = try #require(ManageEventSummary(workspace: workspace, reference: dashboardReference))
        dashboardReference = .subevent(child.id)
        let childSummary = try #require(ManageEventSummary(workspace: workspace, reference: dashboardReference))
        #expect(mainSummary.eventID == workspace.mainEventID)
        #expect(childSummary.eventID == child.id)
        #expect(workspace.selectedEventReference == .main)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>())
            .map(PendingMutationSnapshot.init) == beforeOutbox)
        #expect(pendingNotifications == 0)
    }

    @Test("Scoped dashboard summaries expose only the main event")
    func scopedReferencesStayAtMain() {
        let child = makeChild("Sibling")
        let workspace = makeWorkspace(isScoped: true, timeline: [child])

        #expect(ManageEventSummary.references(in: workspace) == [.main])
        #expect(ManageEventSummary(workspace: workspace, reference: .main) != nil)
        #expect(ManageEventSummary(workspace: workspace, reference: .subevent(child.id)) == nil)
    }

    @Test("Summary selection preserves event-specific permissions and attendance independent of role")
    func summariesPreservePermissionsAndAttendance() throws {
        let host = WorkspaceMember(userID: "dashboard-host", name: "Host", participantRole: .host,
                                   initials: "H", attendance: .going, planningPermission: .manage)
        let contributor = WorkspaceMember(userID: "dashboard-contributor", name: "Contributor",
                                          participantRole: .collaborator, initials: "C",
                                          attendance: .invited, planningPermission: .contribute)
        let guest = WorkspaceMember(userID: "dashboard-guest", name: "Guest", participantRole: .guest,
                                    initials: "G", attendance: .maybe, planningPermission: .viewOnly)
        let mainID = UUID()
        var child = makeChild("Dinner", parentEventID: mainID)
        child.budgetCap = 100
        let workspace = makeWorkspace(
            mainEventID: mainID,
            members: [host, contributor, guest],
            participations: [
                participation(host, eventID: mainID, role: .host, permission: .manage, attendance: .going),
                participation(contributor, eventID: mainID, role: .collaborator,
                              permission: .contribute, attendance: .invited),
                participation(guest, eventID: mainID, role: .guest,
                              permission: .viewOnly, attendance: .maybe),
                participation(host, eventID: child.id, role: .guest,
                              permission: .viewOnly, attendance: .declined),
                participation(contributor, eventID: child.id, role: .collaborator,
                              permission: .manage, attendance: .going),
                participation(guest, eventID: child.id, role: .guest,
                              permission: .viewOnly, attendance: .invited)
            ],
            timeline: [child]
        )
        workspace.configureViewer(account("dashboard-contributor"))

        let permissionBeforeSummaryQueries = (
            workspace.canManageInvitations(for: .main),
            workspace.canManageInvitations(for: .subevent(child.id))
        )
        let main = try #require(ManageEventSummary(workspace: workspace, reference: .main))
        let childSummary = try #require(ManageEventSummary(
            workspace: workspace,
            reference: .subevent(child.id)
        ))
        let budget = BudgetDestinationProjection.make(
            reference: childSummary.reference,
            isScopedEvent: workspace.isScopedEvent,
            mainEventID: workspace.mainEventID,
            workspaceTitle: workspace.title,
            timeline: workspace.timeline,
            expenses: workspace.eventExpenses,
            workspaceBudgetCap: workspace.workspaceBudgetCap,
            mainEventBudgetCap: workspace.mainEventBudgetCap
        )
        #expect(!main.canManageInvitations)
        #expect(main.canSendNote)
        #expect(childSummary.canManageInvitations)
        #expect(childSummary.canSendNote)
        #expect(permissionBeforeSummaryQueries.0 == main.canManageInvitations)
        #expect(permissionBeforeSummaryQueries.1 == childSummary.canManageInvitations)
        #expect(budget.isValid)
        #expect(!budget.isWorkspaceOverview)
        #expect(budget.budgetSummaries.map(\.reference) == [.subevent(child.id)])
        #expect(main.attendance.going == 1)
        #expect(main.attendance.maybe == 1)
        #expect(main.attendance.awaiting == 1)
        #expect(childSummary.attendance.going == 1)
        #expect(childSummary.attendance.declined == 1)
        #expect(childSummary.attendance.awaiting == 1)
        #expect(workspace.selectedEventReference == .main)
    }

    private func makeWorkspace(
        isScoped: Bool = false,
        mainEventID: UUID = UUID(),
        members: [WorkspaceMember]? = nil,
        participations: [EventParticipation]? = nil,
        timeline: [TimelineItem] = []
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            mainEventID: mainEventID,
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: .now,
            venueName: "Venue",
            location: "Address",
            planningMode: .openToIdeas,
            members: members ?? [WorkspaceMember(userID: "dashboard-host", name: "Host",
                                                   participantRole: .host, initials: "H",
                                                   planningPermission: .manage)],
            eventParticipations: participations,
            ideas: [],
            timeline: timeline,
            eventExpenses: [],
            workspaceBudgetCap: 500,
            mainEventBudgetCap: 300,
            registry: []
        )
    }

    private func makeChild(_ title: String, parentEventID: UUID? = nil) -> TimelineItem {
        TimelineItem(title: title, category: .other, scheduledAt: .now,
                     location: "", participantIDs: [], parentEventID: parentEventID,
                     status: .approved)
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
