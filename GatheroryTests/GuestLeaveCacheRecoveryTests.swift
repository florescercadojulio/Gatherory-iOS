import Foundation
import Testing
@testable import Gatherory

struct GuestLeaveCacheRecoveryTests {
    @Test("A durable leave intent is written before DELETE")
    @MainActor func intentPrecedesDelete() async throws {
        let event = try fixture()
        let timeline = LeaveOperationTimeline()
        let io = MemoryGuestInvitationCacheIO(timeline: timeline)
        let transport = LeaveRecoveryTransport(events: [event], timeline: timeline)
        let (store, directory) = makeStore(io: io, transport: transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.activate(account: account("account-a"))
        timeline.entries.removeAll()

        #expect(await store.leave(eventID: event.id))

        let intentWrite = try #require(timeline.entries.firstIndex(of: "write-intent"))
        let deleteRequest = try #require(timeline.entries.firstIndex(of: "delete"))
        #expect(intentWrite < deleteRequest)
        #expect(transport.leaveRequests == [event.id])
        #expect(store.events.isEmpty)
        #expect(io.journalURLs(in: directory).allSatisfy { io.files[$0] == nil })
    }

    @Test("A confirmed leave remains hidden offline after cache write and delete fail, without affecting other principals or origins")
    @MainActor func confirmedLeaveRecoveryIsScopedAndDoesNotReplayDelete() async throws {
        let left = try fixture(), other = try fixture(), otherAccountEvent = try fixture(), otherOriginEvent = try fixture()
        let timeline = LeaveOperationTimeline()
        let io = MemoryGuestInvitationCacheIO(timeline: timeline)
        let transport = LeaveRecoveryTransport(events: [left, other], timeline: timeline)
        transport.leaveBehavior = .delayed
        let (store, directory) = makeStore(io: io, transport: transport, baseURL: url("https://one.example"))
        let accountBTransport = LeaveRecoveryTransport(events: [otherAccountEvent])
        let (accountBStore, _) = makeStore(io: io, transport: accountBTransport, baseURL: url("https://one.example"), cacheDirectory: directory)
        let otherOriginTransport = LeaveRecoveryTransport(events: [otherOriginEvent])
        let (otherOriginStore, _) = makeStore(io: io, transport: otherOriginTransport, baseURL: url("https://two.example"), cacheDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.activate(account: account("account-a"))
        await accountBStore.activate(account: account("account-b"))
        await otherOriginStore.activate(account: account("account-a"))
        // Identify the target cache by its contents so same-origin and other-origin
        // cache entries remain independent in this shared test directory.
        let targetCacheURL = try #require(io.cacheURLs(in: directory).first { url in
            guard let data = io.files[url],
                  let decoded = try? JSONDecoder().decode(GuestInvitationFeed.self, from: data) else { return false }
            return decoded.events.map(\.id).sorted(by: { $0.uuidString < $1.uuidString })
                == [left.id, other.id].sorted(by: { $0.uuidString < $1.uuidString })
        })
        let leaveTask = Task { await store.leave(eventID: left.id) }
        while !transport.hasStartedLeave { await Task.yield() }
        // This feed began after the intent was persisted but before DELETE was
        // acknowledged. The server still returns the old invitation snapshot.
        await store.refresh(force: true)
        io.failWrites.insert(targetCacheURL)
        io.failRemovals.insert(targetCacheURL)
        transport.releaseLeave()
        #expect(await leaveTask.value)
        #expect(transport.leaveRequests == [left.id])

        transport.failRefresh = true
        let (restored, _) = makeStore(io: io, transport: transport, baseURL: url("https://one.example"), cacheDirectory: directory)
        await restored.activate(account: account("account-a"))
        #expect(restored.events.map(\.id) == [other.id])
        #expect(transport.leaveRequests == [left.id])

        accountBTransport.failRefresh = true
        let (restoredAccountB, _) = makeStore(io: io, transport: accountBTransport, baseURL: url("https://one.example"), cacheDirectory: directory)
        await restoredAccountB.activate(account: account("account-b"))
        #expect(restoredAccountB.events.map(\.id) == [otherAccountEvent.id])

        otherOriginTransport.failRefresh = true
        let (restoredOtherOrigin, _) = makeStore(io: io, transport: otherOriginTransport, baseURL: url("https://two.example"), cacheDirectory: directory)
        await restoredOtherOrigin.activate(account: account("account-a"))
        #expect(restoredOtherOrigin.events.map(\.id) == [otherOriginEvent.id])
    }

