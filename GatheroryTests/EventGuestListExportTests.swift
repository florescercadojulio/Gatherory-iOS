import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventGuestListExportTests {
    private let accountID = "guest-export-manager"
    private let locale = Locale(identifier: "en_US")

    @Test("Guest lists require an active exact-event host or manager")
    func authorizationRoles() {
        for role in [WorkspaceRole.host, .collaborator, .guest] {
            for permission in [PlanningPermission.manage, .contribute, .viewOnly] {
                for status in [CollaborationInvitationStatus.active, .invited] {
                    let workspace = fixture(role: role, permission: permission, invitationStatus: status)
                    let allowed = status == .active
                        && (role == .host || (role == .collaborator && permission == .manage))
                    #expect(EventGuestListExport.canExport(workspace: workspace, reference: .main, accountID: accountID) == allowed)
                    #expect((snapshot(workspace) != nil) == allowed)
                }
            }
        }
        for role in [WorkspaceRole.guest, .collaborator] {
            let event = child("Restricted child")
            let workspace = fixture(children: [event], childViewerRole: role, childViewerPermission: .contribute)
            #expect(snapshot(workspace) != nil)
            #expect(snapshot(workspace, .subevent(event.id)) == nil)
        }
        let event = child("Managed child")
        let workspace = fixture(children: [event], childViewerRole: .collaborator, childViewerPermission: .manage)
        #expect(snapshot(workspace, .subevent(event.id)) != nil)
    }

    @Test("Real account identity cannot be replaced by email preview guest or invitation context")
    func accountAndGuestIsolation() {
        let workspace = fixture()
        for principal in [nil, "", "other-account"] as [String?] {
            #expect(EventGuestListExport.makeSnapshot(workspace: workspace, reference: .main, accountID: principal) == nil)
        }
        workspace.configureViewer(account("other-account"))
        #expect(workspace.currentViewerMember?.userID == accountID) // Existing email fallback still resolves.
        #expect(snapshot(workspace) == nil)
        #expect(EventGuestListExport.makeSnapshot(workspace: workspace, reference: .main, accountID: "other-account") == nil)
        workspace.configureViewer(nil)
        #expect(snapshot(workspace) == nil)
        #expect(snapshot(fixture(configure: false)) == nil)

        workspace.configureViewer(account(accountID))
        workspace.isInvitationProjection = true
        #expect(snapshot(workspace) == nil)
        workspace.isInvitationProjection = false
        let guest = LocalGuestProfile(displayName: "Device host")
        workspace.members[0].userID = guest.storageID
        workspace.configureLocalGuestViewer(guest)
        #expect(EventGuestListExport.makeSnapshot(workspace: workspace, reference: .main, accountID: guest.storageID) == nil)
    }

    @Test("An explicit event exports its own roster and contextual RSVP without changing Home or planning state")
    func explicitScopeAndContextualAttendance() throws {
        let rootGuest = person("Root only", attendance: .invited)
        let childGuest = person("Child only", attendance: .maybe)
        let siblingGuest = person("Sibling only", attendance: .declined)
        let shared = person("Shared person", attendance: .going)
        let unrelated = person("Unrelated workspace person", attendance: .going)
        let event = child("Selected child", people: [childGuest.id, shared.id])
        let sibling = child("Sibling", people: [siblingGuest.id])
        let workspace = fixture(people: [rootGuest, childGuest, siblingGuest, shared, unrelated],
            rootPeople: [rootGuest.id, shared.id], children: [event, sibling],
            extraParticipations: [EventParticipation(eventID: event.id, memberID: shared.id,
                role: .guest, planningPermission: .viewOnly, attendance: .declined, invitationStatus: .active)])
        workspace.selectedEventReference = .subevent(sibling.id)
        let beforePeople = workspace.members
        let beforeRelationships = workspace.eventParticipations
        let beforeSelection = workspace.selectedEventReference
        let rootRows = try rows(workspace)
        #expect(rootRows.map { $0[0] } == ["Name", "Manager", "Root only", "Shared person"])
        #expect(rootRows.last == ["Shared person", "Going"])
        let childRows = try rows(workspace, .subevent(event.id))
        #expect(childRows.map { $0[0] } == ["Name", "Manager", "Child only", "Shared person"])
        #expect(childRows.last == ["Shared person", "Can't go"])
        #expect(!childRows.flatMap { $0 }.contains("Root only"))
        #expect(!childRows.flatMap { $0 }.contains("Sibling only"))
        #expect(!rootRows.flatMap { $0 }.contains("Unrelated workspace person"))
        #expect(workspace.members == beforePeople)
        #expect(workspace.eventParticipations == beforeRelationships)
        #expect(workspace.selectedEventReference == beforeSelection)
        #expect(snapshot(workspace, .idea(UUID())) == nil)
        #expect(snapshot(workspace, .subevent(UUID())) == nil)
    }

    @Test("Guest List includes every attendee role and RSVP state while retaining duplicate names")
    func allAttendeesAndStatuses() throws {
        let people = [
            person("Host attendee", role: .host, attendance: .going),
            person("Collaborator attendee", role: .collaborator, attendance: .maybe),
            person("Duplicate", attendance: .declined),
            person("Duplicate", attendance: .invited, invitationStatus: .invited),
        ]
        let workspace = fixture(people: people)
        let exportedRows = try rows(workspace)
        #expect(exportedRows.count == people.count + 2)
        #expect(exportedRows.suffix(4) == [
            ["Host attendee", "Going"], ["Collaborator attendee", "Maybe"],
            ["Duplicate", "Can't go"], ["Duplicate", "Invited"],
        ])
    }

    @Test("Scoped event exports require the genuine scope and never acquire parent or sibling rosters")
    func scopedProjectionAndChildValidation() throws {
        let other = person("Other event attendee")
        let event = child("Cached sibling", people: [other.id])
        let workspace = fixture(people: [other], rootPeople: [], children: [event])
        workspace.isScopedEvent = true
        workspace.scopedMainEventDetails = child("Scope", id: workspace.mainEventID)
        #expect(try rows(workspace) == [["Name", "RSVP Status"], ["Manager", "Going"]])
        #expect(snapshot(workspace, .subevent(event.id)) == nil)
        workspace.scopedMainEventDetails = child("Wrong scope")
        #expect(snapshot(workspace) == nil)
        workspace.scopedMainEventDetails = nil
        #expect(snapshot(workspace) == nil)

        let root = fixture(children: [event])
        root.timeline[0].parentEventID = UUID()
        #expect(snapshot(root, .subevent(event.id)) == nil)
    }

    @Test("Only names and RSVP leave the model and missing names never fall back to email")
    func privacyAndNameFallbacks() throws {
        var blank = person(" \n\t ", email: "blank-secret@example.test")
        blank.profileImageURL = URL(string: "https://example.test/SECRET-AVATAR")
        let emailName = person("  EMAIL-SECRET@EXAMPLE.TEST  ", email: "email-secret@example.test")
        let named = person("Display name", email: "named-secret@example.test")
        let workspace = fixture(people: [blank, emailName, named])
        workspace.eventMessage = "SECRET EVENT MESSAGE"
        workspace.notes = [EventNote(authorUserID: "SECRET AUTHOR", body: "SECRET NOTE")]
        workspace.todos = [EventTodo(eventID: workspace.mainEventID, title: "SECRET TASK")]
        let exported = try #require(snapshot(workspace))
        let exportedRows = try parseCSV(exported.csv)
        #expect(exportedRows[0] == ["Name", "RSVP Status"])
        #expect(exportedRows.map { $0.count }.allSatisfy { $0 == 2 })
        #expect(exportedRows.suffix(3).map { $0[0] } == ["Unnamed Guest", "Unnamed Guest", "Display name"])
        for forbidden in ["SECRET", "@example.test", "@EXAMPLE.TEST", "https://", accountID,
                          workspace.mainEventID.uuidString, blank.id.uuidString, "host", "collaborator", "guest"] {
            #expect(!exported.csv.contains(forbidden))
        }
        #expect(exported.fileName == "Guest List.csv")
        #expect(Array(exported.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(data: exported.data.dropFirst(3), encoding: .utf8) == exported.csv)
    }

    @Test("Spanish headers RSVP and unnamed people resolve from explicit locale resources")
    func spanishLocalization() throws {
        let people = [person("Asiste", attendance: .going), person("Quizás", attendance: .maybe),
                      person("No asiste", attendance: .declined), person("", attendance: .invited)]
        let workspace = fixture(people: people)
        let exported = try #require(EventGuestListExport.makeSnapshot(workspace: workspace, reference: .main,
            accountID: accountID, locale: Locale(identifier: "es_ES")))
        let exportedRows = try parseCSV(exported.csv)
        #expect(exportedRows[0] == ["Nombre", "Estado de confirmación"])
        #expect(exportedRows.suffix(4) == [["Asiste", "Asistirá"], ["Quizás", "Quizá"],
                                         ["No asiste", "No puede asistir"], ["Invitado sin nombre", "Invitado"]])
    }

    @Test("Names round-trip Unicode and CSV punctuation while spreadsheet formulas stay inert")
    func csvRoundTripAndFormulaSafety() throws {
        let names = ["José, \"Invitado\" 🌿\r\nSecond line\nThird", "=1+1", "+SUM(1,2)", "-1+1", "@SUM(1,2)",
                     " \t=1+1", "\r\n+1", "\u{0000}\t@SUM(1,2)", "\u{FEFF}=1+1", "\",=1+1\r\nInjected"]
        let workspace = fixture(people: names.map { person($0) })
        let exported = try #require(snapshot(workspace))
        let exportedRows = try parseCSV(exported.csv)
        #expect(exportedRows.count == names.count + 2)
        #expect(exportedRows.allSatisfy { $0.count == 2 })
        #expect(exportedRows[2][0] == names[0])
        for index in 1...8 {
            #expect(exportedRows[index + 2][0] == "'" + names[index])
        }
        #expect(exportedRows.last?[0] == names.last)
        #expect(exported.csv.hasSuffix("\r\n"))
    }

    @Test("Snapshots are frozen but new exports revalidate principal permission and lifecycle")
    func revalidation() throws {
        let attendee = person("Original attendee", attendance: .maybe)
        let event = child("Child", people: [attendee.id])
        let workspace = fixture(role: .collaborator, permission: .manage, people: [attendee], children: [event])
        let exported = try #require(snapshot(workspace))
        workspace.members[1].name = "Updated attendee"
        #expect(exported.csv.contains("Original attendee"))
        #expect(!exported.csv.contains("Updated attendee"))
        #expect(try #require(snapshot(workspace)).csv.contains("Updated attendee"))
        #expect(workspace.updateParticipant(workspace.members[0].id, role: .collaborator,
                                            planningPermission: .viewOnly, in: .main))
        #expect(snapshot(workspace) == nil)
        for status in [MainEventStatus.finished, .cancelled] {
            let closed = fixture()
            closed.mainEventStatus = status
            #expect(snapshot(closed) == nil)
        }
        let deleted = fixture()
        deleted.isMainEventDeleted = true
        #expect(snapshot(deleted) == nil)
        for status in [EventStatus.archived, .cancelled] {
            workspace.timeline[0].status = status
            #expect(snapshot(workspace, .subevent(event.id)) == nil)
        }
        workspace.configureViewer(account("other-account"))
        #expect(snapshot(workspace) == nil)
    }

    private func snapshot(_ workspace: PlanningWorkspace, _ reference: EventReference = .main) -> EventGuestListExportSnapshot? {
        EventGuestListExport.makeSnapshot(workspace: workspace, reference: reference, accountID: accountID, locale: locale)
    }

    private func rows(_ workspace: PlanningWorkspace, _ reference: EventReference = .main) throws -> [[String]] {
        try parseCSV(#require(snapshot(workspace, reference)).csv)
    }

    private enum CSVParseFailure: Error { case malformed }

    private func parseCSV(_ csv: String) throws -> [[String]] {
        let bytes = Array(csv.utf8)
        var offset = 0
        var rows: [[String]] = []
        var row: [String] = []
        while offset < bytes.count {
            guard bytes[offset] == 34 else { throw CSVParseFailure.malformed }
            offset += 1
            var cell: [UInt8] = []
            var closed = false
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == 34 {
                    if offset < bytes.count, bytes[offset] == 34 {
                        cell.append(34)
                        offset += 1
                    } else {
                        closed = true
                        break
                    }
                } else {
                    cell.append(byte)
                }
            }
            guard closed, let value = String(bytes: cell, encoding: .utf8), offset < bytes.count else {
                throw CSVParseFailure.malformed
            }
            row.append(value)
            if bytes[offset] == 44 {
                offset += 1
            } else if bytes[offset] == 13, offset + 1 < bytes.count, bytes[offset + 1] == 10 {
                rows.append(row)
                row = []
                offset += 2
            } else {
                throw CSVParseFailure.malformed
            }
        }
        guard row.isEmpty else { throw CSVParseFailure.malformed }
        return rows
    }

    private func fixture(
        role: WorkspaceRole = .host, permission: PlanningPermission = .manage,
        invitationStatus: CollaborationInvitationStatus = .active,
        configure: Bool = true, people: [WorkspaceMember] = [], rootPeople: [UUID]? = nil,
        children: [TimelineItem] = [], childViewerRole: WorkspaceRole = .host,
        childViewerPermission: PlanningPermission = .manage,
        extraParticipations: [EventParticipation] = []
    ) -> PlanningWorkspace {
        let manager = person("Manager", role: role, email: "manager-secret@example.test",
                             invitationStatus: invitationStatus, userID: accountID, permission: permission)
        let rootID = UUID()
        let children = children.map { event in
            var event = event
            event.participantIDs = [manager.id] + event.participantIDs
            return event
        }
        let childViewerParticipations = children.map { event in
            EventParticipation(eventID: event.id, memberID: manager.id, role: childViewerRole,
                               planningPermission: childViewerPermission, attendance: .going, invitationStatus: .active)
        }
        let workspace = PlanningWorkspace(mainEventID: rootID, title: "SECRET event title",
            mainEventStartsAt: Date(timeIntervalSince1970: 2_000_000_000),
            venueName: "SECRET venue", location: "SECRET address", planningMode: .openToIdeas,
            members: [manager] + people, eventParticipations: childViewerParticipations + extraParticipations,
            mainEventParticipantIDs: [manager.id] + (rootPeople ?? people.map(\.id)),
            ideas: [], timeline: children, registry: [])
        if configure { workspace.configureViewer(account(accountID)) }
        return workspace
    }

    private func person(
        _ name: String, role: WorkspaceRole = .guest, attendance: AttendanceStatus = .going,
        email: String? = nil, invitationStatus: CollaborationInvitationStatus = .active,
        userID: String? = nil, permission: PlanningPermission = .viewOnly
    ) -> WorkspaceMember {
        WorkspaceMember(userID: userID, name: name, participantRole: role, initials: "P", attendance: attendance,
                        email: email, planningPermission: permission, invitationStatus: invitationStatus)
    }

    private func child(_ title: String, id: UUID = UUID(), people: [UUID] = []) -> TimelineItem {
        TimelineItem(id: id, title: title, category: .other, purpose: .eventExperience,
                     scheduledAt: Date(timeIntervalSince1970: 2_000_000_000), location: "SECRET child location",
                     participantIDs: people)
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "manager-secret@example.test", displayName: "Manager", role: .member,
                    authenticationProvider: .password, createdAt: .now)
    }
}
