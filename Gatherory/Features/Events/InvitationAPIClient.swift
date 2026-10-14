import Foundation

struct InvitationPreview: Decodable {
    let requiresSignIn: Bool
    let title: String?
    let role: String?
    let locationName: String?
    let startsAt: String?
    let status: String?
    let coverURL: URL?
    let requiresApproval: Bool?
    let planningPermission: String?

    func shouldOpenExistingEvent(isAuthenticated: Bool) -> Bool {
        // Only a fresh, account-specific server preview can establish access.
        // A role alone also appears on invitations that still require consent.
        isAuthenticated && !requiresSignIn && status == "accepted"
    }
}

struct InvitationAcceptance: Decodable {
    let eventId: UUID
    let role: String
    let planningScopeId: UUID?
    let status: String?

    var awaitsApproval: Bool { status == "awaiting_approval" }

    enum Destination: Equatable {
        case awaitingApproval
        case planning(UUID)
        case guest(UUID)
    }

    var destination: Destination {
        // Approval always wins, even if a response also contains a scope ID.
        if awaitsApproval { return .awaitingApproval }
        if role == "guest" { return .guest(eventId) }
        if let planningScopeId { return .planning(planningScopeId) }
        if role == "collaborator" { return .planning(eventId) }
        return .guest(eventId)
    }
}

/// Keeps a successful join separate from loading its destination. A retry can
/// resume that load without issuing another join, but never for another account.
struct InvitationJoinProgress {
    private var accountID: String?
    private var response: InvitationAcceptance?

    mutating func record(_ response: InvitationAcceptance, accountID: String) {
        self.accountID = accountID
        self.response = response
    }

    func acceptedResponse(for accountID: String?) -> InvitationAcceptance? {
        guard self.accountID == accountID, let response, !response.awaitsApproval else { return nil }
        return response
    }
}

struct EventJoinRequests: Decodable {
    let requests: [EventJoinRequest]
}

struct EventJoinRequest: Decodable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let planningPermission: String

    var permission: PlanningPermission {
        planningPermission == "view_only" ? .viewOnly : PlanningPermission(rawValue: planningPermission) ?? .contribute
    }
}

struct EventJoinReview: Decodable {
    let status: String
}

struct GuestInvitationFeed: Codable {
    let events: [GuestEventInvitation]
}

struct GuestEventInvitation: Codable, Identifiable {
    let id: UUID
    let title: String
    let startsAt: Date?
    let endsAt: Date?
    let isAllDay: Bool
    let timeZone: String
    let locationName: String?
    let locationAddress: String?
    let locationAddressLine2: String?
    let latitude: Double?
    let longitude: Double?
    let mapItemIdentifier: String?
    let description: String?
    let dressCode: String?
    let status: String?
    let complete: String
    let viewerPersonId: UUID
    let role: String
    var attendance: String
    let coverURL: URL?
    let coverId: UUID?
    var people: [GuestInvitationPerson]
    let ideas: [GuestInvitationIdea]
    let moments: [GuestInvitationMoment]

