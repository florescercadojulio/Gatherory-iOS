import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventCSVExportRequestTests {
    @Test("A pending export cannot survive sign-out and re-entry to the same account")
    func sessionGenerationIsolation() async throws {
        let authentication = session()
        let account = try #require(authentication.currentUser)
        let workspace = fixture(account: account)
        let request = try #require(EventCSVExportRequest.make(kind: .guestList, workspace: workspace,
            reference: .main, authentication: authentication))
        #expect(request.makePayload(workspace: workspace, authentication: authentication)?.kind == .guestList)
        #expect(await authentication.signOut())
        #expect(request.makePayload(workspace: workspace, authentication: authentication) == nil)
        try await authentication.signIn(email: account.email, password: DevelopmentAccountFixtures.plannerPassword)
        #expect(authentication.currentUser?.id == account.id)
        #expect(!request.isAuthorized(workspace: workspace, authentication: authentication))
        #expect(EventCSVExportRequest.make(kind: .guestList, workspace: workspace,
            reference: .main, authentication: authentication) != nil)
    }

    @Test("Export requests use fresh RSVP data, exact workspace scope and current permissions")
    func scopeAndFreshContent() throws {
        let authentication = session()
        let account = try #require(authentication.currentUser)
        let workspace = fixture(account: account)
        let request = try #require(EventCSVExportRequest.make(kind: .guestList, workspace: workspace,
            reference: .main, authentication: authentication))
        let first = try #require(request.makePayload(workspace: workspace, authentication: authentication))
        #expect(request.makePayload(workspace: fixture(account: account), authentication: authentication) == nil)
        workspace.selectedEventReference = .subevent(UUID())
        #expect(request.isAuthorized(workspace: workspace, authentication: authentication))
        workspace.setMainEventResponse(.notSure)
        let updated = try #require(request.makePayload(workspace: workspace, authentication: authentication))
        #expect(first.data != updated.data)
        #expect(workspace.updateParticipant(workspace.members[0].id, role: .collaborator,
            planningPermission: .viewOnly, in: .main))
        #expect(request.makePayload(workspace: workspace, authentication: authentication) == nil)
    }

    @Test("Both CSV kinds stay distinct and an unfinished guest handover cannot create a request")
    func kindAndReadinessIsolation() throws {
        let authentication = session()
        let workspace = fixture(account: try #require(authentication.currentUser))
        let guest = try #require(EventCSVExportRequest.make(kind: .guestList, workspace: workspace,
            reference: .main, authentication: authentication)?.makePayload(workspace: workspace, authentication: authentication))
        let schedule = try #require(EventCSVExportRequest.make(kind: .schedule, workspace: workspace,
            reference: .main, authentication: authentication)?.makePayload(workspace: workspace, authentication: authentication))
        #expect(guest.kind == .guestList)
        #expect(schedule.kind == .schedule)
        #expect(guest.data != schedule.data)
        #expect(!EventCSVExportRequest.canExport(kind: .guestList, workspace: workspace,
            reference: .main, authentication: nil))
        let handover = session(profile: LocalGuestProfile(displayName: "Device guest"))
        #expect(handover.hasPendingGuestImport)
        #expect(EventCSVExportRequest.make(kind: .guestList, workspace: workspace,
            reference: .main, authentication: handover) == nil)
    }

    private func session(profile: LocalGuestProfile? = nil) -> AuthenticationSession {
        AuthenticationSession(environment: .development, skipsAuthentication: true,
            guestProfileStore: ExportProfileStore(profile: profile))
    }

    private func fixture(account: UserAccount) -> PlanningWorkspace {
        let workspace = PlanningWorkspace(title: "Export request fixture", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: account.id, name: "Current manager", participantRole: .collaborator,
                initials: "CM", planningPermission: .manage),
                WorkspaceMember(userID: "another-host", name: "Other host", participantRole: .host,
                    initials: "OH", planningPermission: .manage)], ideas: [], timeline: [], registry: [])
        workspace.configureViewer(account)
        return workspace
    }
}

@MainActor
private final class ExportProfileStore: LocalGuestProfileStore {
    var profile: LocalGuestProfile?
    init(profile: LocalGuestProfile?) { self.profile = profile }
    func load() throws -> LocalGuestProfile? { profile }
    func save(_ profile: LocalGuestProfile) throws { self.profile = profile }
    func remove() throws { profile = nil }
}
