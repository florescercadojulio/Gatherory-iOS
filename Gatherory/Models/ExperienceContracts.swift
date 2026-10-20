import Foundation

nonisolated enum ExperienceGuideVisibility: String, Codable, Hashable, Sendable {
    case planningOnly = "planning_only"
    case eventParticipants = "event_participants"
}

/// Copied instructions that travel with an installed experience. These are
/// read-only in the first native installation slice.
nonisolated struct ExperienceGuide: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let eventID: UUID
    let key: String
    let title: String
    let body: String
    let sortOrder: Int
    let visibility: ExperienceGuideVisibility
}

/// Native-facing configuration kept separate from portable blueprint JSON.
nonisolated struct InstalledExperienceConfiguration: Codable, Hashable, Sendable {
    let experienceType: String
    let categoryOrder: [String]
}

nonisolated struct BlueprintCatalogResponse: Decodable, Sendable {
    let entries: [BlueprintCatalogEntry]
}

nonisolated struct BlueprintCatalogEntry: Codable, Identifiable, Sendable {
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let definition: ExperienceBlueprintDocument
    // Optional while clients and the catalog endpoint roll out independently.
    var discovery: BlueprintDiscoveryMetadata? = nil
    var description: String? = nil
    var creator: BlueprintCreatorMetadata? = nil

    var id: String { "\(catalogKey):\(revision)" }
}

nonisolated struct BlueprintCreatorMetadata: Codable, Equatable, Sendable {
    let displayName: String
}

nonisolated struct BlueprintDiscoveryMetadata: Codable, Sendable {
    let categories: [String]
    let tags: [String]
    let summary: String
}

nonisolated struct BlueprintCatalogChild: Codable, Equatable, Identifiable, Sendable {
    let key: String
    let title: String
    let purpose: String
    let category: String
    let scheduleProposal: BlueprintScheduleProposal?
    var id: String { key }
}

nonisolated struct BlueprintScheduleProposal: Codable, Equatable, Sendable {
    let anchor: String
    let dayOffset: Int
    let localTime: String
}

/// Suggestions are read-only and never become installation dates without confirmation.
nonisolated struct BlueprintScheduleInput: Encodable, Sendable {
    struct MainEvent: Codable, Sendable {
        let startsAt: Date
        let timeZone: String

        init(startsAt: Date, timeZone: String) {
            // Match the existing transport's ISO8601 encoder precision.
            self.startsAt = Date(timeIntervalSince1970: floor(startsAt.timeIntervalSince1970))
            self.timeZone = timeZone
        }
    }
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let mainEvent: MainEvent
    var shareToken: String? = nil
}

nonisolated struct BlueprintScheduleResponse: Decodable, Sendable {
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let mainEvent: BlueprintScheduleInput.MainEvent
    let suggestions: [BlueprintScheduleSuggestion]
}

nonisolated struct BlueprintScheduleSuggestion: Decodable, Sendable {
    let key: String
    let status: String
    let localDateTime: String?
    let candidates: [Date]
}

nonisolated struct BlueprintCatalogIdea: Codable, Equatable, Identifiable, Sendable {
    let key: String
    let title: String
    let category: String
    let notes: String?
    let target: BlueprintTarget
    let configuration: [String: ExperienceJSONValue]
    var id: String { key }
}

nonisolated struct BlueprintCatalogInstruction: Decodable, Identifiable, Sendable {
    let key: String
    let title: String
    let body: String
    let audience: ExperienceGuideVisibility
    let target: BlueprintTarget
    var id: String { key }
}

nonisolated struct BlueprintCatalogCapability: Decodable, Identifiable, Sendable {
    let key: String
    let required: Bool
    let sourceKeys: [String]
    var id: String { key }
}

nonisolated struct BlueprintExperienceTreeConfig: Decodable, Equatable, Sendable {
    let mainEventType: String
    let children: [BlueprintCatalogChild]
}

nonisolated struct BlueprintIdeasConfig: Decodable, Equatable, Sendable {
    let categoryOrder: [String]
    let ideas: [BlueprintCatalogIdea]
}

nonisolated struct BlueprintInstructionsConfig: Decodable, Sendable {
    let sections: [BlueprintCatalogInstruction]
}

extension ExperienceModuleDefinition {
    nonisolated func decodeConfiguration<Value: Decodable>(_ type: Value.Type) -> Value? {
        guard let data = try? JSONEncoder().encode(configuration) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}

nonisolated enum BlueprintTarget: Codable, Equatable, Sendable {
    case main
    case child(key: String)

    private enum CodingKeys: String, CodingKey { case kind, key }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "main": self = .main
        case "child": self = .child(key: try container.decode(String.self, forKey: .key))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported blueprint target."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .main:
            try container.encode("main", forKey: .kind)
        case let .child(key):
            try container.encode("child", forKey: .kind)
            try container.encode(key, forKey: .key)
        }
    }
}

nonisolated struct BlueprintInstallInput: Encodable, Sendable {
    struct MainEvent: Encodable, Sendable {
        let name: String
        let startsAt: Date
        let timeZone: String
    }

    struct SelectedChild: Encodable, Sendable {
        let key: String
        let startsAt: Date
    }

    let requestID: UUID
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let mainEvent: MainEvent
    let selectedChildren: [SelectedChild]
    let selectedIdeaKeys: [String]
    let capabilities: [String]
    var shareToken: String? = nil
    var customizations: BlueprintCustomization? = nil

    private enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case catalogKey
        case revision
        case contentHash
        case mainEvent
        case selectedChildren
        case selectedIdeaKeys
        case capabilities
        case shareToken
        case customizations
    }
}

