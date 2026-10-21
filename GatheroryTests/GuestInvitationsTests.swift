import CryptoKit
import Foundation
import Testing
@testable import Gatherory

struct GuestInvitationsTests {
    @Test("Pulling invitations refreshes each person's RSVP for the matching event")
    @MainActor func refreshAttendance() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-rsvp-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try fixture(role: "guest"), other = try fixture(role: "guest")
        let transport = GuestTestTransport(events: [first, other])
        let store = GuestInvitationStore(baseURL: nil, cacheDirectory: directory, client: transport)
        await store.activate(account: account("guest-a"))
        for (wireValue, attendance) in [("not_sure", AttendanceStatus.maybe), ("not_going", .declined), ("going", .going)] {
            transport.events[0].attendance = wireValue
            transport.events[0].people[0].attendance = wireValue
            await store.refresh(force: true)
            #expect(store.presentations[first.id]?.participants(for: .main).first?.attendance == attendance)
            #expect(store.presentations[other.id]?.participants(for: .main).first?.attendance == .going)
        }
        transport.failRefresh = true
        await store.refresh(force: true)
        #expect(store.errorMessage != nil)
        #expect(store.presentations[first.id]?.participants(for: .main).first?.attendance == .going)
    }
    @Test("Leaving a guest invitation requires server acknowledgement and never deletes other events")
    @MainActor func departure() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-leave-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let guest = try fixture(role: "guest"), other = try fixture(role: "guest"), planner = try fixture(role: "collaborator")
        let transport = GuestTestTransport(events: [guest, other, planner])
        let store = GuestInvitationStore(baseURL: nil, cacheDirectory: directory, client: transport)
        await store.activate(account: account("guest-a"))
        #expect(store.canLeave(eventID: guest.id))
        #expect(!store.canLeave(eventID: planner.id))
        transport.failLeave = true
        #expect(await store.leave(eventID: guest.id) == false)
        #expect(store.events.count == 3)
        #expect(store.errorMessage == AppCopy.Lifecycle.leaveFailed)
        transport.failLeave = false
        #expect(await store.leave(eventID: guest.id))
        #expect(store.presentations[guest.id] == nil)
        #expect(store.events.count == 2)
        #expect(store.events.contains { $0.id == other.id })
        #expect(store.events.contains { $0.id == planner.id })
        let restored = GuestInvitationStore(baseURL: nil, cacheDirectory: directory)
        await restored.activate(account: account("guest-a"))
        #expect(restored.events.count == 2)
        #expect(!restored.events.contains { $0.id == guest.id })
    }
    @Test("Invitation intent survives authentication and relaunch, and rejects other hosts")
    @MainActor
    func invitationContinuation() throws {
        let domain = "invitation-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let base = try #require(URL(string: "https://dev.gatherory.com"))
        let token = UUID()
        let router = InvitationRouter(baseURL: base, defaults: defaults)
        #expect(router.receive(URL(string: "https://dev.gatherory.com/join/\(token)")!))
        router.requiresAuthentication = true
        #expect(router.pendingToken == token)
        let restored = InvitationRouter(baseURL: base, defaults: defaults)
        #expect(restored.pendingToken == token)
        for value in ["https://evil.example/join/\(token)", "https://dev.gatherory.com/join/not-a-token", "https://dev.gatherory.com/join/\(token)?next=evil", "https://dev.gatherory.com/join/\(token)/"] {
            #expect(!router.receive(URL(string: value)!))
        }
        #expect(router.pendingToken == token)
        restored.dismiss(joined: true)
        #expect(restored.didJoinThisSession)
        restored.resetJoinedSession()
        #expect(!restored.didJoinThisSession)
        #expect(InvitationRouter(baseURL: base, defaults: defaults).pendingToken == nil)
    }

    @Test("Guest DTOs render invitation content without editable planning state")
    @MainActor
    func guestProjection() throws {
        let event = try fixture(role: "collaborator")
        let workspace = event.makePresentation(account: account("guest-a"), artwork: [:])
        #expect(workspace.currentViewerMember?.userID == "guest-a")
        #expect(!workspace.showsPlanningInterface)
        #expect(!workspace.canManageMainEvent)
        #expect(!workspace.canDeleteMainEvent)
        #expect(!workspace.canAddEventMoments(to: .main))
        #expect(workspace.workspaceBudgetCap == nil)
        #expect(workspace.eventExpenses.isEmpty)
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.mainEventResponse == .going)
        #expect(workspace.invitationIdeas(for: .main).count == 1)
        #expect(workspace.invitationIdeas(for: .main).first?.musicTracks.first?.title == "BABYDOLL (Speed)")
    }

    @Test("Offline guest cache is account isolated and cleared from memory on sign out")
    @MainActor
    func accountScopedCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-cache-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try fixture(role: "guest")
        struct Cache: Encodable { let events: [GuestEventInvitation]; let artwork: [UUID: Data] }
        let key = SHA256.hash(data: Data("local|guest-a".utf8)).map { String(format: "%02x", $0) }.joined()
        try JSONEncoder().encode(Cache(events: [event], artwork: [:])).write(to: directory.appending(path: "\(key).json"))
        let store = GuestInvitationStore(baseURL: nil, cacheDirectory: directory)
        await store.activate(account: account("guest-a"))
        #expect(store.events.count == 1)
        #expect(store.presentations[event.id] != nil)
        await store.activate(account: account("guest-b"))
        #expect(store.events.isEmpty)
        #expect(store.presentations.isEmpty)
        await store.activate(account: account("guest-a"))
        #expect(store.events.count == 1)
        await store.activate(account: nil)
        #expect(store.events.isEmpty)
        #expect(store.selectedPresentation == nil)
        try store.purgeCache(accountID: "guest-a")
        await store.activate(account: account("guest-a"))
        #expect(store.events.isEmpty)
    }

    @Test("Device guest invitations stay in their own cache and configure a locked local viewer")
    @MainActor
    func localGuestCacheAndViewerIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-device-cache-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalGuestProfile(displayName: "Device Planner")
        let guestEvent = try fixture(role: "guest")
        let accountEvent = try fixture(role: "collaborator")
        let localTransport = LocalGuestTestTransport(events: [guestEvent])
        let accountTransport = GuestTestTransport(events: [accountEvent])
        let store = GuestInvitationStore(
            baseURL: nil,
            cacheDirectory: directory,
            client: accountTransport,
            localClientFactory: { _ in localTransport }
        )

        await store.activate(localGuest: profile)
        #expect(store.events.map(\.id) == [guestEvent.id])
        let projection = try #require(store.presentations[guestEvent.id])
        #expect(projection.currentViewerMember?.userID == profile.storageID)
        #expect(projection.isLocalGuestViewer)
        #expect(!projection.showsPlanningInterface)
        #expect(!projection.canManageMainEvent)

        await store.activate(account: account("existing-account"))
        #expect(store.events.map(\.id) == [accountEvent.id])
        #expect(store.presentations[accountEvent.id]?.currentViewerMember?.userID == "existing-account")
        await store.activate(localGuest: profile)
        #expect(store.events.map(\.id) == [guestEvent.id])

        try store.purgeCache(profileID: profile.id)
        #expect(store.events.isEmpty)
        await store.activate(account: account("existing-account"))
        #expect(store.events.map(\.id) == [accountEvent.id])
        localTransport.events = []
        await store.activate(localGuest: profile)
        #expect(store.events.isEmpty)
    }

    @Test("A delayed local guest response cannot overwrite a later signed-in feed")
    @MainActor
    func delayedGuestFeedCannotCrossIntoAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-device-race-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let guest = try fixture(role: "guest")
        let accountEvent = try fixture(role: "collaborator")
        let delayed = DelayedLocalGuestTestTransport(event: guest)
        let accountTransport = GuestTestTransport(events: [accountEvent])
        let profile = LocalGuestProfile(displayName: "Device Planner")
        let store = GuestInvitationStore(
            baseURL: nil,
            cacheDirectory: directory,
            client: accountTransport,
            localClientFactory: { _ in delayed }
        )

        let guestActivation = Task { await store.activate(localGuest: profile) }
        while !delayed.hasStarted { await Task.yield() }
        await store.activate(account: account("existing-account"))
        delayed.release()
        await guestActivation.value
        #expect(store.events.map(\.id) == [accountEvent.id])
        #expect(store.presentations[guest.id] == nil)
    }

    @Test("A delayed RSVP cannot apply after guest A switches to B and back to A")
    @MainActor
    func delayedGuestResponseCannotCrossIdentityGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-rsvp-roundtrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try fixture(role: "guest")
        let transport = DelayedGuestActionTransport(events: [event])
        let store = GuestInvitationStore(
            baseURL: nil,
            cacheDirectory: directory,
            localClientFactory: { _ in transport }
        )
        let guestA = LocalGuestProfile(displayName: "Guest A")
        await store.activate(localGuest: guestA)

        let responseTask = Task { await store.respond(eventID: event.id, response: .notGoing) }
        while !transport.hasStartedResponse { await Task.yield() }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest B"))
        await store.activate(localGuest: guestA)
        transport.releaseResponse()
        await responseTask.value

        #expect(store.events.first?.attendance == "going")
        #expect(!store.isResponding)
    }

    @Test("A delayed leave cannot remove an invitation after guest A switches to B and back to A")
    @MainActor
    func delayedGuestLeaveCannotCrossIdentityGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-leave-roundtrip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = try fixture(role: "guest")
        let transport = DelayedGuestActionTransport(events: [event])
        let store = GuestInvitationStore(
            baseURL: nil,
            cacheDirectory: directory,
            localClientFactory: { _ in transport }
        )
        let guestA = LocalGuestProfile(displayName: "Guest A")
        await store.activate(localGuest: guestA)

        let leaveTask = Task { await store.leave(eventID: event.id) }
        while !transport.hasStartedLeave { await Task.yield() }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest B"))
        await store.activate(localGuest: guestA)
        transport.releaseLeave()

        #expect(await leaveTask.value == false)
        #expect(store.events.map(\.id) == [event.id])
        #expect(!store.isResponding)
    }

    @MainActor
    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.com", displayName: "Guest", role: .member, authenticationProvider: .password, createdAt: .now)
    }

    @MainActor
    private func fixture(role: String) throws -> GuestEventInvitation {
        let eventID = UUID(), personID = UUID()
        let song: [String: Any] = ["providerID": "apple-music", "catalogID": "i.4YBN1YWf2a62bq9", "title": "BABYDOLL (Speed)",
            "artistName": "Ari Abdul", "duration": 156.651]
        let data = try JSONSerialization.data(withJSONObject: [
            "id": eventID.uuidString, "title": "Shared event", "startsAt": "2027-06-13T20:00:00Z",
            "isAllDay": false, "timeZone": "America/Detroit", "complete": "upcoming", "role": role,
            "viewerPersonId": personID.uuidString, "attendance": "going",
            "people": [["id": personID.uuidString, "name": "Guest", "role": role, "attendance": "going"]],
            "ideas": [["id": UUID().uuidString, "category": "music", "title": "Playlist", "note": "", "tracks": [song], "configuration": ["music": ["_0": ["tracks": [song]]]]]], "moments": [],
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GuestEventInvitation.self, from: data)
    }
}

