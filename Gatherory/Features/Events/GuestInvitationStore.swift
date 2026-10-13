import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor protocol GuestInvitationTransport {
    func invitations() async throws -> GuestInvitationFeed
    func leaveInvitation(eventID: UUID) async throws -> UUID
}

extension InvitationAPIClient: GuestInvitationTransport {
    func invitations() async throws -> GuestInvitationFeed { try await request("api/events/invitations") }
    func leaveInvitation(eventID: UUID) async throws -> UUID {
        struct Acknowledgement: Decodable { let eventId: UUID }
        let result: Acknowledgement = try await request("api/events/invitations", method: "DELETE", body: ["eventId": eventID.uuidString])
        return result.eventId
    }
}

/// An account-scoped, read-only cache. Never inserted into WorkspaceLibrary or its outbox.
@MainActor @Observable
final class GuestInvitationStore {
    private(set) var events: [GuestEventInvitation] = []
    private(set) var presentations: [UUID: PlanningWorkspace] = [:]
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var isResponding = false
    var selectedEventID: UUID?
    @ObservationIgnored private var account: UserAccount?
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let injectedClient: (any GuestInvitationTransport)?
    @ObservationIgnored private var artwork: [UUID: Data] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var feedRevision = UUID()

    init(baseURL: URL?, cacheDirectory: URL? = nil, client: (any GuestInvitationTransport)? = nil) {
        self.baseURL = baseURL
        injectedClient = client
        self.cacheDirectory = cacheDirectory ?? URL.applicationSupportDirectory.appending(path: "GuestInvitations")
    }

    var selectedPresentation: PlanningWorkspace? { selectedEventID.flatMap { presentations[$0] } }

    private var client: (any GuestInvitationTransport)? {
        injectedClient ?? baseURL.map { InvitationAPIClient(baseURL: $0) }
    }

    func purgeCache(accountID: String) throws {
        let source = "\(baseURL?.absoluteString ?? "local")|\(accountID)"
        let key = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = cacheDirectory.appending(path: "\(key).json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        if account?.id == accountID {
            refreshTask?.cancel()
            mediaTask?.cancel()
            account = nil
            events = []
            presentations = [:]
            artwork = [:]
            selectedEventID = nil
            isRefreshing = false
            isResponding = false
            errorMessage = nil
        }
    }

    func activate(account newAccount: UserAccount?) async {
        guard account?.id != newAccount?.id else { return }
        refreshTask?.cancel()
        mediaTask?.cancel()
        feedRevision = UUID()
        refreshTask = nil
        account = newAccount
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        errorMessage = nil
        isRefreshing = false
        guard newAccount != nil else { return }
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
        guard account != nil, client != nil else { return }
        let task = Task { await loadFeed() }
        refreshTask = task
        await task.value
    }

    private func loadFeed() async {
        guard let account, let client else { return }
        let userID = account.id
        let requestRevision = feedRevision
        isRefreshing = true
        defer {
            if self.account?.id == userID {
                isRefreshing = false
                refreshTask = nil
            }
        }
        do {
            let feed = try await client.invitations()
            guard self.account?.id == userID, feedRevision == requestRevision, !Task.isCancelled else { return }
            events = feed.events
            let revision = UUID()
            feedRevision = revision
            let retainedArtwork = Set(events.flatMap { event in [event.coverId].compactMap { $0 } + event.ideas.compactMap(\.imageId) + event.moments.map(\.id) })
            artwork = artwork.filter { retainedArtwork.contains($0.key) }
            rebuildPresentations()
            try saveCache()
            // Save text first; image failures must not hide the invitation.
            mediaTask?.cancel()
            mediaTask = Task { await downloadArtwork(events: feed.events, userID: userID, revision: revision) }
            errorMessage = nil
        } catch {
            guard self.account?.id == userID, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func downloadArtwork(events: [GuestEventInvitation], userID: String, revision: UUID) async {
            for event in events {
                let images = [(event.coverId, event.coverURL)] + event.ideas.map { ($0.imageId, $0.imageURL) } + event.moments.map { (Optional($0.id), $0.imageURL) }
                for (id, url) in images {
                    guard let id, let url, ["https", "http"].contains(url.scheme), artwork[id] == nil else { continue }
                    if let (data, response) = try? await URLSession.shared.data(from: url),
                       let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                       data.count <= 12_000_000, UIImage(data: data) != nil {
                        guard self.account?.id == userID, feedRevision == revision, !Task.isCancelled else { return }
                        artwork[id] = data
                    }
                }
            }
            guard self.account?.id == userID, feedRevision == revision, !Task.isCancelled else { return }
            rebuildPresentations()
            try? saveCache()
    }

    func respond(eventID: UUID, response: EventResponse) async {
        guard !isResponding, let baseURL, let userID = account?.id else { return }
        isResponding = true
        defer { isResponding = false }
        let value = switch response { case .going: "going"; case .notSure: "not_sure"; case .notGoing: "not_going" }
        do {
            let acknowledgement: AttendanceAcknowledgement = try await InvitationAPIClient(baseURL: baseURL).request("api/events/invitations",
                method: "POST", body: ["eventId": eventID.uuidString, "attendance": value])
            guard account?.id == userID else { return }
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
            guard account?.id == userID else { return }
            errorMessage = error.localizedDescription
        }
    }

    func canLeave(eventID: UUID) -> Bool {
        events.contains { $0.id == eventID && $0.role == "guest" }
    }

    func leave(eventID: UUID) async -> Bool {
        guard !isResponding, canLeave(eventID: eventID), let client, let userID = account?.id else { return false }
        isResponding = true
        defer { if account?.id == userID { isResponding = false } }
        do {
            let acknowledgedEventID = try await client.leaveInvitation(eventID: eventID)
            guard account?.id == userID, acknowledgedEventID == eventID else { return false }
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
            guard account?.id == userID else { return false }
            errorMessage = AppCopy.Lifecycle.leaveFailed
            return false
        }
    }

    private func rebuildPresentations() {
        guard let account else { return }
        presentations = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0.makePresentation(account: account, artwork: artwork)) })
        if let selectedEventID, presentations[selectedEventID] == nil { self.selectedEventID = nil }
    }

    private var cacheURL: URL? {
        guard let account else { return nil }
        let source = "\(baseURL?.absoluteString ?? "local")|\(account.id)"
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
    private struct AttendanceAcknowledgement: Decodable { let eventId: UUID; let attendance: String }
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
