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
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .new: "New"
        case .maybe: "Maybe"
        case .shortlisted: "Shortlisted"
        case .chosen: "Approved"
        case .passed: "Passed"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .new: "sparkle"
        case .maybe: "bookmark.fill"
        case .shortlisted: "heart.fill"
        case .chosen: "checkmark.seal.fill"
        case .passed: "xmark"
        case .archived: "archivebox.fill"
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
    var imageData: Data?
    var musicTrack: MusicTrack?

    init(
        id: UUID = UUID(),
        title: String,
        note: String,
        category: IdeaCategory,
        submittedBy: String,
        estimatedCost: Int? = nil,
        status: IdeaStatus = .new,
        submittedAt: Date = .now,
        imageData: Data? = nil,
        musicTrack: MusicTrack? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.category = category
        self.submittedBy = submittedBy
        self.estimatedCost = estimatedCost
        self.status = status
        self.submittedAt = submittedAt
        self.imageData = imageData
        self.musicTrack = musicTrack
    }
}

enum AttendanceStatus: String, CaseIterable, Codable {
    case invited
    case going
    case maybe
    case declined

    var title: String {
        switch self {
        case .invited: "Invited"
        case .going: "Going"
        case .maybe: "Maybe"
        case .declined: "Can't go"
        }
    }
}

enum PlanningPermission: String, CaseIterable, Identifiable, Codable {
    case manage
    case contribute
    case viewOnly

    var id: Self { self }

    static let inviteOptions: [PlanningPermission] = [.contribute, .viewOnly]

    var title: String {
        switch self {
        case .manage: "Can manage"
        case .contribute: "Can contribute"
        case .viewOnly: "View only"
        }
    }

    var detail: String {
        switch self {
        case .manage: "Can change settings and manage the planning circle."
        case .contribute: "Can add ideas, vote, and update shared plans."
        case .viewOnly: "Can follow the plans without making changes."
        }
    }

    var symbol: String {
        switch self {
        case .manage: "person.badge.key.fill"
        case .contribute: "person.badge.plus"
        case .viewOnly: "eye.fill"
        }
    }
}

enum CollaborationInvitationStatus: String, Codable {
    case active
    case invited

    var title: String {
        switch self {
        case .active: "Active"
        case .invited: "Invited"
        }
    }

    var symbol: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .invited: "paperplane.fill"
        }
    }
}

enum WeddingParticipantRole: String, CaseIterable, Identifiable, Codable {
    case host
    case collaborator
    case guest

    var id: Self { self }

    var title: String {
        switch self {
        case .host: "Host"
        case .collaborator: "Collaborator"
        case .guest: "Guest"
        }
    }

    var pluralTitle: String {
        switch self {
        case .host: "Hosts"
        case .collaborator: "Collaborators"
        case .guest: "Guests"
        }
    }

    var detail: String {
        switch self {
        case .host: "Part of the couple getting married, with full planning access."
        case .collaborator: "Helps with ideas, decisions, and the timeline."
        case .guest: "Will receive the wedding invitation when it is ready."
        }
    }

    var symbol: String {
        switch self {
        case .host: "heart.fill"
        case .collaborator: "person.2.fill"
        case .guest: "envelope.fill"
        }
    }

    var defaultPlanningPermission: PlanningPermission {
        switch self {
        case .host: .manage
        case .collaborator: .contribute
        case .guest: .viewOnly
        }
    }
}

struct WeddingMember: Identifiable, Hashable {
    let id: UUID
    var name: String
    var participantRole: WeddingParticipantRole
    var initials: String
    var attendance: AttendanceStatus
    var email: String?
    var planningPermission: PlanningPermission
    var invitationStatus: CollaborationInvitationStatus

    init(
        id: UUID = UUID(),
        name: String,
        participantRole: WeddingParticipantRole,
        initials: String,
        attendance: AttendanceStatus = .going,
        email: String? = nil,
        planningPermission: PlanningPermission = .contribute,
        invitationStatus: CollaborationInvitationStatus = .active
    ) {
        self.id = id
        self.name = name
        self.participantRole = participantRole
        self.initials = initials
        self.attendance = attendance
        self.email = email
        self.planningPermission = planningPermission
        self.invitationStatus = invitationStatus
    }
}

enum EventCompletionStatus: String, Codable {
    case upcoming
    case complete
}

enum EventStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case approved
    case notSure
    case rejected
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .approved: "Approved"
        case .notSure: "Not Sure"
        case .rejected: "Rejected"
        case .archived: "Archived"
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc.badge.ellipsis"
        case .approved: "checkmark.seal.fill"
        case .notSure: "questionmark.circle.fill"
        case .rejected: "xmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }
}

enum EventResponse: String, CaseIterable, Identifiable, Codable {
    case going
    case notSure
    case notGoing

    var id: Self { self }

    var title: String {
        switch self {
        case .going: "Going"
        case .notSure: "Not Sure"
        case .notGoing: "Can't Go"
        }
    }

    var symbol: String {
        switch self {
        case .going: "checkmark.circle.fill"
        case .notSure: "questionmark.circle.fill"
        case .notGoing: "xmark.circle.fill"
        }
    }
}

struct EventNote: Identifiable, Hashable, Codable {
    let id: UUID
    let body: String
    let sentAt: Date

    init(id: UUID = UUID(), body: String, sentAt: Date = .now) {
        self.id = id
        self.body = body
        self.sentAt = sentAt
    }
}

