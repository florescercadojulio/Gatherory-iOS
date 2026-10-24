import Foundation
import Testing
@testable import Gatherory

@MainActor
struct MainInvitationEditingTests {
    @Test("Title, date, and location commands mutate only the focused main event field")
    func commandsPreserveCurrentUnrelatedEventData() {
        let member = manager()
        let workspace = makeWorkspace(member: member)
        let eventID = workspace.mainEventID
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        let existingLocation = EventLocation(address: "10 Museum Way", locationName: "Museum", addressLine2: "East entrance")
        workspace.mainEventStartsAt = start
        workspace.mainEventEndsAt = end
        workspace.mainEventIsAllDay = true
        workspace.mainEventTimeZoneIdentifier = "America/Detroit"
        workspace.mainEventLocation = existingLocation
        workspace.mainEventImageData = Data([1, 2, 3])
        workspace.dressCode = "Garden formal"
        workspace.eventMessage = "Welcome note"
        workspace.mainEventStatus = .ongoing

        let dateSnapshot = makeSnapshot(field: .date, workspace: workspace, member: member)
        workspace.title = "Changed while the date sheet was open"
        workspace.mainEventImageData = Data([9, 8, 7])
        workspace.dressCode = "Cocktail attire"
        workspace.eventMessage = "Updated welcome note"

        let updatedDate = MainInvitationDateValue(
            startsAt: Date(timeIntervalSince1970: 1_900_000_000),
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: "Europe/Paris"
        )
        #expect(commit(.date(updatedDate), snapshot: dateSnapshot, in: workspace))
        #expect(workspace.mainEventStartsAt == updatedDate.startsAt)
        #expect(workspace.mainEventEndsAt == nil)
        #expect(!workspace.mainEventIsAllDay)
        #expect(workspace.mainEventTimeZoneIdentifier == "Europe/Paris")
        #expect(workspace.title == "Changed while the date sheet was open")
        #expect(workspace.mainEventLocation == existingLocation)
        #expect(workspace.mainEventImageData == Data([9, 8, 7]))
        #expect(workspace.dressCode == "Cocktail attire")
        #expect(workspace.eventMessage == "Updated welcome note")
        #expect(workspace.mainEventStatus == .ongoing)
        #expect(!workspace.invitationDateIsUndecided)

        let titleSnapshot = makeSnapshot(field: .title, workspace: workspace, member: member)
        let currentDate = MainInvitationDateValue(
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier
        )
        #expect(commit(.title(" New title "), snapshot: titleSnapshot, in: workspace))
        #expect(workspace.title == "New title")
        #expect(workspace.mainEventStartsAt == currentDate.startsAt)
        #expect(workspace.mainEventTimeZoneIdentifier == currentDate.timeZoneIdentifier)
        #expect(workspace.mainEventLocation == existingLocation)
        #expect(workspace.mainEventImageData == Data([9, 8, 7]))
        #expect(workspace.dressCode == "Cocktail attire")
        #expect(workspace.eventMessage == "Updated welcome note")
        #expect(workspace.mainEventStatus == .ongoing)

        let locationSnapshot = makeSnapshot(field: .location, workspace: workspace, member: member)
        #expect(commit(.location(nil), snapshot: locationSnapshot, in: workspace))
        #expect(workspace.mainEventLocation == nil)
        #expect(workspace.title == "New title")
        #expect(workspace.mainEventStartsAt == currentDate.startsAt)
        #expect(workspace.mainEventEndsAt == currentDate.endsAt)
        #expect(workspace.mainEventIsAllDay == currentDate.isAllDay)
        #expect(workspace.mainEventTimeZoneIdentifier == currentDate.timeZoneIdentifier)
        #expect(workspace.mainEventImageData == Data([9, 8, 7]))
        #expect(workspace.dressCode == "Cocktail attire")
        #expect(workspace.eventMessage == "Updated welcome note")
        #expect(workspace.mainEventStatus == .ongoing)
    }

    @Test("Guest, view-only, inactive, projected, and scoped viewers cannot commit")
    func permissionsAndEventScopeRejectCommit() {
        let eventID = UUID()
        let host = manager()
        let title = "Celebration"
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot(field: .title, eventID: eventID, member: host, title: title, startsAt: start)

        let guestWorkspace = makeWorkspace(member: WorkspaceMember(
            name: "Guest", participantRole: .guest, initials: "G", planningPermission: .manage
        ), mainEventID: eventID, title: title, startsAt: start)
        let guestSnapshot = makeSnapshot(
            field: .title, workspace: guestWorkspace,
            member: guestWorkspace.currentViewerMember(for: .main)!
        )
        #expect(!snapshotMatches(guestSnapshot, in: guestWorkspace, canManage: true),
                "Guest role must be rejected even when the caller reports management capability.")
        #expect(!commit(.title("Changed"), snapshot: guestSnapshot, in: guestWorkspace))