@MainActor private final class GuestTestTransport: GuestInvitationTransport {
    var events: [GuestEventInvitation]
    var failLeave = false
    var failRefresh = false
    init(events: [GuestEventInvitation]) { self.events = events }
    func invitations() async throws -> GuestInvitationFeed {
        if failRefresh { throw EventInvitationFailure.unavailable }
        return GuestInvitationFeed(events: events)
    }
    func leaveInvitation(eventID: UUID) async throws -> UUID {
        if failLeave { throw EventInvitationFailure.unavailable }
        events.removeAll { $0.id == eventID }
        return eventID
    }
}

@MainActor private final class LocalGuestTestTransport: LocalGuestInvitationTransport {
    var events: [GuestEventInvitation]
    var failLeave = false
    init(events: [GuestEventInvitation]) { self.events = events }
    func invitations() async throws -> GuestInvitationFeed { GuestInvitationFeed(events: events) }
    func join(token: UUID) async throws -> InvitationAcceptance {
        InvitationAcceptance(eventId: events[0].id, role: "guest", planningScopeId: nil, status: "accepted")
    }
    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        let value = switch response { case .going: "going"; case .notSure: "not_sure"; case .notGoing: "not_going" }
        return AttendanceAcknowledgement(eventId: eventID, attendance: value)
    }
    func leaveInvitation(eventID: UUID) async throws -> UUID {
        if failLeave { throw EventInvitationFailure.unavailable }
        events.removeAll { $0.id == eventID }
        return eventID
    }
    func claim() async throws -> GuestClaimAcknowledgement { GuestClaimAcknowledgement(claimedEventIds: events.map(\.id)) }
}

