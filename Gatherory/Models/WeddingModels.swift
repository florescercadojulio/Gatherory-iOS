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
    case event
    case registry
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
        case .event: "Event"
        case .registry: "Registry"
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
        case .event: "calendar.badge.plus"
        case .registry: "gift.fill"
        case .venue: "building.2.fill"
        case .attire: "hanger"
        case .flowers: "camera.macro"
        case .food: "fork.knife"
        case .photography: "camera.aperture"
        case .music: "music.note.list"
        case .decor: "lamp.ceiling.fill"
        case .invitations: "envelope.open.fill"
        case .honeymoon: "suitcase.rolling.fill"
        case .other: "ellipsis.circle.fill"
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

enum AttireStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case any
    case blackTie
    case formal
    case cocktail
    case garden
    case casual

    var id: Self { self }

    var title: String {
        switch self {
        case .any: "Any"
        case .blackTie: "Black Tie"
        case .formal: "Formal"
        case .cocktail: "Cocktail"
        case .garden: "Garden"
        case .casual: "Casual"
        }
    }
}

struct AttireIdeaConfiguration: Codable, Hashable {
    var style: AttireStyle
    var restrictions: String
}

enum FoodIdeaType: String, CaseIterable, Identifiable, Codable, Hashable {
    case meal
    case cake
    case dessert
    case drinks
    case tasting
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .meal: "Meal"
        case .cake: "Cake"
        case .dessert: "Dessert"
        case .drinks: "Drinks"
        case .tasting: "Tasting"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .meal: "fork.knife"
        case .cake: "birthday.cake.fill"
        case .dessert: "takeoutbag.and.cup.and.straw.fill"
        case .drinks: "wineglass.fill"
        case .tasting: "checklist"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct FoodIdeaConfiguration: Codable, Hashable {
    var type: FoodIdeaType
    var servings: Int?
    var dietaryNotes: String
}

enum VenueSetting: String, CaseIterable, Identifiable, Codable, Hashable {
    case indoor
    case outdoor
    case both
    case destination
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .indoor: "Indoor"
        case .outdoor: "Outdoor"
        case .both: "Both"
        case .destination: "Destination"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .indoor: "building.2.fill"
        case .outdoor: "tree.fill"
        case .both: "door.left.hand.open"
        case .destination: "airplane"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct VenueIdeaConfiguration: Codable, Hashable {
    var setting: VenueSetting
    var capacity: Int?
    var area: String
}

enum FlowerFocus: String, CaseIterable, Identifiable, Codable, Hashable {
    case bouquet
    case ceremony
    case tables
    case wearable
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .bouquet: "Bouquet"
        case .ceremony: "Ceremony"
        case .tables: "Tables"
        case .wearable: "Wearable"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .bouquet: "camera.macro"
        case .ceremony: "rectangle.portrait.and.arrow.forward"
        case .tables: "table.furniture.fill"
        case .wearable: "person.crop.circle"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct FlowerIdeaConfiguration: Codable, Hashable {
    var focus: FlowerFocus
    var palette: String
}

enum PhotographyStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case documentary
    case editorial
    case classic
    case film
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .documentary: "Documentary"
        case .editorial: "Editorial"
        case .classic: "Classic"
        case .film: "Film"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .documentary: "camera.viewfinder"
        case .editorial: "photo.artframe"
        case .classic: "camera.fill"
        case .film: "film.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct PhotographyIdeaConfiguration: Codable, Hashable {
    var style: PhotographyStyle
    var coverageHours: Int?
    var priorities: String
}

enum DecorFocus: String, CaseIterable, Identifiable, Codable, Hashable {
    case ceremony
    case reception
    case tables
    case lighting
    case signage
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .ceremony: "Ceremony"
        case .reception: "Reception"
        case .tables: "Tables"
        case .lighting: "Lighting"
        case .signage: "Signage"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .ceremony: "heart.fill"
        case .reception: "party.popper.fill"
        case .tables: "table.furniture.fill"
        case .lighting: "lightbulb.led.fill"
        case .signage: "signpost.right.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct DecorIdeaConfiguration: Codable, Hashable {
    var focus: DecorFocus
    var paletteOrMaterials: String
}

enum InvitationFormat: String, CaseIterable, Identifiable, Codable, Hashable {
    case printed
    case digital
    case both
    case saveTheDate
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .printed: "Printed"
        case .digital: "Digital"
        case .both: "Both"
        case .saveTheDate: "Save the Date"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .printed: "envelope.fill"
        case .digital: "iphone"
        case .both: "rectangle.2.swap"
        case .saveTheDate: "calendar.badge.clock"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct InvitationIdeaConfiguration: Codable, Hashable {
    var format: InvitationFormat
    var quantity: Int?
    var productionNotes: String
}

enum TripStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case relaxing
    case adventure
    case city
    case nature
    case roadTrip
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .relaxing: "Relaxing"
        case .adventure: "Adventure"
        case .city: "City"
        case .nature: "Nature"
        case .roadTrip: "Road Trip"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .relaxing: "beach.umbrella.fill"
        case .adventure: "figure.hiking"
        case .city: "building.2.fill"
        case .nature: "mountain.2.fill"
        case .roadTrip: "car.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct HoneymoonIdeaConfiguration: Codable, Hashable {
    var style: TripStyle
    var destination: String
    var nights: Int?
}

struct MusicIdeaConfiguration: Codable, Hashable {
    var tracks: [MusicTrack]
}

struct EventIdeaConfiguration: Codable, Hashable {
    var category: TimelineCategory
    var purpose: EventPurpose
    var proposedDate: Date?
    var location: EventLocation?
}

struct RegistryIdeaConfiguration: Codable, Hashable {
    var category: RegistryCategory
    var price: Decimal?
    var quantity: Int
}

enum IdeaConfiguration: Codable, Hashable {
    case standard
    case attire(AttireIdeaConfiguration)
    case venue(VenueIdeaConfiguration)
    case food(FoodIdeaConfiguration)
    case flowers(FlowerIdeaConfiguration)
    case photography(PhotographyIdeaConfiguration)
    case decor(DecorIdeaConfiguration)
    case invitations(InvitationIdeaConfiguration)
    case honeymoon(HoneymoonIdeaConfiguration)
    case music(MusicIdeaConfiguration)
    case event(EventIdeaConfiguration)
    case registry(RegistryIdeaConfiguration)
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
    var configuration: IdeaConfiguration

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
        musicTrack: MusicTrack? = nil,
        configuration: IdeaConfiguration? = nil
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
        if let configuration {
            self.configuration = configuration
        } else {
            self.configuration = switch category {
            case .attire:
                .attire(AttireIdeaConfiguration(style: .any, restrictions: ""))
            case .venue:
                .venue(VenueIdeaConfiguration(setting: .indoor, capacity: nil, area: ""))
            case .food:
                .food(FoodIdeaConfiguration(type: .meal, servings: nil, dietaryNotes: ""))
            case .flowers:
                .flowers(FlowerIdeaConfiguration(focus: .bouquet, palette: ""))
            case .photography:
                .photography(PhotographyIdeaConfiguration(style: .documentary, coverageHours: nil, priorities: ""))
            case .decor:
                .decor(DecorIdeaConfiguration(focus: .reception, paletteOrMaterials: ""))
            case .invitations:
                .invitations(InvitationIdeaConfiguration(format: .printed, quantity: nil, productionNotes: ""))
            case .honeymoon:
                .honeymoon(HoneymoonIdeaConfiguration(style: .relaxing, destination: "", nights: nil))
            case .music:
                .music(MusicIdeaConfiguration(tracks: musicTrack.map { [$0] } ?? []))
            case .event:
                .event(
                    EventIdeaConfiguration(
                        category: .other,
                        purpose: .planning,
                        proposedDate: nil,
                        location: nil
                    )
                )
            case .registry:
                .registry(
                    RegistryIdeaConfiguration(
                        category: .home,
                        price: nil,
                        quantity: 1
                    )
                )
            default:
                .standard
            }
        }
    }