    @Test("A leave intent write failure prevents DELETE")
    @MainActor func failedIntentPersistencePreventsDelete() async throws {
        let event = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let transport = LeaveRecoveryTransport(events: [event])
        let (store, directory) = makeStore(io: io, transport: transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.activate(account: account("account-a"))
        io.failNextWrite = true

        #expect(await store.leave(eventID: event.id) == false)

        #expect(transport.leaveRequests.isEmpty)
        #expect(store.events.map(\.id) == [event.id])
    }

    @Test("An uncertain leave failure keeps the invitation until an authoritative feed recovers it")
    @MainActor func uncertainFailureRecoversFromFeed() async throws {
        let event = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let transport = LeaveRecoveryTransport(events: [event])
        transport.leaveBehavior = .uncertainFailure
        let (store, directory) = makeStore(io: io, transport: transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.activate(account: account("account-a"))

        #expect(await store.leave(eventID: event.id) == false)
        #expect(store.events.map(\.id) == [event.id])
        #expect(transport.leaveRequests == [event.id])
        #expect(io.journalURLs(in: directory).contains { io.files[$0] != nil })

        await store.refresh(force: true)

        #expect(store.events.map(\.id) == [event.id])
        #expect(transport.leaveRequests == [event.id])
        #expect(io.journalURLs(in: directory).allSatisfy { io.files[$0] == nil })
    }

    @Test("A corrupt leave journal fails closed for that cached identity")
    @MainActor func corruptJournalFailsClosed() async throws {
        let event = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let transport = LeaveRecoveryTransport(events: [event])
        let (seed, directory) = makeStore(io: io, transport: transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        await seed.activate(account: account("account-a"))
        let cacheURL = try #require(io.cacheURLs(in: directory).first)
        let journalURL = cacheURL.deletingPathExtension().appendingPathExtension("leave-intents.json")
        io.setData(Data("not a journal".utf8), at: journalURL)
        transport.failRefresh = true

        let (restored, _) = makeStore(io: io, transport: transport, cacheDirectory: directory)
        await restored.activate(account: account("account-a"))

        #expect(restored.events.isEmpty)
        #expect(await restored.leave(eventID: event.id) == false)
        #expect(transport.leaveRequests.isEmpty)

        transport.failRefresh = false
        await restored.refresh(force: true)
        #expect(restored.events.map(\.id) == [event.id])
        #expect(io.data(at: journalURL) == nil)
        transport.failRefresh = true
        let (reopened, _) = makeStore(io: io, transport: transport, cacheDirectory: directory)
        await reopened.activate(account: account("account-a"))
        #expect(reopened.events.map(\.id) == [event.id])
    }

    @Test("Purging one account removes its cache before its journal and preserves other accounts")
    @MainActor func purgeIsOrderedAndPrincipalScoped() async throws {
        let accountAEvent = try fixture(), accountBEvent = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transportA = LeaveRecoveryTransport(events: [accountAEvent])
        transportA.leaveBehavior = .uncertainFailure
        let (storeA, _) = makeStore(io: io, transport: transportA, baseURL: url("https://one.example"), cacheDirectory: directory)
        let transportB = LeaveRecoveryTransport(events: [accountBEvent])
        let (storeB, _) = makeStore(io: io, transport: transportB, baseURL: url("https://one.example"), cacheDirectory: directory)
        await storeA.activate(account: account("account-a"))
        await storeB.activate(account: account("account-b"))
        #expect(await storeA.leave(eventID: accountAEvent.id) == false)

        let accountACache = try #require(io.cacheURLs(in: directory).first { cacheURL in
            guard let data = io.data(at: cacheURL),
                  let decoded = try? JSONDecoder().decode(GuestInvitationFeed.self, from: data) else { return false }
            return decoded.events.contains { $0.id == accountAEvent.id }
        })
        let accountBCache = try #require(io.cacheURLs(in: directory).first { cacheURL in
            guard let data = io.data(at: cacheURL),
                  let decoded = try? JSONDecoder().decode(GuestInvitationFeed.self, from: data) else { return false }
            return decoded.events.contains { $0.id == accountBEvent.id }
        })
        let accountAJournal = accountACache.deletingPathExtension().appendingPathExtension("leave-intents.json")
        io.clearRemovals()

