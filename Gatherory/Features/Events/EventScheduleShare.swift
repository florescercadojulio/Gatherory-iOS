import Foundation

/// A frozen, public-facing CSV copy. No model, account, invitation credential,
/// or planning-team record crosses the system share-sheet boundary.
nonisolated struct EventScheduleShareSnapshot: Identifiable, Equatable, Sendable {
    let id = UUID()
    let csv: String
    let fileName = "Event Schedule.csv"

    /// A UTF-8 BOM lets spreadsheet apps recognize accented names and headers.
    var data: Data { EventCSVEncoder.data(for: csv) }
}

@MainActor
enum EventScheduleShare {
    static func canShare(workspace: PlanningWorkspace, reference: EventReference, accountID: String?) -> Bool {
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
            guard workspace.isScopedEvent else { return true }
            guard let event = workspace.scopedMainEventDetails,
                  event.id == workspace.mainEventID else { return false }
            return isPublicScheduleEvent(event)
        case .subevent(let id):
            guard !workspace.isScopedEvent,
                  let event = workspace.timeline.first(where: {
                      $0.id == id && $0.parentEventID == workspace.mainEventID
                  }) else { return false }
            return isPublicScheduleEvent(event)
        case .idea:
            return false
        }
    }

    /// Resolve an explicit event again at the user's action. Home selection,
    /// cached preview content, and root membership cannot widen this scope.
    static func makeSnapshot(
        workspace: PlanningWorkspace,
        reference: EventReference,
        accountID: String?,
        locale: Locale = .current
    ) -> EventScheduleShareSnapshot? {
        guard canShare(workspace: workspace, reference: reference, accountID: accountID) else { return nil }

        let bundle = EventCSVEncoder.localizationBundle(for: locale)
        var rows = [[
            String(localized: "event.scheduleShare.csv.event", defaultValue: "Event", bundle: bundle, locale: locale),
            String(localized: "event.scheduleShare.csv.start", defaultValue: "Start", bundle: bundle, locale: locale),
            String(localized: "event.scheduleShare.csv.end", defaultValue: "End", bundle: bundle, locale: locale),
            String(localized: "event.scheduleShare.csv.allDay", defaultValue: "All Day", bundle: bundle, locale: locale),
            String(localized: "event.scheduleShare.csv.timeZone", defaultValue: "Time Zone", bundle: bundle, locale: locale),
            String(localized: "event.scheduleShare.csv.location", defaultValue: "Location", bundle: bundle, locale: locale),
        ]]
        switch reference {
        case .main:
            if workspace.isScopedEvent {
                guard let event = workspace.scopedMainEventDetails else { return nil }
                rows.append(row(for: event))
            } else {
                rows.append(row(
                    title: workspace.title,
                    startsAt: workspace.mainEventHasScheduledDate && !workspace.invitationDateIsUndecided
                        ? workspace.mainEventStartsAt : nil,
                    endsAt: workspace.mainEventEndsAt,
                    isAllDay: workspace.mainEventIsAllDay,
                    timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
                    location: workspace.mainEventLocation
                ))
                let children = workspace.timeline.enumerated().filter { _, event in
                    event.parentEventID == workspace.mainEventID
                        && event.hasScheduledDate
                        && canShare(workspace: workspace, reference: .subevent(event.id), accountID: accountID)
                }.sorted { lhs, rhs in
                    if lhs.element.scheduledAt != rhs.element.scheduledAt {
                        return lhs.element.scheduledAt < rhs.element.scheduledAt
                    }
                    return lhs.offset < rhs.offset
                }
                rows.append(contentsOf: children.map { row(for: $0.element) })
            }
        case .subevent(let id):
            guard let event = workspace.timeline.first(where: { $0.id == id }) else { return nil }
            rows.append(row(for: event))
        case .idea:
            return nil
        }
        return EventScheduleShareSnapshot(csv: EventCSVEncoder.encode(rows: rows))
    }

    private static func isPublicScheduleEvent(_ event: TimelineItem) -> Bool {
        event.purpose == .eventExperience && event.status == .approved
    }

    private static func row(for event: TimelineItem) -> [String] {
        row(title: event.title, startsAt: event.hasScheduledDate ? event.scheduledAt : nil,
            endsAt: event.endsAt, isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier, location: event.eventLocation)
    }

    private static func row(
        title: String, startsAt: Date?, endsAt: Date?, isAllDay: Bool,
        timeZoneIdentifier: String, location: EventLocation?
    ) -> [String] {
        // A corrupt legacy zone gets a stable, explicitly labeled UTC fallback.
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = isAllDay ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ssXXX"
        let start = startsAt.map(formatter.string(from:)) ?? ""
        let end: String
        if let startsAt, let endsAt, endsAt > startsAt {
            end = formatter.string(from: endsAt)
        } else {
            end = ""
        }
        return [title, start, end, isAllDay ? "TRUE" : "FALSE", timeZone.identifier, locationText(location)]
    }

    private static func locationText(_ location: EventLocation?) -> String {
        guard let location else { return "" }
        // Do not copy coordinates, map identifiers, contacts, or URLs.
        let place = [location.locationName, location.placeName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let values = [place, location.addressLine2, location.address.isEmpty ? location.shortAddress : location.address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var unique: [String] = []
        for value in values where !unique.contains(value) { unique.append(value) }
        return unique.joined(separator: ", ")
    }


}
