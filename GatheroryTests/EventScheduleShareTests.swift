import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventScheduleShareTests {
    private let accountID = "schedule-host"
    private let locale = Locale(identifier: "en_US")

    @Test("Only active exact-event hosts and managers can share a schedule")
    func rolesAndInvitationStatus() {
        for role in [WorkspaceRole.host, .collaborator, .guest] {
            for permission in [PlanningPermission.manage, .contribute, .viewOnly] {
                for status in [CollaborationInvitationStatus.active, .invited] {
                    let workspace = fixture(role: role, permission: permission, invitationStatus: status)
                    let permitted = status == .active
                        && (role == .host || (role == .collaborator && permission == .manage))
                    #expect(EventScheduleShare.canShare(workspace: workspace, reference: .main, accountID: accountID) == permitted)
                    #expect((snapshot(workspace) != nil) == permitted)
                }
            }
        }
    }

    @Test("Account identity must match the configured viewer without email or preview fallbacks")
    func principalIsolation() {
        let workspace = fixture()
        #expect(snapshot(workspace) != nil)
        #expect(EventScheduleShare.makeSnapshot(workspace: workspace, reference: .main, accountID: nil) == nil)
        #expect(EventScheduleShare.makeSnapshot(workspace: workspace, reference: .main, accountID: "") == nil)
        #expect(EventScheduleShare.makeSnapshot(workspace: workspace, reference: .main, accountID: "another-account") == nil)
        workspace.configureViewer(account("other-account")) // Same email intentionally resolves to the host in older helpers.
        #expect(workspace.currentViewerMember?.userID == accountID)
        #expect(snapshot(workspace) == nil)
        #expect(EventScheduleShare.makeSnapshot(workspace: workspace, reference: .main, accountID: "other-account") == nil)
        workspace.configureViewer(nil)
        #expect(snapshot(workspace) == nil)
        let unconfigured = fixture(configure: false)
        #expect(unconfigured.currentViewerMember?.userID == accountID)
        #expect(snapshot(unconfigured) == nil)
    }

    @Test("Device guests and invitation projections cannot export planning schedules")
    func guestAndProjectionIsolation() {
        let workspace = fixture()
        workspace.isInvitationProjection = true
        #expect(snapshot(workspace) == nil)
        workspace.isInvitationProjection = false
        let profile = LocalGuestProfile(displayName: "Local host")
        workspace.members[0].userID = profile.storageID
        workspace.configureLocalGuestViewer(profile)
        #expect(EventScheduleShare.makeSnapshot(workspace: workspace, reference: .main, accountID: profile.storageID) == nil)
    }

    @Test("Root export includes only approved scheduled public children with exact-event management")
    func rootScheduleWhitelistAndOrdering() throws {
        let includedLate = child("Included later", date: date("2032-11-07T18:00:00Z"))
        let includedEarly = child("Included earlier", date: date("2032-11-07T14:00:00Z"))
        var planning = child("Secret scouting")
        planning.purpose = .planning
        var draft = child("Secret draft")
        draft.status = .draft
        var unsure = child("Secret undecided")
        unsure.status = .notSure
        var rejected = child("Secret rejected")
        rejected.status = .rejected
        var archived = child("Secret archived")
        archived.status = .archived
        var cancelled = child("Secret cancelled")
        cancelled.status = .cancelled
        var complete = child("Secret complete")
        complete.completionStatus = .complete
        var unscheduled = child("Secret undated")
        unscheduled.schedulingState = .unscheduled
        let guestChild = child("Secret child guest")
        let contributorChild = child("Secret child contributor")
        let noMembershipChild = child("Secret unrelated roster")
        let events = [includedLate, planning, guestChild, draft, unsure, rejected, archived,
                      cancelled, complete, unscheduled, contributorChild, noMembershipChild, includedEarly]
        let workspace = fixture(children: events, childRoleOverrides: [
            guestChild.id: (.guest, .manage), contributorChild.id: (.collaborator, .contribute),
        ], omittedChildMemberships: [noMembershipChild.id])
        let text = try #require(snapshot(workspace)?.csv)
        #expect(text.contains("Root celebration"))
        #expect(text.contains("Included later"))
        #expect(text.contains("Included earlier"))
        #expect(!text.contains("Secret"))
        let earlierRange = try #require(text.range(of: "Included earlier"))
        let laterRange = try #require(text.range(of: "Included later"))
        #expect(earlierRange.lowerBound < laterRange.lowerBound)
    }

    @Test("A selected child excludes parent siblings and ideas even when Home changes")
    func selectedChildScope() throws {
        let selected = child("Selected dinner")
        let sibling = child("Secret sibling")
        let workspace = fixture(children: [selected, sibling])
        workspace.selectedEventReference = .subevent(sibling.id)
        let text = try #require(snapshot(workspace, .subevent(selected.id))?.csv)
        #expect(text.contains("Selected dinner"))
        #expect(!text.contains("Root celebration"))
        #expect(!text.contains("Secret sibling"))
        #expect(snapshot(workspace, .idea(UUID())) == nil)
        #expect(snapshot(workspace, .subevent(UUID())) == nil)
        workspace.timeline[0].parentEventID = UUID()
        #expect(snapshot(workspace, .subevent(selected.id)) == nil)
    }

    @Test("Scoped projections export their own genuine event fields and no cached descendants")
    func scopedProjectionScope() throws {
        let workspace = fixture(children: [child("Secret parent child")])
        workspace.isScopedEvent = true
        let genuine = child("Scoped ceremony", id: workspace.mainEventID)
        workspace.scopedMainEventDetails = genuine
        let text = try #require(snapshot(workspace)?.csv)
        #expect(text.contains("Scoped ceremony"))
        #expect(!text.contains("Root celebration"))
        #expect(!text.contains("Secret parent child"))
        #expect(snapshot(workspace, .subevent(workspace.timeline[0].id)) == nil)
        // A mismatched scope is rejected, never reinterpreted as the root.
        workspace.scopedMainEventDetails = child("Wrong scope")
        #expect(snapshot(workspace) == nil)
        workspace.scopedMainEventDetails = genuine
        workspace.scopedMainEventDetails?.purpose = .planning
        #expect(snapshot(workspace) == nil)
        workspace.scopedMainEventDetails = nil
        #expect(snapshot(workspace) == nil)
    }

    @Test("Undated approved child schedules never expose their placeholder date")
    func unscheduledAndSpanishCopy() throws {
        var event = child("Dinner por confirmar", date: date("2099-01-01T00:00:00Z"))
        event.schedulingState = .unscheduled
        let workspace = fixture(children: [event])
        let english = try #require(snapshot(workspace, .subevent(event.id)))
        let englishRows = try parseCSV(english.csv)
        #expect(englishRows[0] == ["Event", "Start", "End", "All Day", "Time Zone", "Location"])
        #expect(englishRows[1][1] == "")
        #expect(englishRows[1][2] == "")
        #expect(englishRows[1][4] == "America/Detroit")
        #expect(!english.csv.contains("2099"))
        let spanish = try #require(EventScheduleShare.makeSnapshot(
            workspace: workspace, reference: .subevent(event.id), accountID: accountID,
            locale: Locale(identifier: "es_ES")
        ))
        let spanishRows = try parseCSV(spanish.csv)
        #expect(spanishRows[0] == ["Evento", "Inicio", "Fin", "Todo el día", "Zona horaria", "Lugar"])
        #expect(spanishRows[1] == englishRows[1])
        #expect(spanish.fileName == "Event Schedule.csv")
        #expect(Array(spanish.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(data: spanish.data.dropFirst(3), encoding: .utf8) == spanish.csv)
    }

    @Test("ISO timestamps preserve the event zone and both DST offsets without inventing an end")
    func timeZonesAndDST() throws {
        var event = child("Autumn breakfast", date: date("2032-11-07T05:30:00Z"))
        event.endsAt = date("2032-11-07T06:30:00Z")
        let workspace = fixture(children: [event])
        var row = try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1]
        #expect(row[1] == "2032-11-07T01:30:00-04:00")
        #expect(row[2] == "2032-11-07T01:30:00-05:00")
        #expect(row[3] == "FALSE")
        #expect(row[4] == "America/Detroit")
        workspace.timeline[0].endsAt = event.scheduledAt.addingTimeInterval(-3600)
        row = try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1]
        #expect(row[2] == "")
        workspace.timeline[0].endsAt = event.scheduledAt
        #expect(try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1][2] == "")
        workspace.timeline[0].endsAt = nil
        workspace.timeline[0].timeZoneIdentifier = "Asia/Tokyo"
        row = try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1]
        #expect(row[1] == "2032-11-07T14:30:00+09:00")
        #expect(row[2] == "")
        #expect(row[4] == "Asia/Tokyo")
    }

    @Test("All-day CSV ranges use inclusive local ISO dates without fabricated times")
    func allDayInclusiveRange() throws {
        var event = child("Weekend", date: date("2032-03-13T05:00:00Z"))
        event.endsAt = date("2032-03-15T04:00:00Z")
        event.isAllDay = true
        let workspace = fixture(children: [event])
        var row = try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1]
        #expect(row[1] == "2032-03-13")
        #expect(row[2] == "2032-03-15")
        #expect(row[3] == "TRUE")
        #expect(row[4] == "America/Detroit")
        workspace.timeline[0].endsAt = event.scheduledAt.addingTimeInterval(3600)
        row = try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1]
        #expect(row[2] == "2032-03-13")
        workspace.timeline[0].endsAt = nil
        #expect(try parseCSV(#require(snapshot(workspace, .subevent(event.id))).csv)[1][2] == "")
    }

    @Test("CSV round-trips Unicode commas quotes and embedded line breaks as exactly six columns")
    func csvEscapingAndEncoding() throws {
        let title = "José, \"Weekend\" 🌿\r\nSecond line\nThird line"
        var event = child(title)
        event.eventLocation = EventLocation(address: "12 Oak, \"East\"\r\nDetroit")
        let workspace = fixture(children: [event])
        let exported = try #require(snapshot(workspace, .subevent(event.id)))
        let rows = try parseCSV(exported.csv)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.count == 6 })
        #expect(rows[1][0] == title)
        #expect(rows[1][5] == "12 Oak, \"East\"\r\nDetroit")
        #expect(exported.csv.contains("\"\"Weekend\"\""))
        #expect(exported.csv.hasSuffix("\r\n"))
        #expect(String(data: exported.data.dropFirst(3), encoding: .utf8) == exported.csv)
    }

    @Test("Spreadsheet formulas are inert even behind whitespace controls or injected CSV delimiters")
    func spreadsheetFormulaProtection() throws {
        let workspace = fixture()
        for dangerous in ["=1+1", "+SUM(1,2)", "-1+1", "@SUM(1,2)", " \t=1+1",
                          "\r\n+1", "\u{0000}\t@SUM(1,2)", "\u{FEFF}=1+1"] {
            workspace.title = dangerous
            let rows = try parseCSV(#require(snapshot(workspace)).csv)
            #expect(rows.count == 2)
            #expect(rows[1].count == 6)
            #expect(rows[1][0] == "'" + dangerous)
        }
        for safe in ["José's dinner", "A-B", "123", "\",=1+1\r\nInjected", "  Ordinary title"] {
            workspace.title = safe
            #expect(try parseCSV(#require(snapshot(workspace)).csv)[1][0] == safe)
        }
        workspace.mainEventLocation = EventLocation(address: "=HYPERLINK(\"https://example.test\")")
        #expect(try parseCSV(#require(snapshot(workspace)).csv)[1][5].hasPrefix("'="))
    }

    @Test("Only public schedule fields leave the workspace and snapshots remain frozen")
    func nonDisclosureAndImmutableCopy() throws {
        var event = child("Public dinner")
        event.eventDescription = "SECRET DESCRIPTION"
        event.dressCode = "SECRET ATTIRE"
        event.budgetCap = 987654
        event.eventLocation = EventLocation(address: "123 Public Street", shortAddress: "Public Street",
            placeName: "Public venue", addressLine2: "Public suite",
            latitude: 42.987654, longitude: -83.123456, mapItemIdentifier: "SECRET MAP ID")
        let workspace = fixture(children: [event])
        workspace.eventMessage = "SECRET ANNOUNCEMENT"
        workspace.dressCode = "SECRET ROOT ATTIRE"
        workspace.notes = [EventNote(authorUserID: "SECRET AUTHOR", body: "SECRET NOTE")]
        workspace.todos = [EventTodo(eventID: workspace.mainEventID, title: "SECRET TASK")]
        let exported = try #require(snapshot(workspace))
        for field in ["Public dinner", "Public venue", "123 Public Street", "Public suite"] {
            #expect(exported.csv.contains(field))
        }
        for forbidden in ["SECRET", "987654", "42.987654", "-83.123456", accountID,
                          "host@example.test", "Private host", event.id.uuidString,
                          workspace.mainEventID.uuidString] {
            #expect(!exported.csv.contains(forbidden))
        }
        workspace.timeline[0].title = "Updated dinner"
        #expect(exported.csv.contains("Public dinner"))
        #expect(!exported.csv.contains("Updated dinner"))
        #expect(try #require(snapshot(workspace)?.csv).contains("Updated dinner"))
        workspace.configureViewer(account("other-account"))
        #expect(snapshot(workspace) == nil)
    }

    @Test("Lifecycle and permission changes revoke the next export")
    func revalidation() {
        for status in [MainEventStatus.finished, .cancelled] {
            let workspace = fixture()
            workspace.mainEventStatus = status
            #expect(snapshot(workspace) == nil)
        }
        let workspace = fixture(role: .collaborator, permission: .manage)
        workspace.isMainEventDeleted = true
        #expect(snapshot(workspace) == nil)
        workspace.isMainEventDeleted = false
        #expect(workspace.updateParticipant(workspace.members[0].id, role: .collaborator,
                                            planningPermission: .viewOnly, in: .main))
        #expect(snapshot(workspace) == nil)
    }

    private func snapshot(_ workspace: PlanningWorkspace, _ reference: EventReference = .main) -> EventScheduleShareSnapshot? {
        EventScheduleShare.makeSnapshot(workspace: workspace, reference: reference, accountID: accountID, locale: locale)
    }

    private enum CSVParseFailure: Error { case malformed }

    /// Independent byte parser: validates quoting and CRLF row boundaries while
    /// preserving embedded Unicode, commas, quotes, and literal line breaks.
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
        configure: Bool = true, children: [TimelineItem] = [],
        childRoleOverrides: [UUID: (WorkspaceRole, PlanningPermission)] = [:],
        omittedChildMemberships: Set<UUID> = []
    ) -> PlanningWorkspace {
        let host = WorkspaceMember(userID: accountID, name: "Private host", participantRole: role,
                                   initials: "PH", email: "host@example.test", planningPermission: permission,
                                   invitationStatus: invitationStatus)
        let rootID = UUID()
        let children = children.map { event in
            var event = event
            event.participantIDs = omittedChildMemberships.contains(event.id) ? [] : [host.id]
            return event
        }
        let rootParticipation = EventParticipation(eventID: rootID, memberID: host.id, role: role,
            planningPermission: permission, attendance: .going, invitationStatus: invitationStatus)
        let childParticipations = children.filter { !omittedChildMemberships.contains($0.id) }.map { event in
            let (childRole, childPermission) = childRoleOverrides[event.id] ?? (.host, .manage)
            return EventParticipation(eventID: event.id, memberID: host.id, role: childRole,
                planningPermission: childPermission, attendance: .going, invitationStatus: .active)
        }
        let workspace = PlanningWorkspace(mainEventID: rootID, title: "Root celebration",
            mainEventStartsAt: date("2032-11-07T12:00:00Z"), mainEventTimeZoneIdentifier: "America/Detroit",
            venueName: "Root venue", location: "Root address", planningMode: .openToIdeas,
            members: [host], eventParticipations: [rootParticipation] + childParticipations,
            ideas: [], timeline: children, registry: [])
        if configure { workspace.configureViewer(account(accountID)) }
        return workspace
    }

    private func child(_ title: String, id: UUID = UUID(), date: Date? = nil) -> TimelineItem {
        TimelineItem(id: id, title: title, category: .other, purpose: .eventExperience,
                     scheduledAt: date ?? self.date("2032-11-07T15:00:00Z"),
                     location: "Public location", timeZoneIdentifier: "America/Detroit", participantIDs: [])
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "host@example.test", displayName: "Private host", role: .member,
                    authenticationProvider: .password, createdAt: .now)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
