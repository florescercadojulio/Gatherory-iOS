import Foundation
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceArchiveCodecTests {
    // Deliberately literal: this must remain readable independently of changes
    // to today's model initializer or encoder. Only V1's required keys appear.
    private let legacyPayload = Data(#"""
    {
      "mainEventID": "00000000-0000-0000-0000-000000000001",
      "title": "Legacy event",
      "mainEventStartsAt": 123456.25,
      "mainEventIsAllDay": false,
      "mainEventTimeZoneIdentifier": "UTC",
      "venueName": "",
      "location": "",
      "dressCode": "",
      "eventMessage": "Welcome",
      "planningMode": "openToIdeas",
      "members": [],
      "mainEventParticipantIDs": [],
      "ideas": [],
      "timeline": [],
      "eventExpenses": [],
      "notes": [],
      "mainEventStatus": "draft",
      "eventMoments": [],
      "isMainEventDeleted": false,
      "registry": [],
      "isRegistryShared": false,
      "isCollaboratorLinkEnabled": true,
      "requiresCollaboratorApproval": true,
      "defaultCollaboratorPermission": "contribute"
    }
    """#.utf8)

    @Test("A fixed V1 fixture decodes without newer optional keys")
    func fixedLegacyFixture() throws {
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: legacyPayload)
        #expect(archive.mainEventID == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        #expect(archive.title == "Legacy event")
        #expect(archive.mainEventStartsAt == Date(timeIntervalSinceReferenceDate: 123_456.25))
        #expect(archive.currencyCode == nil)
        #expect(archive.eventParticipations == nil)
        #expect(archive.ideaResponses == nil)
        #expect(archive.isScopedEvent == nil)
        #expect(archive.mainEventImageData == nil)
        #expect(archive.workspaceBudgetCap == nil)
        let workspace = archive.makeWorkspace()
        #expect(workspace.currencyCode == Locale.current.currency?.identifier ?? "USD")
        #expect(workspace.eventParticipations.isEmpty)
        #expect(workspace.ideaResponses.isEmpty)
        #expect(!workspace.isScopedEvent)
    }

    @Test("Scoped event archives round trip while older archives default to a root workspace")
    func scopedEventRoundTrip() throws {
        let workspace = makeArchive().makeWorkspace()
        workspace.isScopedEvent = true
        let location = EventLocation(
            address: "123 Garden Lane", shortAddress: "Garden Lane",
            placeName: "The Glasshouse", locationName: "Garden Hall",
            addressLine2: "Suite 2", latitude: 42.1, longitude: -83.2,
            mapItemIdentifier: "server-place-123"
        )
        workspace.scopedMainEventDetails = TimelineItem(
            id: workspace.mainEventID, title: workspace.title,
            category: .rehearsal, purpose: .eventExperience,
            scheduledAt: Date(timeIntervalSince1970: 0),
            schedulingState: .unscheduled, eventLocation: location,
            participantIDs: [], status: .notSure
        )
        let codec = WorkspaceArchiveCodec()
        let encoded = try codec.encode(WorkspaceArchiveV1(workspace: workspace))
        let decoded = try codec.decode(WorkspaceArchiveV1.self, from: encoded)
        #expect(decoded.isScopedEvent == true)
        #expect(decoded.makeWorkspace().isScopedEvent)
        #expect(decoded.scopedEvent?.eventLocation == location)
        #expect(decoded.scopedEvent?.schedulingState == .unscheduled)
        #expect(decoded.scopedEvent?.status == .notSure)
        #expect(!decoded.makeWorkspace().mainEventHasScheduledDate)

        let legacy = try codec.decode(WorkspaceArchiveV1.self, from: legacyPayload)
        #expect(!legacy.makeWorkspace().isScopedEvent)
    }

    @Test("Every required V1 key remains required when decoding")
    func requiredLegacyKeys() throws {
        let object = try #require(JSONSerialization.jsonObject(with: legacyPayload) as? [String: Any])
        let codec = WorkspaceArchiveCodec()
        for key in object.keys.sorted() {
            var incomplete = object
            incomplete.removeValue(forKey: key)
            let payload = try JSONSerialization.data(withJSONObject: incomplete)
            do {
                _ = try codec.decode(WorkspaceArchiveV1.self, from: payload)
                Issue.record("Archive unexpectedly decoded without required key: \(key)")
            } catch DecodingError.keyNotFound(let missingKey, _) {
                #expect(missingKey.stringValue == key)
            }
        }
    }

    @Test("Archive codec preserves sorted bytes and reference-date encoding")
    func encodingCompatibility() throws {
        let archive = makeArchive()
        let codec = WorkspaceArchiveCodec()
        let previousEncoder = JSONEncoder()
        previousEncoder.outputFormatting = [.sortedKeys]

        let payload = try codec.encode(archive)
        #expect(payload == (try previousEncoder.encode(archive)))
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["mainEventStartsAt"] as? Double == 123_456.25)
        #expect(object["mainEventImageData"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(object["schemaVersion"] == nil)
        #expect(WorkspaceArchiveV1.schemaVersion == 1)

        let decoded = try codec.decode(WorkspaceArchiveV1.self, from: payload)
        #expect(try codec.encode(decoded) == payload)
        #expect(decoded.mainEventID == archive.mainEventID)
        #expect(decoded.mainEventStartsAt == archive.mainEventStartsAt)
        #expect(decoded.workspaceBudgetCap == archive.workspaceBudgetCap)
        #expect(decoded.ideaResponses == archive.ideaResponses)
        #expect(decoded.ideas == archive.ideas)
        #expect(decoded.timeline == archive.timeline)
        #expect(decoded.eventMoments == archive.eventMoments)
        #expect(decoded.registry == archive.registry)
    }

    @Test("Legacy optional archive fields keep their restoration defaults")
    func legacyDefaults() throws {
        let archive = makeArchive()
        let codec = WorkspaceArchiveCodec()
        var object = try #require(
            JSONSerialization.jsonObject(with: codec.encode(archive)) as? [String: Any]
        )
        for key in ["currencyCode", "eventParticipations", "ideaResponses"] {
            object.removeValue(forKey: key)
        }
        let legacy = try codec.decode(
            WorkspaceArchiveV1.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(legacy.currencyCode == nil)
        #expect(legacy.eventParticipations == nil)
        #expect(legacy.ideaResponses == nil)

        let workspace = legacy.makeWorkspace()
        #expect(workspace.currencyCode == Locale.current.currency?.identifier ?? "USD")
        #expect(workspace.ideaResponses.isEmpty)
        #expect(workspace.mainEventParticipantIDs == archive.mainEventParticipantIDs)
        #expect(workspace.eventParticipations.contains {
            $0.eventID == archive.mainEventID && $0.memberID == archive.members[0].id
        })
    }

    @Test("Sync projections strip media bytes and keep responses independently versioned")
    func syncProjections() throws {
        let archive = makeArchive()
        let codec = WorkspaceArchiveCodec()
        let originalPayload = try codec.encode(archive)
        let remote = try codec.decode(WorkspaceArchiveV1.self, from: archive.syncPayload(using: codec))
        #expect(remote.mainEventImageData == nil)
        #expect(remote.ideas[0].imageData == nil)
        #expect(remote.timeline[0].imageData == nil)
        #expect(remote.registry[0].imageData == nil)
        #expect(remote.eventMoments[0].imageData.isEmpty)
        #expect(remote.ideaResponses == nil)
        #expect(remote.ideas[0].mediaAssetID == archive.ideas[0].mediaAssetID)

        let entities = try archive.syncEntities(using: codec)
        let response = try #require(archive.ideaResponses?.first)
        #expect(entities[.init(type: .ideaResponse, id: response.id)] == (try codec.encode(response)))
        let ideaPayload = try #require(entities[.init(type: .idea, id: archive.ideas[0].id)])
        let eventPayload = try #require(entities[.init(type: .event, id: archive.timeline[0].id)])
        let registryPayload = try #require(entities[.init(type: .registryItem, id: archive.registry[0].id)])
        let momentPayload = try #require(entities[.init(type: .moment, id: archive.eventMoments[0].id)])
        #expect(try codec.decode(PlanningIdea.self, from: ideaPayload).imageData == nil)
        #expect(try codec.decode(TimelineItem.self, from: eventPayload).imageData == nil)
        #expect(try codec.decode(RegistryItem.self, from: registryPayload).imageData == nil)
        #expect(try codec.decode(EventMoment.self, from: momentPayload).imageData.isEmpty)
        #expect(try codec.encode(archive) == originalPayload)
    }

    @Test("Scoped main event metadata is emitted as an event entity without parent links")
    func scopedMainEventEntity() throws {
        let workspace = makeArchive().makeWorkspace()
        workspace.isScopedEvent = true
        workspace.title = "Welcome dinner"
        workspace.eventMessage = "A family dinner"
        let archive = WorkspaceArchiveV1(workspace: workspace)
        let payload = try #require(archive.syncEntities(using: WorkspaceArchiveCodec())[
            .init(type: .event, id: workspace.mainEventID)
        ])
        let event = try WorkspaceArchiveCodec().decode(TimelineItem.self, from: payload)
        #expect(event.id == workspace.mainEventID)
        #expect(event.title == "Welcome dinner")
        #expect(event.eventDescription == "A family dinner")
        #expect(event.parentEventID == nil)
        #expect(event.linkedIdeaID == nil)
    }

    @Test("Entity merges retain matching cached media and deletes require no payload")
    func entityMediaMerge() throws {
        var archive = makeArchive()
        let codec = WorkspaceArchiveCodec()
        let original = archive.ideas[0]
        var remote = original
        remote.title = "Remote title"
        remote.imageData = nil
        try archive.applyEntity(
            type: .idea, id: remote.id, operation: .update,
            payload: codec.encode(remote), codec: codec
        )
        #expect(archive.ideas[0].title == "Remote title")
        #expect(archive.ideas[0].imageData == original.imageData)

        remote.mediaAssetID = UUID()
        try archive.applyEntity(
            type: .idea, id: remote.id, operation: .update,
            payload: codec.encode(remote), codec: codec
        )
        #expect(archive.ideas[0].imageData == nil)
        #expect(archive.ideas[0].mediaAssetID == remote.mediaAssetID)

        try archive.applyEntity(
            type: .idea, id: remote.id, operation: .delete,
            payload: Data(), codec: codec
        )
        #expect(archive.ideas.isEmpty)
    }

    private func makeArchive() -> WorkspaceArchiveV1 {
        let date = Date(timeIntervalSinceReferenceDate: 123_456.25)
        let bytes = Data([1, 2, 3])
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Archive fixture", startsAt: date, eventLocation: nil,
            imageData: bytes, budgetCap: Decimal(string: "1234.56")
        )
        var archive = WorkspaceArchiveV1(workspace: workspace)
        let idea = PlanningIdea(
            eventID: archive.mainEventID, title: "Idea", note: "", category: .music,
            submittedBy: "Host", submittedAt: date, imageData: bytes, mediaAssetID: UUID()
        )
        archive.ideas = [idea]
        archive.ideaResponses = [IdeaResponse(ideaID: idea.id, userID: "host", choice: .love)]
        archive.timeline = [TimelineItem(
            title: "Event", category: .reception, scheduledAt: date, location: "",
            participantIDs: archive.mainEventParticipantIDs, parentEventID: archive.mainEventID,
            imageData: bytes, mediaAssetID: UUID()
        )]
        archive.eventMoments = [EventMoment(
            eventID: archive.mainEventID, mediaAssetID: UUID(), imageData: bytes,
            addedBy: "Host", addedAt: date
        )]
        archive.registry = [RegistryItem(
            eventID: archive.mainEventID, title: "Gift", note: "", category: .home,
            price: 25, imageData: bytes, mediaAssetID: UUID()
        )]
        return archive
    }
}
