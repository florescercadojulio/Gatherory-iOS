import Foundation

nonisolated enum EventAnnouncementAudience: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, planning, guests
    var id: String { rawValue }
}

nonisolated struct EventAnnouncement: Decodable, Identifiable, Equatable, Sendable {
    let id: UUID
    let eventId: UUID
    let message: String
    let authorId: String?
    let authorName: String
    let createdAt: Date
    let audience: EventAnnouncementAudience

    init(id: UUID, eventId: UUID, message: String, authorName: String, createdAt: Date,
         audience: EventAnnouncementAudience = .all, authorId: String? = nil) {
        self.id = id; self.eventId = eventId; self.message = message
        self.authorId = authorId; self.authorName = authorName
        self.createdAt = createdAt; self.audience = audience
    }
    private enum CodingKeys: String, CodingKey { case id, eventId, message, authorId, authorName, createdAt, audience }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), eventId: try values.decode(UUID.self, forKey: .eventId),
                  message: try values.decode(String.self, forKey: .message), authorName: try values.decode(String.self, forKey: .authorName),
                  createdAt: try values.decode(Date.self, forKey: .createdAt),
                  audience: try values.decodeIfPresent(EventAnnouncementAudience.self, forKey: .audience) ?? .all,
                  authorId: try values.decodeIfPresent(String.self, forKey: .authorId))
    }
}

nonisolated struct EventAnnouncementFeed: Decodable, Sendable {
    let announcements: [EventAnnouncement]
    let canSend: Bool
    let allowedAudiences: [EventAnnouncementAudience]
    init(announcements: [EventAnnouncement], canSend: Bool, allowedAudiences: [EventAnnouncementAudience]? = nil) {
        self.announcements = announcements
        self.allowedAudiences = canSend ? (allowedAudiences ?? [.all]) : []
        self.canSend = !self.allowedAudiences.isEmpty
    }
    private enum CodingKeys: String, CodingKey { case announcements, canSend, allowedAudiences }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(announcements: try values.decode([EventAnnouncement].self, forKey: .announcements),
                  canSend: try values.decode(Bool.self, forKey: .canSend),
                  allowedAudiences: try values.decodeIfPresent([EventAnnouncementAudience].self, forKey: .allowedAudiences) ?? [])
    }
}

nonisolated struct EventAnnouncementScope: Equatable, Sendable {
    let principal: NotificationPrincipal
    let generation: UInt64
    let eventID: UUID
}

nonisolated enum EventAnnouncementFailure: Error, Equatable {
    case unavailable, accessDenied, invalidResponse, invalidMessage, staleSession, requestConflict
}

nonisolated enum EventAnnouncementMessage {
    static let maximumScalars = 750
    static func normalized(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isValid(_ message: String) -> Bool {
        let value = normalized(message)
        return !value.isEmpty && value.unicodeScalars.count <= maximumScalars
    }
}

@MainActor protocol EventAnnouncementTransport {
    func load(eventID: UUID) async throws -> EventAnnouncementFeed
    func send(eventID: UUID, requestID: UUID, message: String, audience: EventAnnouncementAudience) async throws -> EventAnnouncement
}
