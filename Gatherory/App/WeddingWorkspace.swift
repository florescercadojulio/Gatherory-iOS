import Foundation
import Observation

@Observable
final class WeddingWorkspace {
    let mainEventID: UUID
    var title: String
    var weddingDate: Date
    var mainEventEndsAt: Date?
    var mainEventIsAllDay: Bool
    var mainEventTimeZoneIdentifier: String
    var mainEventLocation: EventLocation?
    var mainEventImageData: Data?
    var venueName: String
    var location: String
    var dressCode: String
    var eventMessage: String
    var planningMode: PlanningMode
    var members: [WeddingMember]
    var mainEventParticipantIDs: [UUID]
    var ideas: [WeddingIdea]
    var timeline: [TimelineItem]
    var notes: [EventNote]
    var mainEventStatus: MainEventStatus
    var mainEventResponse: EventResponse?
    var mainEventMoments: [EventMoment]
    var isMainEventDeleted: Bool
    var registry: [RegistryItem]
    var isRegistryShared: Bool
    var isCollaboratorLinkEnabled: Bool
    var requiresCollaboratorApproval: Bool
    var defaultCollaboratorPermission: PlanningPermission
    var collaboratorInviteURL: URL
    /// The event currently being planned across Home, Ideas, and Decide.
    /// It is always either the root event or one of its direct children.
    var selectedEventReference: EventReference = .main

    private var decisionHistory: [DecisionRecord] = []

    init(
        mainEventID: UUID = UUID(),
        title: String,
        weddingDate: Date,
        mainEventEndsAt: Date? = nil,
        mainEventIsAllDay: Bool = false,
        mainEventTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        mainEventLocation: EventLocation? = nil,
        mainEventImageData: Data? = nil,
        venueName: String,
        location: String,
        dressCode: String = "Garden formal",
        eventMessage: String = "Your presence means the world to us. The ceremony and reception will be outdoors, so please plan for the evening weather.",
        planningMode: PlanningMode,
        members: [WeddingMember],
        mainEventParticipantIDs: [UUID]? = nil,
        ideas: [WeddingIdea],
        timeline: [TimelineItem],
        notes: [EventNote] = [],
        mainEventStatus: MainEventStatus = .draft,
        mainEventResponse: EventResponse? = nil,
        mainEventMoments: [EventMoment] = [],
        isMainEventDeleted: Bool = false,
        registry: [RegistryItem],
        isRegistryShared: Bool = false,
        isCollaboratorLinkEnabled: Bool = true,
        requiresCollaboratorApproval: Bool = true,
        defaultCollaboratorPermission: PlanningPermission = .contribute,
        collaboratorInviteURL: URL = URL(string: "https://isaidyes.app/join/planning-circle")!
    ) {
        self.mainEventID = mainEventID
        self.title = title
        self.weddingDate = weddingDate
        self.mainEventEndsAt = mainEventEndsAt
        self.mainEventIsAllDay = mainEventIsAllDay
        self.mainEventTimeZoneIdentifier = mainEventTimeZoneIdentifier
        self.mainEventLocation = mainEventLocation ?? EventLocation(
            address: location,
            shortAddress: location,
            placeName: venueName,
            locationName: venueName
        )
        self.mainEventImageData = mainEventImageData
        self.venueName = venueName
        self.location = location
        self.dressCode = dressCode
        self.eventMessage = eventMessage
        self.planningMode = planningMode
        self.members = members
        self.mainEventParticipantIDs = mainEventParticipantIDs ?? members.map(\.id)
        self.ideas = ideas.map { idea in
            var scopedIdea = idea
            if scopedIdea.eventID == nil {
                scopedIdea.eventID = mainEventID
            }
            return scopedIdea
        }
        self.timeline = timeline.map { event in
            var childEvent = event
            childEvent.parentEventID = mainEventID
            return childEvent
        }
        self.notes = notes.map { note in
            guard note.eventID == nil else { return note }
            return EventNote(id: note.id, eventID: mainEventID, body: note.body, sentAt: note.sentAt)
        }
        self.mainEventStatus = mainEventStatus
        self.mainEventResponse = mainEventResponse
        self.mainEventMoments = mainEventMoments
        self.isMainEventDeleted = isMainEventDeleted
        self.registry = registry
        self.isRegistryShared = isRegistryShared
        self.isCollaboratorLinkEnabled = isCollaboratorLinkEnabled
        self.requiresCollaboratorApproval = requiresCollaboratorApproval
        self.defaultCollaboratorPermission = defaultCollaboratorPermission
        self.collaboratorInviteURL = collaboratorInviteURL
    }

