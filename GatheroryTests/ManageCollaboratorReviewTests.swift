import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ManageCollaboratorReviewTests {
    @Test("Caught-up state requires a successful empty load for an authorized account and event")
    func caughtUpRequiresLoadedAuthorizedEmptyQueue() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        func caughtUp(_ accountID: String? = "host") -> Bool {
            ManageCollaboratorReview.isCaughtUp(in: workspace, store: store,
                reference: .main, accountID: accountID)
        }
        #expect(!caughtUp())
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")
        #expect(caughtUp())
        #expect(!caughtUp("other"))
        #expect(!caughtUp(nil))
        workspace.configureViewer(account("reader"))
        #expect(!caughtUp())
        workspace.configureViewer(account("host"))
        client.values = [request("Pending")]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host", force: true)
        #expect(!caughtUp())
        #expect(await ManageCollaboratorReview.review(client.values[0], in: workspace, store: store,
            reference: .main, accountID: "host", action: .approve))
        #expect(caughtUp())
        client.failLoads = true
        await store.refresh(eventID: workspace.mainEventID, accountID: "host", force: true)
        #expect(!caughtUp())
    }

    @Test("Inline review drains the pending queue without reopening or refreshing the people screen")
    func inlineQueueContinuesUntilEmpty() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        let pending = (1...5).map { request("Person \($0)") }
        client.values = pending
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")

        for (index, expected) in pending.reversed().enumerated() {
            let current = ManageCollaboratorReview.latestRequest(
                in: workspace, store: store, reference: .main, accountID: "host")
            #expect(current?.id == expected.id)
            #expect(await ManageCollaboratorReview.review(expected, in: workspace, store: store,
                reference: .main, accountID: "host", action: index.isMultiple(of: 2) ? .approve : .decline))
            #expect(store.requestCount(eventID: workspace.mainEventID, accountID: "host") == pending.count - index - 1)
            #expect(store.reviewingRequestID == nil)
        }
        #expect(ManageCollaboratorReview.latestRequest(
            in: workspace, store: store, reference: .main, accountID: "host") == nil)
        #expect(client.reviewedRequestIDs == pending.reversed().map(\.id))
    }

    @Test("Latest request is the last pending API entry and stays account and event scoped")
    func latestRequestUsesLastAuthorizedEventRequest() async throws {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        let child = makeChild("Dinner")
        workspace.timeline = [child]
        workspace.configureViewer(account("host"))
        let older = request("Older")
        let latest = request("Latest")
        let siblingRequest = request("Sibling")
        client.values = [older, latest]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")
        client.values = [siblingRequest]
        await store.refresh(eventID: child.id, accountID: "host")

        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host")?.id == latest.id)
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "other") == nil)
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .subevent(child.id), accountID: "host") == nil)
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: nil) == nil)
    }

    @Test("Latest request rejects viewers without invitation permission and scoped sibling events")
    func latestRequestEnforcesAuthorizationAndScope() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        let child = makeChild("Dinner")
        workspace.timeline = [child]
        let request = self.request("Pending")
        client.values = [request]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")

        workspace.configureViewer(account("reader"))
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host") == nil)

        let scoped = makeWorkspace(isScoped: true)
        let injectedSibling = makeChild("Injected sibling")
        scoped.timeline = [injectedSibling]
        scoped.configureViewer(account("host"))
        #expect(ManageCollaboratorReview.latestRequest(in: scoped, store: store,
                                                       reference: .subevent(injectedSibling.id), accountID: "host") == nil)
    }

    @Test("Approve and decline review the exact request and event, then expose the next request")
    func reviewActionsTargetExactRequestAndSwitchToNext() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        let first = request("First")
        let second = request("Second")
        client.values = [first, second]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")

        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host")?.id == second.id)
        #expect(await ManageCollaboratorReview.review(second, in: workspace, store: store,
                                                       reference: .main, accountID: "host", action: .approve))
        #expect(client.reviewedEventIDs == [workspace.mainEventID])
        #expect(client.reviewedRequestIDs == [second.id])
        #expect(client.actions == [.approve])
        #expect(store.requests(eventID: workspace.mainEventID, accountID: "host").map(\.id) == [first.id])
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host")?.id == first.id)

        #expect(await ManageCollaboratorReview.review(first, in: workspace, store: store,
                                                       reference: .main, accountID: "host", action: .decline))
        #expect(client.reviewedEventIDs == [workspace.mainEventID, workspace.mainEventID])
        #expect(client.reviewedRequestIDs == [second.id, first.id])
        #expect(client.actions == [.approve, .decline])
        #expect(store.requests(eventID: workspace.mainEventID, accountID: "host").isEmpty)
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host") == nil)
    }

    @Test("A failed review retains the current request and makes it available again")
    func failedReviewRetainsRequest() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        let pending = request("Pending")
        client.values = [pending]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")
        client.failReviews = true

        #expect(!(await ManageCollaboratorReview.review(pending, in: workspace, store: store,
                                                         reference: .main, accountID: "host", action: .approve)))
        #expect(client.reviewedEventIDs == [workspace.mainEventID])
        #expect(client.reviewedRequestIDs == [pending.id])
        #expect(store.requests(eventID: workspace.mainEventID, accountID: "host").map(\.id) == [pending.id])
        #expect(ManageCollaboratorReview.latestRequest(in: workspace, store: store,
                                                       reference: .main, accountID: "host")?.id == pending.id)
    }

    @Test("Revoked permission and a request absent from the event cause no review network call")
    func reviewGatesAvoidNetworkCalls() async {
        let client = ReviewRequestsTestClient()
        let store = EventJoinRequestStore(client: client)
        let workspace = makeWorkspace()
        workspace.configureViewer(account("host"))
        let pending = request("Pending")
        client.values = [pending]
        await store.refresh(eventID: workspace.mainEventID, accountID: "host")

        workspace.configureViewer(account("reader"))
        #expect(!(await ManageCollaboratorReview.review(pending, in: workspace, store: store,
                                                         reference: .main, accountID: "host", action: .approve)))
        #expect(client.reviewedRequestIDs.isEmpty)

        workspace.configureViewer(account("host"))
        let absent = request("Not pending")
        #expect(!(await ManageCollaboratorReview.review(absent, in: workspace, store: store,
                                                         reference: .main, accountID: "host", action: .decline)))
        #expect(client.reviewedEventIDs.isEmpty)
        #expect(client.reviewedRequestIDs.isEmpty)
    }

    private func makeWorkspace(isScoped: Bool = false) -> PlanningWorkspace {
        PlanningWorkspace(
            isScopedEvent: isScoped,
            title: "Weekend",
            mainEventStartsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            venueName: "Venue",
            location: "Address",
            planningMode: .openToIdeas,
            members: [
                WorkspaceMember(userID: "host", name: "Host", participantRole: .host,
                                 initials: "H", planningPermission: .manage),
                WorkspaceMember(userID: "reader", name: "Reader", participantRole: .collaborator,
                                 initials: "R", planningPermission: .viewOnly)
            ],
            ideas: [], timeline: [], registry: []
        )
    }

    private func makeChild(_ title: String) -> TimelineItem {
        TimelineItem(title: title, category: .other, scheduledAt: .now, location: "",
                     participantIDs: [], status: .approved)
    }

    private func request(_ name: String) -> EventJoinRequest {
        EventJoinRequest(id: UUID(), name: name, email: "\(name.lowercased())@example.test",
                         planningPermission: "contribute")
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: id,
                    role: .planner, authenticationProvider: .password, createdAt: .now)
    }
}

@MainActor
private final class ReviewRequestsTestClient: EventJoinRequestTransport {
    var values: [EventJoinRequest] = []
    var actions: [JoinRequestReviewAction] = []
    var reviewedEventIDs: [UUID] = []
    var reviewedRequestIDs: [UUID] = []
    var failReviews = false
    var failLoads = false

    func joinRequests(eventID: UUID) async throws -> [EventJoinRequest] {
        if failLoads { throw URLError(.notConnectedToInternet) }
        return values
    }

    func reviewJoinRequest(eventID: UUID, requestID: UUID, action: JoinRequestReviewAction) async throws {
        reviewedEventIDs.append(eventID)
        reviewedRequestIDs.append(requestID)
        actions.append(action)
        if failReviews { throw URLError(.notConnectedToInternet) }
    }
}
