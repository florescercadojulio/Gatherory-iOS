import Foundation
import Observation

enum BudgetAccount: Hashable {
    case freePool
    case event(EventReference)
}

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
    private(set) var ideas: [WeddingIdea]
    var timeline: [TimelineItem]
    private(set) var eventExpenses: [EventExpense]
    /// The top-level spending limit. Event allocations always add up to this cap.
    var workspaceBudgetCap: Decimal?
    /// The main event owns the portion that hasn't been allocated to child events.
    var mainEventBudgetCap: Decimal?
    var notes: [EventNote]
    var mainEventStatus: MainEventStatus
    var mainEventResponse: EventResponse?
    private(set) var eventMoments: [EventMoment]
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
        eventExpenses: [EventExpense] = [],
        workspaceBudgetCap: Decimal? = nil,
        mainEventBudgetCap: Decimal? = nil,
        notes: [EventNote] = [],
        mainEventStatus: MainEventStatus = .draft,
        mainEventResponse: EventResponse? = nil,
        eventMoments: [EventMoment] = [],
        isMainEventDeleted: Bool = false,
        registry: [RegistryItem],
        isRegistryShared: Bool = false,
        isCollaboratorLinkEnabled: Bool = true,
        requiresCollaboratorApproval: Bool = true,
        defaultCollaboratorPermission: PlanningPermission = .contribute,
        collaboratorInviteURL: URL = URL(string: "https://gatherory.app/join/planning-circle")!
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
        let scopedTimeline = timeline.map { event in
            var childEvent = event
            childEvent.parentEventID = mainEventID
            return childEvent
        }
        self.timeline = scopedTimeline
        self.eventExpenses = eventExpenses
        self.workspaceBudgetCap = workspaceBudgetCap
        let delegatedBudget = scopedTimeline.compactMap(\.budgetCap).reduce(Decimal.zero, +)
        if let mainEventBudgetCap {
            self.mainEventBudgetCap = mainEventBudgetCap
        } else if let workspaceBudgetCap {
            self.mainEventBudgetCap = max(.zero, workspaceBudgetCap - delegatedBudget)
        } else {
            self.mainEventBudgetCap = nil
        }
        self.notes = notes.map { note in
            guard note.eventID == nil else { return note }
            return EventNote(id: note.id, eventID: mainEventID, body: note.body, sentAt: note.sentAt)
        }
        self.mainEventStatus = mainEventStatus
        self.mainEventResponse = mainEventResponse
        self.eventMoments = eventMoments
        self.isMainEventDeleted = isMainEventDeleted
        self.registry = registry
        self.isRegistryShared = isRegistryShared
        self.isCollaboratorLinkEnabled = isCollaboratorLinkEnabled
        self.requiresCollaboratorApproval = requiresCollaboratorApproval
        self.defaultCollaboratorPermission = defaultCollaboratorPermission
        self.collaboratorInviteURL = collaboratorInviteURL

        // Reconcile workspaces created before undated event approvals were
        // promoted to Timeline. The linked ID keeps this migration idempotent.
        for idea in self.ideas where idea.category == .event && idea.status == .chosen {
            guard !self.timeline.contains(where: { $0.linkedIdeaID == idea.id }) else { continue }
            _ = scheduleEventIdea(idea)
        }
    }

    var decisionQueue: [WeddingIdea] {
        contextualIdeas.filter { $0.status == .new }
    }

    var availableEventContexts: [EventReference] {
        ([.main] + scheduledChildEvents.map { .subevent($0.id) })
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
        let candidates = scheduledChildEvents.filter { $0.completionStatus == .upcoming }

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

    /// The single guest-presentation policy for ideas. Approval alone does not
    /// publish a planning choice: it must also be marked for the invitation and
    /// belong to the event being viewed.
    func invitationIdeas(for reference: EventReference) -> [WeddingIdea] {
        let eventID: UUID
        switch reference {
        case .main:
            eventID = mainEventID
        case .subevent(let id):
            eventID = id
        case .idea(let ideaID):
            guard let linkedEventID = timeline.first(where: { $0.linkedIdeaID == ideaID })?.id else {
                return []
            }
            eventID = linkedEventID
        }

        return ideas
            .filter { idea in
                (idea.eventID ?? mainEventID) == eventID
                    && idea.status == .chosen
                    && idea.isShownOnInvitation
                    && idea.category.supportsInvitationVisibility
            }
            .sorted { lhs, rhs in
                if lhs.category.title == rhs.category.title {
                    return lhs.submittedAt < rhs.submittedAt
                }
                return lhs.category.title < rhs.category.title
            }
    }

    var contextualNotes: [EventNote] {
        notes.filter { ($0.eventID ?? mainEventID) == selectedEventID }
    }

    var workspaceCostTotal: Decimal {
        eventExpenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var workspaceBudgetRemaining: Decimal? {
        workspaceBudgetCap.map { $0 - workspaceCostTotal }
    }

    var allocatedBudgetTotal: Decimal {
        (mainEventBudgetCap ?? .zero)
            + timeline.compactMap(\.budgetCap).reduce(Decimal.zero, +)
    }

    var freeBudgetPool: Decimal {
        guard let workspaceBudgetCap else { return .zero }
        return max(.zero, workspaceBudgetCap - allocatedBudgetTotal)
    }

    func budgetCap(for reference: EventReference) -> Decimal? {
        switch reference {
        case .main:
            mainEventBudgetCap
        case .subevent(let id):
            timeline.first(where: { $0.id == id })?.budgetCap
        case .idea:
            nil
        }
    }

    func budgetRemaining(for reference: EventReference) -> Decimal? {
        budgetCap(for: reference).map { $0 - costTotal(for: reference) }
    }

    /// Changes the workspace cap while preserving every existing allocation.
    /// Increasing the cap adds to the free pool; a new cap starts on the main event.
    @discardableResult
    func updateWorkspaceBudgetCap(_ newCap: Decimal?) -> Bool {
        guard let newCap else {
            workspaceBudgetCap = nil
            mainEventBudgetCap = nil
            for index in timeline.indices {
                timeline[index].budgetCap = nil
            }
            return true
        }

        guard newCap >= .zero else { return false }
        let hadBudget = workspaceBudgetCap != nil
        guard !hadBudget || newCap >= allocatedBudgetTotal else { return false }
        workspaceBudgetCap = newCap
        if !hadBudget {
            mainEventBudgetCap = newCap
        }
        return true
    }

    /// Opts a child event into allocation. Removing it returns its allocation
    /// to the free pool so the workspace never loses budget capacity.
    @discardableResult
    func setEventRequiresBudget(_ requiresBudget: Bool, eventID: UUID) -> Bool {
        guard workspaceBudgetCap != nil,
              let index = timeline.firstIndex(where: { $0.id == eventID }) else {
            return false
        }

        if requiresBudget {
            timeline[index].budgetCap = timeline[index].budgetCap ?? .zero
        } else if timeline[index].budgetCap != nil {
            timeline[index].budgetCap = nil
        }
        return true
    }

    /// Allocates a requested starting budget to a newly created child event.
    /// The unallocated pool is used first, then the main event supplies the
    /// remainder. The workspace cap never changes.
    @discardableResult
    func allocateInitialBudget(_ amount: Decimal?, to eventID: UUID) -> Bool {
        guard let amount, amount > .zero,
              workspaceBudgetCap != nil,
              budgetCap(for: .subevent(eventID)) != nil else {
            return false
        }

        let poolContribution = min(freeBudgetPool, amount)
        let mainContribution = amount - poolContribution
        guard (mainEventBudgetCap ?? .zero) >= mainContribution else { return false }

        let destination = BudgetAccount.event(.subevent(eventID))
        if poolContribution > .zero,
           !transferBudget(poolContribution, from: .freePool, to: destination) {
            return false
        }

        if mainContribution > .zero,
           !transferBudget(mainContribution, from: .event(.main), to: destination) {
            return false
        }

        return true
    }

    func budgetBalance(for account: BudgetAccount) -> Decimal? {
        switch account {
        case .freePool:
            workspaceBudgetCap == nil ? nil : freeBudgetPool
        case .event(let reference):
            budgetCap(for: reference)
        }
    }

    /// Moves budget between the free pool and event allocations, or directly
    /// from one event to another. The workspace cap never changes.
    @discardableResult
    func transferBudget(
        _ amount: Decimal,
        from source: BudgetAccount,
        to destination: BudgetAccount
    ) -> Bool {
        guard workspaceBudgetCap != nil,
              source != destination,
              amount > .zero,
              let sourceBalance = budgetBalance(for: source),
              sourceBalance >= amount,
              budgetBalance(for: destination) != nil else {
            return false
        }

        switch (source, destination) {
        case (.freePool, .event(let destinationEvent)):
            guard let destinationCap = budgetCap(for: destinationEvent) else { return false }
            return setBudgetCap(destinationCap + amount, for: destinationEvent)

        case (.event(let sourceEvent), .freePool):
            guard let sourceCap = budgetCap(for: sourceEvent) else { return false }
            return setBudgetCap(sourceCap - amount, for: sourceEvent)

        case (.event(let sourceEvent), .event(let destinationEvent)):
            guard let sourceCap = budgetCap(for: sourceEvent),
                  let destinationCap = budgetCap(for: destinationEvent),
                  setBudgetCap(sourceCap - amount, for: sourceEvent) else {
                return false
            }
            return setBudgetCap(destinationCap + amount, for: destinationEvent)

        case (.freePool, .freePool):
            return false
        }
    }

    /// Moves existing budget power between events. No transfer can increase
    /// the workspace's overall cap or make a source allocation negative.
    @discardableResult
    func transferBudget(
        _ amount: Decimal,
        from source: EventReference,
        to destination: EventReference
    ) -> Bool {
        transferBudget(amount, from: .event(source), to: .event(destination))
    }

    private func setBudgetCap(_ amount: Decimal, for reference: EventReference) -> Bool {
        switch reference {
        case .main:
            mainEventBudgetCap = amount
            return true
        case .subevent(let id):
            guard let index = timeline.firstIndex(where: { $0.id == id }),
                  timeline[index].budgetCap != nil else {
                return false
            }
            timeline[index].budgetCap = amount
            return true
        case .idea:
            return false
        }
    }

    func expenses(for reference: EventReference) -> [EventExpense] {
        let eventID: UUID = switch reference {
        case .main, .idea:
            mainEventID
        case .subevent(let id):
            id
        }

        return expenses(forEventID: eventID)
    }

    func expenses(forEventID eventID: UUID) -> [EventExpense] {
        eventExpenses
            .filter { $0.eventID == eventID }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func costTotal(for reference: EventReference) -> Decimal {
        expenses(for: reference).reduce(Decimal.zero) { $0 + $1.amount }
    }

    func costTotal(status: EventExpenseStatus) -> Decimal {
        eventExpenses
            .filter { $0.status == status }
            .reduce(Decimal.zero) { $0 + $1.amount }
    }

    func replaceExpenses(_ expenses: [EventExpense], forEventID eventID: UUID) {
        eventExpenses.removeAll { $0.eventID == eventID }
        eventExpenses.append(contentsOf: expenses.map { expense in
            var scopedExpense = expense
            scopedExpense.eventID = eventID
            return scopedExpense
        })
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

    @discardableResult
    func updateParticipant(
        _ participantID: UUID,
        role: WeddingParticipantRole,
        planningPermission: PlanningPermission
    ) -> Bool {
        guard let index = members.firstIndex(where: { $0.id == participantID }) else {
            return false
        }

        guard canAssignParticipantRole(role, to: participantID) else { return false }

        members[index].participantRole = role
        members[index].planningPermission = role == .collaborator
            ? planningPermission
            : role.defaultPlanningPermission
        return true
    }

    func canAssignParticipantRole(
        _ role: WeddingParticipantRole,
        to participantID: UUID
    ) -> Bool {
        guard let member = members.first(where: { $0.id == participantID }) else {
            return false
        }

        if member.participantRole == .host,
           role != .host,
           members.filter({ $0.participantRole == .host }).count == 1 {
            return false
        }

        return true
    }

    func canRemoveParticipant(
        _ participantID: UUID,
        from reference: EventReference? = nil
    ) -> Bool {
        let target = reference ?? selectedEventReference
        guard let member = members.first(where: { $0.id == participantID }),
              participants(for: target).contains(where: { $0.id == participantID }) else {
            return false
        }

        switch target {
        case .subevent:
            return true
        case .main, .idea:
            guard member.participantRole == .host else { return true }
            return participants(for: target)
                .filter { $0.participantRole == .host }
                .count > 1
        }
    }

    @discardableResult
    func removeParticipant(
        _ participantID: UUID,
        from reference: EventReference? = nil
    ) -> Bool {
        let target = reference ?? selectedEventReference
        guard canRemoveParticipant(participantID, from: target) else { return false }

        switch target {
        case .main, .idea:
            mainEventParticipantIDs.removeAll { $0 == participantID }
        case .subevent(let eventID):
            guard let index = timeline.firstIndex(where: { $0.id == eventID }) else {
                return false
            }
            timeline[index].participantIDs.removeAll { $0 == participantID }
        }

        return true
    }

    func selectEventContext(_ reference: EventReference) {
        switch reference {
        case .main:
            selectedEventReference = .main
        case .subevent(let id):
            guard scheduledChildEvents.contains(where: { $0.id == id }) else { return }
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
            .filter {
                $0.status != .archived
                    && $0.completionStatus == .upcoming
                    && $0.hasScheduledDate
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var childEvents: [TimelineItem] {
        timeline
            .filter { $0.parentEventID == mainEventID && $0.status != .archived }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var scheduledChildEvents: [TimelineItem] {
        childEvents.filter(\.hasScheduledDate)
    }

    var approvedChildEvents: [TimelineItem] {
        scheduledChildEvents.filter { $0.status == .approved }
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

    func moments(for reference: EventReference) -> [EventMoment] {
        let eventID: UUID
        switch reference {
        case .main:
            eventID = mainEventID
        case .subevent(let id):
            eventID = id
        case .idea(let ideaID):
            guard let linkedEventID = timeline.first(where: { $0.linkedIdeaID == ideaID })?.id else {
                return []
            }
            eventID = linkedEventID
        }

        return eventMoments
            .filter { ($0.eventID ?? mainEventID) == eventID }
            .sorted { $0.addedAt > $1.addedAt }
    }

    func canAddEventMoments(to reference: EventReference) -> Bool {
        switch reference {
        case .main:
            !isMainEventDeleted && !currentMainEventStatus.isReadOnly
        case .subevent(let id):
            timeline.contains { $0.id == id && $0.status != .archived }
        case .idea(let ideaID):
            timeline.contains {
                $0.linkedIdeaID == ideaID && $0.status != .archived
            }
        }
    }

    var mainEventWindow: ClosedRange<Date> {
        let eventExperiences = timeline.filter {
            $0.parentEventID == mainEventID
                && $0.purpose == .eventExperience
                && $0.status == .approved
                && $0.hasScheduledDate
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

        var updatedIdea = ideas[index]
        updatedIdea.status = switch choice {
        case .pass: .passed
        case .maybe: .maybe
        case .love: .chosen
        }
        replaceIdea(at: index, with: updatedIdea)
    }

    func undoLastDecision() {
        guard let decision = decisionHistory.popLast(),
              let index = ideas.firstIndex(where: { $0.id == decision.ideaID }) else {
            return
        }

        var restoredIdea = ideas[index]
        restoredIdea.status = decision.previousStatus
        replaceIdea(at: index, with: restoredIdea)
    }

    func toggleTimelineItem(_ item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        timeline[index].completionStatus = timeline[index].completionStatus == .complete ? .upcoming : .complete
    }

    func addTimelineItem(_ item: TimelineItem) {
        guard canAddChildEvent(to: item.parentEventID ?? mainEventID) else { return }
        var childEvent = item
        childEvent.parentEventID = mainEventID
        if workspaceBudgetCap == nil {
            childEvent.budgetCap = nil
        } else if childEvent.budgetCap != nil {
            childEvent.budgetCap = .zero
        }
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
        let previousAllocation = timeline[index].budgetCap
        if !childEvent.hasScheduledDate,
           selectedEventReference == .subevent(childEvent.id) {
            selectedEventReference = .main
        }
        guard workspaceBudgetCap != nil else {
            childEvent.budgetCap = nil
            timeline[index] = childEvent
            return
        }
        switch (previousAllocation, childEvent.budgetCap) {
        case (.some, .none):
            break
        case (.none, .some):
            childEvent.budgetCap = .zero
        case (.some(let allocation), .some):
            // Allocation changes go through `transferBudget` so this editor
            // can't accidentally create or discard budget.
            childEvent.budgetCap = allocation
        case (.none, .none):
            break
        }
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

    func addEventMoment(_ imageData: Data, to reference: EventReference) {
        guard canAddEventMoments(to: reference) else { return }
        let eventID: UUID
        switch reference {
        case .main:
            eventID = mainEventID
        case .subevent(let id):
            eventID = id
        case .idea(let ideaID):
            guard let linkedEventID = timeline.first(where: { $0.linkedIdeaID == ideaID })?.id else {
                return
            }
            eventID = linkedEventID
        }

        let contributor = members.first?.name ?? "Guest"
        eventMoments.insert(
            EventMoment(eventID: eventID, imageData: imageData, addedBy: contributor),
            at: 0
        )
    }

    func deleteMainEvent() {
        guard canDeleteMainEvent else { return }
        isMainEventDeleted = true
        mainEventResponse = nil
        eventMoments.removeAll()
        eventExpenses.removeAll()
        timeline.removeAll { $0.parentEventID == mainEventID }
        mainEventBudgetCap = workspaceBudgetCap
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
        eventExpenses.removeAll { $0.eventID == item.id }
        eventMoments.removeAll { $0.eventID == item.id }
        if selectedEventReference == .subevent(item.id) {
            selectedEventReference = .main
        }
    }

    func updateIdea(_ idea: WeddingIdea, status: IdeaStatus) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        var updatedIdea = ideas[index]
        updatedIdea.status = status
        replaceIdea(at: index, with: updatedIdea)
    }

    func updateIdea(_ idea: WeddingIdea) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        replaceIdea(at: index, with: idea)
    }

    func addIdea(_ idea: WeddingIdea) {
        var scopedIdea = idea
        if scopedIdea.eventID == nil {
            scopedIdea.eventID = selectedEventID
        }
        ideas.insert(scopedIdea, at: 0)
        reconcileScheduledEvent(for: scopedIdea)
        reconcileExpense(for: scopedIdea)
    }

    /// Moves an approved event proposal into the timeline without duplicating
    /// it. Undated approvals remain explicit timeline items that need a date;
    /// they do not become selectable Home contexts until they are scheduled.
    @discardableResult
    func scheduleEventIdea(_ idea: WeddingIdea) -> UUID? {
        guard idea.status == .chosen,
              let configuration = idea.eventConfiguration else {
            return nil
        }

        let inheritedParticipants = mainEventParticipantIDs
        let hostParticipants = members
            .filter { $0.participantRole == .host && inheritedParticipants.contains($0.id) }
            .map(\.id)
        let participantIDs = configuration.audience == .hostsOnly && !hostParticipants.isEmpty
            ? hostParticipants
            : inheritedParticipants
        let existing = timeline.first(where: { $0.linkedIdeaID == idea.id })
        let schedulingState: EventSchedulingState = if configuration.proposedDate != nil {
            .scheduled
        } else if existing?.schedulingState == .scheduled {
            .scheduled
        } else {
            .unscheduled
        }
        let startsAt = configuration.proposedDate ?? existing?.scheduledAt ?? .now
        let item = TimelineItem(
            id: existing?.id ?? UUID(),
            title: idea.title,
            category: configuration.category,
            purpose: configuration.purpose,
            scheduledAt: startsAt,
            schedulingState: schedulingState,
            eventLocation: configuration.location,
            endsAt: configuration.proposedEndDate,
            isAllDay: configuration.isAllDay,
            timeZoneIdentifier: configuration.timeZoneIdentifier,
            participantIDs: participantIDs,
            parentEventID: mainEventID,
            status: existing?.status ?? .approved,
            completionStatus: existing?.completionStatus ?? .upcoming,
            response: existing?.response,
            linkedIdeaID: idea.id,
            imageData: idea.imageData,
            eventDescription: idea.note,
            dressCode: existing.flatMap { $0.dressCode.isEmpty ? nil : $0.dressCode }
                ?? configuration.attireDescription,
            budgetCap: existing?.budgetCap
                ?? (configuration.proposedBudget != nil || configuration.requiresBudget ? .zero : nil)
        )
        if existing == nil {
            addTimelineItem(item)
            allocateInitialBudget(configuration.proposedBudget, to: item.id)
        } else {
            updateTimelineItem(item)
        }
        return timeline.contains { $0.id == item.id } ? item.id : nil
    }

    /// This is the single write path for existing ideas. Keeping financial
    /// reconciliation here prevents individual screens from implementing
    /// their own budget behavior.
    private func replaceIdea(at index: Int, with idea: WeddingIdea) {
        ideas[index] = idea
        reconcileScheduledEvent(for: idea)
        reconcileExpense(for: idea)
    }

    /// Keeps approved event ideas and real child events as one lifecycle.
    /// Approval creates a linked event even when its date still needs to be
    /// configured; revoking approval removes only that generated event.
    private func reconcileScheduledEvent(for idea: WeddingIdea) {
        guard idea.category == .event else { return }

        if idea.status == .chosen {
            _ = scheduleEventIdea(idea)
        } else if let linkedEvent = timeline.first(where: { $0.linkedIdeaID == idea.id }) {
            deleteTimelineItem(linkedEvent)
        }
    }

    /// Mirrors one cost-bearing idea into exactly one event expense.
    /// Proposed ideas are estimated costs, while approved ideas are committed.
    /// Ideas that are passed, archived, or have no positive estimate do not
    /// consume the workspace budget.
    private func reconcileExpense(for idea: WeddingIdea) {
        let existingIndex = eventExpenses.firstIndex { $0.sourceIdeaID == idea.id }
        guard let estimate = idea.estimatedCost,
              estimate > 0,
              idea.status != .passed,
              idea.status != .archived else {
            if let existingIndex {
                eventExpenses.remove(at: existingIndex)
            }
            return
        }

        let linkedEventID = timeline.first(where: { $0.linkedIdeaID == idea.id })?.id
        let expense = EventExpense(
            id: existingIndex.map { eventExpenses[$0].id } ?? UUID(),
            eventID: linkedEventID ?? idea.eventID ?? mainEventID,
            sourceIdeaID: idea.id,
            title: idea.title,
            amount: Decimal(estimate),
            category: idea.expenseCategory,
            status: idea.status == .chosen ? .committed : .estimated,
            createdAt: existingIndex.map { eventExpenses[$0].createdAt } ?? idea.submittedAt
        )

        if let existingIndex {
            eventExpenses[existingIndex] = expense
        } else {
            eventExpenses.append(expense)
        }
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

private extension WeddingIdea {
    var expenseCategory: EventExpenseCategory {
        switch category {
        case .venue:
            .venue
        case .food:
            .foodAndDrink
        case .attire:
            .attire
        case .flowers, .decor:
            .decor
        case .music:
            .entertainment
        case .photography:
            .photography
        case .invitations:
            .stationery
        case .honeymoon:
            .travel
        case .registry:
            .gifts
        case .event:
            switch eventConfiguration?.category {
            case .venue: .venue
            case .foodTasting: .foodAndDrink
            case .photography: .photography
            case .honeymoon: .travel
            case .attireFitting: .attire
            case .reception: .entertainment
            case .weddingShower, .bachelorBachelorette, .rehearsal, .ceremony, .other, .none: .other
            }
        case .other:
            .other
        }
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
        let photographyLocation = EventLocation(
            address: "3000 Fuller Road, Ann Arbor, Michigan 48105",
            shortAddress: "Ann Arbor, MI",
            placeName: "Gallup Park",
            locationName: "Gallup Park",
            latitude: 42.2778,
            longitude: -83.6967
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

        let workspace = WeddingWorkspace(
            title: "Alex & Jordan",
            weddingDate: weddingDate,
            venueName: "Willow & Stone Estate",
            location: "Ann Arbor, Michigan",
            planningMode: .openToIdeas,
            members: [alex, jordan, sarah, mia, chris],
            ideas: [
                WeddingIdea(
                    title: "Venue",
                    note: "Garden ceremony, dinner under the trees, and space for everyone we love.",
                    category: .event,
                    submittedBy: "Alex & Jordan",
                    estimatedCost: 12_000,
                    status: .chosen,
                    configuration: .event(
                        EventIdeaConfiguration(
                            category: .venue,
                            purpose: .planning,
                            proposedDate: nil,
                            location: venueLocation
                        )
                    )
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
                    title: "Photography",
                    note: "Golden-hour portraits by the river, with room for candid photographs along the trails.",
                    category: .event,
                    submittedBy: "Jordan",
                    estimatedCost: 2800,
                    status: .chosen,
                    configuration: .event(
                        EventIdeaConfiguration(
                            category: .photography,
                            purpose: .planning,
                            proposedDate: nil,
                            location: photographyLocation
                        )
                    )
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
                    title: "Reception",
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
            workspaceBudgetCap: 30_000,
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

        if workspace.timeline.count >= 7 {
            _ = workspace.setEventRequiresBudget(true, eventID: workspace.timeline[4].id)
            _ = workspace.transferBudget(
                4_000,
                from: .main,
                to: .subevent(workspace.timeline[4].id)
            )
            _ = workspace.setEventRequiresBudget(true, eventID: workspace.timeline[6].id)
            _ = workspace.transferBudget(
                10_000,
                from: .main,
                to: .subevent(workspace.timeline[6].id)
            )
            _ = workspace.transferBudget(
                2_000,
                from: .event(.main),
                to: .freePool
            )

            workspace.eventExpenses = [
                EventExpense(
                    eventID: workspace.mainEventID,
                    title: "Venue deposit",
                    amount: 6_000,
                    category: .venue,
                    status: .paid
                ),
                EventExpense(
                    eventID: workspace.mainEventID,
                    title: "Photography package",
                    amount: 2_800,
                    category: .photography,
                    status: .committed
                ),
                EventExpense(
                    eventID: workspace.timeline[4].id,
                    title: "Ceremony musicians",
                    amount: 1_200,
                    category: .entertainment,
                    status: .estimated
                ),
                EventExpense(
                    eventID: workspace.timeline[6].id,
                    title: "Dinner service",
                    amount: 8_400,
                    category: .foodAndDrink,
                    status: .committed
                )
            ]
        }

        return workspace
    }
}