    var decisionQueue: [WeddingIdea] {
        contextualIdeas.filter { $0.status == .new }
    }

    var availableEventContexts: [EventReference] {
        ([.main] + childEvents.map { .subevent($0.id) })
            .sorted { lhs, rhs in
                let lhsDate = eventDate(for: lhs)
                let rhsDate = eventDate(for: rhs)
                if lhsDate == rhsDate { return lhs == .main }
                return lhsDate < rhsDate
            }
    }

    /// The child event that is happening now, or the next incomplete child
    /// event on the calendar. Home-tab reselection uses this as the companion
    /// destination to the main event.
    func currentOrNextChildEventReference(at date: Date = .now) -> EventReference? {
        let candidates = childEvents.filter { $0.completionStatus == .upcoming }

        if let current = candidates.last(where: { event in
            guard event.scheduledAt <= date else { return false }
            let effectiveEnd = event.endsAt ?? event.scheduledAt
            return date <= effectiveEnd
        }) {
            return .subevent(current.id)
        }

        return candidates
            .first(where: { $0.scheduledAt > date })
            .map { .subevent($0.id) }
    }

    var selectedEventID: UUID {
        switch selectedEventReference {
        case .main:
            mainEventID
        case .subevent(let id):
            id
        case .idea:
            mainEventID
        }
    }

    var isMainEventContext: Bool {
        selectedEventReference == .main
    }

    var selectedEventTitle: String {
        switch selectedEventReference {
        case .main:
            title
        case .subevent(let id):
            timeline.first(where: { $0.id == id })?.title ?? title
        case .idea:
            title
        }
    }

    var contextualIdeas: [WeddingIdea] {
        ideas.filter { ($0.eventID ?? mainEventID) == selectedEventID }
    }

    var contextualNotes: [EventNote] {
        notes.filter { ($0.eventID ?? mainEventID) == selectedEventID }
    }

    func participants(for reference: EventReference) -> [WeddingMember] {
        switch reference {
        case .main, .idea:
            let participantIDs = Set(mainEventParticipantIDs)
            return members.filter { participantIDs.contains($0.id) }
        case .subevent(let id):
            guard let event = timeline.first(where: { $0.id == id }) else { return [] }
            let participantIDs = Set(event.participantIDs)
            return members.filter { participantIDs.contains($0.id) }
        }
    }

    var selectedEventCoordinators: [WeddingMember] {
        participants(for: selectedEventReference)
            .filter { $0.participantRole != .guest }
    }

    var selectedEventParticipants: [WeddingMember] {
        participants(for: selectedEventReference)
    }

    func addParticipant(_ participantID: UUID, to reference: EventReference? = nil) {
        guard members.contains(where: { $0.id == participantID }) else { return }

        switch reference ?? selectedEventReference {
        case .main, .idea:
            guard !mainEventParticipantIDs.contains(participantID) else { return }
            mainEventParticipantIDs.append(participantID)
        case .subevent(let eventID):
            guard let index = timeline.firstIndex(where: { $0.id == eventID }),
                  !timeline[index].participantIDs.contains(participantID) else { return }
            timeline[index].participantIDs.append(participantID)
        }
    }

    func selectEventContext(_ reference: EventReference) {
        switch reference {
        case .main:
            selectedEventReference = .main
        case .subevent(let id):
            guard childEvents.contains(where: { $0.id == id }) else { return }
            selectedEventReference = .subevent(id)
        case .idea:
            return
        }
    }

    func eventDate(for reference: EventReference) -> Date {
        switch reference {
        case .main:
            weddingDate
        case .subevent(let id):
            timeline.first(where: { $0.id == id })?.scheduledAt ?? .distantFuture
        case .idea:
            .distantFuture
        }
    }

