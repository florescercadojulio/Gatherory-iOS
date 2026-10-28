import CryptoKit
import Foundation
import Observation
import UIKit

@MainActor protocol GuestInvitationCacheIO {
    /// Returns nil only when the file does not exist. Read failures must throw.
    func readData(at url: URL) throws -> Data?
    func writeAtomically(_ data: Data, to url: URL) throws
    /// Removing a file that is already absent succeeds.
    func removeItem(at url: URL) throws
}

@MainActor struct FileGuestInvitationCacheIO: GuestInvitationCacheIO {
    func readData(at url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func writeAtomically(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func removeItem(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Repeated purge and journal reconciliation are safe.
        }
    }
}

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

/// Transient feedback belongs to one event and is discarded on identity changes.
/// A failed attempt retains the choice for an explicit retry, never an offline send.
struct GuestAttendanceUpdate: Equatable {
    enum Phase: Equatable {
        case sending
        case saved
        case failed(String)
    }

    let eventID: UUID
    let response: EventResponse
    let phase: Phase
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
    private(set) var attendanceUpdate: GuestAttendanceUpdate?
    var selectedEventID: UUID?
    @ObservationIgnored private var account: UserAccount?
    @ObservationIgnored private var localGuest: LocalGuestProfile?
    @ObservationIgnored private var localClient: (any LocalGuestInvitationTransport)?
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private let cacheDirectory: URL
    @ObservationIgnored private let cacheIO: any GuestInvitationCacheIO
    @ObservationIgnored private let injectedClient: (any GuestInvitationTransport)?
    @ObservationIgnored private let localClientFactory: @MainActor (LocalGuestProfile) -> any LocalGuestInvitationTransport
    @ObservationIgnored private var artwork: [UUID: Data] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var mediaTask: Task<Void, Never>?
    @ObservationIgnored private var feedRevision = UUID()
    @ObservationIgnored private var identityGeneration = UUID()
    @ObservationIgnored private var leaveIntentEventIDs: Set<UUID> = []
    @ObservationIgnored private var leaveJournalUnreadable = false
    @ObservationIgnored private var leaveRequestsInFlight: Set<UUID> = []
    @ObservationIgnored private var accountCacheNeedsRefresh = false

    init(
        baseURL: URL?,
        cacheDirectory: URL? = nil,
        client: (any GuestInvitationTransport)? = nil,
        localClientFactory: (@MainActor (LocalGuestProfile) -> any LocalGuestInvitationTransport)? = nil,
        cacheIO: (any GuestInvitationCacheIO)? = nil
    ) {
        self.baseURL = baseURL
        injectedClient = client
        self.cacheDirectory = cacheDirectory ?? URL.applicationSupportDirectory.appending(path: "GuestInvitations")
        self.cacheIO = cacheIO ?? FileGuestInvitationCacheIO()
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
        let file = cacheURL(identity: identity)
        try cacheIO.removeItem(at: file)
        try cacheIO.removeItem(at: leaveJournalURL(for: file))
        if activeIdentity == identity { leaveIntentEventIDs = []; leaveJournalUnreadable = false }
    }

    func activate(account newAccount: UserAccount?, refreshRemote: Bool = true) async {
        guard account?.id != newAccount?.id || localGuest != nil else {
            if refreshRemote, newAccount != nil, accountCacheNeedsRefresh {
                await refresh()
            }
            return
        }
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
        attendanceUpdate = nil
        leaveIntentEventIDs = []
        leaveJournalUnreadable = false
        leaveRequestsInFlight = []
        accountCacheNeedsRefresh = newAccount != nil
        guard newAccount != nil else { return }
        restoreCache()
        if refreshRemote { await refresh() }
    }

