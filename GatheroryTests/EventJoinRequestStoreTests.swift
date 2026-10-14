import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventJoinRequestStoreTests {
    @Test("Home and settings share counts; approval and decline update only the target event")
    func sharedCounts() async {
        let client = JoinRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let first = UUID(), second = UUID()
        let request = fixture()
        client.values = [request]
        await store.refresh(eventID: first, accountID: "host")
        await store.refresh(eventID: second, accountID: "host")
        #expect(store.requests(eventID: first, accountID: "host").count == 1)
        #expect(await store.review(request, eventID: first, accountID: "host", action: .approve))
        #expect(store.requests(eventID: first, accountID: "host").isEmpty)
        #expect(store.requests(eventID: second, accountID: "host").count == 1)
        #expect(client.actions == [.approve])
        #expect(await store.review(request, eventID: second, accountID: "host", action: .decline))
        #expect(store.requests(eventID: second, accountID: "host").isEmpty)
        #expect(client.actions == [.approve, .decline])
        #expect(client.reviewedEventIDs == [first, second])
        #expect(client.reviewedRequestIDs == [request.id, request.id])
    }

    @Test("Passive refresh is throttled, explicit refresh bypasses it, and failures retain counts")
    func refreshBehavior() async {
        let client = JoinRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let eventID = UUID()
        client.values = [fixture()]
        await store.refresh(eventID: eventID, accountID: "host")
        await store.refresh(eventID: eventID, accountID: "host")
        #expect(client.reads == 1)
        client.fail = true
        await store.refresh(eventID: eventID, accountID: "host", force: true)
        #expect(client.reads == 2)
        #expect(store.requests(eventID: eventID, accountID: "host").count == 1)
        #expect(store.error(eventID: eventID, accountID: "host") != nil)
        #expect(!store.isLoading(eventID: eventID))
        #expect(await store.review(client.values[0], eventID: eventID, accountID: "host", action: .approve) == false)
        #expect(store.requests(eventID: eventID, accountID: "host").count == 1)
    }

    @Test("Account switches cannot expose another host's requests or errors")
    func accountIsolation() async {
        let client = JoinRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let eventID = UUID(), request = fixture()
        client.values = [request]
        await store.refresh(eventID: eventID, accountID: "host-a")
        #expect(store.requests(eventID: eventID, accountID: "host-b").isEmpty)
        #expect(store.requests(eventID: eventID, accountID: nil).isEmpty)
        #expect(await store.review(request, eventID: eventID, accountID: "host-b", action: .approve) == false)
        client.values = []
        await store.refresh(eventID: eventID, accountID: "host-b")
        #expect(store.requests(eventID: eventID, accountID: "host-a").isEmpty)
        #expect(store.requests(eventID: eventID, accountID: "host-b").isEmpty)
    }

    private func fixture() -> EventJoinRequest {
        EventJoinRequest(id: UUID(), name: "Invitee", email: "invitee@example.test", planningPermission: "contribute")
    }
}

@MainActor
private final class JoinRequestsTestClient: EventJoinRequestTransport {
    var values: [EventJoinRequest] = []
    var actions: [JoinRequestReviewAction] = []
    var reviewedEventIDs: [UUID] = []
    var reviewedRequestIDs: [UUID] = []
    var reads = 0
    var fail = false

    func joinRequests(eventID: UUID) async throws -> [EventJoinRequest] {
        reads += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return values
    }

    func reviewJoinRequest(eventID: UUID, requestID: UUID, action: JoinRequestReviewAction) async throws {
        if fail { throw URLError(.notConnectedToInternet) }
        actions.append(action)
        reviewedEventIDs.append(eventID)
        reviewedRequestIDs.append(requestID)
    }
}
