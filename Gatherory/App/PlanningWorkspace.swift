import Foundation
import Observation

enum BudgetAccount: Hashable {
    case freePool
    case event(EventReference)
}

nonisolated struct WorkspaceMediaAttachment: Sendable {
    let entityID: UUID
    let mediaAssetID: UUID?
    let imageData: Data?
}

@Observable
final class PlanningWorkspace {
    let mainEventID: UUID
    var title: String
    var mainEventStartsAt: Date
    var mainEventEndsAt: Date?
    var mainEventIsAllDay: Bool
    var mainEventTimeZoneIdentifier: String
    var mainEventLocation: EventLocation?
    var mainEventImageData: Data?
    var mainEventMediaAssetID: UUID?
    var venueName: String
    var location: String
    var dressCode: String
    var eventMessage: String
    var planningMode: PlanningMode
    var members: [WorkspaceMember]
    /// Normalized event-to-person relationships. The legacy participant-ID
    /// arrays remain as a UI compatibility projection during the migration.
    private(set) var eventParticipations: [EventParticipation]
    var mainEventParticipantIDs: [UUID]
    private(set) var ideas: [PlanningIdea]
    var timeline: [TimelineItem]
    private(set) var eventExpenses: [EventExpense]
    /// The top-level spending limit. Event allocations always add up to this cap.
    var workspaceBudgetCap: Decimal?
    /// ISO 4217 code shared by every monetary amount in this workspace.
    var currencyCode: String
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

    /// The signed-in account is runtime presentation context, not persisted
    /// workspace data. Keeping only its stable identity here lets every feature
    /// enforce the same participant perspective without coupling archives to an
    /// authentication session.
    private var viewerUserID: String?
    private var viewerEmail: String?
    private var isViewerConfigured = false

    private var decisionHistory: [DecisionRecord] = []

    init(
        mainEventID: UUID = UUID(),
        title: String,
        mainEventStartsAt: Date,
        mainEventEndsAt: Date? = nil,
        mainEventIsAllDay: Bool = false,
        mainEventTimeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        mainEventLocation: EventLocation? = nil,
        mainEventImageData: Data? = nil,
        mainEventMediaAssetID: UUID? = nil,
        venueName: String,
        location: String,
        dressCode: String = "Garden formal",
        eventMessage: String = "We’re looking forward to sharing this experience with you.",
        planningMode: PlanningMode,
        members: [WorkspaceMember],
        eventParticipations: [EventParticipation]? = nil,
        mainEventParticipantIDs: [UUID]? = nil,
        ideas: [PlanningIdea],
        timeline: [TimelineItem],
        eventExpenses: [EventExpense] = [],
        workspaceBudgetCap: Decimal? = nil,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
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
        self.mainEventStartsAt = mainEventStartsAt
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
        self.mainEventMediaAssetID = mainEventMediaAssetID
        self.venueName = venueName
        self.location = location
        self.dressCode = dressCode
        self.eventMessage = eventMessage
        self.planningMode = planningMode
        self.members = members
        let validMemberIDs = Set(members.map(\.id))
        let normalizedMainParticipantIDs = (mainEventParticipantIDs ?? members.map(\.id))
            .reduce(into: [UUID]()) { result, id in
                guard validMemberIDs.contains(id), !result.contains(id) else { return }
                result.append(id)
            }
        self.mainEventParticipantIDs = normalizedMainParticipantIDs
        let scopedIdeas = ideas.map { idea in
            var scopedIdea = idea
            if scopedIdea.eventID == nil {
                scopedIdea.eventID = mainEventID
            }
            return scopedIdea
        }
        self.ideas = Self.normalizedIdeas(scopedIdeas, mainEventID: mainEventID)
        let scopedTimeline = timeline.map { event in
            var childEvent = event
            childEvent.parentEventID = mainEventID
            childEvent.participantIDs = childEvent.participantIDs
                .reduce(into: [UUID]()) { result, id in
                    guard validMemberIDs.contains(id), !result.contains(id) else { return }
                    result.append(id)
                }
            return childEvent
        }
        self.timeline = scopedTimeline
        let validEventIDs = Set([mainEventID] + scopedTimeline.map(\.id))
        var normalizedParticipations: [EventParticipation] = []
        for participation in eventParticipations ?? []
        where validEventIDs.contains(participation.eventID)
            && validMemberIDs.contains(participation.memberID)
            && !normalizedParticipations.contains(where: {
                $0.eventID == participation.eventID
                    && $0.memberID == participation.memberID
            }) {
            normalizedParticipations.append(participation)
        }

        let participantIDsByEvent = [(mainEventID, normalizedMainParticipantIDs)]
            + scopedTimeline.map { ($0.id, $0.participantIDs) }
        for (eventID, participantIDs) in participantIDsByEvent {
            for memberID in participantIDs where !normalizedParticipations.contains(where: {
                $0.eventID == eventID && $0.memberID == memberID
            }) {
                guard let member = members.first(where: { $0.id == memberID }) else { continue }
                normalizedParticipations.append(
                    EventParticipation(
                        eventID: eventID,
                        memberID: memberID,
                        role: member.participantRole,
                        planningPermission: member.planningPermission,
                        attendance: member.attendance,
                        invitationStatus: member.invitationStatus
                    )
                )
            }
        }
        self.eventParticipations = normalizedParticipations
        self.eventExpenses = eventExpenses
        self.workspaceBudgetCap = workspaceBudgetCap
        let normalizedCurrencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.currencyCode = normalizedCurrencyCode.count == 3 ? normalizedCurrencyCode : "USD"
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
            return EventNote(
                id: note.id,
                eventID: mainEventID,
                authorUserID: note.authorUserID,
                body: note.body,
                sentAt: note.sentAt
            )
        }
        self.mainEventStatus = mainEventStatus
        self.mainEventResponse = mainEventResponse
        self.eventMoments = eventMoments
        self.isMainEventDeleted = isMainEventDeleted
        self.registry = registry.map { item in
            var scopedItem = item
            if scopedItem.eventID == nil {
                scopedItem.eventID = mainEventID
            }
            return scopedItem
        }
        self.isRegistryShared = isRegistryShared
        self.isCollaboratorLinkEnabled = isCollaboratorLinkEnabled
        self.requiresCollaboratorApproval = requiresCollaboratorApproval
        self.defaultCollaboratorPermission = defaultCollaboratorPermission
        self.collaboratorInviteURL = collaboratorInviteURL