    var upcomingTimeline: [TimelineItem] {
        timeline
            .filter { $0.status != .archived && $0.completionStatus == .upcoming }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var childEvents: [TimelineItem] {
        timeline
            .filter { $0.parentEventID == mainEventID && $0.status != .archived }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var approvedChildEvents: [TimelineItem] {
        childEvents.filter { $0.status == .approved }
    }

    /// The event hierarchy is deliberately shallow. The root can contain events;
    /// subevents are leaves and can never acquire children of their own.
    var eventTree: EventTreeNode {
        EventTreeNode(
            id: mainEventID,
            parentID: nil,
            kind: .main,
            children: childEvents.map {
                EventTreeNode(
                    id: $0.id,
                    parentID: mainEventID,
                    kind: .subevent,
                    children: []
                )
            }
        )
    }

    func canAddChildEvent(to parentID: UUID) -> Bool {
        parentID == mainEventID
    }

    var planningMembers: [WeddingMember] {
        members.filter { $0.participantRole != .guest }
    }

    var canManageMainEvent: Bool {
        members.first?.planningPermission == .manage && !mainEventStatus.isReadOnly
    }

    var canDeleteMainEvent: Bool {
        members.first?.planningPermission == .manage && mainEventStatus == .draft
    }

    var canAddEventMoments: Bool {
        currentMainEventStatus == .ongoing
    }

    var mainEventWindow: ClosedRange<Date> {
        let eventExperiences = timeline.filter {
            $0.parentEventID == mainEventID
                && $0.purpose == .eventExperience
                && $0.status == .approved
        }
        let starts = [weddingDate] + eventExperiences.map(\.scheduledAt)
        let ends = [mainEventEndsAt ?? weddingDate] + eventExperiences.map {
            $0.endsAt ?? $0.scheduledAt
        }
        return (starts.min() ?? weddingDate)...(ends.max() ?? weddingDate)
    }

    var currentMainEventStatus: MainEventStatus {
        guard mainEventStatus != .draft, mainEventStatus != .finished else {
            return mainEventStatus
        }

        if Date.now > mainEventWindow.upperBound {
            return .finished
        }

        if mainEventWindow.contains(Date.now) {
            return .ongoing
        }

        return mainEventStatus
    }

    var canUndoDecision: Bool {
        !decisionHistory.isEmpty
    }

    func decide(_ choice: DecisionChoice, on idea: WeddingIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }

        decisionHistory.append(
            DecisionRecord(ideaID: idea.id, previousStatus: ideas[index].status)
        )

        ideas[index].status = switch choice {
        case .pass: .passed
        case .maybe: .maybe
        case .love: .shortlisted
        }
    }

    func undoLastDecision() {
        guard let decision = decisionHistory.popLast(),
              let index = ideas.firstIndex(where: { $0.id == decision.ideaID }) else {
            return
        }

        ideas[index].status = decision.previousStatus
    }

    func toggleTimelineItem(_ item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        timeline[index].completionStatus = timeline[index].completionStatus == .complete ? .upcoming : .complete
    }

    func addTimelineItem(_ item: TimelineItem) {
        guard canAddChildEvent(to: item.parentEventID ?? mainEventID) else { return }
        var childEvent = item
        childEvent.parentEventID = mainEventID
        if childEvent.participantIDs.isEmpty {
            childEvent.participantIDs = mainEventParticipantIDs
        }
        timeline.append(childEvent)
    }

    func updateTimelineItem(_ item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        guard canAddChildEvent(to: item.parentEventID ?? mainEventID) else { return }
        var childEvent = item
        childEvent.parentEventID = mainEventID
        timeline[index] = childEvent
    }

    func setResponse(_ response: EventResponse?, for item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        timeline[index].response = response
    }

    func setEventStatus(_ status: EventStatus, for item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        timeline[index].status = status
        if status == .archived, selectedEventReference == .subevent(item.id) {
            selectedEventReference = .main
        }
    }

    func setMainEventResponse(_ response: EventResponse?) {
        guard !currentMainEventStatus.isReadOnly else { return }
        mainEventResponse = response
    }

    func updateMainEvent(
        title: String,
        status: MainEventStatus,
        startsAt: Date,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        eventLocation: EventLocation?,
        imageData: Data?,
        dressCode: String,
        message: String
    ) {
        guard canManageMainEvent else { return }

        self.title = title
        mainEventStatus = status
        weddingDate = startsAt
        mainEventEndsAt = endsAt
        mainEventIsAllDay = isAllDay
        mainEventTimeZoneIdentifier = timeZoneIdentifier
        mainEventLocation = eventLocation
        mainEventImageData = imageData
        venueName = eventLocation?.title ?? ""
        location = eventLocation?.detail ?? ""
        self.dressCode = dressCode
        eventMessage = message
        isMainEventDeleted = false
    }

    func addMainEventMoment(_ imageData: Data) {
        guard canAddEventMoments else { return }
        let contributor = members.first?.name ?? "Guest"
        mainEventMoments.insert(
            EventMoment(imageData: imageData, addedBy: contributor),
            at: 0
        )
    }

    func deleteMainEvent() {
        guard canDeleteMainEvent else { return }
        isMainEventDeleted = true
        mainEventResponse = nil
        mainEventMoments.removeAll()
        timeline.removeAll { $0.parentEventID == mainEventID }
        selectedEventReference = .main
    }

    func sendNote(_ body: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        notes.insert(
            EventNote(eventID: selectedEventID, body: String(trimmedBody.prefix(750))),
            at: 0
        )
    }

    func deleteTimelineItem(_ item: TimelineItem) {
        timeline.removeAll { $0.id == item.id }
        if selectedEventReference == .subevent(item.id) {
            selectedEventReference = .main
        }
    }

    func updateIdea(_ idea: WeddingIdea, status: IdeaStatus) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index].status = status
    }

    func updateIdea(_ idea: WeddingIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index] = idea
    }

    func addIdea(_ idea: WeddingIdea) {
        var scopedIdea = idea
        if scopedIdea.eventID == nil {
            scopedIdea.eventID = selectedEventID
        }
        ideas.insert(scopedIdea, at: 0)
    }

    func addRegistryItem(_ item: RegistryItem) {
        registry.append(item)
    }

    func updateRegistryItem(_ item: RegistryItem) {
        guard let index = registry.firstIndex(where: { $0.id == item.id }) else { return }
        registry[index] = item
    }

    func commitToRegistryItem(_ item: RegistryItem) {
        guard isRegistryShared,
              let index = registry.firstIndex(where: { $0.id == item.id }),
              registry[index].remainingCount > 0 else { return }

        registry[index].committedCount += 1
    }

    func inviteParticipant(
        name: String,
        email: String? = nil,
        initials: String,
        role: WeddingParticipantRole
    ) {
        if let existingMember = members.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            addParticipant(existingMember.id)
            return
        }

        let member = WeddingMember(
            name: name,
            participantRole: role,
            initials: initials,
            attendance: .invited,
            email: email,
            planningPermission: role == .collaborator
                ? defaultCollaboratorPermission
                : role.defaultPlanningPermission,
            invitationStatus: .invited
        )
        members.append(member)
        addParticipant(member.id)
    }
}