        io.failRemovals.insert(accountACache)
        #expect(throws: (any Error).self) { try storeA.purgeCache(accountID: "account-a") }
        #expect(io.removals == [accountACache])
        #expect(io.data(at: accountAJournal) != nil)
        #expect(io.data(at: accountBCache) != nil)

        io.failRemovals.remove(accountACache)
        io.failRemovals.insert(accountAJournal)
        io.clearRemovals()
        #expect(throws: (any Error).self) { try storeA.purgeCache(accountID: "account-a") }
        #expect(io.removals == [accountACache, accountAJournal])
        #expect(io.data(at: accountACache) == nil)
        #expect(io.data(at: accountAJournal) != nil)
        #expect(io.data(at: accountBCache) != nil)

        io.failRemovals.remove(accountAJournal)
        io.clearRemovals()
        try storeA.purgeCache(accountID: "account-a")

        #expect(io.removals.suffix(2).elementsEqual([accountACache, accountAJournal]))
        #expect(io.data(at: accountACache) == nil)
        #expect(io.data(at: accountAJournal) == nil)
        #expect(io.data(at: accountBCache) != nil)
    }

    @Test("A fresh authoritative feed makes a rejoined event visible again")
    @MainActor func freshRejoinIsVisible() async throws {
        let event = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let transport = LeaveRecoveryTransport(events: [event])
        let (store, directory) = makeStore(io: io, transport: transport)
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.activate(account: account("account-a"))
        let cacheURL = try #require(io.cacheURLs(in: directory).first)
        io.failWrites.insert(cacheURL)

        #expect(await store.leave(eventID: event.id))
        #expect(store.events.isEmpty)
        #expect(io.journalURLs(in: directory).contains { io.files[$0] != nil })

        io.failWrites.remove(cacheURL)
        transport.events = [event]
        await store.refresh(force: true)

        #expect(store.events.map(\.id) == [event.id])
        #expect(io.journalURLs(in: directory).allSatisfy { io.files[$0] == nil })
        transport.failRefresh = true
        let (restored, _) = makeStore(io: io, transport: transport, cacheDirectory: directory)
        await restored.activate(account: account("account-a"))
        #expect(restored.events.map(\.id) == [event.id])
    }

    @Test("A delayed A to B to A leave completion cannot mutate the next session")
    @MainActor func staleRoundTripLeaveDoesNotMutateNextSession() async throws {
        let event = try fixture(), other = try fixture()
        let io = MemoryGuestInvitationCacheIO()
        let transport = LeaveRecoveryTransport(events: [event, other])
        transport.leaveBehavior = .delayed
        let directory = uniqueDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let guestA = LocalGuestProfile(displayName: "Guest A")
        let store = GuestInvitationStore(
            baseURL: nil,
            cacheDirectory: directory,
            localClientFactory: { _ in transport },
            cacheIO: io
        )
        await store.activate(localGuest: guestA)

        let task = Task { await store.leave(eventID: event.id) }
        while !transport.hasStartedLeave { await Task.yield() }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest B"))
        await store.activate(localGuest: guestA)
        let visibleIDsBeforeAcknowledgement = store.events.map(\.id)
        transport.releaseLeave()
        #expect(await task.value == false)

        #expect(store.events.map(\.id) == visibleIDsBeforeAcknowledgement)
        #expect(store.events.contains { $0.id == other.id })
        #expect(!store.isResponding)
        #expect(transport.leaveRequests == [event.id])
    }

    @MainActor private func makeStore(
        io: MemoryGuestInvitationCacheIO,
        transport: LeaveRecoveryTransport,
        baseURL: URL? = nil,
        cacheDirectory: URL? = nil
    ) -> (GuestInvitationStore, URL) {
        let directory = cacheDirectory ?? uniqueDirectory()
        let store = GuestInvitationStore(baseURL: baseURL, cacheDirectory: directory, client: transport, cacheIO: io)
        return (store, directory)
    }

    @MainActor private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.com", displayName: id, role: .member,
                    authenticationProvider: .password, createdAt: .now)
    }

    @MainActor private func fixture() throws -> GuestEventInvitation {
        let eventID = UUID(), personID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": eventID.uuidString, "title": "Shared event", "startsAt": "2027-06-13T20:00:00Z",
            "isAllDay": false, "timeZone": "America/Detroit", "complete": "upcoming", "role": "guest",
            "viewerPersonId": personID.uuidString, "attendance": "going",
            "people": [["id": personID.uuidString, "name": "Guest", "role": "guest", "attendance": "going"]],
            "ideas": [], "moments": [],
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GuestEventInvitation.self, from: data)
    }

    private func url(_ value: String) -> URL? { URL(string: value) }

    private func uniqueDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "guest-leave-cache-test-\(UUID())")
    }
}

