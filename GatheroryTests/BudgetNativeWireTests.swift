import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct BudgetNativeWireTests {
    private let codec = WorkspaceArchiveCodec()

    @Test("Server expense JSON decodes numeric money and the native foodAndDrink category")
    func expenseEntityDecodesServerWireValues() throws {
        let expenseID = UUID()
        let eventID = UUID()
        let fixture: [String: Any] = [
            "id": expenseID.uuidString,
            "eventID": eventID.uuidString,
            "sourceIdeaID": NSNull(),
            "title": "Catering",
            "amount": NSDecimalNumber(string: "250.01"),
            "category": "foodAndDrink",
            "status": "paid",
            "createdByUserID": NSNull(),
            "createdAt": 900_000_000.0,
            "updatedAt": NSNull()
        ]
        let decoded = try codec.decode(EventExpense.self, from: jsonData(fixture))

        #expect(decoded.id == expenseID)
        #expect(decoded.eventID == eventID)
        #expect(decoded.amount == Decimal(string: "250.01"))
        #expect(decoded.category == .foodAndDrink)
        #expect(decoded.status == .paid)

        var stringAmount = fixture
        stringAmount["amount"] = "250.01"
        #expect(throws: (any Error).self) {
            try codec.decode(EventExpense.self, from: jsonData(stringAmount))
        }
    }

    @Test("Bootstrap and budget pull decode server numeric caps, null allocations, and exact cents")
    func bootstrapAndPullDecodeNumericBudgetWireValues() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "budget-manager")
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Server budget fixture", startsAt: .now, eventLocation: nil, imageData: nil
        )
        let numericChild = TimelineItem(
            title: "Funded", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: 250.01
        )
        let nullableChild = TimelineItem(
            title: "Unallocated", category: .other, scheduledAt: .now,
            participantIDs: [], parentEventID: workspace.mainEventID, budgetCap: nil
        )
        workspace.addTimelineItem(numericChild)
        workspace.addTimelineItem(nullableChild)
        var archive = WorkspaceArchiveV1(workspace: workspace)
        let maximumCap = Decimal(string: "999999999999.99")!
        let pulledExpense = EventExpense(
            eventID: archive.mainEventID, title: "Server catering", amount: 250.01,
            category: .foodAndDrink, status: .paid
        )
        archive.eventExpenses = [pulledExpense]

        // Model a server archive projection with JSON number tokens and an
        // explicit null, rather than an archive encoded by the native encoder.
        var object = try #require(
            JSONSerialization.jsonObject(with: codec.encode(archive)) as? [String: Any]
        )
        object["workspaceBudgetCap"] = NSDecimalNumber(decimal: maximumCap)
        object["mainEventBudgetCap"] = NSDecimalNumber(string: "250.01")
        var timeline = try #require(object["timeline"] as? [[String: Any]])
        let numericIndex = try #require(timeline.firstIndex { ($0["id"] as? String) == numericChild.id.uuidString })
        let nullableIndex = try #require(timeline.firstIndex { ($0["id"] as? String) == nullableChild.id.uuidString })
        timeline[numericIndex]["budgetCap"] = NSDecimalNumber(string: "250.01")
        timeline[nullableIndex]["budgetCap"] = NSNull()
        object["timeline"] = timeline
        var expenses = try #require(object["eventExpenses"] as? [[String: Any]])
        let expenseIndex = try #require(expenses.firstIndex { ($0["id"] as? String) == pulledExpense.id.uuidString })
        expenses[expenseIndex]["amount"] = NSDecimalNumber(string: "250.01")
        expenses[expenseIndex]["category"] = "foodAndDrink"
        object["eventExpenses"] = expenses

        let decoded = try codec.decode(WorkspaceArchiveV1.self, from: jsonData(object))
        #expect(decoded.workspaceBudgetCap == maximumCap)
        #expect(decoded.mainEventBudgetCap == Decimal(string: "250.01"))
        #expect(decoded.timeline.first { $0.id == numericChild.id }?.budgetCap == Decimal(string: "250.01"))
        #expect(decoded.timeline.first { $0.id == nullableChild.id }?.budgetCap == nil)
        #expect(decoded.eventExpenses.first?.amount == Decimal(string: "250.01"))
        #expect(decoded.eventExpenses.first?.category == .foodAndDrink)

        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(
                scopeID: archive.mainEventID, payload: jsonData(object), serverVersion: 1, updatedAt: .now
            )
        ], to: library)
        let bootstrapped = try #require(library.workspaces.first)
        #expect(bootstrapped.workspaceBudgetCap == maximumCap)
        #expect(bootstrapped.timeline.first { $0.id == numericChild.id }?.budgetCap == Decimal(string: "250.01"))
        #expect(bootstrapped.timeline.first { $0.id == nullableChild.id }?.budgetCap == nil)
        #expect(bootstrapped.eventExpenses.first?.amount == Decimal(string: "250.01"))
        #expect(bootstrapped.eventExpenses.first?.category == .foodAndDrink)

        let budgetEntityJSON = """
        {"operation":"replace_budget","expectedBudgetVersion":4,"workspaceCapCents":99999999999999,"allocations":[{"eventID":"\(archive.mainEventID.uuidString)","amountCents":25001},{"eventID":"\(numericChild.id.uuidString)","amountCents":25001},{"eventID":"\(nullableChild.id.uuidString)","amountCents":null}]}
        """
        let budgetEntityData = Data(budgetEntityJSON.utf8)
        let budgetEntity = RemoteChangeEnvelope(
            id: UUID(), scopeID: archive.mainEventID, entityType: .budgetTransfer,
            entityID: archive.mainEventID, operation: .update, payload: budgetEntityData,
            serverVersion: 4, occurredAt: .now
        )
        let expenseEntityJSON: [String: Any] = [
            "id": pulledExpense.id.uuidString,
            "eventID": archive.mainEventID.uuidString,
            "sourceIdeaID": NSNull(),
            "title": "Pulled catering",
            "amount": NSDecimalNumber(string: "250.01"),
            "category": "foodAndDrink",
            "status": "paid",
            "createdByUserID": NSNull(),
            "createdAt": 900_000_000.0,
            "updatedAt": NSNull()
        ]
        let expenseEntity = RemoteChangeEnvelope(
            id: UUID(), scopeID: archive.mainEventID, entityType: .expense,
            entityID: pulledExpense.id, operation: .update, payload: try jsonData(expenseEntityJSON),
            serverVersion: 1, occurredAt: .now
        )
        try persistence.applyRemotePage(
            SyncPullPage(changes: [budgetEntity, expenseEntity], nextCursor: "numeric-budget", hasMore: false),
            scopeID: archive.mainEventID, to: library
        )

        let pulled = try #require(library.workspaces.first)
        #expect(pulled.workspaceBudgetCap == maximumCap)
        #expect(pulled.mainEventBudgetCap == Decimal(string: "250.01"))
        #expect(pulled.timeline.first { $0.id == numericChild.id }?.budgetCap == Decimal(string: "250.01"))
        #expect(pulled.timeline.first { $0.id == nullableChild.id }?.budgetCap == nil)
        #expect(pulled.eventExpenses.first?.title == "Pulled catering")
        #expect(pulled.eventExpenses.first?.amount == Decimal(string: "250.01"))
        #expect(pulled.eventExpenses.first?.category == .foodAndDrink)

        let stringCentsJSON = budgetEntityJSON.replacingOccurrences(
            of: "\"amountCents\":25001", with: "\"amountCents\":\"25001\""
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ReplaceBudgetMutationPayload.self, from: Data(stringCentsJSON.utf8))
        }
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