    func makePresentation(account: UserAccount, artwork: [UUID: Data]) -> PlanningWorkspace {
        let members = people.map { person in
            WorkspaceMember(id: person.id, userID: person.userId ?? (person.id == viewerPersonId ? account.id : nil),
                name: person.name, participantRole: WorkspaceRole(rawValue: person.role) ?? .guest,
                initials: person.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased(),
                attendance: Self.attendance(person.attendance), profileImageURL: person.imageURL,
                planningPermission: .viewOnly)
        }
        let publishedIdeas = ideas.compactMap { item -> PlanningIdea? in
            guard let category = IdeaCategory(rawValue: item.category) else { return nil }
            return PlanningIdea(id: item.id, eventID: id, title: item.title, note: item.note,
                category: category, submittedBy: "", submittedByUserID: item.submittedByUserId, status: .chosen,
                imageData: item.imageId.flatMap { artwork[$0] }, mediaAssetID: item.imageId, configuration: item.configuration,
                invitationVisibility: .shownToGuests)
        }
        let workspace = PlanningWorkspace(mainEventID: id, title: title,
            mainEventStartsAt: startsAt ?? .distantFuture, mainEventEndsAt: endsAt,
            mainEventIsAllDay: isAllDay, mainEventTimeZoneIdentifier: timeZone,
            mainEventLocation: EventLocation(address: locationAddress ?? "", locationName: locationName ?? "",
                addressLine2: locationAddressLine2 ?? "", latitude: latitude, longitude: longitude,
                mapItemIdentifier: mapItemIdentifier),
            mainEventImageData: coverId.flatMap { artwork[$0] }, venueName: locationName ?? "", location: locationAddress ?? "",
            dressCode: dressCode ?? "", eventMessage: description ?? "", planningMode: .quietPlanning,
            members: members, ideas: publishedIdeas, timeline: [],
            mainEventStatus: status == "cancelled" ? .cancelled : status == "finished" || complete == "complete" ? .finished : status == "draft" ? .draft : .ongoing,
            mainEventResponse: Self.response(attendance),
            eventMoments: moments.compactMap { photo in
                guard let data = artwork[photo.id] else { return nil }
                return EventMoment(id: photo.id, eventID: id, mediaAssetID: photo.id, imageData: data, addedBy: photo.addedBy, addedByUserID: photo.addedByUserId, addedAt: photo.addedAt)
            }, registry: [])
        workspace.isInvitationProjection = true
        workspace.mainEventMediaAssetID = coverId
        workspace.invitationDateIsUndecided = startsAt == nil
        if locationName == nil && locationAddress == nil && latitude == nil { workspace.mainEventLocation = nil }
        workspace.configureViewer(account)
        return workspace
    }

    static func attendance(_ value: String) -> AttendanceStatus {
        switch value { case "going": .going; case "not_sure": .maybe; case "not_going": .declined; default: .invited }
    }
    static func response(_ value: String) -> EventResponse? {
        switch value { case "going": .going; case "not_sure": .notSure; case "not_going": .notGoing; default: nil }
    }
}

struct GuestInvitationMoment: Codable {
    let id: UUID
    let imageURL: URL?
    let addedAt: Date
    let addedBy: String
    var addedByUserId: String? = nil
}

struct GuestInvitationPerson: Codable {
    let id: UUID
    let name: String
    let imageURL: URL?
    let role: String
    var attendance: String
    var userId: String? = nil
}

struct GuestInvitationIdea: Codable {
    let id: UUID
    let category: String
    let title: String
    let note: String
    let tracks: [MusicTrack]
    let linkURL: URL?
    let imageURL: URL?
    let imageId: UUID?
    let configuration: IdeaConfiguration
    let submittedByUserId: String?

    enum CodingKeys: String, CodingKey { case id, category, title, note, tracks, linkURL, imageURL, imageId, configuration, submittedByUserId }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        category = try values.decode(String.self, forKey: .category)
        title = try values.decode(String.self, forKey: .title)
        note = try values.decode(String.self, forKey: .note)
        tracks = try values.decode([MusicTrack].self, forKey: .tracks)
        linkURL = try values.decodeIfPresent(URL.self, forKey: .linkURL)
        imageURL = try values.decodeIfPresent(URL.self, forKey: .imageURL)
        imageId = try values.decodeIfPresent(UUID.self, forKey: .imageId)
        submittedByUserId = try values.decodeIfPresent(String.self, forKey: .submittedByUserId)
        configuration = (try? values.decode(IdeaConfiguration.self, forKey: .configuration)) ?? .standard
    }
}

struct InvitationAPIClient {
    let baseURL: URL
    var session: URLSession = .shared
    var tokenStore: any SessionTokenStore = KeychainSessionTokenStore()
    var recordDiagnostic: (String, [String: String], Error) -> Void = { event, fields, error in
        SyncDiagnostics.record(event, fields: fields, error: error)
    }

