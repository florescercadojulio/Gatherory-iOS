import Foundation

@MainActor
struct HomeEventsOverviewDayGroup: Identifiable {
    let id: String
    let title: String
    let events: [TimelineItem]

    static func groups(for events: [TimelineItem], now: Date = .now) -> [HomeEventsOverviewDayGroup] {
        var scheduledEventsByDay: [String: [TimelineItem]] = [:]
        var componentsByDay: [String: DateComponents] = [:]
        var unscheduledEvents: [TimelineItem] = []

        for event in events {
            guard event.hasScheduledDate else {
                unscheduledEvents.append(event)
                continue
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: event.timeZoneIdentifier) ?? .autoupdatingCurrent
            let components = calendar.dateComponents([.year, .month, .day], from: event.scheduledAt)
            guard let year = components.year, let month = components.month, let day = components.day else {
                continue
            }

            let id = String(
                format: "%04d-%02d-%02d",
                locale: Locale(identifier: "en_US_POSIX"),
                year,
                month,
                day
            )
            scheduledEventsByDay[id, default: []].append(event)
            componentsByDay[id] = components
        }

        let datedGroups = scheduledEventsByDay.keys.sorted().compactMap { id -> HomeEventsOverviewDayGroup? in
            guard let events = scheduledEventsByDay[id],
                  let components = componentsByDay[id] else { return nil }
            let orderedEvents = ordered(events)
            guard let representativeEvent = orderedEvents.first,
                  let title = dateTitle(for: components, timeZoneIdentifier: representativeEvent.timeZoneIdentifier, now: now)
            else { return nil }
            return HomeEventsOverviewDayGroup(id: id, title: title, events: orderedEvents)
        }.sorted { lhs, rhs in
            let leftIsUpcoming = lhs.events.contains { EventDateOrdering.key(for: $0, now: now).period == 0 }
            let rightIsUpcoming = rhs.events.contains { EventDateOrdering.key(for: $0, now: now).period == 0 }
            if leftIsUpcoming != rightIsUpcoming { return leftIsUpcoming }
            return leftIsUpcoming ? lhs.id < rhs.id : lhs.id > rhs.id
        }

        guard !unscheduledEvents.isEmpty else { return datedGroups }
        return datedGroups + [HomeEventsOverviewDayGroup(
            id: "unscheduled",
            title: String(localized: "Date to be decided"),
            events: ordered(unscheduledEvents)
        )]
    }

    private static func ordered(_ events: [TimelineItem]) -> [TimelineItem] {
        events.sorted { lhs, rhs in
            if lhs.scheduledAt != rhs.scheduledAt {
                return lhs.scheduledAt < rhs.scheduledAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func dateTitle(for components: DateComponents, timeZoneIdentifier: String, now: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        calendar.timeZone = timeZone
        var stableComponents = DateComponents()
        stableComponents.calendar = calendar
        stableComponents.timeZone = timeZone
        stableComponents.year = components.year
        stableComponents.month = components.month
        stableComponents.day = components.day
        guard let date = calendar.date(from: stableComponents) else { return nil }

        let targetDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let dayOffset = calendar.dateComponents([.day], from: today, to: targetDay).day
        if let dayOffset, (-1...7).contains(dayOffset) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.locale = .autoupdatingCurrent
            relativeFormatter.unitsStyle = .full
            relativeFormatter.dateTimeStyle = .named
            var relativeComponents = DateComponents()
            relativeComponents.day = dayOffset
            let label = relativeFormatter.localizedString(from: relativeComponents)
            return String(label.prefix(1)).uppercased(with: .autoupdatingCurrent) + String(label.dropFirst())
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
