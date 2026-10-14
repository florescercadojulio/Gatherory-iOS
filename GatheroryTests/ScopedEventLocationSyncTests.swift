import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct ScopedEventLocationSyncTests {
    private let codec = WorkspaceArchiveCodec()

    @Test("Switching from host to an invited contributor never queues a location edit")
    func accountSwitchInvitationDoesNotEcho() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "host")
        let root = PlanningWorkspace.newWorkspace(
            title: "Weekend", startsAt: .now, eventLocation: nil, imageData: nil, budgetCap: nil
        )
        library.add(root)
        try persistence.flushForAccountTransition(library)
        let hostIDs = Set(try queued(persistence).map(\.id))
        #expect(!hostIDs.isEmpty)
        persistence.startObserving(library)
        persistence.activate(userID: nil, in: library)
        persistence.activate(userID: "invitee", in: library)
        let archive = makeArchive()
        let acceptance = InvitationAcceptance(eventId: archive.mainEventID, role: "collaborator",
                                              planningScopeId: archive.mainEventID, status: "accepted")
        #expect(acceptance.destination == .planning(archive.mainEventID))
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(scopeID: archive.mainEventID, payload: try codec.encode(archive),
                                    serverVersion: 1, updatedAt: .now)
        ], to: library)
        let scoped = try #require(library.workspaces.first)
        scoped.configureViewer(UserAccount(id: "invitee", email: "invitee@example.test", displayName: "Invitee",
            role: .planner, authenticationProvider: .password, createdAt: .now))
        #expect(scoped.showsPlanningInterface)
        #expect(!scoped.canManageMainEvent)
        #expect(scoped.mainEventLocation == nil)
        try persistence.flushForAccountTransition(library)
        #expect(Set(try queued(persistence).map(\.id)) == hostIDs)

        // A real offline contribution still persists and retains its retry ID.
        scoped.addIdea(PlanningIdea(eventID: scoped.mainEventID, title: "Menu", note: "",
                                   category: .food, submittedBy: "Invitee"))
        try persistence.saveChanges(in: library)
        let contributions = try queued(persistence).filter { $0.ownerUserID == "invitee" }
        #expect(!contributions.isEmpty)
        #expect(contributions.allSatisfy { $0.entityType == .idea })
        let contributionIDs = Set(contributions.map(\.id))
        persistence.activate(userID: "host", in: library)
        #expect(library.workspaces.first?.mainEventID == root.mainEventID)
        persistence.activate(userID: "invitee", in: library)
        try persistence.flushForAccountTransition(library)
        #expect(library.workspaces.first?.mainEventLocation == nil)
        #expect(Set(try queued(persistence).filter { $0.ownerUserID == "invitee" }.map(\.id)) == contributionIDs)
        #expect(Set(try queued(persistence).filter { $0.ownerUserID == "host" }.map(\.id)) == hostIDs)
    }

    @Test("A duplicate authoritative pull removes only the rejected location echo and commits the cursor")
    func exactRepairPreservesOtherWork() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let archive = makeArchive()
        var cached = archive
        cached.mainEventLocation = EventLocation(address: "")
        context.insert(WorkspaceRecord(id: archive.mainEventID, payload: try codec.encode(cached),
                                       sortOrder: 0, ownerUserID: "invitee"))
        let echo = try rejectedEcho(archive)
        let otherAccount = try rejectedEcho(archive, owner: "host")
        let realEdit = try rejectedEcho(archive)
        var edited = try codec.decode(TimelineItem.self, from: realEdit.payload)
        edited.title = "Real offline title"
        realEdit.payload = try codec.encode(edited)
        let retainedPayload = realEdit.payload
        [echo, otherAccount, realEdit].forEach(context.insert)
        let envelopeID = UUID()
        context.insert(AppliedSyncEnvelope(id: envelopeID, scopeID: archive.mainEventID, ownerUserID: "invitee"))
        try context.save()
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "invitee")
        try persistence.applyRemotePage(try page(archive, id: envelopeID), scopeID: archive.mainEventID, to: library)

        let remaining = try queued(persistence)
        #expect(Set(remaining.map(\.id)) == [otherAccount.id, realEdit.id])
        #expect(remaining.first { $0.id == realEdit.id }?.payload == retainedPayload)
        #expect(remaining.first { $0.id == realEdit.id }?.state == .requiresAttention)
        #expect(library.workspaces.first?.title == "Real offline title")
        #expect(try persistence.currentCursor(for: archive.mainEventID) == "42")
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<AppliedSyncEnvelope>()).count == 1)
        try persistence.saveChanges(in: library)
        #expect(Set(try queued(persistence).map(\.id)) == [otherAccount.id, realEdit.id])
    }

    @Test("Location echo cleanup is staged with the merge and can roll back")
    func repairRollsBackWithMerge() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        context.autosaveEnabled = false
        let archive = makeArchive()
        let echo = try rejectedEcho(archive)
        context.insert(echo)
        try context.save()
        _ = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "invitee")
            .stagePage(page(archive), scopeID: archive.mainEventID, existingWorkspaceCount: 0)
        #expect(try queued(persistence).map(\.id) == [echo.id])
        context.rollback()
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).map(\.id) == [echo.id])
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
    }

    @Test("Cleanup never removes real or unproven changes",
          arguments: ["title", "location", "unknownField", "otherCode", "pending", "sending", "create", "root"])
    func conservativeRepair(variant: String) throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        var archive = makeArchive()
        let mutation = try rejectedEcho(archive)
        var object = try #require(JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any])
        switch variant {
        case "title": object["title"] = "Actual change"
        case "location": object["eventLocation"] = ["address": "A real place", "shortAddress": "", "placeName": "", "locationName": "", "addressLine2": ""]
        case "unknownField": object["futureField"] = "Preserve me"
        case "otherCode": mutation.lastFailureCode = "EVENT_PERMISSION_REQUIRED"
        case "pending": mutation.state = .pending
        case "sending": mutation.state = .sending
        case "create": mutation.operation = .create
        case "root": archive.isScopedEvent = false
        default: break
        }
        mutation.payload = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        let original = mutation.payload
        context.insert(mutation)
        try context.save()
        _ = try WorkspaceRemoteMerger(context: context, codec: codec, ownerUserID: "invitee")
            .stagePage(page(archive), scopeID: archive.mainEventID, existingWorkspaceCount: 0)
        try context.save()
        let remaining = try queued(persistence)
        #expect(remaining.map(\.id) == [mutation.id])
        #expect(remaining.first?.payload == original)
    }

    @Test("A later page error rolls back the repair before another local save")
    func failedPageDoesNotCommitRepair() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let archive = makeArchive()
        context.insert(WorkspaceRecord(id: archive.mainEventID, payload: try codec.encode(archive),
                                       sortOrder: 0, ownerUserID: "invitee"))
        let echo = try rejectedEcho(archive)
        context.insert(echo)
        try context.save()
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "invitee")
        let validPage = try page(archive)
        let invalid = RemoteChangeEnvelope(id: UUID(), scopeID: archive.mainEventID,
            payloadSchemaVersion: 999, entityType: .idea, entityID: UUID(), operation: .update,
            payload: Data(), serverVersion: 1, occurredAt: .now)
        #expect(throws: WorkspacePersistenceError.self) {
            try persistence.applyRemotePage(SyncPullPage(changes: validPage.changes + [invalid],
                nextCursor: "invalid", hasMore: false), scopeID: archive.mainEventID, to: library)
        }
        try persistence.saveChanges(in: library)
        #expect(try queued(persistence).map(\.id) == [echo.id])
        #expect(try persistence.currentCursor(for: archive.mainEventID) == nil)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
    }

    private func makeArchive() -> WorkspaceArchiveV1 {
        let workspace = PlanningWorkspace(isScopedEvent: true, title: "Food Tasting",
            mainEventStartsAt: Date(timeIntervalSinceReferenceDate: 813_695_209.141),
            venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: "invitee", name: "Invitee", participantRole: .collaborator,
                                      initials: "I", planningPermission: .contribute)],
            ideas: [], timeline: [], registry: [])
        var archive = WorkspaceArchiveV1(workspace: workspace)
        // Match the server projection, independently of model initializer behavior.
        archive.mainEventLocation = nil
        archive.mainEventStatus = .ongoing
        archive.scopedEvent = TimelineItem(id: archive.mainEventID, title: archive.title,
            category: .foodTasting, purpose: .eventExperience, scheduledAt: archive.mainEventStartsAt,
            location: "", timeZoneIdentifier: archive.mainEventTimeZoneIdentifier,
            participantIDs: archive.mainEventParticipantIDs, status: .approved,
            eventDescription: archive.eventMessage, dressCode: archive.dressCode)
        return archive
    }

    private func rejectedEcho(_ archive: WorkspaceArchiveV1, owner: String = "invitee") throws -> PendingMutation {
        var buggy = archive
        buggy.mainEventLocation = EventLocation(address: "")
        let payload = try #require(buggy.syncEntities(using: codec)[.init(type: .event, id: archive.mainEventID)])
        let mutation = PendingMutation(scopeID: archive.mainEventID, entityType: .event,
            entityID: archive.mainEventID, operation: .update, payload: payload, ownerUserID: owner)
        mutation.state = .requiresAttention
        mutation.lastFailureCode = "EVENT_SCOPE_FORBIDDEN"
        return mutation
    }

    private func page(_ archive: WorkspaceArchiveV1, id: UUID = UUID()) throws -> SyncPullPage {
        SyncPullPage(changes: [RemoteChangeEnvelope(id: id, scopeID: archive.mainEventID,
            entityType: .workspace, entityID: archive.mainEventID, operation: .update,
            payload: try codec.encode(archive), serverVersion: 1, occurredAt: .now)],
            nextCursor: "42", hasMore: false)
    }

    private func queued(_ persistence: WorkspacePersistenceController) throws -> [PendingMutation] {
        try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
    }
}