nonisolated struct BlueprintPreviewResponse: Decodable, Sendable {
    let plan: BlueprintExpandedPlan
    let contentHash: String
}

nonisolated struct BlueprintExpandedPlan: Decodable, Sendable {
    let plannerVersion: Int
    let experienceType: String
    let categoryOrder: [String]
    let main: BlueprintPlannedEvent
    let children: [BlueprintPlannedEvent]
    let ideas: [BlueprintPlannedIdea]
    let instructions: [BlueprintPlannedInstruction]
    let omissions: [BlueprintPlanOmission]
}

nonisolated struct BlueprintPlannedEvent: Decodable, Identifiable, Sendable {
    let sourceKey: String
    let name: String
    let eventType: String
    let startsAt: Date
    let timeZone: String
    let parentSourceKey: String?
    let purpose: String?
    let category: String?
    let planningStatus: String?
    var id: String { sourceKey }
}

nonisolated struct BlueprintPlannedIdea: Decodable, Identifiable, Sendable {
    let sourceKey: String
    let title: String
    let category: String
    let notes: String?
    let targetSourceKey: String
    let configuration: [String: ExperienceJSONValue]
    let status: String
    var id: String { sourceKey }
}

nonisolated struct BlueprintPlannedInstruction: Decodable, Identifiable, Sendable {
    let sourceKey: String
    let title: String
    let body: String
    let audience: ExperienceGuideVisibility
    let targetSourceKey: String
    var id: String { sourceKey }
}

nonisolated struct BlueprintPlanOmission: Decodable, Identifiable, Sendable {
    let sourceKey: String
    let reason: String
    var id: String { "\(sourceKey):\(reason)" }
}

nonisolated struct BlueprintInstallationResult: Decodable, Sendable {
    let installationID: UUID
    let organizationID: String
    let scopeID: UUID
}

nonisolated enum BlueprintInstallationState: String, Decodable, Sendable {
    case pending
    case provisioned
    case completed
    case failed
}

nonisolated struct BlueprintInstallationStatus: Decodable, Sendable {
    let state: BlueprintInstallationState
    let result: BlueprintInstallationResult?
}

/// Cross-platform wire representation of a reusable Gatherory experience.
///
/// Blueprint documents configure a `PlanningWorkspace` without coupling the
/// portable format to native persistence or SwiftUI presentation.
nonisolated struct ExperienceBlueprintDocument: Codable, Hashable, Sendable {
    let schema: URL
    let kind: String
    let schemaVersion: Int
    let blueprint: ExperienceBlueprintIdentity
    let experienceDefaults: ExperienceDefaults
    let roles: [ExperienceRoleDefinition]
    let modules: [ExperienceModuleDefinition]
    let presentation: ExperiencePresentationHints?

    var supportsCurrentSchema: Bool {
        kind == "experience_blueprint" && schemaVersion == 1
    }

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case kind
        case schemaVersion
        case blueprint
        case experienceDefaults
        case roles
        case modules
        case presentation
    }
}

nonisolated struct ExperienceBlueprintIdentity: Codable, Hashable, Sendable {
    let id: String
    let revision: Int
    let name: String
}

nonisolated struct ExperienceDefaults: Codable, Hashable, Sendable {
    let type: String
    let timeZone: String?
}

nonisolated struct ExperienceRoleDefinition: Codable, Hashable, Sendable {
    let key: String
    let permissions: [String]
}

nonisolated struct ExperienceModuleDefinition: Codable, Hashable, Sendable {
    let key: String
    let type: String
    let version: Int
    let isRequired: Bool
    let configuration: [String: ExperienceJSONValue]

    private enum CodingKeys: String, CodingKey {
        case key
        case type
        case version
        case isRequired = "required"
        case configuration = "config"
    }
}

nonisolated struct ExperiencePresentationHints: Codable, Hashable, Sendable {
    let theme: String?
    let coverAssetID: UUID?
    let moduleOrder: [String]?

    private enum CodingKeys: String, CodingKey {
        case theme
        case coverAssetID = "coverAssetId"
        case moduleOrder
    }
}

/// Portable JSON used only inside a module's versioned configuration. Durable
/// participants, authorization, money, and live collaboration remain typed,
/// normalized records rather than arbitrary JSON values.
nonisolated enum ExperienceJSONValue: Codable, Hashable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([ExperienceJSONValue])
    case object([String: ExperienceJSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ExperienceJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ExperienceJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported experience configuration value."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

nonisolated enum ExperienceContributionScope: String, Codable, Hashable, Sendable {
    case authorOnly = "author_only"
    case participantGroup = "participant_group"
    case experienceParticipants = "experience_participants"
    case experienceManagers = "experience_managers"
    case resourceCommunity = "resource_community"
    case externalPublic = "external_public"
}

nonisolated struct ContributionVisibilityPolicy: Codable, Hashable, Sendable {
    let scope: ExperienceContributionScope
    let participantGroupID: String?

    init(scope: ExperienceContributionScope, participantGroupID: String? = nil) throws {
        if scope == .participantGroup,
           participantGroupID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ExperienceContractError.participantGroupRequired
        }
        if scope != .participantGroup, participantGroupID != nil {
            throw ExperienceContractError.unexpectedParticipantGroup
        }
        self.scope = scope
        self.participantGroupID = participantGroupID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            scope: container.decode(ExperienceContributionScope.self, forKey: .scope),
            participantGroupID: container.decodeIfPresent(String.self, forKey: .participantGroupID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case participantGroupID = "groupId"
    }
}

nonisolated enum ExperienceContractError: Error {
    case participantGroupRequired
    case unexpectedParticipantGroup
}