    func activate(localGuest newGuest: LocalGuestProfile?) async {
        guard localGuest?.id != newGuest?.id || account != nil else { return }
        refreshTask?.cancel()
        mediaTask?.cancel()
        identityGeneration = UUID()
        feedRevision = UUID()
        refreshTask = nil
        account = nil
        accountCacheNeedsRefresh = false
        localGuest = newGuest
        localClient = newGuest.map(localClientFactory)
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        errorMessage = nil
        isRefreshing = false
        isResponding = false
        attendanceUpdate = nil
        leaveIntentEventIDs = []
        leaveJournalUnreadable = false
        leaveRequestsInFlight = []
        guard newGuest != nil else { return }
        restoreCache()
        await refresh()
    }

    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            if !force { return }
        }
        guard activeIdentity != nil, activeTransport != nil else { return }
        accountCacheNeedsRefresh = false
        let task = Task { await loadFeed() }
        refreshTask = task
        await task.value
    }

    private func loadFeed() async {
        guard let identity = activeIdentity, let transport = activeTransport else { return }
        let requestGeneration = identityGeneration
        let requestRevision = feedRevision
        let leaveRequestsAtStart = leaveRequestsInFlight
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
            // A fresh server feed resolves every leave intent, including a
            // previously ambiguous request or a later explicit rejoin. Keep
            // the journal until this authoritative snapshot is safely cached.
            var cacheAndJournalSaved = false
            do {
                try saveCache()
                try clearLeaveIntentsAfterCacheWrite(preserving: leaveRequestsAtStart)
                cacheAndJournalSaved = true
            } catch {
                errorMessage = cacheRecoveryMessage
            }
            // Save text first; image failures must not hide the invitation.
            mediaTask?.cancel()
            mediaTask = Task { await downloadArtwork(events: feed.events, identity: identity, revision: revision) }
            if cacheAndJournalSaved { errorMessage = nil }
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
        guard !isResponding, let identity = activeIdentity,
              events.contains(where: { $0.id == eventID }),
              localClient != nil || (baseURL != nil && account != nil) else { return }
        let requestGeneration = identityGeneration
        isResponding = true
        errorMessage = nil
        attendanceUpdate = GuestAttendanceUpdate(eventID: eventID, response: response, phase: .sending)
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
            guard acknowledgement.eventId == eventID,
                  ["going", "not_sure", "not_going"].contains(acknowledgement.attendance) else {
                throw EventInvitationFailure.unavailable
            }
            // An older feed request must not overwrite the acknowledged response.
            feedRevision = UUID()
            attendanceUpdate = GuestAttendanceUpdate(eventID: eventID, response: response, phase: .saved)
            if let index = events.firstIndex(where: { $0.id == eventID }) {
                events[index].attendance = acknowledgement.attendance
                let viewer = events[index].viewerPersonId
                events[index].people = events[index].people.map { person in
                    var person = person
                    if person.id == viewer { person.attendance = acknowledgement.attendance }
                    return person
                }
                rebuildPresentations()
                // A local-cache failure cannot turn a confirmed remote RSVP into
                // an unconfirmed write. A subsequent refresh can recover the cache.
                do { try saveCache() }
                catch { errorMessage = error.localizedDescription }
            }
            await refresh(force: true)
        } catch {
            guard isCurrent(identity: identity, generation: requestGeneration) else { return }
            attendanceUpdate = GuestAttendanceUpdate(eventID: eventID, response: response,
                                                    phase: .failed(error.localizedDescription))
        }
    }

    func retryAttendanceResponse(eventID: UUID) async {
        guard let update = attendanceUpdate, update.eventID == eventID,
              case .failed = update.phase else { return }
        await respond(eventID: eventID, response: update.response)
    }

    func canLeave(eventID: UUID) -> Bool {
        events.contains { $0.id == eventID && $0.role == "guest" }
    }

    func leave(eventID: UUID) async -> Bool {
        guard !isResponding, canLeave(eventID: eventID), let transport = activeTransport,
              let identity = activeIdentity, !leaveJournalUnreadable else { return false }
        let requestGeneration = identityGeneration
        var nextLeaveIntents = leaveIntentEventIDs
        nextLeaveIntents.insert(eventID)
        do {
            try writeLeaveIntents(nextLeaveIntents)
            leaveIntentEventIDs = nextLeaveIntents
        } catch {
            errorMessage = cacheRecoveryMessage
            return false
        }
        mediaTask?.cancel()
        mediaTask = nil
        leaveRequestsInFlight.insert(eventID)
        // Fence any older feed before yielding to the DELETE request. If it
        // completes later, it cannot restore the invitation from stale data.
        feedRevision = UUID()
        isResponding = true
        defer {
            if isCurrent(identity: identity, generation: requestGeneration) {
                isResponding = false
                leaveRequestsInFlight.remove(eventID)
            }
        }
        do {
            let acknowledgedEventID = try await transport.leaveInvitation(eventID: eventID)
            guard isCurrent(identity: identity, generation: requestGeneration) else { return false }
            guard acknowledgedEventID == eventID else {
                errorMessage = AppCopy.Lifecycle.leaveFailed
                return false
            }
            feedRevision = UUID()
            mediaTask?.cancel()
            events.removeAll { $0.id == eventID }
            if attendanceUpdate?.eventID == eventID { attendanceUpdate = nil }
            let retained = Set(events.flatMap { event in [event.coverId].compactMap { $0 } + event.ideas.compactMap(\.imageId) + event.moments.map(\.id) })
            artwork = artwork.filter { retained.contains($0.key) }
            rebuildPresentations()
            do { try saveCache() }
            catch {
                // The durable intent remains until the current cache is safe.
                // Removing a stale cache is best effort; a later authoritative
                // feed will repair it and resolve the intent.
                if let cacheURL { try? cacheIO.removeItem(at: cacheURL) }
                errorMessage = cacheRecoveryMessage
                return true
            }
            var resolvedLeaveIntents = leaveIntentEventIDs
            resolvedLeaveIntents.remove(eventID)
            do {
                try writeLeaveIntents(resolvedLeaveIntents)
                leaveIntentEventIDs = resolvedLeaveIntents
                leaveJournalUnreadable = false
            } catch {
                // The current cache is safe. Keep the old journal so the next
                // launch still filters any cache that could predate this write.
                errorMessage = cacheRecoveryMessage
                return true
            }
            if leaveIntentEventIDs.isEmpty { errorMessage = nil }
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
        return cacheURL(identity: identity)
    }

    private func cacheURL(identity: String) -> URL {
        let source = "\(baseURL?.absoluteString ?? "local")|\(identity)"
        let key = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appending(path: "\(key).json")
    }

    private func leaveJournalURL(for cacheURL: URL) -> URL {
        cacheURL.deletingPathExtension().appendingPathExtension("leave-intents.json")
    }

    private func restoreCache() {
        guard let cacheURL else { return }
        do {
            let journalURL = leaveJournalURL(for: cacheURL)
            if let journalData = try cacheIO.readData(at: journalURL) {
                let journal = try JSONDecoder().decode(LeaveIntentJournal.self, from: journalData)
                guard journal.schemaVersion == LeaveIntentJournal.currentSchemaVersion else {
                    throw LeaveIntentJournalError.unsupportedVersion
                }
                leaveIntentEventIDs = Set(journal.eventIDs)
            }
        } catch {
            // Unknown intents make the cache unsafe to display. A fresh feed
            // can replace the journal after its cache has been written.
            leaveIntentEventIDs = []
            leaveJournalUnreadable = true
            errorMessage = cacheRecoveryMessage
            return
        }

        do {
            guard let data = try cacheIO.readData(at: cacheURL) else { return }
            let cache = try JSONDecoder().decode(Cache.self, from: data)
            events = cache.events.filter { !leaveIntentEventIDs.contains($0.id) }
            let retainedArtwork = artworkIDs(in: events)
            artwork = cache.artwork.filter { retainedArtwork.contains($0.key) }
            rebuildPresentations()
        } catch {
            errorMessage = cacheRecoveryMessage
        }
    }

    private func artworkIDs(in events: [GuestEventInvitation]) -> Set<UUID> {
        Set(events.flatMap { event in
            [event.coverId].compactMap { $0 }
                + event.ideas.compactMap(\.imageId)
                + event.moments.map(\.id)
        })
    }

    private func writeLeaveIntents(_ eventIDs: Set<UUID>) throws {
        guard let cacheURL else { throw EventInvitationFailure.unavailable }
        let journalURL = leaveJournalURL(for: cacheURL)
        guard !eventIDs.isEmpty else {
            try cacheIO.removeItem(at: journalURL)
            return
        }
        let journal = LeaveIntentJournal(schemaVersion: LeaveIntentJournal.currentSchemaVersion,
                                         eventIDs: eventIDs.sorted { $0.uuidString < $1.uuidString })
        try cacheIO.writeAtomically(try JSONEncoder().encode(journal), to: journalURL)
    }

    private func clearLeaveIntentsAfterCacheWrite(preserving inFlight: Set<UUID>) throws {
        guard leaveJournalUnreadable || !leaveIntentEventIDs.isEmpty else { return }
        // A feed started while DELETE was still in flight can predate its
        // server-side effect. Keep those markers until a later feed begins
        // after the request has settled.
        let remaining = leaveJournalUnreadable ? [] : leaveIntentEventIDs.intersection(inFlight)
        try writeLeaveIntents(remaining)
        leaveIntentEventIDs = remaining
        leaveJournalUnreadable = false
    }

    private func saveCache() throws {
        guard let cacheURL else { return }
        let data = try JSONEncoder().encode(Cache(events: events, artwork: artwork))
        try cacheIO.writeAtomically(data, to: cacheURL)
    }

    private struct Cache: Codable { let events: [GuestEventInvitation]; let artwork: [UUID: Data] }

    private struct LeaveIntentJournal: Codable {
        static let currentSchemaVersion = 1
        let schemaVersion: Int
        let eventIDs: [UUID]
    }

    private enum LeaveIntentJournalError: Error { case unsupportedVersion }

    private var cacheRecoveryMessage: String {
        String(localized: "Saved invitations need to be refreshed. Try again when you’re online.")
    }

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
        accountCacheNeedsRefresh = false
        localGuest = nil
        localClient = nil
        events = []
        presentations = [:]
        artwork = [:]
        selectedEventID = nil
        isRefreshing = false
        isResponding = false
        leaveIntentEventIDs = []
        leaveJournalUnreadable = false
        leaveRequestsInFlight = []
        attendanceUpdate = nil
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
