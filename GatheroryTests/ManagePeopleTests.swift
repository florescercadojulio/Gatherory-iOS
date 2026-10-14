import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ManagePeopleTests {
    @Test("RSVP bar counts all attendance states independently of planning roles")
    func attendanceSummary() {
        let participants = [
            WorkspaceMember(name: "Host", participantRole: .host, initials: "H", attendance: .invited),
            WorkspaceMember(name: "Planner", participantRole: .collaborator, initials: "P", attendance: .going),
            WorkspaceMember(name: "Guest", participantRole: .guest, initials: "G", attendance: .maybe),
            WorkspaceMember(name: "Declined", participantRole: .guest, initials: "D", attendance: .declined),
            WorkspaceMember(name: "Going", participantRole: .guest, initials: "G", attendance: .going)
        ]
        let summary = ManageAttendanceSummary(participants: participants)
        #expect(summary.going == 2)
        #expect(summary.maybe == 1)
        #expect(summary.declined == 1)
        #expect(summary.awaiting == 1)
        #expect(summary.total == participants.count)
        #expect(ManageAttendanceSummary(participants: []).total == 0)
    }

    @Test("Guest List includes every attendee while Collaborators excludes guests")
    func sectionFilters() {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H", attendance: .going)
        let planner = WorkspaceMember(name: "Planner", participantRole: .collaborator, initials: "P", attendance: .maybe)
        let guest = WorkspaceMember(name: "Guest", participantRole: .guest, initials: "G", attendance: .invited)
        let participants = [host, planner, guest]

        #expect(EventPeopleSection.guests.people(from: participants).map(\.id) == [host.id, planner.id, guest.id])
        #expect(EventPeopleSection.collaborators.people(from: participants).map(\.id) == [host.id, planner.id])
        #expect(EventPeopleSection.guests.people(from: participants).map(\.attendance) == [.going, .maybe, .invited])
    }

    @Test("Pinned event permissions and participant edits stay scoped when another event is selected")
    func exactEventPermissionsAndEdits() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let manager = WorkspaceMember(name: "Manager", participantRole: .collaborator, initials: "M")
        let attendee = WorkspaceMember(name: "Attendee", participantRole: .guest, initials: "A")
        let mainEventID = UUID()
        let dinner = TimelineItem(title: "Dinner", category: .other, scheduledAt: .now,
                                  location: "", participantIDs: [manager.id, attendee.id])
        let brunch = TimelineItem(title: "Brunch", category: .other, scheduledAt: .now,
                                  location: "", participantIDs: [manager.id, attendee.id])
        let participations = [
            EventParticipation(eventID: mainEventID, memberID: host.id, role: .host,
                               planningPermission: .manage, attendance: .going, invitationStatus: .active),
            EventParticipation(eventID: mainEventID, memberID: manager.id, role: .collaborator,
                               planningPermission: .contribute, attendance: .going, invitationStatus: .active),
            EventParticipation(eventID: dinner.id, memberID: manager.id, role: .collaborator,
                               planningPermission: .manage, attendance: .invited, invitationStatus: .active),
            EventParticipation(eventID: dinner.id, memberID: attendee.id, role: .guest,
                               planningPermission: .viewOnly, attendance: .maybe, invitationStatus: .active),
            EventParticipation(eventID: brunch.id, memberID: manager.id, role: .guest,
                               planningPermission: .viewOnly, attendance: .going, invitationStatus: .active),
            EventParticipation(eventID: brunch.id, memberID: attendee.id, role: .guest,
                               planningPermission: .viewOnly, attendance: .invited, invitationStatus: .active)
        ]
        let workspace = PlanningWorkspace(
            mainEventID: mainEventID, title: "Weekend", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [manager, host, attendee], eventParticipations: participations,
            ideas: [], timeline: [dinner, brunch], registry: []
        )
        workspace.selectedEventReference = .subevent(brunch.id)

        let dinnerReference = EventReference.subevent(dinner.id)
        let brunchReference = EventReference.subevent(brunch.id)
        #expect(workspace.canManageInvitations(for: dinnerReference))
        #expect(!workspace.canManageInvitations(for: brunchReference))
        #expect(workspace.updateParticipant(attendee.id, role: .collaborator,
                                            planningPermission: .contribute, in: dinnerReference))
        #expect(workspace.participants(for: dinnerReference).first { $0.id == attendee.id }?.participantRole == .collaborator)
        #expect(workspace.participants(for: brunchReference).first { $0.id == attendee.id }?.participantRole == .guest)
    }
}
