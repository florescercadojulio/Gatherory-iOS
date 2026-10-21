import Foundation
import Testing
@testable import Gatherory

struct GuestAttendanceRecoveryTests {
    @Test("A failed RSVP retry resends the selected response")
    @MainActor func retryResendsSelectedResponse() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        transport.responseResults = [.failure, .ack(event.id, "not_sure")]
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))

        await store.respond(eventID: event.id, response: .notSure)
        #expect(store.attendanceUpdate?.eventID == event.id)
        #expect(store.attendanceUpdate?.response == .notSure)
        if case .some(.failed) = store.attendanceUpdate?.phase {
            #expect(true)
        } else {
            Issue.record("The failed RSVP should remain available for retry.")
        }

        await store.retryAttendanceResponse(eventID: event.id)

        #expect(transport.responses.map { $0.response } == [.notSure, .notSure])
        #expect(store.events.first?.attendance == "not_sure")
        #expect(store.attendanceUpdate?.phase == .saved)
    }

    @Test("An RSVP stays pending until its acknowledgement, then becomes saved")
    @MainActor func pendingThenSaved() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        transport.delayResponse = true
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))

        let task = Task { await store.respond(eventID: event.id, response: .notGoing) }
        while !transport.hasPendingResponse { await Task.yield() }
        #expect(store.attendanceUpdate?.phase == .sending)
        #expect(store.events.first?.attendance == "going")

        await store.respond(eventID: event.id, response: .going)
        #expect(transport.responses.count == 1)
        #expect(store.attendanceUpdate?.response == .notGoing)

        transport.releaseResponse(with: .ack(event.id, "not_going"))
        await task.value

        #expect(store.attendanceUpdate?.phase == .saved)
        #expect(store.events.first?.attendance == "not_going")
    }

    @Test("A wrong-event acknowledgement changes neither event")
    @MainActor func wrongEventAcknowledgementIsIgnored() async throws {
        let requested = try fixture(), other = try fixture()
        let transport = AttendanceRecoveryTransport(events: [requested, other])
        transport.responseResults = [.ack(other.id, "not_going")]
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))

        await store.respond(eventID: requested.id, response: .notSure)

        #expect(store.events.first(where: { $0.id == requested.id })?.attendance == "going")
        #expect(store.events.first(where: { $0.id == other.id })?.attendance == "going")
        #expect(store.attendanceUpdate?.eventID == requested.id)
        #expect(store.attendanceUpdate?.phase != .saved)
    }

    @Test("An unknown attendance value is rejected")
    @MainActor func unknownAttendanceIsRejected() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        transport.responseResults = [.ack(event.id, "maybe")]
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))

        await store.respond(eventID: event.id, response: .notSure)

        #expect(store.events.first?.attendance == "going")
        #expect(store.attendanceUpdate?.eventID == event.id)
        #expect(store.attendanceUpdate?.phase != .saved)
    }

    @Test("A retry for another event or principal is ignored")
    @MainActor func retryScopeIsBoundToFailedUpdateAndPrincipal() async throws {
        let event = try fixture()
        let profileA = LocalGuestProfile(displayName: "Guest A")
        let transport = AttendanceRecoveryTransport(events: [event])
        transport.responseResults = [.failure, .ack(event.id, "not_sure")]
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: profileA)
        await store.respond(eventID: event.id, response: .notSure)

        await store.retryAttendanceResponse(eventID: UUID())
        #expect(transport.responses.count == 1)

        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest B"))
        await store.retryAttendanceResponse(eventID: event.id)
        #expect(transport.responses.count == 1)
        #expect(store.attendanceUpdate == nil)
    }

    @Test("A successful acknowledgement stays saved if the following refresh fails")
    @MainActor func acknowledgementSurvivesRefreshFailure() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))
        transport.failRefresh = true
        transport.responseResults = [.ack(event.id, "not_sure")]

        await store.respond(eventID: event.id, response: .notSure)

        #expect(store.events.first?.attendance == "not_sure")
        #expect(store.attendanceUpdate?.phase == .saved)
        #expect(store.errorMessage != nil)
    }

    @Test("A cache write failure after acknowledgement does not mark the RSVP failed")
    @MainActor func acknowledgementSurvivesCacheFailure() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))
        try FileManager.default.removeItem(at: cacheDirectory)
        try Data("occupied cache path".utf8).write(to: cacheDirectory)
        transport.responseResults = [.ack(event.id, "not_sure")]

        await store.respond(eventID: event.id, response: .notSure)

        #expect(store.events.first?.attendance == "not_sure")
        #expect(store.attendanceUpdate?.phase == .saved)
        #expect(store.errorMessage != nil)
    }

    @Test("A delayed pre-RSVP feed cannot replace the acknowledgement and forced refresh converges")
    @MainActor func staleFeedCannotOverwriteAcknowledgement() async throws {
        let event = try fixture()
        let transport = AttendanceRecoveryTransport(events: [event])
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest"))
        transport.delayNextFeed = true
        let staleRefresh = Task { await store.refresh(force: true) }
        while !transport.hasPendingFeed { await Task.yield() }

        transport.responseResults = [.ack(event.id, "not_going")]
        let responseTask = Task { await store.respond(eventID: event.id, response: .notGoing) }
        while store.attendanceUpdate?.phase != .saved { await Task.yield() }
        #expect(store.events.first?.attendance == "not_going")

        transport.releaseFeed()
        await responseTask.value
        await staleRefresh.value

        #expect(transport.invitationRequestCount >= 3)
        #expect(store.events.first?.attendance == "not_going")
        #expect(store.attendanceUpdate?.phase == .saved)
    }

    @Test("An RSVP result from guest A is ignored after switching to B and back to A")
    @MainActor func staleResultCannotCrossIdentityRoundTrip() async throws {
        let event = try fixture()
        let profileA = LocalGuestProfile(displayName: "Guest A")
        let transport = AttendanceRecoveryTransport(events: [event])
        transport.delayResponse = true
        let (store, cacheDirectory) = makeStore(transport)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        await store.activate(localGuest: profileA)

        let task = Task { await store.respond(eventID: event.id, response: .notGoing) }
        while !transport.hasPendingResponse { await Task.yield() }
        await store.activate(localGuest: LocalGuestProfile(displayName: "Guest B"))
        await store.activate(localGuest: profileA)
        transport.releaseResponse(with: .ack(event.id, "not_going"))
        await task.value

        #expect(store.events.first?.attendance == "going")
        #expect(store.attendanceUpdate == nil)
        #expect(!store.isResponding)
    }

    @MainActor private func makeStore(_ transport: AttendanceRecoveryTransport) -> (store: GuestInvitationStore, cacheDirectory: URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "guest-attendance-recovery-\(UUID())")
        let store = GuestInvitationStore(baseURL: nil, cacheDirectory: directory, localClientFactory: { _ in transport })
        return (store, directory)
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
}

