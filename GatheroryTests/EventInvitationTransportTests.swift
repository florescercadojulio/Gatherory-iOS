import Foundation
import Testing
@testable import Gatherory

struct EventInvitationTransportTests {
    @Test("The account-linked participant emitted by the server decodes in iOS")
    @MainActor
    func acceptedParticipantDecodes() throws {
        let personID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": personID.uuidString.lowercased(), "userID": "better-auth-user",
            "name": "New Collaborator", "email": "collaborator@example.com",
            "initials": "NC", "participantRole": "collaborator",
            "planningPermission": "manage", "attendance": "invited",
            "invitationStatus": "active", "profileImageURL": "https://example.com/avatar.jpg"
        ])
        let member = try JSONDecoder().decode(WorkspaceMember.self, from: data)
        #expect(member.id == personID)
        #expect(member.userID == "better-auth-user")
        #expect(member.invitationStatus == .active)
        #expect(member.planningPermission == .manage)
        #expect(member.profileImageURL?.absoluteString == "https://example.com/avatar.jpg")
    }
}
