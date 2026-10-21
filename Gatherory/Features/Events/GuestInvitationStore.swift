import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor protocol GuestInvitationTransport {
    func invitations() async throws -> GuestInvitationFeed
    func leaveInvitation(eventID: UUID) async throws -> UUID
}

@MainActor protocol LocalGuestInvitationTransport: GuestInvitationTransport {
    func join(token: UUID) async throws -> InvitationAcceptance
    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement
    func claim() async throws -> GuestClaimAcknowledgement
}

struct AttendanceAcknowledgement: Decodable, Equatable {
    let eventId: UUID
    let attendance: String
}

struct GuestClaimAcknowledgement: Decodable, Equatable {
    let claimedEventIds: [UUID]
}

extension InvitationAPIClient: GuestInvitationTransport {
    func invitations() async throws -> GuestInvitationFeed { try await request("api/events/invitations") }
    func leaveInvitation(eventID: UUID) async throws -> UUID {
        struct Acknowledgement: Decodable { let eventId: UUID }
        let result: Acknowledgement = try await request("api/events/invitations", method: "DELETE", body: ["eventId": eventID.uuidString])
        return result.eventId
    }
}

/// An account- or device-guest-scoped invitation cache. Event projections never
/// enter the planner workspace library or its sync outbox.
@MainActor @Observable
final class GuestInvitationStore {
    private(set) var events: [GuestEventInvitation] = []
    private(set) var presentations: [UUID: PlanningWorkspace] = [:]
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var isResponding = false
    var selectedEventID: UUID?
    @ObservationIgnored private var account: UserAccount?
    @ObservationIgnored private var localGuest: LocalGuestProfile?
    @ObservationIgnored private var localClient: (any LocalGuestInvitationTransport)?
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let injectedClient: (any GuestInvitationTransport)?
    @ObservationIgnored private let localClientFactory: @MainActor (LocalGuestProfile) -> any LocalGuestInvitationTransport
    @ObservationIgnored private var artwork: [UUID: Data] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var feedRevision = UUID()
    @ObservationIgnored private var identityGeneration = UUID()

    init(
        baseURL: URL?,
        cacheDirectory: URL? = nil,
        client: (any GuestInvitationTransport)? = nil,
        localClientFactory: (@MainActor (LocalGuestProfile) -> any LocalGuestInvitationTransport)? = nil
    ) {
        self.baseURL = baseURL
        injectedClient = client
        self.cacheDirectory = cacheDirectory ?? URL.applicationSupportDirectory.appending(path: "GuestInvitations")
        self.localClientFactory = localClientFactory ?? { profile in
            DeviceGuestInvitationClient(baseURL: baseURL, profile: profile)
        }
    }

    var selectedPresentation: PlanningWorkspace? { selectedEventID.flatMap { presentations[$0] } }

    private var client: (any GuestInvitationTransport)? {
        injectedClient ?? baseURL.map { InvitationAPIClient(baseURL: $0) }
    }

    func purgeCache(accountID: String) throws {
        try purgeCache(identity: accountID)
        if account?.id == accountID {
            clearActiveState()
        }
    }

    func deactivateDeletedAccount(_ accountID: String) async {
        guard account?.id == accountID else { return }
        await activate(account: nil)
    }

    func purgeCache(profileID: UUID) throws {
        try purgeCache(identity: "device-guest:\(profileID.uuidString.lowercased())")
        if localGuest?.id == profileID { clearActiveState() }
    }

    private func purgeCache(identity: String) throws {
        let source = "\(baseURL?.absoluteString ?? "local")|\(identity)"
        let key = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheDirectory.appending(path: "\(key).json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    func activate(account newAccount: UserAccount?) async {
        guard account?.id != newAccount?.id || localGuest != nil else { return }
        refreshTask?.cancel()
        mediaTask?.cancel()
        identityGeneration = UUID()
        feedRevision = UUID()
        refreshTask = nil
        account = newAccount
        localGuest = nil
        localClient = nil
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        errorMessage = nil
        isRefreshing = false
        isResponding = false
        guard newAccount != nil else { return }
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            events = cache.events
            artwork = cache.artwork
            rebuildPresentations()
        }
        await refresh()
    }

