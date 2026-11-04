import Foundation
import Testing
@testable import Gatherory

@MainActor
struct IdeaImportWorkspaceProjectionTests {
    @Test("Workspace and child projections retain titles, IDs, and artwork")
    func projectsRootAndChildArtwork() throws {
        let rootImage = Data([0x01, 0x02])
        let childImage = Data([0x03, 0x04])
        let fixture = makeWorkspace(title: "Weekend", image: rootImage)
        let child = addChild("Dinner", image: childImage, to: fixture.workspace)

        let projected = try #require(projection([fixture.workspace], account: fixture.account.id).first)
        #expect(projected.id == fixture.workspace.mainEventID)
        #expect(projected.title == "Weekend")
        #expect(projected.imageData == rootImage)
        #expect(projected.destinations.map(\.id) == [fixture.workspace.mainEventID, child.id])
        #expect(projected.destinations.map(\.title) == ["Weekend", "Dinner"])
        #expect(projected.destinations.map(\.imageData) == [rootImage, childImage])
        #expect(projected.destinations.map(\.reference) == [.main, .subevent(child.id)])
    }

    @Test("Child search finds its parent without revealing private siblings, then detail restores eligible targets")
    func childSearchDoesNotExposePrivateSiblings() throws {
        let fixture = makeWorkspace(title: "Weekend")
        let dinner = addChild("Dinner", to: fixture.workspace)
        let privateBrunch = addChild("Private Brunch", to: fixture.workspace)
        addCoHost(to: [privateBrunch.id], in: fixture.workspace)
        let owner = try #require(fixture.workspace.members.first)
        #expect(fixture.workspace.updateParticipant(owner.id, role: .guest,
            planningPermission: .viewOnly, in: .subevent(privateBrunch.id)))

        let projected = try #require(projection([fixture.workspace], account: fixture.account.id, search: "dinner").first)
        #expect(projected.id == fixture.workspace.mainEventID)
        #expect(projected.destinations.map(\.id) == [fixture.workspace.mainEventID, dinner.id])
        #expect(!projected.destinations.contains { $0.title == "Private Brunch" })

        let parentMatch = try #require(projection([fixture.workspace], account: fixture.account.id, search: "weekend").first)
        #expect(parentMatch.destinations.map(\.id) == [fixture.workspace.mainEventID, dinner.id])
        let detail = try #require(workspaceProjection([fixture.workspace], id: fixture.workspace.mainEventID,
            account: fixture.account.id, search: ""))
        #expect(detail.destinations.map(\.id) == [fixture.workspace.mainEventID, dinner.id])
        #expect(!detail.destinations.contains { $0.title == "Private Brunch" })
    }

    @Test("A writable child remains available when the main event is view-only")
    func childWritePermissionCanOutliveMainWritePermission() throws {
        let fixture = makeWorkspace(title: "Weekend")
        let child = addChild("Dinner", to: fixture.workspace)
        let owner = try #require(fixture.workspace.members.first)
        let coHost = WorkspaceMember(name: "Co-host", participantRole: .host, initials: "CH")
        fixture.workspace.members.append(coHost)
        fixture.workspace.addParticipant(coHost.id, to: .main)
        fixture.workspace.addParticipant(coHost.id, to: .subevent(child.id))
        #expect(fixture.workspace.updateParticipant(owner.id, role: .collaborator,
            planningPermission: .viewOnly, in: .main))
        #expect(fixture.workspace.updateParticipant(owner.id, role: .collaborator,
            planningPermission: .contribute, in: .subevent(child.id)))

        let projected = try #require(projection([fixture.workspace], account: fixture.account.id).first)
        #expect(projected.destinations.map(\.id) == [child.id])
        let detail = try #require(workspaceProjection([fixture.workspace], id: fixture.workspace.mainEventID,
            account: fixture.account.id, search: ""))
        #expect(detail.destinations.map(\.id) == [child.id])
    }

    @Test("Workspace and destination search folds case and diacritics")
    func searchIsCaseAndDiacriticInsensitive() throws {
        let fixture = makeWorkspace(title: "Café Weekend")
        let child = addChild("Crème brûlée Dinner", to: fixture.workspace)

        #expect(projection([fixture.workspace], account: fixture.account.id, search: "CAFE").map(\.id) == [fixture.workspace.mainEventID])
        let childMatch = try #require(projection([fixture.workspace], account: fixture.account.id, search: "CREME BRULEE").first)
        #expect(childMatch.destinations.map(\.id) == [fixture.workspace.mainEventID, child.id])
    }

    @Test("Only active contributors can see a child destination")
    func filtersViewOnlyGuestAndInvitedParticipants() throws {
        let fixture = makeWorkspace(title: "Weekend")
        let viewOnly = addChild("View only", to: fixture.workspace)
        let contributor = addChild("Contributor", to: fixture.workspace)
        let guest = addChild("Guest", to: fixture.workspace)
        addCoHost(to: [viewOnly.id, contributor.id, guest.id], in: fixture.workspace)
        let owner = try #require(fixture.workspace.members.first)
        #expect(fixture.workspace.updateParticipant(owner.id, role: .collaborator,
            planningPermission: .viewOnly, in: .subevent(viewOnly.id)))
        #expect(fixture.workspace.updateParticipant(owner.id, role: .collaborator,
            planningPermission: .contribute, in: .subevent(contributor.id)))
        #expect(fixture.workspace.updateParticipant(owner.id, role: .guest,
            planningPermission: .viewOnly, in: .subevent(guest.id)))
        let projected = try #require(projection([fixture.workspace], account: fixture.account.id).first)
        #expect(projected.destinations.map(\.id) == [fixture.workspace.mainEventID, contributor.id])

        let invitedAccount = UserAccount(id: "invited-account", email: "invited@example.test", displayName: "Invited",
            role: .member, authenticationProvider: .password, createdAt: Date(timeIntervalSince1970: 1_700_000_001))
        let invitedWorkspace = PlanningWorkspace.newWorkspace(title: "Invited event", startsAt: .now,
            eventLocation: nil, imageData: nil, owner: fixture.account)
        let pending = WorkspaceMember(userID: invitedAccount.id, name: "Invited", participantRole: .collaborator,
            initials: "I", invitationStatus: .invited)
        invitedWorkspace.members.append(pending)
        let pendingChild = addChild("Invited child", to: invitedWorkspace)
        invitedWorkspace.addParticipant(pending.id, to: .main)
        invitedWorkspace.addParticipant(pending.id, to: .subevent(pendingChild.id))
        invitedWorkspace.configureViewer(invitedAccount)
        #expect(projection([invitedWorkspace], account: invitedAccount.id).isEmpty)
    }

    @Test("Deleted, archived, cancelled, and completed destinations are unavailable")
    func filtersUnavailableEvents() throws {
        let fixture = makeWorkspace(title: "Weekend")
        let archived = addChild("Archived", to: fixture.workspace)
        let cancelled = addChild("Cancelled", to: fixture.workspace)
        let completed = addChild("Completed", to: fixture.workspace)
        setChildStatus(archived.id, status: .archived, in: fixture.workspace)
        setChildStatus(cancelled.id, status: .cancelled, in: fixture.workspace)
        setChildCompletion(completed.id, status: .complete, in: fixture.workspace)

        let projected = try #require(projection([fixture.workspace], account: fixture.account.id).first)
        #expect(projected.destinations.map(\.id) == [fixture.workspace.mainEventID])

        fixture.workspace.isMainEventDeleted = true
        #expect(projection([fixture.workspace], account: fixture.account.id).isEmpty)
        fixture.workspace.isMainEventDeleted = false
        fixture.workspace.mainEventStatus = .cancelled
        #expect(projection([fixture.workspace], account: fixture.account.id).isEmpty)
    }

    @Test("Event ideas are limited to the main event, and scoped workspaces have no child rows")
    func categoryAndScopedWorkspaceLimits() throws {
        let fixture = makeWorkspace(title: "Weekend")
        let child = addChild("Dinner", to: fixture.workspace)
        let eventIdeaTargets = try #require(projection([fixture.workspace], account: fixture.account.id, category: IdeaCategory.event.rawValue).first)
        #expect(eventIdeaTargets.destinations.map(\.id) == [fixture.workspace.mainEventID])

        let scoped = makeWorkspace(title: "Scoped Dinner").workspace
        scoped.isScopedEvent = true
        _ = addChild("Nested should be ignored", to: scoped)
        let scopedResult = try #require(projection([scoped], account: fixture.account.id).first)
        #expect(scopedResult.destinations.map(\.id) == [scoped.mainEventID])
        #expect(scopedResult.destinations[0].id != child.id)
    }

    @Test("Account identity gates projection and A/B account workspaces stay isolated")
    func accountIdentityAndLibraryIsolation() throws {
        let accountA = makeWorkspace(title: "Account A")
        let accountB = makeWorkspace(title: "Account B", accountID: "account-b")
        #expect(projection([accountA.workspace], account: "account-b").isEmpty)
        #expect(projection([accountB.workspace], account: accountA.account.id).isEmpty)
        #expect(projection([accountA.workspace, accountB.workspace], account: accountA.account.id).map(\.id) == [accountA.workspace.mainEventID])
        #expect(projection([accountA.workspace, accountB.workspace], account: accountB.account.id).map(\.id) == [accountB.workspace.mainEventID])
        #expect(projection([accountA.workspace], account: nil).isEmpty)
    }

    @Test("Projection is read-only and empty search preserves input order")
    func readOnlyAndStableEmptySearchOrder() throws {
        let first = makeWorkspace(title: "First")
        let second = makeWorkspace(title: "Second", accountID: first.account.id)
        let child = addChild("Child", to: first.workspace)
        let library = WorkspaceLibrary(workspaces: [first.workspace, second.workspace])
        library.configureViewer(first.account)
        library.open(second.workspace)
        first.workspace.selectEventContext(.subevent(child.id))
        let originalSelection = library.selectedWorkspaceID
        let originalContext = first.workspace.selectedEventReference
        let originalIdeas = first.workspace.ideas
        let originalTimeline = first.workspace.timeline

        let projected = projection(library.workspaces, account: first.account.id)
        #expect(projected.map(\.id) == [first.workspace.mainEventID, second.workspace.mainEventID])
        #expect(library.selectedWorkspaceID == originalSelection)
        #expect(first.workspace.selectedEventReference == originalContext)
        #expect(first.workspace.ideas == originalIdeas)
        #expect(first.workspace.timeline == originalTimeline)

        let ordered = projection([second.workspace, first.workspace], account: first.account.id)
        #expect(ordered.map(\.id) == [second.workspace.mainEventID, first.workspace.mainEventID])
        let both = projection([second.workspace, first.workspace], account: first.account.id)
        #expect(both.map(\.id) == [second.workspace.mainEventID, first.workspace.mainEventID])
    }

    private func projection(
        _ workspaces: [PlanningWorkspace],
        account accountID: String?,
        search: String = "",
        category: String = IdeaCategory.other.rawValue
    ) -> [IdeaImportWorkspaceProjection.Workspace] {
        IdeaImportWorkspaceProjection.workspaces(in: workspaces, accountID: accountID,
            search: search, sourceCategory: category)
    }

    private func workspaceProjection(
        _ workspaces: [PlanningWorkspace],
        id: UUID,
        account accountID: String?,
        search: String,
        category: String = IdeaCategory.other.rawValue
    ) -> IdeaImportWorkspaceProjection.Workspace? {
        IdeaImportWorkspaceProjection.workspace(in: workspaces, mainEventID: id,
            accountID: accountID, search: search, sourceCategory: category)
    }

    private func makeWorkspace(title: String, image: Data? = nil, accountID: String = "projection-account") -> (account: UserAccount, workspace: PlanningWorkspace) {
        let account = UserAccount(id: accountID, email: "\(accountID)@example.test", displayName: "Morgan Planner",
            role: .planner, authenticationProvider: .password, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let workspace = PlanningWorkspace.newWorkspace(title: title, startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            eventLocation: nil, imageData: image, owner: account)
        workspace.configureViewer(account)
        return (account, workspace)
    }

    private func addChild(_ title: String, image: Data? = nil, to workspace: PlanningWorkspace) -> TimelineItem {
        let child = TimelineItem(title: title, category: .other, scheduledAt: Date(timeIntervalSince1970: 1_800_100_000),
            location: "", participantIDs: workspace.members.map(\.id), parentEventID: workspace.mainEventID,
            imageData: image)
        workspace.timeline.append(child)
        for member in workspace.members { workspace.addParticipant(member.id, to: .subevent(child.id)) }
        return child
    }

    private func addCoHost(to childIDs: [UUID], in workspace: PlanningWorkspace) {
        let coHost = WorkspaceMember(name: "Co-host", participantRole: .host, initials: "CH")
        workspace.members.append(coHost)
        for childID in childIDs { workspace.addParticipant(coHost.id, to: .subevent(childID)) }
    }

    private func setChildStatus(_ id: UUID, status: EventStatus, in workspace: PlanningWorkspace) {
        guard let index = workspace.timeline.firstIndex(where: { $0.id == id }) else { Issue.record("Missing child"); return }
        workspace.timeline[index].status = status
    }

    private func setChildCompletion(_ id: UUID, status: EventCompletionStatus, in workspace: PlanningWorkspace) {
        guard let index = workspace.timeline.firstIndex(where: { $0.id == id }) else { Issue.record("Missing child"); return }
        workspace.timeline[index].completionStatus = status
    }
}