    var musicTracks: [MusicTrack] {
        guard case .music(let configuration) = configuration else { return [] }
        return configuration.tracks
    }

    var musicTrack: MusicTrack? {
        musicTracks.first
    }

    var attireConfiguration: AttireIdeaConfiguration? {
        guard case .attire(let configuration) = configuration else { return nil }
        return configuration
    }

    var foodConfiguration: FoodIdeaConfiguration? {
        guard case .food(let configuration) = configuration else { return nil }
        return configuration
    }

    var venueConfiguration: VenueIdeaConfiguration? {
        guard case .venue(let configuration) = configuration else { return nil }
        return configuration
    }

    var flowerConfiguration: FlowerIdeaConfiguration? {
        guard case .flowers(let configuration) = configuration else { return nil }
        return configuration
    }

    var photographyConfiguration: PhotographyIdeaConfiguration? {
        guard case .photography(let configuration) = configuration else { return nil }
        return configuration
    }

    var decorConfiguration: DecorIdeaConfiguration? {
        guard case .decor(let configuration) = configuration else { return nil }
        return configuration
    }

    var invitationConfiguration: InvitationIdeaConfiguration? {
        guard case .invitations(let configuration) = configuration else { return nil }
        return configuration
    }

    var honeymoonConfiguration: HoneymoonIdeaConfiguration? {
        guard case .honeymoon(let configuration) = configuration else { return nil }
        return configuration
    }