    func activate(localGuest newGuest: LocalGuestProfile?) async {
        guard localGuest?.id != newGuest?.id || account != nil else { return }
        refreshTask?.cancel()
        mediaTask?.cancel()
        identityGeneration = UUID()
        feedRevision = UUID()
        refreshTask = nil
        account = nil
        localGuest = newGuest
        localClient = newGuest.map(localClientFactory)
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        errorMessage = nil
        isRefreshing = false
        isResponding = false
        guard newGuest != nil else { return }
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            events = cache.events
            artwork = cache.artwork
            rebuildPresentations()
        }
        await refresh()
    }

    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if !force { return }
        }
        guard activeIdentity != nil, activeTransport != nil else { return }
        let task = Task { await loadFeed() }
        refreshTask = task
        await task.value
    }

    private func loadFeed() async {
        guard let identity = activeIdentity, let transport = activeTransport else { return }
        let requestGeneration = identityGeneration
        let requestRevision = feedRevision
        isRefreshing = true
        defer {
            if isCurrent(identity: identity, generation: requestGeneration) {
                isRefreshing = false
                refreshTask = nil
            }
        }
        do {
            let feed = try await transport.invitations()
            guard isCurrent(identity: identity, generation: requestGeneration),
                  feedRevision == requestRevision,
                  !Task.isCancelled else { return }
            events = feed.events
            let revision = UUID()
            feedRevision = revision
            let retainedArtwork = Set(events.flatMap { event in [event.coverId].compactMap { $0 } + event.ideas.compactMap(\.imageId) + event.moments.map(\.id) })
            artwork = artwork.filter { retainedArtwork.contains($0.key) }
            rebuildPresentations()
            try saveCache()
            // Save text first; image failures must not hide the invitation.
            mediaTask?.cancel()
            mediaTask = Task { await downloadArtwork(events: feed.events, identity: identity, revision: revision) }
            errorMessage = nil
        } catch {
            guard isCurrent(identity: identity, generation: requestGeneration),
                  feedRevision == requestRevision,
                  !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func downloadArtwork(events: [GuestEventInvitation], identity: String, revision: UUID) async {
            for event in events {
                let images = [(event.coverId, event.coverURL)] + event.ideas.map { ($0.imageId, $0.imageURL) } + event.moments.map { (Optional($0.id), $0.imageURL) }
                for (id, url) in images {
                    guard let id, let url, ["https", "http"].contains(url.scheme), artwork[id] == nil else { continue }
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                       data.count <= 20 * 1024 * 1024 {
                        // Guest projections are display-only. Prepare a bounded
                        // local copy off the main actor; never alter the upload.
                        let prepared = await Task.detached(priority: .utility) {
                            InvitationImageDecoder.thumbnail(data: data)?.pngData()
                        }.value
                        guard activeIdentity == identity, feedRevision == revision, !Task.isCancelled else { return }
                        if let prepared { artwork[id] = prepared }
                    }
                }
            }
            guard activeIdentity == identity, feedRevision == revision, !Task.isCancelled else { return }
            rebuildPresentations()
            try? saveCache()
    }

    func respond(eventID: UUID, response: EventResponse) async {
        guard !isResponding, let identity = activeIdentity else { return }
        let requestGeneration = identityGeneration
        isResponding = true
        defer {
            if isCurrent(identity: identity, generation: requestGeneration) {
                isResponding = false
            }
        }
        do {
            let acknowledgement: AttendanceAcknowledgement
            if let localClient {
                acknowledgement = try await localClient.respond(eventID: eventID, response: response)
            } else if let baseURL, let account {
                let value = Self.wireAttendance(response)
                acknowledgement = try await InvitationAPIClient(baseURL: baseURL).request("api/events/invitations",
                    method: "POST", body: ["eventId": eventID.uuidString, "attendance": value])
                guard self.account?.id == account.id else { return }
            } else { return }
            guard isCurrent(identity: identity, generation: requestGeneration) else { return }
            if let index = events.firstIndex(where: { $0.id == acknowledgement.eventId }) {
                events[index].attendance = acknowledgement.attendance
                let viewer = events[index].viewerPersonId
                events[index].people = events[index].people.map { person in
                    var person = person
                    if person.id == viewer { person.attendance = acknowledgement.attendance }
                    return person
                }
                rebuildPresentations()
                try saveCache()
            }
            await refresh(force: true)
        } catch {
            guard isCurrent(identity: identity, generation: requestGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func canLeave(eventID: UUID) -> Bool {
        events.contains { $0.id == eventID && $0.role == "guest" }
    }

    func leave(eventID: UUID) async -> Bool {
        guard !isResponding, canLeave(eventID: eventID), let transport = activeTransport,
              let identity = activeIdentity else { return false }
        let requestGeneration = identityGeneration
        isResponding = true
        defer {
            if isCurrent(identity: identity, generation: requestGeneration) {
                isResponding = false
            }
        }
        do {
            let acknowledgedEventID = try await transport.leaveInvitation(eventID: eventID)
            guard isCurrent(identity: identity, generation: requestGeneration),
                  acknowledgedEventID == eventID else { return false }
            feedRevision = UUID()
            mediaTask?.cancel()
            events.removeAll { $0.id == eventID }
            let retained = Set(events.flatMap { event in [event.coverId].compactMap { $0 } + event.ideas.compactMap(\.imageId) + event.moments.map(\.id) })
            artwork = artwork.filter { retained.contains($0.key) }
            rebuildPresentations()
            do { try saveCache() }
            catch {
                // Never keep a stale invitation on disk after the server has
                // acknowledged departure. The remaining feed is recoverable.
                if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
            }
            errorMessage = nil
            return true
        } catch {
            guard isCurrent(identity: identity, generation: requestGeneration) else { return false }
            errorMessage = AppCopy.Lifecycle.leaveFailed
            return false
        }
    }

    private func rebuildPresentations() {
        if let account {
            presentations = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.makePresentation(account: account, artwork: artwork)) })
        } else if let localGuest {
            presentations = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.makePresentation(localGuest: localGuest, artwork: artwork)) })
        } else {
            presentations = [:]
        }
        if let selectedEventID, presentations[selectedEventID] == nil { self.selectedEventID = nil }
    }

    private var cacheURL: URL? {
        guard let identity = activeIdentity else { return nil }
        let source = "\(baseURL?.absoluteString ?? "local")|\(identity)"
        let key = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: "\(key).json")
    }

    private func saveCache() throws {
        guard let cacheURL else { return }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Cache(events: events, artwork: artwork))
        try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private struct Cache: Codable { let events: [GuestEventInvitation]; let artwork: [UUID: Data] }

    private var activeIdentity: String? { account?.id ?? localGuest?.storageID }

    private func isCurrent(identity: String, generation: UUID) -> Bool {
        activeIdentity == identity && identityGeneration == generation
    }

    private var activeTransport: (any GuestInvitationTransport)? {
        if let localClient { return localClient }
        return account == nil ? nil : client
    }

    private static func wireAttendance(_ response: EventResponse) -> String {
        switch response { case .going: "going"; case .notSure: "not_sure"; case .notGoing: "not_going" }
    }

    private func clearActiveState() {
        refreshTask?.cancel()
        mediaTask?.cancel()
        identityGeneration = UUID()
        feedRevision = UUID()
        refreshTask = nil
        account = nil
        localGuest = nil
        localClient = nil
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        isRefreshing = false
        isResponding = false
        errorMessage = nil
    }
}

@MainActor @Observable
final class InvitationRouter {
    private(set) var pendingToken: UUID?
    var requiresAuthentication = false
    private(set) var didJoinThisSession = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private let storageKey = "pendingEventInvitation"

    init(baseURL: URL?, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL
        self.defaults = defaults
        pendingToken = defaults.string(forKey: storageKey).flatMap(UUID.init(uuidString:))
    }

    func receive(_ url: URL) -> Bool {
        guard let token = Self.token(from: url, baseURL: baseURL) else { return false }
        pendingToken = token
        defaults.set(token.uuidString, forKey: storageKey)
        requiresAuthentication = false
        return true
    }

    static func token(from url: URL, baseURL: URL?) -> UUID? {
        guard let baseURL, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].isEmpty, parts[1] == "join" else { return nil }
        return UUID(uuidString: String(parts[2]))
    }

    func dismiss(joined: Bool = false) {
        pendingToken = nil
        requiresAuthentication = false
        didJoinThisSession = didJoinThisSession || joined
        defaults.removeObject(forKey: storageKey)
    }

    func resetJoinedSession() { didJoinThisSession = false }
}
