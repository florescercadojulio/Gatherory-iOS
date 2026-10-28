import Foundation
import Testing
@testable import Gatherory

private final class McpPlanningPayloadTestBundleMarker: NSObject {}

private struct McpConferencePayloadFixture: Decodable {
    let workspace: WorkspaceArchiveV1
    let childEvents: [TimelineItem]
    let notes: [EventNote]
    let tasks: [EventTodo]
}

@MainActor
struct McpPlanningPayloadTests {
    private let codec = WorkspaceArchiveCodec()

    private func conferenceFixture() throws -> McpConferencePayloadFixture {
        guard let url = Bundle(for: McpPlanningPayloadTestBundleMarker.self)
            .url(forResource: "McpConferencePayloads", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try codec.decode(McpConferencePayloadFixture.self, from: Data(contentsOf: url))
    }

    // These fixtures use the native sync entity payload shape emitted by the
    // MCP service and persisted by native sync. IDs and people are synthetic.
    private let childEventPayload = Data(#"""
    {
      "id": "21000000-0000-4000-8000-000000000001",
      "title": "Opening reception",
      "category": "reception",
      "purpose": "eventExperience",
      "scheduledAt": 814714200,
      "schedulingState": "scheduled",
      "endsAt": 814719600,
      "isAllDay": false,
      "timeZoneIdentifier": "America/New_York",
      "eventLocation": {
        "address": "4 Main St",
        "shortAddress": "4 Main St",
        "placeName": "Harbor Room",
        "locationName": "Harbor Room",
        "addressLine2": "Suite 2",
        "latitude": 33.749,
        "longitude": -84.388,
        "mapItemIdentifier": null
      },
      "participantIDs": [],
      "parentEventID": "11000000-0000-4000-8000-000000000001",
      "status": "approved",
      "statusBeforeArchiving": null,
      "completionStatus": "upcoming",
      "response": null,
      "linkedIdeaID": null,
      "imageData": null,
      "mediaAssetID": null,
      "eventDescription": "Conference welcome",
      "dressCode": "Cocktail",
      "budgetCap": null
    }
    """#.utf8)

    private let representativeNotePayload = Data(#"""
    {
      "id": "31000000-0000-4000-8000-000000000001",
      "eventID": "21000000-0000-4000-8000-000000000001",
      "authorUserID": "synthetic-planner-account",
      "body": "Meet by the registration desk.",
      "sentAt": 814207500
    }
    """#.utf8)

    private let representativeTaskPayload = Data(#"""
    {
      "id": "41000000-0000-4000-8000-000000000001",
      "eventID": "21000000-0000-4000-8000-000000000001",
      "title": "Confirm the room setup",
      "dueDate": "2026-10-26",
      "websiteURL": "https://conference.example.test/venue/setup",
      "assigneePersonID": null,
      "isCompleted": false,
      "createdAt": 814546800
    }
    """#.utf8)

    @Test("Actual exported MCP conference payloads decode through native workspace models")
    func importedConferencePayloads() throws {
        let fixture = try conferenceFixture()
        let workspace = fixture.workspace
        let eventIDs = Set([workspace.mainEventID] + fixture.childEvents.map(\.id))

        #expect(fixture.childEvents.count == 17)
        #expect(!fixture.notes.isEmpty)
        #expect(fixture.tasks.count == 5)
        #expect(workspace.timeline.isEmpty)
        #expect(workspace.todos?.count == fixture.tasks.count)
        #expect(workspace.mainEventTimeZoneIdentifier == "America/New_York")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: workspace.mainEventTimeZoneIdentifier))
        let start = calendar.dateComponents([.year, .month, .day, .hour], from: workspace.mainEventStartsAt)
        let end = calendar.dateComponents([.year, .month, .day, .hour], from: try #require(workspace.mainEventEndsAt))
        #expect(start.year == 2026 && start.month == 10 && start.day == 26 && start.hour == 12)
        #expect(end.year == 2026 && end.month == 10 && end.day == 29 && end.hour == 12)

        for child in fixture.childEvents {
            #expect(child.parentEventID == workspace.mainEventID)
            #expect(child.purpose == .eventExperience)
            #expect(child.status == .approved)
            #expect(child.schedulingState == .scheduled)
            #expect(child.endsAt != nil)
            #expect(child.timeZoneIdentifier == workspace.mainEventTimeZoneIdentifier)
        }
        for note in fixture.notes {
            #expect(note.eventID.map(eventIDs.contains) == true)
            #expect(!(note.authorUserID ?? "").isEmpty)
            #expect(!note.body.isEmpty)
        }
        #expect(fixture.tasks.map(\.dueDate) == [
            "2026-10-26", "2026-10-26", "2026-10-29", "2026-11-02", "2026-11-28",
        ])
        for task in fixture.tasks {
            #expect(eventIDs.contains(task.eventID))
            #expect(EventTodo.isValidDueDate(task.dueDate))
            #expect(EventTodo.isValidWebsiteURL(task.websiteURL))
            #expect(task.websiteURL == nil)
        }
    }

    @Test("A server-shaped scheduled child payload decodes with its native metadata and local date")
    func scheduledChildEventPayload() throws {
        let event = try codec.decode(TimelineItem.self, from: childEventPayload)

        #expect(event.id == UUID(uuidString: "21000000-0000-4000-8000-000000000001"))
        #expect(event.parentEventID == UUID(uuidString: "11000000-0000-4000-8000-000000000001"))
        #expect(event.title == "Opening reception")
        #expect(event.category == .reception)
        #expect(event.purpose == .eventExperience)
        #expect(event.status == .approved)
        #expect(event.completionStatus == .upcoming)
        #expect(event.schedulingState == .scheduled)
        #expect(event.timeZoneIdentifier == "America/New_York")
        #expect(event.eventDescription == "Conference welcome")
        #expect(event.dressCode == "Cocktail")
        #expect(event.eventLocation?.title == "Harbor Room")
        #expect(event.eventLocation?.addressLine2 == "Suite 2")
        #expect(event.eventLocation?.latitude == 33.749)
        #expect(event.eventLocation?.longitude == -84.388)
        #expect(event.endsAt == Date(timeIntervalSinceReferenceDate: 814719600))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.scheduledAt)
        #expect(local.year == 2026)
        #expect(local.month == 10)
        #expect(local.day == 26)
        #expect(local.hour == 9)
        #expect(local.minute == 30)
    }

    @Test("Server note payload keeps the child event, synthetic author, and Apple epoch timestamp")
    func notePayload() throws {
        let note = try codec.decode(EventNote.self, from: representativeNotePayload)

        #expect(note.id == UUID(uuidString: "31000000-0000-4000-8000-000000000001"))
        #expect(note.eventID == UUID(uuidString: "21000000-0000-4000-8000-000000000001"))
        #expect(note.authorUserID == "synthetic-planner-account")
        #expect(note.body == "Meet by the registration desk.")
        #expect(note.sentAt == Date(timeIntervalSinceReferenceDate: 814207500))
    }

    @Test("Server task payload preserves the event-zone due date, URL, completion, and epoch metadata")
    func taskPayload() throws {
        let task = try codec.decode(EventTodo.self, from: representativeTaskPayload)

        #expect(task.id == UUID(uuidString: "41000000-0000-4000-8000-000000000001"))
        #expect(task.eventID == UUID(uuidString: "21000000-0000-4000-8000-000000000001"))
        #expect(task.title == "Confirm the room setup")
        #expect(task.dueDate == "2026-10-26")
        #expect(EventTodo.isValidDueDate(task.dueDate))
        #expect(task.websiteURL == "https://conference.example.test/venue/setup")
        #expect(EventTodo.isValidWebsiteURL(task.websiteURL))
        #expect(task.assigneePersonID == nil)
        #expect(!task.isCompleted)
        #expect(task.createdAt == Date(timeIntervalSinceReferenceDate: 814546800))
    }
}
