import Foundation

/// Only the selected event's display names and contextual attendance leave the
/// planning model. Account/contact fields never become attachment content.
nonisolated struct EventGuestListExportSnapshot: Identifiable, Equatable, Sendable {
    let id = UUID()
    let csv: String
    let fileName = "Guest List.csv"
    var data: Data { EventCSVEncoder.data(for: csv) }
}

@MainActor
enum EventGuestListExport {
    static func canExport(workspace: PlanningWorkspace, reference: EventReference, accountID: String?) -> Bool {
        guard let accountID,
              workspace.hasAuthenticatedViewer(accountID: accountID),
              !workspace.isInvitationProjection,
              !workspace.isMainEventDeleted,
              workspace.canManageInvitations(for: reference),
              let viewer = workspace.currentViewerMember(for: reference),
              viewer.userID == accountID,
              viewer.invitationStatus == .active else { return false }

        switch reference {
        case .main:
            return !workspace.isScopedEvent || workspace.scopedMainEventDetails?.id == workspace.mainEventID
        case .subevent(let id):
            return !workspace.isScopedEvent && workspace.timeline.contains {
                $0.id == id && $0.parentEventID == workspace.mainEventID
            }
        case .idea:
            return false
        }
    }

    static func makeSnapshot(
        workspace: PlanningWorkspace,
        reference: EventReference,
        accountID: String?,
        locale: Locale = .current
    ) -> EventGuestListExportSnapshot? {
        guard canExport(workspace: workspace, reference: reference, accountID: accountID) else { return nil }
        let bundle = EventCSVEncoder.localizationBundle(for: locale)
        var rows = [[
            String(localized: "event.guestListExport.csv.name", defaultValue: "Name", bundle: bundle, locale: locale),
            String(localized: "event.guestListExport.csv.rsvpStatus", defaultValue: "RSVP Status", bundle: bundle, locale: locale),
        ]]
        // The Guest List includes attendees in every planning role and every
        // RSVP state. Retain roster order and distinct people with equal names.
        rows.append(contentsOf: workspace.participants(for: reference).map { person in
            let trimmedName = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = person.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isEmailFallback = email.map {
                trimmedName.caseInsensitiveCompare($0) == .orderedSame
            } ?? false
            let name = trimmedName.isEmpty || isEmailFallback
                ? String(localized: "event.guestListExport.unnamedGuest", defaultValue: "Unnamed Guest", bundle: bundle, locale: locale)
                : person.name
            return [name, attendanceText(person.attendance, bundle: bundle, locale: locale)]
        })
        return EventGuestListExportSnapshot(csv: EventCSVEncoder.encode(rows: rows))
    }

    private static func attendanceText(_ status: AttendanceStatus, bundle: Bundle, locale: Locale) -> String {
        switch status {
        case .invited:
            String(localized: "event.guestListExport.rsvp.invited", defaultValue: "Invited", bundle: bundle, locale: locale)
        case .going:
            String(localized: "event.guestListExport.rsvp.going", defaultValue: "Going", bundle: bundle, locale: locale)
        case .maybe:
            String(localized: "event.guestListExport.rsvp.maybe", defaultValue: "Maybe", bundle: bundle, locale: locale)
        case .declined:
            String(localized: "event.guestListExport.rsvp.declined", defaultValue: "Can't go", bundle: bundle, locale: locale)
        }
    }
}
