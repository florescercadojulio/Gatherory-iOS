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