        let viewOnlyMember = WorkspaceMember(
            id: host.id, name: "Reader", participantRole: .host,
            initials: "R", planningPermission: .viewOnly
        )
        let viewOnlyWorkspace = makeWorkspace(member: viewOnlyMember, mainEventID: eventID, title: title, startsAt: start)
        let viewOnlySnapshot = makeSnapshot(
            field: .title, workspace: viewOnlyWorkspace,
            member: viewOnlyWorkspace.currentViewerMember(for: .main)!
        )
        #expect(!commit(.title("Changed"), snapshot: viewOnlySnapshot, in: viewOnlyWorkspace))
        #expect(!commit(.title("Changed"), snapshot: snapshot, in: viewOnlyWorkspace),
                "A host snapshot must be invalid after that same member ID loses permission.")

        let changedRoleWorkspace = makeWorkspace(member: WorkspaceMember(
            id: host.id, name: "Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        ), mainEventID: eventID, title: title, startsAt: start)
        #expect(!commit(.title("Changed"), snapshot: snapshot, in: changedRoleWorkspace))

        let inactiveWorkspace = makeWorkspace(member: WorkspaceMember(
            name: "Pending", participantRole: .host, initials: "P", planningPermission: .manage,
            invitationStatus: .invited
        ), mainEventID: eventID, title: title, startsAt: start)
        let inactiveSnapshot = makeSnapshot(
            field: .title, workspace: inactiveWorkspace,
            member: inactiveWorkspace.currentViewerMember(for: .main)!
        )
        #expect(!snapshotMatches(inactiveSnapshot, in: inactiveWorkspace, canManage: true),
                "Inactive participation must be rejected even when the caller reports management capability.")
        #expect(!commit(.title("Changed"), snapshot: inactiveSnapshot, in: inactiveWorkspace))

        let projectionWorkspace = makeWorkspace(member: host, mainEventID: eventID, title: title, startsAt: start)
        projectionWorkspace.isInvitationProjection = true
        #expect(!commit(.title("Changed"), snapshot: snapshot, in: projectionWorkspace))

        let scopedWorkspace = makeWorkspace(member: host, mainEventID: eventID, title: title, startsAt: start)
        scopedWorkspace.isScopedEvent = true
        let scopedSnapshot = makeSnapshot(field: .title, workspace: scopedWorkspace, member: host)
        #expect(!commit(.title("Changed"), snapshot: scopedSnapshot, in: scopedWorkspace))

        let otherEventWorkspace = makeWorkspace(member: host, mainEventID: UUID(), title: title, startsAt: start)
        #expect(!commit(.title("Changed"), snapshot: snapshot, in: otherEventWorkspace))

        let wrongFieldWorkspace = makeWorkspace(member: host, mainEventID: eventID, title: title, startsAt: start)
        #expect(!commit(.date(MainInvitationDateValue(
            startsAt: start.addingTimeInterval(86_400), endsAt: nil,
            isAllDay: false, timeZoneIdentifier: "America/Detroit"
        )), snapshot: snapshot, in: wrongFieldWorkspace))

        #expect(!MainInvitationEditCommand.commit(
            .title("Changed"), for: snapshot, in: wrongFieldWorkspace,
            accountID: "manager-account", localGuestProfileID: nil,
            principalGeneration: 4, reference: .subevent(UUID()), isCurrentPrincipal: true
        ))
        #expect(!MainInvitationEditCommand.commit(
            .title("Changed"), for: snapshot, in: wrongFieldWorkspace,
            accountID: "manager-account", localGuestProfileID: nil,
            principalGeneration: 4, reference: .idea(UUID()), isCurrentPrincipal: true
        ))
    }

    @Test("A stale target field or principal generation rejects the commit")
    func staleTargetAndPrincipalRejectCommit() {
        let member = manager()
        let workspace = makeWorkspace(member: member)
        let snapshot = makeSnapshot(field: .date, workspace: workspace, member: member)
        workspace.mainEventStartsAt = workspace.mainEventStartsAt.addingTimeInterval(60)
        #expect(!commit(.date(MainInvitationDateValue(
            startsAt: Date(timeIntervalSince1970: 1_900_000_000), endsAt: nil,
            isAllDay: false, timeZoneIdentifier: "America/Detroit"
        )), snapshot: snapshot, in: workspace))

        workspace.mainEventStartsAt = snapshot.startsAt
        #expect(!MainInvitationEditCommand.commit(
            .date(MainInvitationDateValue(
                startsAt: Date(timeIntervalSince1970: 1_900_000_000), endsAt: nil,
                isAllDay: false, timeZoneIdentifier: "America/Detroit"
            )),
            for: snapshot,
            in: workspace,
            accountID: "another-account",
            localGuestProfileID: nil,
            principalGeneration: 4,
            reference: .main,
            isCurrentPrincipal: true
        ))
        #expect(workspace.title == snapshot.title, "A mismatched account must not mutate the event.")
        #expect(!MainInvitationEditCommand.commit(
            .date(MainInvitationDateValue(
                startsAt: Date(timeIntervalSince1970: 1_900_000_000), endsAt: nil,
                isAllDay: false, timeZoneIdentifier: "America/Detroit"
            )),
            for: snapshot,
            in: workspace,
            accountID: "manager-account",
            localGuestProfileID: nil,
            principalGeneration: 5,
            reference: .main,
            isCurrentPrincipal: true
        ))
    }

    @Test("A device-local host is bound to its exact local guest profile")
    func localGuestIdentityIsScopedExactly() {
        let profile = LocalGuestProfile(displayName: "Local host")
        let member = WorkspaceMember(
            userID: profile.storageID, name: "Local host", participantRole: .host,
            initials: "L", planningPermission: .manage
        )
        let workspace = makeWorkspace(member: member)
        workspace.configureLocalGuestViewer(profile)
        let snapshot = MainInvitationEditSnapshot(
            field: .title,
            accountID: nil,
            localGuestProfileID: profile.id,
            principalGeneration: 4,
            mainEventID: workspace.mainEventID,
            isScopedEvent: false,
            member: workspace.currentViewerMember(for: .main)!,
            title: workspace.title,
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
            location: workspace.mainEventLocation,
            invitationDateIsUndecided: workspace.invitationDateIsUndecided
        )

        #expect(MainInvitationEditCommand.commit(
            .title("Local change"),
            for: snapshot,
            in: workspace,
            accountID: nil,
            localGuestProfileID: profile.id,
            principalGeneration: 4,
            reference: .main,
            isCurrentPrincipal: true
        ))
        #expect(workspace.title == "Local change")
        let nextSnapshot = MainInvitationEditSnapshot(
            field: .title,
            accountID: nil,
            localGuestProfileID: profile.id,
            principalGeneration: 4,
            mainEventID: workspace.mainEventID,
            isScopedEvent: false,
            member: member,
            title: workspace.title,
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
            location: workspace.mainEventLocation,
            invitationDateIsUndecided: workspace.invitationDateIsUndecided
        )
        #expect(!MainInvitationEditCommand.commit(
            .title("Wrong profile"),
            for: nextSnapshot,
            in: workspace,
            accountID: nil,
            localGuestProfileID: UUID(),
            principalGeneration: 4,
            reference: .main,
            isCurrentPrincipal: true
        ))
        #expect(workspace.title == "Local change", "A wrong local profile must not mutate the event.")
    }

    private func manager() -> WorkspaceMember {
        WorkspaceMember(
            userID: "manager-account", name: "Host", participantRole: .host,
            initials: "H", planningPermission: .manage
        )
    }

    private func makeWorkspace(
        member: WorkspaceMember,
        mainEventID: UUID = UUID(),
        title: String = "Celebration",
        startsAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            mainEventID: mainEventID,
            title: title,
            mainEventStartsAt: startsAt,
            venueName: "Museum",
            location: "10 Museum Way",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            registry: []
        )
    }

    private func makeSnapshot(
        field: MainInvitationEditField,
        workspace: PlanningWorkspace,
        member: WorkspaceMember
    ) -> MainInvitationEditSnapshot {
        makeSnapshot(
            field: field,
            eventID: workspace.mainEventID,
            member: member,
            title: workspace.title,
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
            location: workspace.mainEventLocation
        )
    }

    private func makeSnapshot(
        field: MainInvitationEditField,
        eventID: UUID,
        member: WorkspaceMember,
        title: String,
        startsAt: Date,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String = "America/Detroit",
        location: EventLocation? = nil
    ) -> MainInvitationEditSnapshot {
        MainInvitationEditSnapshot(
            field: field,
            accountID: "manager-account",
            principalGeneration: 4,
            mainEventID: eventID,
            isScopedEvent: false,
            member: member,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            location: location,
            invitationDateIsUndecided: false
        )
    }

    private func commit(
        _ value: MainInvitationEditValue,
        snapshot: MainInvitationEditSnapshot,
        in workspace: PlanningWorkspace
    ) -> Bool {
        MainInvitationEditCommand.commit(
            value,
            for: snapshot,
            in: workspace,
            accountID: "manager-account",
            localGuestProfileID: nil,
            principalGeneration: 4,
            reference: .main,
            isCurrentPrincipal: true
        )
    }

    private func snapshotMatches(
        _ snapshot: MainInvitationEditSnapshot,
        in workspace: PlanningWorkspace,
        canManage: Bool
    ) -> Bool {
        let date = MainInvitationDateValue(
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier
        )
        return snapshot.matches(
            accountID: snapshot.accountID,
            localGuestProfileID: snapshot.localGuestProfileID,
            principalGeneration: snapshot.principalGeneration,
            mainEventID: workspace.mainEventID,
            isScopedEvent: workspace.isScopedEvent,
            reference: .main,
            member: workspace.currentViewerMember(for: .main),
            canManageMainEvent: canManage,
            isCurrentPrincipal: true,
            isInvitationProjection: workspace.isInvitationProjection,
            title: workspace.title,
            startsAt: date.startsAt,
            endsAt: date.endsAt,
            isAllDay: date.isAllDay,
            timeZoneIdentifier: date.timeZoneIdentifier,
            location: workspace.mainEventLocation,
            invitationDateIsUndecided: workspace.invitationDateIsUndecided
        )
    }
}
