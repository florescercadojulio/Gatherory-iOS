import Foundation

enum PlanningMode: String, CaseIterable, Identifiable, Codable {
    case openToIdeas
    case helpMeDecide
    case quietPlanning
    case decisionMade

    var id: Self { self }

    var title: String {
        switch self {
        case .openToIdeas: "Open to Ideas"
        case .helpMeDecide: "Help Me Decide"
        case .quietPlanning: "Quiet Planning"
        case .decisionMade: "Decision Made"
        }
    }

    var detail: String {
        switch self {
        case .openToIdeas: "Your circle can send inspiration."
        case .helpMeDecide: "Invite votes on selected options."
        case .quietPlanning: "Collect ideas without interruptions."
        case .decisionMade: "This planning topic is closed."
        }
    }

    var symbol: String {
        switch self {
        case .openToIdeas: "lightbulb.max.fill"
        case .helpMeDecide: "person.2.wave.2.fill"
        case .quietPlanning: "moon.stars.fill"
        case .decisionMade: "checkmark.seal.fill"
        }
    }
}

enum IdeaCategory: String, CaseIterable, Identifiable, Codable {
    case venue
    case attire
    case flowers
    case food
    case photography
    case music
    case decor
    case invitations
    case honeymoon
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .venue: "Venue"
        case .attire: "Attire"
        case .flowers: "Flowers"
        case .food: "Food & Cake"
        case .photography: "Photography"
        case .music: "Music"
        case .decor: "Decor"
        case .invitations: "Invitations"
        case .honeymoon: "Honeymoon"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .venue: "building.columns.fill"
        case .attire: "tshirt.fill"
        case .flowers: "camera.macro"
        case .food: "fork.knife"
        case .photography: "camera.fill"
        case .music: "music.note"
        case .decor: "lamp.floor.fill"
        case .invitations: "envelope.fill"
        case .honeymoon: "airplane"
        case .other: "sparkles"
        }
    }
}

enum IdeaStatus: String, CaseIterable, Identifiable, Codable {
    case new
    case maybe
    case shortlisted
    case chosen
    case passed

    var id: Self { self }

    var title: String {
        switch self {
        case .new: "New"
        case .maybe: "Maybe"
        case .shortlisted: "Shortlisted"
        case .chosen: "Chosen"
        case .passed: "Passed"
        }
    }

    var symbol: String {
        switch self {
        case .new: "sparkle"
        case .maybe: "bookmark.fill"
        case .shortlisted: "heart.fill"
        case .chosen: "checkmark.seal.fill"
        case .passed: "xmark"
        }
    }
}

enum DecisionChoice {
    case pass
    case maybe
    case love
}

struct WeddingIdea: Identifiable, Hashable {
    let id: UUID
    var title: String
    var note: String
    var category: IdeaCategory
    var submittedBy: String
    var estimatedCost: Int?
    var status: IdeaStatus
    var submittedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String,
        category: IdeaCategory,
        submittedBy: String,
        estimatedCost: Int? = nil,
        status: IdeaStatus = .new,
        submittedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.category = category
        self.submittedBy = submittedBy
        self.estimatedCost = estimatedCost
        self.status = status
        self.submittedAt = submittedAt
    }
}

struct WeddingMember: Identifiable, Hashable {
    let id: UUID
    var name: String
    var role: String
    var initials: String

    init(id: UUID = UUID(), name: String, role: String, initials: String) {
        self.id = id
        self.name = name
        self.role = role
        self.initials = initials
    }
}

enum TimelineStatus: String, Codable {
    case upcoming
    case complete
}

struct TimelineItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var dueDate: Date
    var owner: String
    var status: TimelineStatus
    var linkedIdeaID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        owner: String,
        status: TimelineStatus = .upcoming,
        linkedIdeaID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.owner = owner
        self.status = status
        self.linkedIdeaID = linkedIdeaID
    }
}
