import Foundation
import Testing
@testable import Gatherory

struct EventInvitationTests {
    @Test("RSVP updates only the viewer's participation in that event and survives sync encoding")
    @MainActor
    func perPersonAttendance() throws {
        let workspace = PlanningWorkspace.sample
        let collaboratorIndex = try #require(workspace.members.firstIndex { $0.participantRole == .collaborator })
        let memberID = workspace.members[collaboratorIndex].id
        workspace.members[collaboratorIndex].userID = "rsvp-collaborator"
        let account = UserAccount(id: "rsvp-collaborator", email: "rsvp@example.com", displayName: "Collaborator",
                                  role: .member, authenticationProvider: .password, createdAt: .now)
        workspace.configureViewer(account)
        let child = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now, location: "", participantIDs: [memberID])
        workspace.timeline.append(child)
        workspace.addParticipant(memberID, to: .subevent(child.id))
        let otherPeople = workspace.eventParticipations.filter { $0.memberID != memberID }
        let childBefore = workspace.currentViewerResponse(for: .subevent(child.id))
        for (response, attendance) in [(EventResponse.going, AttendanceStatus.going), (.notSure, .maybe), (.notGoing, .declined)] {
            workspace.setMainEventResponse(response)
            #expect(workspace.currentViewerResponse(for: .main) == response)
            #expect(workspace.participants(for: .main).first { $0.id == memberID }?.attendance == attendance)
            #expect(workspace.currentViewerResponse(for: .subevent(child.id)) == childBefore)
            #expect(workspace.eventParticipations.filter { $0.memberID != memberID } == otherPeople)

            let archive = WorkspaceArchiveV1(workspace: workspace)
            let relationship = try #require(workspace.eventParticipations.first { $0.memberID == memberID && $0.eventID == workspace.mainEventID })
            let payload = try JSONEncoder().encode(relationship)
            #expect(try JSONDecoder().decode(EventParticipation.self, from: payload).attendance == attendance)
            let restored = try JSONDecoder().decode(WorkspaceArchiveV1.self, from: JSONEncoder().encode(archive)).makeWorkspace()
            restored.configureViewer(account)
            #expect(restored.currentViewerResponse(for: .main) == response)
        }
        workspace.setResponse(.notSure, for: child)
        #expect(workspace.currentViewerResponse(for: .subevent(child.id)) == .notSure)
        #expect(workspace.currentViewerResponse(for: .main) == .notGoing)
        workspace.configureViewer(UserAccount(id: "not-in-event", email: "stranger@example.com", displayName: "Stranger",
                                              role: .member, authenticationProvider: .password, createdAt: .now))
        #expect(workspace.currentViewerResponse(for: .main) == nil)
        let before = workspace.eventParticipations
        workspace.setMainEventResponse(.going)
        #expect(workspace.eventParticipations == before)
    }

    @Test("Messages contains the real invitation URL and preserves the original event context")
    @MainActor
    func nativeMessageDraftContent() throws {
        let originalLink = try #require(URL(string: "https://app.gatherory.com/join/\(UUID())"))
        let newLink = try #require(URL(string: "https://app.gatherory.com/join/\(UUID())"))
        let original = InvitationMessageDraft(eventTitle: "Alex & Jordan's Wedding? #1 🎉", invitationURL: originalLink)
        let next = InvitationMessageDraft(eventTitle: "Cabin weekend", invitationURL: newLink)
        #expect(original.body.contains(original.eventTitle))
        #expect(original.body.hasSuffix("\n" + originalLink.absoluteString))
        #expect(!original.body.contains(newLink.absoluteString))
        #expect(next.body.hasSuffix("\n" + newLink.absoluteString))
        #expect(original.id != next.id)
    }

    @Test("Anyone-link responses do not require an email address")
    @MainActor
    func publicInvitationResponse() throws {
        let eventID = UUID()
        let token = UUID()
        let data = Data("{\"eventId\":\"\(eventID)\",\"email\":null,\"expiresAt\":\"2026-10-26T00:00:00Z\",\"url\":\"https://dev.gatherory.com/join/\(token)\"}".utf8)
        let invitation = try JSONDecoder().decode(GeneratedEventInvitation.self, from: data)
        #expect(invitation.email == nil)
        #expect(invitation.isValid(for: eventID, baseURL: URL(string: "https://dev.gatherory.com")!))
    }
    @Test("Invitation links require the matching event, configured host, and a real server token")
    @MainActor
    func invitationLinkValidation() throws {
        let eventID = UUID()
        let token = UUID()
        let base = try #require(URL(string: "https://dev.gatherory.com"))
        func invitation(_ url: String, event: UUID? = nil) throws -> GeneratedEventInvitation {
            GeneratedEventInvitation(eventId: event ?? eventID, email: "guest@example.com", expiresAt: "2026-10-26T00:00:00Z", url: try #require(URL(string: url)))
        }
        #expect(try invitation("https://dev.gatherory.com/join/\(token)").isValid(for: eventID, baseURL: base))
        #expect(try !invitation("https://app.gatherory.com/join/\(token)").isValid(for: eventID, baseURL: base))
        #expect(try !invitation("https://dev.gatherory.com/join/planning-circle").isValid(for: eventID, baseURL: base))
        #expect(try !invitation("https://dev.gatherory.com/join/\(token)", event: UUID()).isValid(for: eventID, baseURL: base))
        #expect(try !invitation("https://dev.gatherory.com/join/\(token)?next=evil").isValid(for: eventID, baseURL: base))
    }

    @Test("Share compose URLs preserve event titles containing query delimiters")
    @MainActor
    func invitationComposeEscaping() throws {
        let link = try #require(URL(string: "https://app.gatherory.com/join/\(UUID())"))
        let title = "Alex & Jordan's Wedding? #1"
        for scheme in ["sms", "mailto"] {
            let url = try #require(EventInvitationClient.messageURL(scheme: scheme, title: title, invitationURL: link))
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            #expect(components.queryItems?.first(where: { $0.name == "body" })?.value == "\(title): \(link.absoluteString)")
            #expect(components.queryItems?.count == (scheme == "mailto" ? 2 : 1))
            #expect(components.fragment == nil)
        }
    }
}