enum TimelineCategory: String, CaseIterable, Identifiable, Codable {
    case venue
    case foodTasting
    case attireFitting
    case weddingShower
    case bachelorBachelorette
    case rehearsal
    case ceremony
    case reception
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .venue: "Venue"
        case .foodTasting: "Food Tasting"
        case .attireFitting: "Attire Fitting"
        case .weddingShower: "Wedding Shower"
        case .bachelorBachelorette: "Bachelor or Bachelorette"
        case .rehearsal: "Rehearsal"
        case .ceremony: "Ceremony"
        case .reception: "Reception"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .venue: "building.columns.fill"
        case .foodTasting: "fork.knife"
        case .attireFitting: "tshirt.fill"
        case .weddingShower: "gift.fill"
        case .bachelorBachelorette: "party.popper.fill"
        case .rehearsal: "figure.2"
        case .ceremony: "heart.fill"
        case .reception: "music.note"
        case .other: "ellipsis.circle.fill"
        }
    }
}

enum EventPurpose: String, CaseIterable, Identifiable, Codable {
    case planning
    case eventExperience

    var id: Self { self }

    var title: String {
        switch self {
        case .planning: "Planning & Scouting"
        case .eventExperience: "Part of the Event"
        }
    }

    var shortTitle: String {
        switch self {
        case .planning: "Planning"
        case .eventExperience: "Event"
        }
    }

    var description: String {
        switch self {
        case .planning:
            "A visit, appointment, or task that helps bring the event to life."
        case .eventExperience:
            "An activity guests can attend as part of the event experience."
        }
    }

    var symbol: String {
        switch self {
        case .planning: "binoculars.fill"
        case .eventExperience: "party.popper.fill"
        }
    }
}

struct EventLocation: Hashable, Codable, Sendable {
    var address: String
    var shortAddress: String
    var placeName: String
    var locationName: String
    var addressLine2: String
    var latitude: Double?
    var longitude: Double?
    var mapItemIdentifier: String?

    init(
        address: String,
        shortAddress: String = "",
        placeName: String = "",
        locationName: String = "",
        addressLine2: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        mapItemIdentifier: String? = nil
    ) {
        self.address = address
        self.shortAddress = shortAddress
        self.placeName = placeName
        self.locationName = locationName
        self.addressLine2 = addressLine2
        self.latitude = latitude
        self.longitude = longitude
        self.mapItemIdentifier = mapItemIdentifier
    }

    var title: String {
        firstNonempty(locationName, placeName, shortAddress, address)
    }

    var detail: String {
        let values = [addressLine2, address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != title }
        return values.joined(separator: ", ")
    }

    var formatted: String {
        detail.isEmpty ? title : "\(title), \(detail)"
    }

    private func firstNonempty(_ values: String...) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Location"
    }
}

struct TimelineItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var category: TimelineCategory
    var purpose: EventPurpose
    var scheduledAt: Date
    var endsAt: Date?
    var isAllDay: Bool
    var timeZoneIdentifier: String
    var eventLocation: EventLocation?
    var participantIDs: [UUID]
    var parentEventID: UUID?
    var status: EventStatus
    var completionStatus: EventCompletionStatus
    var response: EventResponse?
    var linkedIdeaID: UUID?
    var imageData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        category: TimelineCategory,
        purpose: EventPurpose = .planning,
        scheduledAt: Date,
        location: String,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        participantIDs: [UUID],
        parentEventID: UUID? = nil,
        status: EventStatus = .draft,
        completionStatus: EventCompletionStatus = .upcoming,
        response: EventResponse? = nil,
        linkedIdeaID: UUID? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.purpose = purpose
        self.scheduledAt = scheduledAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.eventLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : EventLocation(address: location)
        self.participantIDs = participantIDs
        self.parentEventID = parentEventID
        self.status = status
        self.completionStatus = completionStatus
        self.response = response
        self.linkedIdeaID = linkedIdeaID
        self.imageData = imageData
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: TimelineCategory,
        purpose: EventPurpose = .planning,
        scheduledAt: Date,
        eventLocation: EventLocation? = nil,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        participantIDs: [UUID],
        parentEventID: UUID? = nil,
        status: EventStatus = .draft,
        completionStatus: EventCompletionStatus = .upcoming,
        response: EventResponse? = nil,
        linkedIdeaID: UUID? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.purpose = purpose
        self.scheduledAt = scheduledAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.eventLocation = eventLocation
        self.participantIDs = participantIDs
        self.parentEventID = parentEventID
        self.status = status
        self.completionStatus = completionStatus
        self.response = response
        self.linkedIdeaID = linkedIdeaID
        self.imageData = imageData
    }

    var location: String? {
        eventLocation?.title
    }
}

enum RegistryCategory: String, CaseIterable, Identifiable, Codable {
    case home
    case kitchen
    case travel
    case experience
    case cashFund

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .kitchen: "Kitchen"
        case .travel: "Travel"
        case .experience: "Experience"
        case .cashFund: "Cash fund"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .kitchen: "fork.knife"
        case .travel: "airplane"
        case .experience: "ticket.fill"
        case .cashFund: "giftcard.fill"
        }
    }
}

struct RegistryItem: Identifiable, Hashable {
    let id: UUID
    var title: String
    var note: String
    var category: RegistryCategory
    var price: Decimal
    var quantity: Int
    var committedCount: Int
    var imageData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        note: String,
        category: RegistryCategory,
        price: Decimal,
        quantity: Int = 1,
        committedCount: Int = 0,
        imageData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.category = category
        self.price = price
        self.quantity = quantity
        self.committedCount = committedCount
        self.imageData = imageData
    }

    var remainingCount: Int {
        max(quantity - committedCount, 0)
    }

    var isFulfilled: Bool {
        remainingCount == 0
    }
}