@MainActor private final class AttendanceRecoveryTransport: LocalGuestInvitationTransport {
    enum ResponseResult {
        case failure
        case ack(UUID, String)
    }

    var events: [GuestEventInvitation]
    var responseResults: [ResponseResult] = []
    var responses: [(eventID: UUID, response: EventResponse)] = []
    var failRefresh = false
    var delayResponse = false
    var delayNextFeed = false
    private var feedContinuation: CheckedContinuation<GuestInvitationFeed, Never>?
    private var delayedFeedSnapshot: GuestInvitationFeed?
    private var responseContinuation: CheckedContinuation<AttendanceAcknowledgement, Never>?
    private var pendingRequestEventID: UUID?
    private(set) var hasPendingResponse = false
    private(set) var hasPendingFeed = false
    private(set) var invitationRequestCount = 0

    init(events: [GuestEventInvitation]) { self.events = events }

    func invitations() async throws -> GuestInvitationFeed {
        invitationRequestCount += 1
        if failRefresh { throw EventInvitationFailure.unavailable }
        if delayNextFeed {
            delayNextFeed = false
            let snapshot = GuestInvitationFeed(events: events)
            delayedFeedSnapshot = snapshot
            hasPendingFeed = true
            return await withCheckedContinuation { feedContinuation = $0 }
        }
        return GuestInvitationFeed(events: events)
    }

    func join(token: UUID) async throws -> InvitationAcceptance {
        InvitationAcceptance(eventId: events[0].id, role: "guest", planningScopeId: nil, status: "accepted")
    }

    func respond(eventID: UUID, response: EventResponse) async throws -> AttendanceAcknowledgement {
        responses.append((eventID, response))
        if delayResponse {
            pendingRequestEventID = eventID
            hasPendingResponse = true
            return await withCheckedContinuation { responseContinuation = $0 }
        }
        guard !responseResults.isEmpty else {
            return AttendanceAcknowledgement(eventId: eventID, attendance: "going")
        }
        switch responseResults.removeFirst() {
        case .failure: throw EventInvitationFailure.unavailable
        case let .ack(id, attendance):
            let acknowledgement = AttendanceAcknowledgement(eventId: id, attendance: attendance)
            apply(acknowledgement, requestedEventID: eventID)
            return acknowledgement
        }
    }

    func leaveInvitation(eventID: UUID) async throws -> UUID { eventID }

    func claim() async throws -> GuestClaimAcknowledgement {
        GuestClaimAcknowledgement(claimedEventIds: events.map(\.id))
    }

    func releaseResponse(with result: ResponseResult) {
        guard let responseContinuation else { return }
        self.responseContinuation = nil
        hasPendingResponse = false
        let acknowledgement: AttendanceAcknowledgement
        switch result {
        case .failure: acknowledgement = AttendanceAcknowledgement(eventId: UUID(), attendance: "going")
        case let .ack(id, attendance): acknowledgement = AttendanceAcknowledgement(eventId: id, attendance: attendance)
        }
        if let pendingRequestEventID {
            apply(acknowledgement, requestedEventID: pendingRequestEventID)
        }
        pendingRequestEventID = nil
        responseContinuation.resume(returning: acknowledgement)
    }

    func releaseFeed() {
        guard let feedContinuation, let delayedFeedSnapshot else { return }
        self.feedContinuation = nil
        self.delayedFeedSnapshot = nil
        hasPendingFeed = false
        feedContinuation.resume(returning: delayedFeedSnapshot)
    }

    private func apply(_ acknowledgement: AttendanceAcknowledgement, requestedEventID: UUID) {
        guard acknowledgement.eventId == requestedEventID,
              ["going", "not_sure", "not_going"].contains(acknowledgement.attendance),
              let index = events.firstIndex(where: { $0.id == requestedEventID }) else { return }
        events[index].attendance = acknowledgement.attendance
        let viewerPersonID = events[index].viewerPersonId
        events[index].people = events[index].people.map { person in
            var person = person
            if person.id == viewerPersonID { person.attendance = acknowledgement.attendance }
            return person
        }
    }
}