@MainActor private final class DelayedLocalGuestTestTransport: LocalGuestInvitationTransport {
    private let event: GuestEventInvitation
    private var continuation: CheckedContinuation<GuestInvitationFeed, Never>?
    private(set) var hasStarted = false
    init(event: GuestEventInvitation) { self.event = event }
    func invitations() async throws -> GuestInvitationFeed {
        hasStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func join(token: UUID) async throws -> InvitationAcceptance {
        InvitationAcceptance(eventId: event.id, role: "guest", planningScopeId: nil, status: "accepted")
    }
    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        AttendanceAcknowledgement(eventId: eventID, attendance: "going")
    }
    func leaveInvitation(eventID: UUID) async throws -> UUID { eventID }
    func claim() async throws -> GuestClaimAcknowledgement { GuestClaimAcknowledgement(claimedEventIds: [event.id]) }
    func release() { continuation?.resume(returning: GuestInvitationFeed(events: [event])); continuation = nil }
}

@MainActor private final class DelayedGuestActionTransport: LocalGuestInvitationTransport {
    var events: [GuestEventInvitation]
    private var responseContinuation: CheckedContinuation<AttendanceAcknowledgement, Never>?
    private var leaveContinuation: CheckedContinuation<UUID, Never>?
    private(set) var hasStartedResponse = false
    private(set) var hasStartedLeave = false

    init(events: [GuestEventInvitation]) { self.events = events }

    func invitations() async throws -> GuestInvitationFeed { GuestInvitationFeed(events: events) }

    func join(token: UUID) async throws -> InvitationAcceptance {
        InvitationAcceptance(eventId: events[0].id, role: "guest", planningScopeId: nil, status: "accepted")
    }

    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        hasStartedResponse = true
        return await withCheckedContinuation { responseContinuation = $0 }
    }

    func leaveInvitation(eventID: UUID) async throws -> UUID {
        hasStartedLeave = true
        return await withCheckedContinuation { leaveContinuation = $0 }
    }

    func claim() async throws -> GuestClaimAcknowledgement {
        GuestClaimAcknowledgement(claimedEventIds: events.map(\.id))
    }

    func releaseResponse() {
        responseContinuation?.resume(
            returning: AttendanceAcknowledgement(eventId: events[0].id, attendance: "not_going")
        )
        responseContinuation = nil
    }

    func releaseLeave() {
        leaveContinuation?.resume(returning: events[0].id)
        leaveContinuation = nil
    }
}
