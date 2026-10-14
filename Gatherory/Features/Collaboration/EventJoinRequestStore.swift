import Foundation
import Observation

enum JoinRequestReviewAction: String { case approve, decline }

@MainActor
protocol EventJoinRequestTransport {
    func joinRequests(eventID: UUID) async throws -> [EventJoinRequest]
    func reviewJoinRequest(eventID: UUID, requestID: UUID, action: JoinRequestReviewAction) async throws
}

extension InvitationAPIClient: EventJoinRequestTransport {
    func joinRequests(eventID: UUID) async throws -> [EventJoinRequest] {
        let result: EventJoinRequests = try await request("api/invitations",
            query: [URLQueryItem(name: "eventId", value: eventID.uuidString)])
        return result.requests
    }

    func reviewJoinRequest(eventID: UUID, requestID: UUID, action: JoinRequestReviewAction) async throws {
        let _: EventJoinReview = try await request("api/invitations", method: "PATCH",
            body: ["eventId": eventID.uuidString, "requestId": requestID.uuidString, "action": action.rawValue])
    }
}

/// Transient, account-scoped state shared by Home, settings, and the invite screen.
/// It is not part of workspace persistence or the offline mutation outbox.
@MainActor @Observable
final class EventJoinRequestStore {
    private var accountID: String?
    private var accountRevision = UUID()
    private var requestsByEvent: [UUID: [EventJoinRequest]] = [:]
    private var errors: [UUID: String] = [:]
    private var loading: [UUID: UUID] = [:]
    private var loadedAt: [UUID: Date] = [:]
    private(set) var reviewingRequestID: UUID?
    @ObservationIgnored private let injectedClient: (any EventJoinRequestTransport)?

    init(client: (any EventJoinRequestTransport)? = nil) { injectedClient = client }

    private var client: (any EventJoinRequestTransport)? {
        injectedClient ?? AppRuntimeConfiguration.authenticationBaseURL.map { InvitationAPIClient(baseURL: $0) }
    }

    func requests(eventID: UUID, accountID: String?) -> [EventJoinRequest] {
        guard let accountID, self.accountID == accountID else { return [] }
        return requestsByEvent[eventID] ?? []
    }

    /// Unknown is distinct from a successfully loaded empty list. Read-only and
    /// account-scoped, so summary UI never presents another account's count.
    func requestCount(eventID: UUID, accountID: String?) -> Int? {
        guard let accountID, self.accountID == accountID else { return nil }
        return requestsByEvent[eventID]?.count
    }

    func error(eventID: UUID, accountID: String?) -> String? {
        self.accountID == accountID ? errors[eventID] : nil
    }

    func isLoading(eventID: UUID) -> Bool { loading[eventID] != nil }

    private func activate(_ accountID: String) {
        guard self.accountID != accountID else { return }
        self.accountID = accountID
        accountRevision = UUID()
        requestsByEvent = [:]
        errors = [:]
        loading = [:]
        loadedAt = [:]
        reviewingRequestID = nil
    }

    func refresh(eventID: UUID, accountID: String, force: Bool = false) async {
        activate(accountID)
        guard let client, reviewingRequestID == nil, !Task.isCancelled else { return }
        if !force, loading[eventID] != nil || (loadedAt[eventID].map { Date().timeIntervalSince($0) < 45 } ?? false) { return }
        let revision = UUID()
        loading[eventID] = revision
        defer { if self.accountID == accountID, loading[eventID] == revision { loading[eventID] = nil } }
        do {
            let requests = try await client.joinRequests(eventID: eventID)
            guard self.accountID == accountID, loading[eventID] == revision, !Task.isCancelled else { return }
            requestsByEvent[eventID] = requests
            loadedAt[eventID] = .now
            errors[eventID] = nil
        } catch {
            guard self.accountID == accountID, loading[eventID] == revision, !Task.isCancelled else { return }
            errors[eventID] = error.localizedDescription
        }
    }

    func review(_ request: EventJoinRequest, eventID: UUID, accountID: String, action: JoinRequestReviewAction) async -> Bool {
        guard self.accountID == accountID, reviewingRequestID == nil, let client else { return false }
        reviewingRequestID = request.id
        let revision = accountRevision
        // A pre-review GET must not put an approved request back into the badge.
        loading[eventID] = nil
        defer { if accountRevision == revision { reviewingRequestID = nil } }
        do {
            try await client.reviewJoinRequest(eventID: eventID, requestID: request.id, action: action)
            guard accountRevision == revision, !Task.isCancelled else { return false }
            requestsByEvent[eventID]?.removeAll { $0.id == request.id }
            errors[eventID] = nil
            loadedAt[eventID] = nil
            return true
        } catch {
            guard accountRevision == revision, !Task.isCancelled else { return false }
            errors[eventID] = error.localizedDescription
            return false
        }
    }
}