        // Dated, approved event ideas are the only ideas that become Home
        // events. Older local workspaces could contain linked undated items;
        // remove those duplicates because the proposal remains in Ideas.
        self.timeline.removeAll { item in
            guard let linkedIdeaID = item.linkedIdeaID,
                  let idea = self.ideas.first(where: { $0.id == linkedIdeaID }) else {
                return false
            }
            return idea.category == .event
                && idea.status == .chosen
                && idea.eventConfiguration?.proposedDate == nil
        }

        // Reconcile dated approvals created before the current event-idea
        // lifecycle. The linked ID keeps this migration idempotent.
        for idea in self.ideas where idea.category == .event && idea.status == .chosen {
            guard idea.eventConfiguration?.proposedDate != nil else { continue }
            guard !self.timeline.contains(where: { $0.linkedIdeaID == idea.id }) else { continue }
            _ = scheduleEventIdea(idea)
        }
    }

    var decisionQueue: [PlanningIdea] {
        decisionQueue(for: nil)
    }

    /// The decision deck is workspace-wide. Event context controls where new
    /// ideas are created and viewed, but it must not hide another event's
    /// pending decision.
    func decisionQueue(for eventID: UUID?) -> [PlanningIdea] {
        ideas
            .filter { idea in
                guard idea.status == .new else { return false }
                guard let eventID else { return true }
                return (idea.eventID ?? mainEventID) == eventID
            }
            .sorted {
                if $0.submittedAt != $1.submittedAt {
                    return $0.submittedAt > $1.submittedAt
                }
                return $0.id.uuidString > $1.id.uuidString
            }
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

    /// Planners see the complete event plan. Guests only see invitations for
    /// events in which they have an explicit participation relationship.
    var visibleEventContexts: [EventReference] {
        guard !showsPlanningInterface else { return availableEventContexts }
        return availableEventContexts.filter { currentViewerMember(for: $0) != nil }
    }

    /// Resolves the signed-in account to this workspace's normalized person.
    /// Unconfigured workspaces retain the first-member fallback for previews,
    /// migration tests, and locally-created workspaces before the app shell has
    /// attached its authentication context.
    var currentViewerMember: WorkspaceMember? {
        identityMember
    }

    var showsPlanningInterface: Bool {
        guard let member = currentViewerMember(for: .main) else { return false }
        return member.participantRole != .guest
    }

    var isGuestViewer: Bool {
        !showsPlanningInterface
    }

    func configureViewer(_ account: UserAccount?) {
        isViewerConfigured = true
        viewerUserID = account?.id
        viewerEmail = account?.email

        if !visibleEventContexts.contains(selectedEventReference),
           let firstVisibleEvent = visibleEventContexts.first {
            selectedEventReference = firstVisibleEvent
        }
    }

    func currentViewerMember(for reference: EventReference) -> WorkspaceMember? {
        guard let identityMember else { return nil }
        return participants(for: reference).first { $0.id == identityMember.id }
    }

    private var identityMember: WorkspaceMember? {
        guard isViewerConfigured else { return members.first }

        return members.first { member in
            if let viewerUserID, member.userID == viewerUserID {
                return true
            }

            guard let viewerEmail, let memberEmail = member.email else { return false }
            return memberEmail.caseInsensitiveCompare(viewerEmail) == .orderedSame
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

    func eventTitle(for eventID: UUID) -> String {
        guard eventID != mainEventID else { return title }
        return timeline.first(where: { $0.id == eventID })?.title ?? title
    }

    func eventTitle(for idea: PlanningIdea) -> String {
        eventTitle(for: idea.eventID ?? mainEventID)
    }

    var contextualIdeas: [PlanningIdea] {
        ideas.filter { ($0.eventID ?? mainEventID) == selectedEventID }
    }

    /// Music is an event resource, not a set of competing proposals. There is
    /// exactly one shared playlist aggregate for each event context.
    func musicPlaylist(for eventID: UUID) -> PlanningIdea? {
        ideas.first {
            $0.category == .music && ($0.eventID ?? mainEventID) == eventID
        }
    }

    /// A playlist is a living event resource. It stays open while its event is
    /// being planned or underway, then becomes read-only with the completed
    /// event so the published soundtrack remains an accurate record.
    func canEditMusicPlaylist(for playlist: PlanningIdea) -> Bool {
        canEditMusicPlaylist(forEventID: playlist.eventID ?? mainEventID)
    }

    func canEditMusicPlaylist(forEventID eventID: UUID) -> Bool {
        if eventID == mainEventID {
            return canManageEvent(.main)
        }

        return canManageEvent(.subevent(eventID))
    }

    /// The single guest-presentation policy for ideas. Approval alone does not
    /// publish a planning choice: it must also be marked for the invitation and
    /// belong to the event being viewed.
    func invitationIdeas(for reference: EventReference) -> [PlanningIdea] {
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

    func participants(for reference: EventReference) -> [WorkspaceMember] {
        let eventID = participantEventID(for: reference)
        let relationships = eventParticipations.filter { $0.eventID == eventID }
        let relationshipsByMemberID = Dictionary(
            uniqueKeysWithValues: relationships.map { ($0.memberID, $0) }
        )

        return members.compactMap { member in
            guard let participation = relationshipsByMemberID[member.id] else { return nil }
            var contextualMember = member
            contextualMember.participantRole = participation.role
            contextualMember.planningPermission = participation.planningPermission
            contextualMember.attendance = participation.attendance
            contextualMember.invitationStatus = participation.invitationStatus
            return contextualMember
        }
    }

    var selectedEventCoordinators: [WorkspaceMember] {
        participants(for: selectedEventReference)
            .filter { $0.participantRole != .guest }
    }

    var selectedEventParticipants: [WorkspaceMember] {
        participants(for: selectedEventReference)
    }

    func addParticipant(_ participantID: UUID, to reference: EventReference? = nil) {
        guard let member = members.first(where: { $0.id == participantID }) else { return }

        let target = reference ?? selectedEventReference
        let eventID = participantEventID(for: target)
        guard eventID == mainEventID || timeline.contains(where: { $0.id == eventID }) else {
            return
        }
        guard !eventParticipations.contains(where: {
            $0.eventID == eventID && $0.memberID == participantID
        }) else { return }

        eventParticipations.append(
            EventParticipation(
                eventID: eventID,
                memberID: participantID,
                role: member.participantRole,
                planningPermission: member.planningPermission,
                attendance: member.attendance,
                invitationStatus: member.invitationStatus
            )
        )
        setParticipantProjection(participantID, eventID: eventID, isIncluded: true)
    }

    @discardableResult
    func updateParticipant(
        _ participantID: UUID,
        role: WorkspaceRole,
        planningPermission: PlanningPermission,
        in reference: EventReference? = nil
    ) -> Bool {
        guard members.contains(where: { $0.id == participantID }) else {
            return false
        }

        let target = reference ?? selectedEventReference
        guard canAssignParticipantRole(role, to: participantID, in: target) else { return false }
        let eventID = participantEventID(for: target)
        guard let participationIndex = eventParticipations.firstIndex(where: {
            $0.eventID == eventID && $0.memberID == participantID
        }) else { return false }

        eventParticipations[participationIndex].role = role
        eventParticipations[participationIndex].planningPermission = role == .collaborator
            ? planningPermission
            : role.defaultPlanningPermission
        eventParticipations[participationIndex].updatedAt = .now

        // Preserve the original fields as main-event defaults for code that has
        // not yet moved to the relationship projection.
        if eventID == mainEventID,
           let memberIndex = members.firstIndex(where: { $0.id == participantID }) {
            members[memberIndex].participantRole = role
            members[memberIndex].planningPermission = eventParticipations[participationIndex].planningPermission
        }
        return true
    }

    func canAssignParticipantRole(
        _ role: WorkspaceRole,
        to participantID: UUID,
        in reference: EventReference? = nil
    ) -> Bool {
        let target = reference ?? selectedEventReference
        guard let member = participants(for: target).first(where: { $0.id == participantID }) else {
            return false
        }

        if member.participantRole == .host,
           role != .host,
           participants(for: target).filter({ $0.participantRole == .host }).count == 1 {
            return false
        }

        return true
    }

    func canRemoveParticipant(
        _ participantID: UUID,
        from reference: EventReference? = nil
    ) -> Bool {
        let target = reference ?? selectedEventReference
        guard let member = participants(for: target).first(where: { $0.id == participantID }) else {
            return false
        }

        if participantEventID(for: target) != mainEventID {
            return true
        }

        guard member.participantRole == .host else { return true }
        return participants(for: target)
            .filter { $0.participantRole == .host }
            .count > 1
    }

    @discardableResult
    func removeParticipant(
        _ participantID: UUID,
        from reference: EventReference? = nil
    ) -> Bool {
        let target = reference ?? selectedEventReference
        guard canRemoveParticipant(participantID, from: target) else { return false }

        let eventID = participantEventID(for: target)
        setParticipantProjection(participantID, eventID: eventID, isIncluded: false)
        eventParticipations.removeAll {
            $0.eventID == eventID && $0.memberID == participantID
        }

        return true
    }

    private func participantEventID(for reference: EventReference) -> UUID {
        switch reference {
        case .main:
            mainEventID
        case .subevent(let id):
            id
        case .idea(let ideaID):
            ideas.first(where: { $0.id == ideaID })?.eventID ?? mainEventID
        }
    }

    /// Keeps the temporary participant-ID arrays in lockstep while older views
    /// migrate to the normalized relationship collection.
    private func setParticipantProjection(
        _ participantID: UUID,
        eventID: UUID,
        isIncluded: Bool
    ) {
        if eventID == mainEventID {
            mainEventParticipantIDs.removeAll { $0 == participantID }
            if isIncluded { mainEventParticipantIDs.append(participantID) }
            return
        }

        guard let index = timeline.firstIndex(where: { $0.id == eventID }) else { return }
        timeline[index].participantIDs.removeAll { $0 == participantID }
        if isIncluded { timeline[index].participantIDs.append(participantID) }
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
            mainEventStartsAt
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

    var planningMembers: [WorkspaceMember] {
        members.filter { $0.participantRole != .guest }
    }

    var canManageMainEvent: Bool {
        canManageEvent(.main)
    }

    var canDeleteMainEvent: Bool {
        showsPlanningInterface && mainEventStatus == .draft
    }

    func canManageEvent(_ reference: EventReference) -> Bool {
        guard showsPlanningInterface else { return false }

        switch reference {
        case .main:
            return !isMainEventDeleted && !mainEventStatus.isReadOnly
        case .subevent(let id):
            return timeline.contains {
                $0.id == id
                    && $0.status != .archived
                    && $0.completionStatus != .complete
            }
        case .idea:
            return false
        }
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
        let starts = [mainEventStartsAt] + eventExperiences.map(\.scheduledAt)
        let ends = [mainEventEndsAt ?? mainEventStartsAt] + eventExperiences.map {
            $0.endsAt ?? $0.scheduledAt
        }
        return (starts.min() ?? mainEventStartsAt)...(ends.max() ?? mainEventStartsAt)
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

    func decide(_ choice: DecisionChoice, on idea: PlanningIdea) {
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
        reconcileParticipations(for: childEvent.id, participantIDs: childEvent.participantIDs)
    }

    func updateTimelineItem(_ item: TimelineItem) {
        guard let index = timeline.firstIndex(where: { $0.id == item.id }) else { return }
        guard canAddChildEvent(to: item.parentEventID ?? mainEventID) else { return }
        var childEvent = item
        childEvent.parentEventID = mainEventID
        if timeline[index].imageData != childEvent.imageData {
            childEvent.mediaAssetID = nil
        }
        let previousAllocation = timeline[index].budgetCap
        if !childEvent.hasScheduledDate,
           selectedEventReference == .subevent(childEvent.id) {
            selectedEventReference = .main
        }
        guard workspaceBudgetCap != nil else {
            childEvent.budgetCap = nil
            timeline[index] = childEvent
            reconcileParticipations(for: childEvent.id, participantIDs: childEvent.participantIDs)
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
        reconcileParticipations(for: childEvent.id, participantIDs: childEvent.participantIDs)
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
        mainEventStartsAt = startsAt
        mainEventEndsAt = endsAt
        mainEventIsAllDay = isAllDay
        mainEventTimeZoneIdentifier = timeZoneIdentifier
        mainEventLocation = eventLocation
        if mainEventImageData != imageData {
            mainEventMediaAssetID = nil
        }
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

        let contributor = currentViewerMember?.name ?? "Guest"
        eventMoments.insert(
            EventMoment(eventID: eventID, imageData: imageData, addedBy: contributor),
            at: 0
        )
    }

    var mediaAttachments: [WorkspaceMediaAttachment] {
        var attachments = [
            WorkspaceMediaAttachment(
                entityID: mainEventID,
                mediaAssetID: mainEventMediaAssetID,
                imageData: mainEventImageData
            )
        ]
        attachments += timeline.map {
            WorkspaceMediaAttachment(entityID: $0.id, mediaAssetID: $0.mediaAssetID, imageData: $0.imageData)
        }
        attachments += ideas.map {
            WorkspaceMediaAttachment(entityID: $0.id, mediaAssetID: $0.mediaAssetID, imageData: $0.imageData)
        }
        attachments += registry.map {
            WorkspaceMediaAttachment(entityID: $0.id, mediaAssetID: $0.mediaAssetID, imageData: $0.imageData)
        }
        attachments += eventMoments.map {
            WorkspaceMediaAttachment(entityID: $0.id, mediaAssetID: $0.mediaAssetID, imageData: $0.imageData)
        }
        return attachments
    }

    @discardableResult
    func applyMediaAssetID(_ mediaAssetID: UUID, to entityID: UUID) -> Bool {
        if entityID == mainEventID {
            mainEventMediaAssetID = mediaAssetID
            return true
        }
        if let index = timeline.firstIndex(where: { $0.id == entityID }) {
            timeline[index].mediaAssetID = mediaAssetID
            return true
        }
        if let index = ideas.firstIndex(where: { $0.id == entityID }) {
            ideas[index].mediaAssetID = mediaAssetID
            return true
        }
        if let index = registry.firstIndex(where: { $0.id == entityID }) {
            registry[index].mediaAssetID = mediaAssetID
            return true
        }
        if let index = eventMoments.firstIndex(where: { $0.id == entityID }) {
            eventMoments[index].mediaAssetID = mediaAssetID
            return true
        }
        return false
    }

    @discardableResult
    func applyDownloadedMedia(_ imageData: Data, to entityID: UUID) -> Bool {
        if entityID == mainEventID {
            mainEventImageData = imageData
            return true
        }
        if let index = timeline.firstIndex(where: { $0.id == entityID }) {
            timeline[index].imageData = imageData
            return true
        }
        if let index = ideas.firstIndex(where: { $0.id == entityID }) {
            ideas[index].imageData = imageData
            return true
        }
        if let index = registry.firstIndex(where: { $0.id == entityID }) {
            registry[index].imageData = imageData
            return true
        }
        if let index = eventMoments.firstIndex(where: { $0.id == entityID }) {
            eventMoments[index].imageData = imageData
            return true
        }
        return false
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
        eventParticipations.removeAll { $0.eventID == item.id }
        ideas.removeAll { $0.eventID == item.id }
        eventExpenses.removeAll { $0.eventID == item.id }
        notes.removeAll { $0.eventID == item.id }
        eventMoments.removeAll { $0.eventID == item.id }
        registry.removeAll { $0.eventID == item.id }
        if selectedEventReference == .subevent(item.id) {
            selectedEventReference = .main
        }
    }

    func updateIdea(_ idea: PlanningIdea, status: IdeaStatus) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        var updatedIdea = ideas[index]
        updatedIdea.status = updatedIdea.category == .music ? .chosen : status
        replaceIdea(at: index, with: updatedIdea)
    }

    func updateIdea(_ idea: PlanningIdea) {
        if idea.category == .music {
            upsertMusicPlaylist(idea)
            return
        }
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        replaceIdea(at: index, with: idea)
    }

    func addIdea(_ idea: PlanningIdea) {
        var scopedIdea = idea
        if scopedIdea.category == .event {
            // Event ideas become first-level sub-events when approved. Never
            // attach one to an existing child event, because the event tree
            // deliberately stops at two levels.
            scopedIdea.eventID = mainEventID
        } else if scopedIdea.eventID == nil {
            scopedIdea.eventID = selectedEventID
        }
        if scopedIdea.category == .music {
            upsertMusicPlaylist(scopedIdea)
            return
        }
        ideas.insert(scopedIdea, at: 0)
        reconcileScheduledEvent(for: scopedIdea)
        reconcileExpense(for: scopedIdea)
    }

    /// Promotes a dated, approved event proposal into a Home event without
    /// duplicating it. Undated approvals remain in Ideas until a date is set.
    @discardableResult
    func scheduleEventIdea(_ idea: PlanningIdea) -> UUID? {
        guard idea.status == .chosen,
              let configuration = idea.eventConfiguration,
              let proposedDate = configuration.proposedDate else {
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
        let item = TimelineItem(
            id: existing?.id ?? UUID(),
            title: idea.title,
            category: configuration.category,
            purpose: configuration.purpose,
            scheduledAt: proposedDate,
            schedulingState: .scheduled,
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
    private func replaceIdea(at index: Int, with idea: PlanningIdea) {
        var updated = idea
        if ideas[index].imageData != updated.imageData {
            updated.mediaAssetID = nil
        }
        ideas[index] = updated
        reconcileScheduledEvent(for: updated)
        reconcileExpense(for: updated)
    }

    private func upsertMusicPlaylist(_ playlist: PlanningIdea) {
        let eventID = playlist.eventID ?? selectedEventID
        guard canEditMusicPlaylist(forEventID: eventID) else { return }
        let matchingIndices = ideas.indices.filter {
            ideas[$0].category == .music
                && (ideas[$0].eventID ?? mainEventID) == eventID
        }

        var updated = playlist
        updated.eventID = eventID
        updated.status = .chosen
        updated.estimatedCost = nil
        updated.invitationVisibility = .shownToGuests

        guard let canonicalIndex = matchingIndices.first else {
            ideas.insert(updated, at: 0)
            reconcileExpense(for: updated)
            return
        }

        var canonical = ideas[canonicalIndex]
        canonical.title = updated.title
        canonical.note = updated.note
        canonical.submittedBy = updated.submittedBy
        canonical.submittedByUserID = updated.submittedByUserID
        canonical.status = .chosen
        canonical.imageData = updated.imageData
        canonical.estimatedCost = nil
        canonical.invitationVisibility = .shownToGuests
        canonical.configuration = .music(
            MusicIdeaConfiguration(
                tracks: canonical.id == updated.id
                    ? updated.musicTracks
                    : Self.mergedMusicTracks(canonical.musicTracks, updated.musicTracks)
            )
        )

        for index in matchingIndices.dropFirst().reversed() {
            ideas.remove(at: index)
        }
        if let submittedIndex = ideas.firstIndex(where: { $0.id == playlist.id }),
           submittedIndex != canonicalIndex {
            ideas.remove(at: submittedIndex)
        }
        guard let resolvedIndex = ideas.firstIndex(where: { $0.id == canonical.id }) else { return }
        replaceIdea(at: resolvedIndex, with: canonical)
    }

    private static func normalizedIdeas(
        _ ideas: [PlanningIdea],
        mainEventID: UUID
    ) -> [PlanningIdea] {
        var normalized: [PlanningIdea] = []
        var playlistIndexByEventID: [UUID: Int] = [:]

        for var idea in ideas {
            let eventID = idea.eventID ?? mainEventID
            idea.eventID = eventID
            guard idea.category == .music else {
                normalized.append(idea)
                continue
            }

            idea.status = .chosen
            idea.estimatedCost = nil
            idea.invitationVisibility = .shownToGuests
            if let existingIndex = playlistIndexByEventID[eventID] {
                var playlist = normalized[existingIndex]
                playlist.configuration = .music(
                    MusicIdeaConfiguration(
                        tracks: mergedMusicTracks(playlist.musicTracks, idea.musicTracks)
                    )
                )
                normalized[existingIndex] = playlist
            } else {
                playlistIndexByEventID[eventID] = normalized.count
                normalized.append(idea)
            }
        }

        return normalized
    }

    private static func mergedMusicTracks(
        _ lhs: [MusicTrack],
        _ rhs: [MusicTrack]
    ) -> [MusicTrack] {
        (lhs + rhs).reduce(into: [MusicTrack]()) { tracks, track in
            guard !tracks.contains(where: { $0.id == track.id }) else { return }
            tracks.append(track)
        }
    }

    /// Keeps approved event ideas and dated Home events as one lifecycle.
    /// A date promotes an approved idea; removing that date returns it to
    /// Ideas. Revoking approval removes only that generated event.
    private func reconcileScheduledEvent(for idea: PlanningIdea) {
        guard idea.category == .event else { return }

        if idea.status == .chosen, idea.eventConfiguration?.proposedDate != nil {
            _ = scheduleEventIdea(idea)
        } else if let linkedEvent = timeline.first(where: { $0.linkedIdeaID == idea.id }) {
            deleteTimelineItem(linkedEvent)
        }
    }

    /// Mirrors one cost-bearing idea into exactly one event expense.
    /// Proposed ideas are estimated costs, while approved ideas are committed.
    /// Ideas that are passed, archived, or have no positive estimate do not
    /// consume the workspace budget.
    private func reconcileExpense(for idea: PlanningIdea) {
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
            amount: estimate,
            category: idea.expenseCategory,
            status: idea.status == .chosen ? .committed : .estimated,
            createdByUserID: existingIndex.flatMap { eventExpenses[$0].createdByUserID }
                ?? idea.submittedByUserID,
            createdAt: existingIndex.map { eventExpenses[$0].createdAt } ?? idea.submittedAt,
            updatedAt: .now
        )

        if let existingIndex {
            eventExpenses[existingIndex] = expense
        } else {
            eventExpenses.append(expense)
        }
    }

    func addRegistryItem(_ item: RegistryItem) {
        var scopedItem = item
        scopedItem.eventID = scopedItem.eventID ?? selectedEventID
        registry.append(scopedItem)
    }

    func updateRegistryItem(_ item: RegistryItem) {
        guard let index = registry.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        if registry[index].imageData != updated.imageData {
            updated.mediaAssetID = nil
        }
        registry[index] = updated
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
        role: WorkspaceRole
    ) {
        if let existingMember = members.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            addParticipant(existingMember.id)
            return
        }

        let member = WorkspaceMember(
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

    private func reconcileParticipations(for eventID: UUID, participantIDs: [UUID]) {
        let validIDs = Set(participantIDs).intersection(members.map(\.id))
        eventParticipations.removeAll {
            $0.eventID == eventID && !validIDs.contains($0.memberID)
        }

        for memberID in validIDs where !eventParticipations.contains(where: {
            $0.eventID == eventID && $0.memberID == memberID
        }) {
            guard let member = members.first(where: { $0.id == memberID }) else { continue }
            let inherited = eventParticipations.first {
                $0.eventID == mainEventID && $0.memberID == memberID
            }
            eventParticipations.append(
                EventParticipation(
                    eventID: eventID,
                    memberID: memberID,
                    role: inherited?.role ?? member.participantRole,
                    planningPermission: inherited?.planningPermission ?? member.planningPermission,
                    attendance: inherited?.attendance ?? member.attendance,
                    invitationStatus: inherited?.invitationStatus ?? member.invitationStatus
                )
            )
        }
    }
}

private extension PlanningIdea {
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
        case .link, .other:
            .other
        }
    }
}

private struct DecisionRecord {
    let ideaID: UUID
    let previousStatus: IdeaStatus
}

extension PlanningWorkspace {
    static var sample: PlanningWorkspace {
        let calendar = Calendar.current
        let now = Date.now
        let mainEventStartsAt = calendar.date(byAdding: .day, value: 248, to: now) ?? now
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
        let alex = WorkspaceMember(
            name: "Alex",
            participantRole: .host,
            initials: "A",
            planningPermission: .manage
        )
        let jordan = WorkspaceMember(
            name: "Jordan",
            participantRole: .host,
            initials: "J",
            planningPermission: .manage
        )
        let sarah = WorkspaceMember(name: "Sarah", participantRole: .collaborator, initials: "S")
        let mia = WorkspaceMember(name: "Mia", participantRole: .collaborator, initials: "M")
        let chris = WorkspaceMember(
            name: "Chris",
            participantRole: .guest,
            initials: "C",
            attendance: .invited,
            planningPermission: .viewOnly
        )

        let workspace = PlanningWorkspace(
            title: "Alex & Jordan’s Wedding",
            mainEventStartsAt: mainEventStartsAt,
            venueName: "Willow & Stone Estate",
            location: "Ann Arbor, Michigan",
            planningMode: .openToIdeas,
            members: [alex, jordan, sarah, mia, chris],
            ideas: [
                PlanningIdea(
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
                PlanningIdea(
                    title: "Garden ceremony lighting",
                    note: "Warm string lights through the trees for the ceremony and dinner.",
                    category: .decor,
                    submittedBy: "Sarah",
                    estimatedCost: 400
                ),
                PlanningIdea(
                    title: "Wildflower table arrangements",
                    note: "Loose seasonal flowers in small mismatched glass vases.",
                    category: .flowers,
                    submittedBy: "Mia",
                    estimatedCost: 650
                ),
                PlanningIdea(
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
                PlanningIdea(
                    title: "Letterpress invitation suite",
                    note: "Warm ivory paper with a simple botanical detail.",
                    category: .invitations,
                    submittedBy: "Alex",
                    estimatedCost: 520,
                    status: .chosen
                ),
                PlanningIdea(
                    title: "Alex & Jordan’s Wedding Playlist",
                    note: "Add songs that will keep the dance floor moving all night.",
                    category: .music,
                    submittedBy: "Jordan",
                    status: .chosen,
                    configuration: .music(MusicIdeaConfiguration(tracks: [])),
                    invitationVisibility: .shownToGuests
                ),
                PlanningIdea(
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
                PlanningIdea(
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
                    scheduledAt: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: mainEventStartsAt) ?? mainEventStartsAt,
                    eventLocation: venueLocation,
                    endsAt: calendar.date(bySettingHour: 16, minute: 30, second: 0, of: mainEventStartsAt),
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                ),
                TimelineItem(
                    title: "Cocktail Hour",
                    category: .reception,
                    purpose: .eventExperience,
                    scheduledAt: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: mainEventStartsAt) ?? mainEventStartsAt,
                    eventLocation: venueLocation,
                    endsAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: mainEventStartsAt),
                    participantIDs: [alex.id, jordan.id],
                    status: .approved
                ),
                TimelineItem(
                    title: "Dinner & Dancing",
                    category: .reception,
                    purpose: .eventExperience,
                    scheduledAt: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: mainEventStartsAt) ?? mainEventStartsAt,
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
