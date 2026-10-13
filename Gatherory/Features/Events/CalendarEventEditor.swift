import EventKit
import EventKitUI
import SwiftUI

nonisolated struct CalendarEventDraft: Equatable, Sendable, Identifiable {
    let id = UUID()
    let title: String
    let startsAt: Date
    let endsAt: Date
    let isAllDay: Bool
    let timeZone: TimeZone
    let location: String?
    let notes: String?

    static func make(title: String, startsAt: Date?, endsAt: Date?, isAllDay: Bool, timeZoneIdentifier: String, location: String?, notes: String?) -> Self? {
        guard let startsAt else { return nil }
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = isAllDay ? calendar.startOfDay(for: startsAt) : startsAt
        let end: Date
        if isAllDay {
            // Gatherory's displayed end date is inclusive; EventKit's is exclusive.
            let lastDay = calendar.startOfDay(for: max(endsAt ?? startsAt, startsAt))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
            end = nextDay
        } else {
            end = endsAt.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
        }
        return Self(title: title, startsAt: start, endsAt: end, isAllDay: isAllDay, timeZone: timeZone, location: location, notes: notes)
    }
}

/// On iOS 17+, the system editor can save an event without calendar read access.
/// Do not request full/write access, fetch calendars, or select a default calendar.
struct CalendarEventEditor: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let draft: CalendarEventDraft

    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let editor = EKEventEditViewController()
        editor.eventStore = context.coordinator.store
        editor.editViewDelegate = context.coordinator
        let event = EKEvent(eventStore: context.coordinator.store)
        event.title = draft.title
        event.startDate = draft.startsAt
        event.endDate = draft.endsAt
        event.isAllDay = draft.isAllDay
        event.timeZone = draft.timeZone
        event.location = draft.location
        event.notes = draft.notes
        editor.event = event
        return editor
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let finish: () -> Void
        init(finish: @escaping () -> Void) { self.finish = finish }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { finish() }
    }
}
