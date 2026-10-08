import Foundation
import Observation

@Observable
final class WeddingWorkspace {
    var title: String
    var weddingDate: Date
    var venueName: String
    var location: String
    var planningMode: PlanningMode
    var members: [WeddingMember]
    var ideas: [WeddingIdea]
    var timeline: [TimelineItem]
    var registry: [RegistryItem]
    var isRegistryShared: Bool
    var isCollaboratorLinkEnabled: Bool
    var requiresCollaboratorApproval: Bool
    var defaultCollaboratorPermission: PlanningPermission
    var collaboratorInviteURL: URL

    private var decisionHistory: [DecisionRecord] = []

    init(
        title: String,
        weddingDate: Date,
        venueName: String,
        location: String,
        planningMode: PlanningMode,
        members: [WeddingMember],
        ideas: [WeddingIdea],
        timeline: [TimelineItem],
        registry: [RegistryItem],
        isRegistryShared: Bool = false,
        isCollaboratorLinkEnabled: Bool = true,
        requiresCollaboratorApproval: Bool = true,
        defaultCollaboratorPermission: PlanningPermission = .contribute,
        collaboratorInviteURL: URL = URL(string: "https://isaidyes.app/join/planning-circle")!
    ) {
        self.title = title
        self.weddingDate = weddingDate
        self.venueName = venueName
        self.location = location
        self.planningMode = planningMode
        self.members = members
        self.ideas = ideas
        self.timeline = timeline
        self.registry = registry
        self.isRegistryShared = isRegistryShared
        self.isCollaboratorLinkEnabled = isCollaboratorLinkEnabled
        self.requiresCollaboratorApproval = requiresCollaboratorApproval
        self.defaultCollaboratorPermission = defaultCollaboratorPermission
        self.collaboratorInviteURL = collaboratorInviteURL
    }

    var decisionQueue: [WeddingIdea] {
        ideas.filter { $0.status == .new }
    }

    var upcomingTimeline: [TimelineItem] {
        timeline
            .filter { $0.status == .upcoming }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var planningMembers: [WeddingMember] {
        members.filter { $0.participantRole != .guest }
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
        timeline[index].status = timeline[index].status == .complete ? .upcoming : .complete
    }

    func addTimelineItem(_ item: TimelineItem) {
        timeline.append(item)
    }

    func deleteTimelineItem(_ item: TimelineItem) {
        timeline.removeAll { $0.id == item.id }
    }

    func updateIdea(_ idea: WeddingIdea, status: IdeaStatus) {
        guard let index = ideas.firstIndex(where: { $0.id == idea.id }) else { return }
        ideas[index].status = status
    }

    func addIdea(_ idea: WeddingIdea) {
        ideas.insert(idea, at: 0)
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
        guard !members.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return
        }

        members.append(
            WeddingMember(
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
        )
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
            weddingDate: calendar.date(byAdding: .day, value: 248, to: now) ?? now,
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
                )
            ],
            timeline: [
                TimelineItem(
                    title: "Meet with the venue coordinator",
                    category: .venue,
                    scheduledAt: calendar.date(byAdding: .day, value: 12, to: now) ?? now,
                    location: "Willow & Stone Estate",
                    participantIDs: [alex.id, jordan.id]
                ),
                TimelineItem(
                    title: "Plan the photographer shot list",
                    category: .ceremony,
                    scheduledAt: calendar.date(byAdding: .day, value: 26, to: now) ?? now,
                    location: "Video call",
                    participantIDs: [jordan.id, sarah.id]
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
                    status: .complete
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
