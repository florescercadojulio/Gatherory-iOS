import Foundation

nonisolated enum NotificationPrincipal: Hashable, Sendable {
    case account(id: String)
    case guest(id: UUID)

    var recipientKind: String { if case .account = self { "user" } else { "device_guest" } }
    var recipientID: String {
        switch self { case .account(let id): id; case .guest(let id): id.uuidString.lowercased() }
    }
    var storageKey: String { "\(recipientKind):\(recipientID)" }
}

nonisolated enum NotificationRouteIntent: Equatable, Sendable {
    case event(id: String)
    case todo(eventID: String, todoID: String)
    case announcement(eventID: String, announcementID: String)
}

nonisolated enum GatheroryNotificationPayload {
    static func route(from userInfo: [AnyHashable: Any], principal: NotificationPrincipal) -> NotificationRouteIntent? {
        guard let type = userInfo["type"] as? String,
              let eventID = validIdentifier(userInfo["eventId"]),
              userInfo["recipientKind"] as? String == principal.recipientKind,
              userInfo["recipientId"] as? String == principal.recipientID,
              let entityID = validIdentifier(userInfo["entityId"]) else { return nil }
        switch type {
        case "event_changed": return .event(id: eventID)
        case "assignment_changed": return .todo(eventID: eventID, todoID: entityID)
        case "event_announcement": return .announcement(eventID: eventID, announcementID: entityID)
        default: return nil
        }
    }

    private static func validIdentifier(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty, value.count <= 128,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("/") else { return nil }
        return value
    }
}

nonisolated struct NotificationInstallation: Codable, Equatable, Sendable {
    let installationID: UUID
    let secret: String
    var revision: Int
    var mayBeBound: Bool

    init(installationID: UUID = UUID(), secret: String, revision: Int = 0, mayBeBound: Bool = false) {
        self.installationID = installationID
        self.secret = secret
        self.revision = revision
        self.mayBeBound = mayBeBound
    }

    private enum CodingKeys: String, CodingKey { case installationID, secret, revision, mayBeBound }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        installationID = try values.decode(UUID.self, forKey: .installationID)
        secret = try values.decode(String.self, forKey: .secret)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        mayBeBound = try values.decodeIfPresent(Bool.self, forKey: .mayBeBound) ?? false
    }
}

nonisolated struct NotificationInstallationAcknowledgement: Decodable, Sendable {
    let installationId: String
    let bindingGeneration: Int
    let revision: Int
    let accepted: Bool
}
