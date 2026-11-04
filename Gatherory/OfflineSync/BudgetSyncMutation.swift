import Foundation

nonisolated struct BudgetAllocationMutationValue: Codable, Equatable, Sendable {
    let eventID: UUID
    let amountCents: Int64?

    private enum CodingKeys: String, CodingKey { case eventID, amountCents }

    init(eventID: UUID, amountCents: Int64?) {
        self.eventID = eventID
        self.amountCents = amountCents
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decode(UUID.self, forKey: .eventID)
        amountCents = try container.decode(Int64?.self, forKey: .amountCents)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(amountCents, forKey: .amountCents)
    }
}

/// One compare-and-swap command for the complete shared allocation vector.
/// The vector is deliberately carried as one outbox record so retries and
/// conflicts can never apply only one side of a transfer.
nonisolated struct ReplaceBudgetMutationPayload: Codable, Equatable, Sendable {
    let operation: String
    var expectedBudgetVersion: Int
    let workspaceCapCents: Int64?
    let allocations: [BudgetAllocationMutationValue]

    private enum CodingKeys: String, CodingKey {
        case operation, expectedBudgetVersion, workspaceCapCents, allocations
    }

    init(expectedBudgetVersion: Int, workspaceCapCents: Int64?, allocations: [BudgetAllocationMutationValue]) {
        operation = "replace_budget"
        self.expectedBudgetVersion = expectedBudgetVersion
        self.workspaceCapCents = workspaceCapCents
        self.allocations = allocations
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operation = try container.decode(String.self, forKey: .operation)
        expectedBudgetVersion = try container.decode(Int.self, forKey: .expectedBudgetVersion)
        workspaceCapCents = try container.decode(Int64?.self, forKey: .workspaceCapCents)
        allocations = try container.decode([BudgetAllocationMutationValue].self, forKey: .allocations)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .operation)
        try container.encode(expectedBudgetVersion, forKey: .expectedBudgetVersion)
        try container.encode(workspaceCapCents, forKey: .workspaceCapCents)
        try container.encode(allocations, forKey: .allocations)
    }
}

enum BudgetSyncMutationError: Error {
    case unsupportedPrecision
    case duplicateEventID
    case missingRootAllocation
}

extension WorkspaceArchiveV1 {
    func budgetMutationPayload(expectedBudgetVersion: Int) throws -> ReplaceBudgetMutationPayload {
        var allocations = [BudgetAllocationMutationValue(
            eventID: mainEventID,
            amountCents: try Self.minorUnits(mainEventBudgetCap)
        )]
        var seenIDs: Set<UUID> = [mainEventID]
        for event in timeline {
            guard seenIDs.insert(event.id).inserted else { throw BudgetSyncMutationError.duplicateEventID }
            allocations.append(BudgetAllocationMutationValue(
                eventID: event.id,
                amountCents: try Self.minorUnits(event.budgetCap)
            ))
        }
        return ReplaceBudgetMutationPayload(
            expectedBudgetVersion: expectedBudgetVersion,
            workspaceCapCents: try Self.minorUnits(workspaceBudgetCap),
            allocations: allocations
        )
    }

    func hasBudgetChanges(comparedTo previous: WorkspaceArchiveV1) -> Bool {
        guard workspaceBudgetCap == previous.workspaceBudgetCap,
              mainEventBudgetCap == previous.mainEventBudgetCap else { return true }
        let prior = Dictionary(uniqueKeysWithValues: previous.timeline.map { ($0.id, $0.budgetCap) })
        let current = Dictionary(uniqueKeysWithValues: timeline.map { ($0.id, $0.budgetCap) })
        return Set(prior.keys).union(current.keys).contains {
            (prior[$0] ?? nil) != (current[$0] ?? nil)
        }
    }

    mutating func apply(_ payload: ReplaceBudgetMutationPayload) throws {
        guard payload.operation == "replace_budget" else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Unsupported budget sync operation.")
            )
        }
        func amount(_ cents: Int64?) -> Decimal? {
            cents.map { Decimal($0) / 100 }
        }
        workspaceBudgetCap = amount(payload.workspaceCapCents)
        var allocations: [UUID: BudgetAllocationMutationValue] = [:]
        var seenIDs = Set<UUID>()
        for allocation in payload.allocations {
            guard seenIDs.insert(allocation.eventID).inserted else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Duplicate event in budget sync vector.")
                )
            }
            allocations[allocation.eventID] = allocation
        }
        guard let mainAllocation = allocations[mainEventID] else {
            throw BudgetSyncMutationError.missingRootAllocation
        }
        mainEventBudgetCap = amount(mainAllocation.amountCents)
        timeline = timeline.map { event in
            var event = event
            if let allocation = allocations[event.id] {
                event.budgetCap = amount(allocation.amountCents)
            } else {
                event.budgetCap = nil
            }
            return event
        }
    }

    /// Ordinary updates omit budget fields so the server preserves its
    /// canonical values. Explicit null would mean "clear" and is not safe.
    func syncPayloadOmittingBudgetFields(using codec: WorkspaceArchiveCodec) throws -> Data {
        try Self.removingBudgetFields(from: syncPayload(using: codec), includeWorkspaceFields: true)
    }

    func syncEntitiesOmittingBudgetFields(using codec: WorkspaceArchiveCodec) throws -> [WorkspaceSyncEntityKey: Data] {
        var entities = try syncEntities(using: codec)
        for (key, payload) in Array(entities) where key.type == .event {
            entities[key] = try Self.removingBudgetFields(from: payload, includeWorkspaceFields: false)
        }
        return entities
    }

    private static func removingBudgetFields(from data: Data, includeWorkspaceFields: Bool) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid synchronized budget payload.")
            )
        }
        if includeWorkspaceFields {
            object.removeValue(forKey: "workspaceBudgetCap")
            object.removeValue(forKey: "mainEventBudgetCap")
            if var timeline = object["timeline"] as? [[String: Any]] {
                timeline = timeline.map { event in
                    var event = event
                    event.removeValue(forKey: "budgetCap")
                    return event
                }
                object["timeline"] = timeline
            }
        } else {
            object.removeValue(forKey: "budgetCap")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func minorUnits(_ amount: Decimal?) throws -> Int64? {
        guard let amount else { return nil }
        var scaled = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled,
              let value = Int64(NSDecimalNumber(decimal: rounded).stringValue) else {
            throw BudgetSyncMutationError.unsupportedPrecision
        }
        return value
    }
}
