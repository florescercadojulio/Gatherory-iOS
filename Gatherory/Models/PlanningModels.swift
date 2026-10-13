import Foundation

enum PlanningMode: String, CaseIterable, Identifiable, Codable {
    case openToIdeas
    case helpMeDecide
    case quietPlanning
    case decisionMade

    var id: Self { self }

    var title: String {
        switch self {
        case .openToIdeas: AppCopy.Planning.openToIdeas
        case .helpMeDecide: AppCopy.Planning.helpMeDecide
        case .quietPlanning: AppCopy.Planning.quietPlanning
        case .decisionMade: AppCopy.Planning.decisionMade
        }
    }

    var detail: String {
        switch self {
        case .openToIdeas: AppCopy.Planning.openToIdeasDetail
        case .helpMeDecide: AppCopy.Planning.helpMeDecideDetail
        case .quietPlanning: AppCopy.Planning.quietPlanningDetail
        case .decisionMade: AppCopy.Planning.decisionMadeDetail
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

enum IdeaInvitationVisibility: String, CaseIterable, Identifiable, Codable {
    case planningOnly
    case shownToGuests

    var id: Self { self }
}

enum IdeaCategory: String, CaseIterable, Identifiable, Codable {
    case event
    case registry
    case link
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
        case .event: AppCopy.IdeaCategory.event
        case .registry: AppCopy.IdeaCategory.registry
        case .link: AppCopy.IdeaCategory.link
        case .venue: AppCopy.IdeaCategory.venue
        case .attire: AppCopy.IdeaCategory.attire
        case .flowers: AppCopy.IdeaCategory.flowers
        case .food: AppCopy.IdeaCategory.food
        case .photography: AppCopy.IdeaCategory.photography
        case .music: AppCopy.IdeaCategory.music
        case .decor: AppCopy.IdeaCategory.decor
        case .invitations: AppCopy.IdeaCategory.invitations
        case .honeymoon: AppCopy.IdeaCategory.honeymoon
        case .other: AppCopy.IdeaCategory.other
        }
    }

    var symbol: String {
        switch self {
        case .event: "calendar.badge.plus"
        case .registry: "gift.fill"
        case .link: "link"
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

    /// Event proposals and registry gifts already have dedicated guest-facing
    /// experiences. The remaining categories can optionally contribute a
    /// concise detail to the invitation for the event they belong to.
    var supportsInvitationVisibility: Bool {
        self != .event && self != .registry && self != .link
    }

    /// Attire and the event playlist are actionable information for guests.
    /// Other ideas stay inside planning unless a collaborator deliberately
    /// shares them.
    var defaultInvitationVisibility: IdeaInvitationVisibility {
        switch self {
        case .attire, .music:
            .shownToGuests
        default:
            .planningOnly
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
        case .new: AppCopy.IdeaStatus.new
        case .maybe: AppCopy.IdeaStatus.maybe
        case .shortlisted: AppCopy.IdeaStatus.shortlisted
        case .chosen: AppCopy.IdeaStatus.approved
        case .passed: AppCopy.IdeaStatus.passed
        case .archived: AppCopy.IdeaStatus.archived
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
        case .any: AppCopy.Attire.any
        case .blackTie: AppCopy.Attire.blackTie
        case .formal: AppCopy.Attire.formal
        case .cocktail: AppCopy.Attire.cocktail
        case .garden: AppCopy.Attire.garden
        case .casual: AppCopy.Attire.casual
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
        case .meal: AppCopy.Food.meal
        case .cake: AppCopy.Food.cake
        case .dessert: AppCopy.Food.dessert
        case .drinks: AppCopy.Food.drinks
        case .tasting: AppCopy.Food.tasting
        case .other: AppCopy.Food.other
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

struct LinkIdeaConfiguration: Codable, Hashable {
    var url: URL

    /// Converts casual website input such as `example.com` into a web URL.
    /// Keeping this at the model boundary gives every future editor and sync
    /// path the same validation behavior.
    static func normalizedURL(from address: String) -> URL? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return nil }

        let addressWithScheme = trimmedAddress.contains("://")
            ? trimmedAddress
            : "https://\(trimmedAddress)"
        guard let components = URLComponents(string: addressWithScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let url = components.url else {
            return nil
        }

        return url
    }
}

enum EventAudience: String, Codable, Hashable {
    case inherited
    case hostsOnly

    var title: String {
        switch self {
        case .inherited: "Everyone in the event"
        case .hostsOnly: "Hosts only"
        }
    }

    var symbol: String {
        switch self {
        case .inherited: "person.3.fill"
        case .hostsOnly: "person.2.fill"
        }
    }
}

struct EventIdeaConfiguration: Codable, Hashable {
    var category: TimelineCategory
    var purpose: EventPurpose
    var audience: EventAudience
    var requiresBudget: Bool
    var proposedBudget: Decimal?
    var proposedDate: Date?
    var proposedEndDate: Date?
    var isAllDay: Bool
    var timeZoneIdentifier: String
    var location: EventLocation?
    var attireStyle: AttireStyle
    var attireGuidance: String

    init(
        category: TimelineCategory,
        purpose: EventPurpose,
        audience: EventAudience = .inherited,
        requiresBudget: Bool = false,
        proposedBudget: Decimal? = nil,
        proposedDate: Date?,
        proposedEndDate: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        location: EventLocation?,
        attireStyle: AttireStyle = .any,
        attireGuidance: String = ""
    ) {
        self.category = category
        self.purpose = purpose
        self.audience = audience
        self.requiresBudget = requiresBudget || proposedBudget != nil
        self.proposedBudget = proposedBudget
        self.proposedDate = proposedDate
        self.proposedEndDate = proposedEndDate
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.location = location
        self.attireStyle = attireStyle
        self.attireGuidance = attireGuidance
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case purpose
        case audience
        case requiresBudget
        case proposedBudget
        case proposedDate
        case proposedEndDate
        case isAllDay
        case timeZoneIdentifier
        case location
        case attireStyle
        case attireGuidance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(TimelineCategory.self, forKey: .category)
        purpose = try container.decode(EventPurpose.self, forKey: .purpose)
        audience = try container.decodeIfPresent(EventAudience.self, forKey: .audience) ?? .inherited
        proposedBudget = try container.decodeIfPresent(Decimal.self, forKey: .proposedBudget)
        requiresBudget = (try container.decodeIfPresent(Bool.self, forKey: .requiresBudget) ?? false)
            || proposedBudget != nil
        proposedDate = try container.decodeIfPresent(Date.self, forKey: .proposedDate)
        proposedEndDate = try container.decodeIfPresent(Date.self, forKey: .proposedEndDate)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
            ?? TimeZone.autoupdatingCurrent.identifier
        location = try container.decodeIfPresent(EventLocation.self, forKey: .location)
        attireStyle = try container.decodeIfPresent(AttireStyle.self, forKey: .attireStyle) ?? .any
        attireGuidance = try container.decodeIfPresent(String.self, forKey: .attireGuidance) ?? ""
    }

    var attireDescription: String {
        let guidance = attireGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (attireStyle, guidance.isEmpty) {
        case (.any, true): ""
        case (.any, false): guidance
        case (_, true): attireStyle.title
        case (_, false): "\(attireStyle.title) · \(guidance)"
        }
    }
}

struct RegistryIdeaConfiguration: Codable, Hashable {
    var category: RegistryCategory
    var price: Decimal?
    var quantity: Int
}

enum IdeaConfiguration: Codable, Hashable {
    case standard
    case link(LinkIdeaConfiguration)
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

struct PlanningIdea: Identifiable, Hashable, Codable {
    let id: UUID
    /// The root event or direct child event this idea helps plan.
    /// Older mock data is attached to the root event by `PlanningWorkspace`.
    var eventID: UUID?
    var title: String
    var note: String
    var category: IdeaCategory
    var submittedBy: String
    /// Stable account identity when the author has signed in. The display name
    /// remains a snapshot so ideas still render after an account is removed.
    var submittedByUserID: String?
    var estimatedCost: Decimal?
    var status: IdeaStatus
    var submittedAt: Date
    var imageData: Data?
    /// R2-backed image identity. Image bytes remain local-only and are never
    /// embedded in replication envelopes.
    var mediaAssetID: UUID?
    var configuration: IdeaConfiguration
    /// Optional so workspaces saved before this setting existed still decode.
    /// `effectiveInvitationVisibility` supplies the category-aware default.
    var invitationVisibility: IdeaInvitationVisibility?

    init(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        title: String,
        note: String,
        category: IdeaCategory,
        submittedBy: String,
        submittedByUserID: String? = nil,
        estimatedCost: Decimal? = nil,
        status: IdeaStatus = .new,
        submittedAt: Date = .now,
        imageData: Data? = nil,
        mediaAssetID: UUID? = nil,
        musicTrack: MusicTrack? = nil,
        configuration: IdeaConfiguration? = nil,
        invitationVisibility: IdeaInvitationVisibility? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.title = title
        self.note = note
        self.category = category
        self.submittedBy = submittedBy
        self.submittedByUserID = submittedByUserID
        self.estimatedCost = estimatedCost
        self.status = status
        self.submittedAt = submittedAt
        self.imageData = imageData
        self.mediaAssetID = mediaAssetID
        self.invitationVisibility = invitationVisibility
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

    var linkConfiguration: LinkIdeaConfiguration? {
        guard case .link(let configuration) = configuration else { return nil }
        return configuration
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

    var effectiveInvitationVisibility: IdeaInvitationVisibility {
        guard category.supportsInvitationVisibility else { return .planningOnly }
        return invitationVisibility ?? category.defaultInvitationVisibility
    }

    var isShownOnInvitation: Bool {
        effectiveInvitationVisibility == .shownToGuests
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

enum WorkspaceRole: String, CaseIterable, Identifiable, Codable {
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
        case .host: "Organizes the experience with full planning access."
        case .collaborator: "Helps with ideas, decisions, and the schedule."
        case .guest: "Receives invitations and event updates."
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

struct WorkspaceMember: Identifiable, Hashable, Codable {
    let id: UUID
    /// Better Auth user ID once this person has accepted and linked an account.
    /// Invited people intentionally remain valid without one.
    var userID: String?
    var name: String
    var participantRole: WorkspaceRole
    var initials: String
    var attendance: AttendanceStatus
    var email: String?
    /// Profile media copied from the linked account so collaborators can show
    /// this person's avatar without requiring that account to be signed in.
    var profileImageAssetName: String?
    var profileImageURL: URL?
    var planningPermission: PlanningPermission
    var invitationStatus: CollaborationInvitationStatus

    init(
        id: UUID = UUID(),
        userID: String? = nil,
        name: String,
        participantRole: WorkspaceRole,
        initials: String,
        attendance: AttendanceStatus = .going,
        email: String? = nil,
        profileImageAssetName: String? = nil,
        profileImageURL: URL? = nil,
        planningPermission: PlanningPermission = .contribute,
        invitationStatus: CollaborationInvitationStatus = .active
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.participantRole = participantRole
        self.initials = initials
        self.attendance = attendance
        self.email = email
        self.profileImageAssetName = profileImageAssetName
        self.profileImageURL = profileImageURL
        self.planningPermission = planningPermission
        self.invitationStatus = invitationStatus
    }
}

/// Event-specific state for a person. Identity lives in `WorkspaceMember`, while
/// role, permissions, invitation state, and RSVP belong to this relationship.
/// This mirrors PostgreSQL's `event_participant` table and lets one person host
/// the main event while attending a child event as a guest.
struct EventParticipation: Identifiable, Hashable, Codable {
    let id: UUID
    let eventID: UUID
    let memberID: UUID
    var role: WorkspaceRole
    var planningPermission: PlanningPermission
    var attendance: AttendanceStatus
    var invitationStatus: CollaborationInvitationStatus
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID? = nil,
        eventID: UUID,
        memberID: UUID,
        role: WorkspaceRole,
        planningPermission: PlanningPermission,
        attendance: AttendanceStatus,
        invitationStatus: CollaborationInvitationStatus,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id ?? Self.stableID(eventID: eventID, memberID: memberID)
        self.eventID = eventID
        self.memberID = memberID
        self.role = role
        self.planningPermission = planningPermission
        self.attendance = attendance
        self.invitationStatus = invitationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Old archives only stored participant IDs on each event. A deterministic
    /// ID prevents those migrated relationships from changing on every launch.
    private static func stableID(eventID: UUID, memberID: UUID) -> UUID {
        let event = withUnsafeBytes(of: eventID.uuid) { Array($0) }
        let member = withUnsafeBytes(of: memberID.uuid) { Array($0) }
        var bytes = (0..<16).map { event[$0] ^ member[(($0 * 5) + 3) % 16] }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
    case cancelled

    var id: Self { self }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .approved: "Approved"
        case .notSure: "Not Sure"
        case .rejected: "Rejected"
        case .archived: "Archived"
        case .cancelled: AppCopy.Lifecycle.cancelled
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc.badge.ellipsis"
        case .approved: "checkmark.seal.fill"
        case .notSure: "questionmark.circle.fill"
        case .rejected: "xmark.circle.fill"
        case .archived: "archivebox.fill"
        case .cancelled: "calendar.badge.minus"
        }
    }
}

enum MainEventStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case ongoing
    case finished
    case cancelled

    var id: Self { self }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .ongoing: "Ongoing"
        case .finished: "Finished"
        case .cancelled: AppCopy.Lifecycle.cancelled
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
        case .cancelled:
            AppCopy.Lifecycle.cancelledDetail
        }
    }

    var symbol: String {
        switch self {
        case .draft: "doc.badge.ellipsis"
        case .ongoing: "sparkles"
        case .finished: "checkmark.seal.fill"
        case .cancelled: "calendar.badge.minus"
        }
    }

    var isReadOnly: Bool {
        self == .finished || self == .cancelled
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
    let eventID: UUID?
    let authorUserID: String?
    let body: String
    let sentAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        authorUserID: String? = nil,
        body: String,
        sentAt: Date = .now
    ) {
        self.id = id
        self.eventID = eventID
        self.authorUserID = authorUserID
        self.body = body
        self.sentAt = sentAt
    }
}

struct EventMoment: Identifiable, Hashable, Codable {
    let id: UUID
    /// The event this photo belongs to. `nil` is retained for decoding older
    /// main-event photos and is treated as the workspace's main event.
    var eventID: UUID?
    /// Server media identity after the local image has uploaded.
    var mediaAssetID: UUID?
    var imageData: Data
    var addedBy: String
    var addedByUserID: String?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        mediaAssetID: UUID? = nil,
        imageData: Data,
        addedBy: String,
        addedByUserID: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.eventID = eventID
        self.mediaAssetID = mediaAssetID
        self.imageData = imageData
        self.addedBy = addedBy
        self.addedByUserID = addedByUserID
        self.addedAt = addedAt
    }
}

enum EventExpenseStatus: String, CaseIterable, Identifiable, Codable {
    case estimated
    case committed
    case paid

    var id: Self { self }

    var title: String {
        switch self {
        case .estimated: "Estimated"
        case .committed: "Committed"
        case .paid: "Paid"
        }
    }

    var symbol: String {
        switch self {
        case .estimated: "sparkles"
        case .committed: "doc.text.fill"
        case .paid: "checkmark.circle.fill"
        }
    }
}

enum EventExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case venue
    case foodAndDrink
    case attire
    case decor
    case entertainment
    case photography
    case stationery
    case travel
    case gifts
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .venue: "Venue"
        case .foodAndDrink: "Food & Drink"
        case .attire: "Attire"
        case .decor: "Decor"
        case .entertainment: "Entertainment"
        case .photography: "Photography"
        case .stationery: "Stationery"
        case .travel: "Travel"
        case .gifts: "Gifts"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .venue: "building.2.fill"
        case .foodAndDrink: "fork.knife"
        case .attire: "hanger"
        case .decor: "lamp.ceiling.fill"
        case .entertainment: "music.note"
        case .photography: "camera.fill"
        case .stationery: "envelope.fill"
        case .travel: "airplane"
        case .gifts: "gift.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

/// A cost belongs to exactly one event. Keeping this as its own record makes it
/// straightforward to sync and query once the local workspace gains a backend.
struct EventExpense: Identifiable, Hashable, Codable {
    let id: UUID
    var eventID: UUID
    /// Set when this cost is derived from an idea. The stable relationship
    /// lets the workspace update one ledger entry instead of creating copies.
    var sourceIdeaID: UUID?
    var title: String
    var amount: Decimal
    var category: EventExpenseCategory
    var status: EventExpenseStatus
    var createdByUserID: String?
    var createdAt: Date
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        eventID: UUID,
        sourceIdeaID: UUID? = nil,
        title: String,
        amount: Decimal,
        category: EventExpenseCategory = .other,
        status: EventExpenseStatus = .estimated,
        createdByUserID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.sourceIdeaID = sourceIdeaID
        self.title = title
        self.amount = amount
        self.category = category
        self.status = status
        self.createdByUserID = createdByUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum TimelineCategory: String, CaseIterable, Identifiable, Codable {
    case venue
    case foodTasting
    case photography
    case honeymoon
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
        case .photography: "Photography"
        case .honeymoon: "Honeymoon"
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
        case .photography: "camera.fill"
        case .honeymoon: "airplane.departure"
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

enum EventSchedulingState: String, Hashable, Codable {
    case scheduled
    case unscheduled
}

struct TimelineItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var category: TimelineCategory
    var purpose: EventPurpose
    var scheduledAt: Date
    /// Optional for backwards-compatible decoding of events saved before
    /// scheduling state was modeled. A missing value represents a scheduled
    /// legacy event; only `.unscheduled` means the event still needs a date.
    var schedulingState: EventSchedulingState?
    var endsAt: Date?
    var isAllDay: Bool
    var timeZoneIdentifier: String
    var eventLocation: EventLocation?
    /// A snapshot of the main event roster for this event. New child events
    /// start with the root roster, then can diverge without changing it.
    var participantIDs: [UUID]
    var parentEventID: UUID?
    var status: EventStatus
    /// Restore the original state rather than silently approving an archived draft.
    var statusBeforeArchiving: EventStatus?
    var completionStatus: EventCompletionStatus
    var response: EventResponse?
    var linkedIdeaID: UUID?
    var imageData: Data?
    var mediaAssetID: UUID?
    var eventDescription: String
    var dressCode: String
    /// `nil` means this event doesn't participate in budget allocation.
    /// A zero value means it participates but hasn't received funds yet.
    var budgetCap: Decimal?

    init(
        id: UUID = UUID(),
        title: String,
        category: TimelineCategory,
        purpose: EventPurpose = .planning,
        scheduledAt: Date,
        schedulingState: EventSchedulingState? = .scheduled,
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
        mediaAssetID: UUID? = nil,
        eventDescription: String = "",
        dressCode: String = "",
        budgetCap: Decimal? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.purpose = purpose
        self.scheduledAt = scheduledAt
        self.schedulingState = schedulingState
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.eventLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : EventLocation(address: location)
        self.participantIDs = participantIDs
        self.parentEventID = parentEventID
        self.status = status
        self.statusBeforeArchiving = nil
        self.completionStatus = completionStatus
        self.response = response
        self.linkedIdeaID = linkedIdeaID
        self.imageData = imageData
        self.mediaAssetID = mediaAssetID
        self.eventDescription = eventDescription
        self.dressCode = dressCode
        self.budgetCap = budgetCap
    }

    init(
        id: UUID = UUID(),
        title: String,
        category: TimelineCategory,
        purpose: EventPurpose = .planning,
        scheduledAt: Date,
        schedulingState: EventSchedulingState? = .scheduled,
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
        mediaAssetID: UUID? = nil,
        eventDescription: String = "",
        dressCode: String = "",
        budgetCap: Decimal? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.purpose = purpose
        self.scheduledAt = scheduledAt
        self.schedulingState = schedulingState
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.eventLocation = eventLocation
        self.participantIDs = participantIDs
        self.parentEventID = parentEventID
        self.status = status
        self.statusBeforeArchiving = nil
        self.completionStatus = completionStatus
        self.response = response
        self.linkedIdeaID = linkedIdeaID
        self.imageData = imageData
        self.mediaAssetID = mediaAssetID
        self.eventDescription = eventDescription
        self.dressCode = dressCode
        self.budgetCap = budgetCap
    }

    var location: String? {
        eventLocation?.title
    }

    var hasScheduledDate: Bool {
        schedulingState != .unscheduled
    }
}

/// A stable reference to either the root event or one of its direct children.
/// Gatherory intentionally supports two levels: one main event and its subevents.
enum EventReference: Identifiable, Hashable, Codable {
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

struct EventTreeNode: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
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

struct RegistryItem: Identifiable, Hashable, Codable {
    let id: UUID
    /// Registry entries are event-scoped just like ideas and expenses.
    var eventID: UUID?
    var sourceIdeaID: UUID?
    var title: String
    var note: String
    var category: RegistryCategory
    var price: Decimal
    var quantity: Int
    var committedCount: Int
    var imageData: Data?
    var mediaAssetID: UUID?

    init(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        sourceIdeaID: UUID? = nil,
        title: String,
        note: String,
        category: RegistryCategory,
        price: Decimal,
        quantity: Int = 1,
        committedCount: Int = 0,
        imageData: Data? = nil,
        mediaAssetID: UUID? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.sourceIdeaID = sourceIdeaID
        self.title = title
        self.note = note
        self.category = category
        self.price = price
        self.quantity = quantity
        self.committedCount = committedCount
        self.imageData = imageData
        self.mediaAssetID = mediaAssetID
    }

    var remainingCount: Int {
        max(quantity - committedCount, 0)
    }

    var isFulfilled: Bool {
        remainingCount == 0
    }
}
