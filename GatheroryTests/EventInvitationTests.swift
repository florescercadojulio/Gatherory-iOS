import Foundation
import Testing
@testable import Gatherory

struct EventInvitationTests {
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
