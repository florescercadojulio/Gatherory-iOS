import Foundation

/// Cross-platform wire representation of a reusable Gatherory experience.
///
/// This is deliberately separate from `WeddingWorkspace`, which remains the
/// first-release, offline domain aggregate. API documents decode here and are
/// then adapted into the native model and SwiftUI presentation.
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