@MainActor private final class MemoryGuestInvitationCacheIO: GuestInvitationCacheIO {
    private(set) var files: [URL: Data] = [:]
    private(set) var writes: [URL] = []
    private(set) var removals: [URL] = []
    var failNextWrite = false
    var failWrites = Set<URL>()
    var failRemovals = Set<URL>()
    let timeline: LeaveOperationTimeline?

    init(timeline: LeaveOperationTimeline? = nil) { self.timeline = timeline }

    func readData(at url: URL) throws -> Data? { files[url] }

    func data(at url: URL) -> Data? { files[url] }

    func setData(_ data: Data, at url: URL) { files[url] = data }

    func clearRemovals() { removals.removeAll() }

    func writeAtomically(_ data: Data, to url: URL) throws {
        writes.append(url)
        let isIntent = url.lastPathComponent.hasSuffix(".leave-intents.json")
        timeline?.entries.append(isIntent ? "write-intent" : "write-cache")
        if failNextWrite {
            failNextWrite = false
            throw LeaveCacheIOFailure.injected
        }
        if failWrites.contains(url) { throw LeaveCacheIOFailure.injected }
        files[url] = data
    }

    func removeItem(at url: URL) throws {
        removals.append(url)
        if failRemovals.contains(url) { throw LeaveCacheIOFailure.injected }
        files.removeValue(forKey: url)
    }

    func cacheURLs(in directory: URL) -> [URL] {
        files.keys.filter {
            $0.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
                && !$0.lastPathComponent.hasSuffix(".leave-intents.json")
        }
    }

    func journalURLs(in directory: URL) -> [URL] {
        writes.filter {
            $0.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
                && $0.lastPathComponent.hasSuffix(".leave-intents.json")
        }
    }
}

@MainActor private final class LeaveOperationTimeline {
    var entries: [String] = []
}

private enum LeaveCacheIOFailure: Error { case injected }

@MainActor private final class LeaveRecoveryTransport: LocalGuestInvitationTransport {
    enum LeaveBehavior { case acknowledge, uncertainFailure, delayed }

    var events: [GuestEventInvitation]
    var failRefresh = false
    var leaveBehavior: LeaveBehavior = .acknowledge
    private let timeline: LeaveOperationTimeline?
    private var leaveContinuation: CheckedContinuation<UUID, any Error>?
    private(set) var hasStartedLeave = false
    private(set) var leaveRequests: [UUID] = []

    init(events: [GuestEventInvitation], timeline: LeaveOperationTimeline? = nil) {
        self.events = events
        self.timeline = timeline
    }

    func invitations() async throws -> GuestInvitationFeed {
        if failRefresh { throw LeaveCacheIOFailure.injected }
        return GuestInvitationFeed(events: events)
    }

    func leaveInvitation(eventID: UUID) async throws -> UUID {
        leaveRequests.append(eventID)
        hasStartedLeave = true
        timeline?.entries.append("delete")
        switch leaveBehavior {
        case .acknowledge:
            events.removeAll { $0.id == eventID }
            return eventID
        case .uncertainFailure:
            throw LeaveCacheIOFailure.injected
        case .delayed:
            return try await withCheckedThrowingContinuation { leaveContinuation = $0 }
        }
    }

    func releaseLeave() {
        guard let leaveContinuation else { return }
        self.leaveContinuation = nil
        events.removeAll { $0.id == leaveRequests.last }
        leaveContinuation.resume(returning: leaveRequests.last!)
    }

    func join(token: UUID) async throws -> InvitationAcceptance {
        InvitationAcceptance(eventId: events[0].id, role: "guest", planningScopeId: nil, status: "accepted")
    }

    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        let attendance = switch response { case .going: "going"; case .notSure: "not_sure"; case .notGoing: "not_going" }
        return AttendanceAcknowledgement(eventId: eventID, attendance: attendance)
    }

    func claim() async throws -> GuestClaimAcknowledgement {
        GuestClaimAcknowledgement(claimedEventIds: events.map(\.id))
    }
}