    func request<Value: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil,
                                   query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> Value {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        // Only static endpoint names are diagnostic data; never log query tokens or URLs.
        let endpoint = ["api/events/invitations", "api/invitations", "api/invitations/preview", "api/invitations/accept"].contains(path)
            ? path : "other"
        var fields = ["endpoint": endpoint, "method": method, "request_id": requestID]
        if let token = try tokenStore.read(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if authenticated { throw CloudSyncFailure.invalidSession }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            recordDiagnostic("invitation_request_failed", fields, error)
            throw error
        }
        guard let response = response as? HTTPURLResponse else { throw EventInvitationFailure.unavailable }
        fields["http_status"] = String(response.statusCode)
        fields["response_bytes"] = String(data.count)
        if let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let serverError = root["error"] as? [String: Any] {
            for (key, field) in [("traceId", "server_trace_id"), ("errorId", "server_error_id")] {
                if let value = serverError[key] as? String, let id = UUID(uuidString: value) {
                    fields[field] = id.uuidString.lowercased()
                }
            }
        }
        if response.statusCode == 401 {
            recordDiagnostic("invitation_request_failed", fields, CloudSyncFailure.invalidSession)
            throw CloudSyncFailure.invalidSession
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result: InvitationEnvelope<Value>
        do {
            result = try decoder.decode(InvitationEnvelope<Value>.self, from: data)
        } catch {
            fields.merge(InvitationDecodingDiagnostics.fields(for: error)) { _, new in new }
            recordDiagnostic("invitation_response_decode_failed", fields, error)
            throw EventInvitationFailure.invalidResponse
        }
        guard (200..<300).contains(response.statusCode), result.ok, let value = result.data else {
            if (200..<300).contains(response.statusCode), result.ok {
                fields["decode_kind"] = "missing_payload"
                fields["decode_path"] = "data"
                recordDiagnostic("invitation_response_decode_failed", fields, EventInvitationFailure.invalidResponse)
                throw EventInvitationFailure.invalidResponse
            }
            let error = EventInvitationFailure.server(result.error?.userMessage ?? String(localized: "The invitation could not be loaded. Try again."))
            recordDiagnostic("invitation_request_failed", fields, error)
            throw error
        }
        return value
    }
}

enum InvitationDecodingDiagnostics {
    /// Coding keys identify the contract failure. Never include debugDescription,
    /// underlying errors, response values, or arbitrary dictionary keys.
    nonisolated static func fields(for error: Error) -> [String: String] {
        let kind: String
        let path: [any CodingKey]
        var missingKey: String?
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            kind = "key_not_found"
            path = context.codingPath + [key]
            missingKey = safeKey(key)
        case DecodingError.valueNotFound(_, let context):
            kind = "null_value"
            path = context.codingPath
        case DecodingError.typeMismatch(_, let context):
            kind = "type_mismatch"
            path = context.codingPath
        case DecodingError.dataCorrupted(let context):
            kind = "invalid_value"
            path = context.codingPath
        default:
            return ["decode_kind": "unknown"]
        }
        var fields = ["decode_kind": kind, "decode_path": path.isEmpty ? "$" : path.map(safeKey).joined(separator: ".")]
        fields["missing_key"] = missingKey
        return fields
    }

    nonisolated private static func safeKey(_ key: any CodingKey) -> String {
        if let index = key.intValue { return "[\(index)]" }
        let keys: Set<String> = [
            "ok", "data", "error", "userMessage", "events", "id", "title", "startsAt", "endsAt",
            "isAllDay", "timeZone", "locationName", "locationAddress", "locationAddressLine2",
            "latitude", "longitude", "mapItemIdentifier", "description", "dressCode", "status", "complete",
            "viewerPersonId", "role", "attendance", "coverURL", "coverId", "people", "ideas", "moments",
            "name", "imageURL", "userId", "category", "note", "tracks", "linkURL", "imageId",
            "configuration", "submittedByUserId", "addedAt", "addedBy", "addedByUserId",
            "providerID", "rawValue", "catalogID", "artistName", "albumTitle", "artworkURL", "previewURL",
            "externalURL", "isrc", "duration", "requiresSignIn", "eventId", "planningScopeId"
        ]
        return keys.contains(key.stringValue) ? key.stringValue : "<redacted-key>"
    }
}

private struct InvitationEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let data: Value?
    let error: InvitationSafeError?
}
private struct InvitationSafeError: Decodable { let userMessage: String }