private struct DecisionRecord {
    let ideaID: UUID
    let previousStatus: IdeaStatus
}

extension WeddingWorkspace {
    static var sample: WeddingWorkspace {
        let calendar = Calendar.current
        let now = Date.now
        let weddingDate = calendar.date(byAdding: .day, value: 248, to: now) ?? now
        let venueLocation = EventLocation(
            address: "Ann Arbor, Michigan",
            shortAddress: "Ann Arbor, MI",
            placeName: "Willow & Stone Estate",
            locationName: "Willow & Stone Estate",
            latitude: 42.2808,
            longitude: -83.7430
        )
        let alex = WeddingMember(
            name: "Alex",
            participantRole: .host,
            initials: "A",
            planningPermission: .manage
        )
        let jordan = WeddingMember(
            name: "Jordan",
            participantRole: .host,
            initials: "J",
            planningPermission: .manage
        )
        let sarah = WeddingMember(name: "Sarah", participantRole: .collaborator, initials: "S")
        let mia = WeddingMember(name: "Mia", participantRole: .collaborator, initials: "M")
        let chris = WeddingMember(
            name: "Chris",
            participantRole: .guest,
            initials: "C",
            attendance: .invited,
            planningPermission: .viewOnly
        )

        return WeddingWorkspace(
            title: "Alex & Jordan",
            weddingDate: weddingDate,
            venueName: "Willow & Stone Estate",
            location: "Ann Arbor, Michigan",
            planningMode: .openToIdeas,
            members: [alex, jordan, sarah, mia, chris],
            ideas: [
                WeddingIdea(
                    title: "Willow & Stone Estate",
                    note: "Garden ceremony, dinner under the trees, and space for everyone we love.",
                    category: .venue,
                    submittedBy: "Alex & Jordan",
                    estimatedCost: 12_000,
                    status: .chosen
                ),
                WeddingIdea(
                    title: "Garden ceremony lighting",
                    note: "Warm string lights through the trees for the ceremony and dinner.",
                    category: .decor,
                    submittedBy: "Sarah",
                    estimatedCost: 400
                ),
                WeddingIdea(
                    title: "Wildflower table arrangements",
                    note: "Loose seasonal flowers in small mismatched glass vases.",
                    category: .flowers,
                    submittedBy: "Mia",
                    estimatedCost: 650
                ),
                WeddingIdea(
                    title: "Documentary-style photographer",
                    note: "Candid photographs with a few relaxed portraits after the ceremony.",
                    category: .photography,
                    submittedBy: "Jordan",
                    estimatedCost: 2800,
                    status: .chosen
                ),
                WeddingIdea(
                    title: "Letterpress invitation suite",
                    note: "Warm ivory paper with a simple botanical detail.",
                    category: .invitations,
                    submittedBy: "Alex",
                    estimatedCost: 520,
                    status: .chosen
                ),
                WeddingIdea(
                    title: "Acoustic cocktail-hour duo",
                    note: "Guitar and vocals before the reception band begins.",
                    category: .music,
                    submittedBy: "Jordan",
                    estimatedCost: 900,
                    status: .maybe
                ),
                WeddingIdea(
                    title: "Welcome Dinner",
                    note: "A relaxed dinner for the planning circle and out-of-town family before the wedding weekend begins.",
                    category: .event,
                    submittedBy: "Alex",
                    status: .maybe,
                    configuration: .event(
                        EventIdeaConfiguration(
                            category: .reception,
                            purpose: .eventExperience,
                            proposedDate: calendar.date(byAdding: .day, value: 246, to: now),
                            location: venueLocation
                        )
                    )
                ),
                WeddingIdea(
                    title: "Weekend Getaway Fund",
                    note: "A flexible fund for a quiet first trip after the celebration.",
                    category: .registry,
                    submittedBy: "Jordan",
                    status: .new,
                    configuration: .registry(
                        RegistryIdeaConfiguration(
                            category: .cashFund,
                            price: 1_500,
                            quantity: 1
                        )
                    )
                )
            ],
            timeline: [
                TimelineItem(
                    title: "Meet with the venue coordinator",
                    category: .venue,
                    scheduledAt: calendar.date(byAdding: .day, value: 7, to: now) ?? now,
                    eventLocation: venueLocation,
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                ),
                TimelineItem(
                    title: "Plan the photographer shot list",
                    category: .ceremony,
                    scheduledAt: calendar.date(byAdding: .day, value: 26, to: now) ?? now,
                    location: "Video call",
                    participantIDs: [jordan.id, sarah.id],
                    status: .notSure
                ),
                TimelineItem(
                    title: "Finalize the guest list",
                    category: .other,
                    scheduledAt: calendar.date(byAdding: .day, value: 41, to: now) ?? now,
                    location: "Home",
                    participantIDs: [alex.id, mia.id]
                ),
                TimelineItem(
                    title: "Create inspiration boards",
                    category: .other,
                    scheduledAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                    location: "Home",
                    participantIDs: [alex.id, mia.id],
                    status: .approved,
                    completionStatus: .complete
                ),
                TimelineItem(
                    title: "Ceremony",
                    category: .ceremony,
                    purpose: .eventExperience,
                    scheduledAt: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: weddingDate) ?? weddingDate,
                    eventLocation: venueLocation,
                    endsAt: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: weddingDate),
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                ),
                TimelineItem(
                    title: "Cocktail Hour",
                    category: .reception,
                    purpose: .eventExperience,
                    scheduledAt: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: weddingDate) ?? weddingDate,
                    eventLocation: venueLocation,
                    endsAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: weddingDate),
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                ),
                TimelineItem(
                    title: "Dinner & Dancing",
                    category: .reception,
                    purpose: .eventExperience,
                    scheduledAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: weddingDate) ?? weddingDate,
                    eventLocation: venueLocation,
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                )
            ],
            registry: [
                RegistryItem(
                    title: "Weekend getaway fund",
                    note: "Help us plan a quiet first trip after the wedding.",
                    category: .cashFund,
                    price: 1_500
                ),
                RegistryItem(
                    title: "Dutch oven",
                    note: "A forever piece for Sunday dinners and sourdough experiments.",
                    category: .kitchen,
                    price: 280,
                    committedCount: 1
                ),
                RegistryItem(
                    title: "Linen sheet set",
                    note: "Soft, breathable sheets in warm ivory.",
                    category: .home,
                    price: 190,
                    quantity: 2,
                    committedCount: 1
                ),
                RegistryItem(
                    title: "Cooking class for two",
                    note: "An evening learning handmade pasta together.",
                    category: .experience,
                    price: 160
                )
            ],
            isRegistryShared: true
        )
    }
}
