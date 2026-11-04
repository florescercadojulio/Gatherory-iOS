import Foundation

/// Display ordering only. It does not reorder persisted events or change selection.
@MainActor
enum EventDateOrdering {
    nonisolated struct Key: Comparable, Sendable {
        // Today/ongoing/upcoming, then past, then no date.
        let period: Int
        let startsAt: Date
        let identity: String

        static func < (lhs: Key, rhs: Key) -> Bool {
            if lhs.period != rhs.period { return lhs.period < rhs.period }
            if lhs.period != 2, lhs.startsAt != rhs.startsAt {
                return lhs.period == 1 ? lhs.startsAt > rhs.startsAt : lhs.startsAt < rhs.startsAt
            }
            return lhs.identity < rhs.identity
        }
    }

    static func key(for event: TimelineItem, now: Date) -> Key {
        key(startsAt: event.hasScheduledDate ? event.scheduledAt : nil,
            endsAt: event.endsAt, timeZoneIdentifier: event.timeZoneIdentifier,
            identity: event.id, now: now)
    }

    static func key(for workspace: PlanningWorkspace, now: Date) -> Key {
        let hasDate = !workspace.invitationDateIsUndecided && workspace.mainEventHasScheduledDate
        return key(startsAt: hasDate ? workspace.mainEventStartsAt : nil,
                   endsAt: workspace.mainEventEndsAt,
                   timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
                   identity: workspace.mainEventID, now: now)
    }

    private static func key(
        startsAt: Date?, endsAt: Date?, timeZoneIdentifier: String,
        identity: UUID, now: Date
    ) -> Key {
        guard let startsAt else {
            return Key(period: 2, startsAt: .distantFuture, identity: identity.uuidString)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        let lastDay = calendar.startOfDay(for: max(startsAt, endsAt ?? startsAt))
        let today = calendar.startOfDay(for: now)
        return Key(period: lastDay >= today ? 0 : 1,
                   startsAt: startsAt, identity: identity.uuidString)
    }
}
