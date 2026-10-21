import Foundation
import Observation

/// Online-only announcements never enter workspace archives or the sync outbox.
@Observable @MainActor final class EventAnnouncementController {
    private(set) var scope: EventAnnouncementScope?
    private(set) var announcements: [EventAnnouncement] = []
    private(set) var canSend = false
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var loadFailure: EventAnnouncementFailure?
    private(set) var sendFailure: EventAnnouncementFailure?
    private(set) var hasLoaded = false
    var draft = ""
    var audience: EventAnnouncementAudience = .planning
    private(set) var allowedAudiences: [EventAnnouncementAudience] = []
    @ObservationIgnored private var preferredAudience: EventAnnouncementAudience?
    @ObservationIgnored private var transport: (any EventAnnouncementTransport)?
    @ObservationIgnored private var isCurrent: () -> Bool = { false }
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var retry: (message: String, audience: EventAnnouncementAudience, id: UUID)?

    var canSubmit: Bool {
        canSend && allowedAudiences.contains(audience) && !isSending && !isLoading && EventAnnouncementMessage.isValid(draft)
            && !(sendFailure == .requestConflict && retry?.message == EventAnnouncementMessage.normalized(draft) && retry?.audience == audience)
    }

    func activate(scope: EventAnnouncementScope?, transport: (any EventAnnouncementTransport)?,
                  initialAudience: EventAnnouncementAudience? = nil, isCurrent: @escaping () -> Bool) {
        generation &+= 1
        self.scope = scope
        self.transport = transport
        self.isCurrent = isCurrent
        announcements = []
        canSend = false
        isLoading = false
        isSending = false
        hasLoaded = false
        loadFailure = nil
        sendFailure = nil
        draft = ""
        retry = nil
        allowedAudiences = []
        preferredAudience = initialAudience
        audience = initialAudience ?? .planning
    }

    func refresh() async {
        guard !isLoading, !isSending, let scope, let transport, isCurrent() else { return }
        let operation = generation
        isLoading = true
        defer { if operation == generation { isLoading = false } }
        do {
            let feed = try await transport.load(eventID: scope.eventID)
            guard operation == generation, isCurrent(), !Task.isCancelled else { return }
            guard feed.announcements.allSatisfy({ $0.eventId == scope.eventID }) else {
                throw EventAnnouncementFailure.invalidResponse
            }
            announcements = Self.sorted(feed.announcements)
            if case .account = scope.principal { canSend = feed.canSend } else { canSend = false }
            allowedAudiences = canSend ? EventAnnouncementAudience.allCases.filter(feed.allowedAudiences.contains) : []
            canSend = canSend && !allowedAudiences.isEmpty
            if !hasLoaded || !allowedAudiences.contains(audience) {
                audience = preferredAudience.flatMap { allowedAudiences.contains($0) ? $0 : nil }
                    ?? (allowedAudiences.contains(.planning) ? .planning : allowedAudiences.first ?? .planning)
            }
            hasLoaded = true
            loadFailure = nil
        } catch {
            guard operation == generation, isCurrent(), !Task.isCancelled else { return }
            let failure = error as? EventAnnouncementFailure ?? .unavailable
            loadFailure = failure
            if failure == .accessDenied {
                announcements = []
                canSend = false
                allowedAudiences = []
                hasLoaded = false
            }
        }
    }

    /// A failed request retains its draft and idempotency key. Only an explicit
    /// second Send retries it; refresh, reconnection and sync cannot send it.
    @discardableResult func send() async -> Bool {
        guard canSubmit, let scope, let transport, isCurrent(), case .account = scope.principal else { return false }
        let message = EventAnnouncementMessage.normalized(draft)
        let recipientAudience = audience
        let requestID = retry?.message == message && retry?.audience == recipientAudience ? retry!.id : UUID()
        retry = (message, recipientAudience, requestID)
        let operation = generation
        isSending = true
        sendFailure = nil
        defer { if operation == generation { isSending = false } }
        do {
            let value = try await transport.send(eventID: scope.eventID, requestID: requestID, message: message, audience: recipientAudience)
            guard operation == generation, isCurrent(), !Task.isCancelled else { return false }
            guard value.eventId == scope.eventID, value.audience == recipientAudience else { throw EventAnnouncementFailure.invalidResponse }
            announcements.removeAll { $0.id == value.id }
            announcements.insert(value, at: 0)
            announcements = Self.sorted(announcements)
            hasLoaded = true
            if EventAnnouncementMessage.normalized(draft) == message { draft = "" }
            retry = nil
            return true
        } catch {
            guard operation == generation, isCurrent(), !Task.isCancelled else { return false }
            sendFailure = error as? EventAnnouncementFailure ?? .unavailable
            if sendFailure == .accessDenied { canSend = false }
            return false
        }
    }

    private static func sorted(_ values: [EventAnnouncement]) -> [EventAnnouncement] {
        values.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
}