    var eventConfiguration: EventIdeaConfiguration? {
        guard case .event(let configuration) = configuration else { return nil }
        return configuration
    }

    var registryConfiguration: RegistryIdeaConfiguration? {
        guard case .registry(let configuration) = configuration else { return nil }
        return configuration
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

enum MainEventStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case ongoing
    case finished

    var id: Self { self }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .ongoing: "Ongoing"
        case .finished: "Finished"
        }
    }

    var detail: String {
        switch self {
        case .draft:
            "Hosts and collaborators can keep setting up the event."
        case .ongoing:
            "The celebration is happening, including its scheduled events."
        case .finished:
            "The event is preserved as a read-only memory."
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc.badge.ellipsis"
        case .ongoing: "sparkles"
        case .finished: "checkmark.seal.fill"
        }
    }

    var isReadOnly: Bool {
        self == .finished
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
        case .notGoing: "Not Going"
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

struct EventMoment: Identifiable, Hashable {
    let id: UUID
    var imageData: Data
    var addedBy: String
    var addedAt: Date

    init(
        id: UUID = UUID(),
        imageData: Data,
        addedBy: String,
        addedAt: Date = .now
    ) {
        self.id = id
        self.imageData = imageData
        self.addedBy = addedBy
        self.addedAt = addedAt
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
    var eventDescription: String
    var dressCode: String

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
        status: EventStatus = .approved,
        completionStatus: EventCompletionStatus = .upcoming,
        response: EventResponse? = nil,
        linkedIdeaID: UUID? = nil,
        imageData: Data? = nil,
        eventDescription: String = "",
        dressCode: String = ""
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
        self.eventDescription = eventDescription
        self.dressCode = dressCode
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
        status: EventStatus = .approved,
        completionStatus: EventCompletionStatus = .upcoming,
        response: EventResponse? = nil,
        linkedIdeaID: UUID? = nil,
        imageData: Data? = nil,
        eventDescription: String = "",
        dressCode: String = ""
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
        self.eventDescription = eventDescription
        self.dressCode = dressCode
    }

    var location: String? {
        eventLocation?.title
    }
}

/// A stable reference to either the root event or one of its direct children.
/// Gatherory intentionally supports two levels: one main event and its subevents.
enum EventReference: Identifiable, Hashable {
    case main
    case subevent(UUID)
    case idea(UUID)

    var id: String {
        switch self {
        case .main:
            "main"
        case .subevent(let id):
            "subevent-\(id.uuidString)"
        case .idea(let id):
            "idea-\(id.uuidString)"
        }
    }

    var canHaveChildren: Bool {
        self == .main
    }
}

struct EventTreeNode: Identifiable, Hashable {
    enum Kind: Hashable {
        case main
        case subevent
    }

    let id: UUID
    let parentID: UUID?
    let kind: Kind
    let children: [EventTreeNode]

    var canHaveChildren: Bool {
        kind == .main
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
