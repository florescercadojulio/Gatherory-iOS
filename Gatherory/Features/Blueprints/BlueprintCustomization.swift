import Foundation

nonisolated struct BlueprintCustomization: Codable, Equatable, Sendable {
    var version: Int
    var children: [BlueprintCatalogChild]
    var ideas: [BlueprintCatalogIdea]

    init(version: Int = 1, children: [BlueprintCatalogChild] = [], ideas: [BlueprintCatalogIdea] = []) {
        self.version = version
        self.children = children
        self.ideas = ideas
    }

    private enum CodingKeys: String, CodingKey { case version, children, ideas }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        children = try container.decodeIfPresent([BlueprintCatalogChild].self, forKey: .children) ?? []
        ideas = try container.decodeIfPresent([BlueprintCatalogIdea].self, forKey: .ideas) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(children, forKey: .children)
        try container.encode(ideas, forKey: .ideas)
    }

    var isEmpty: Bool { children.isEmpty && ideas.isEmpty }

    enum CustomizationError: Error, Equatable {
        case unsupportedVersion(Int)
        case missingTreeConfiguration
        case missingIdeasConfiguration
        case invalidValue(String)
    }

    mutating func upsert(_ child: BlueprintCatalogChild) throws {
        let child = Self.normalized(child)
        try Self.validate(child)
        if let index = children.firstIndex(where: { $0.key == child.key }) {
            children[index] = child
        } else {
            guard children.count < 50 else { throw CustomizationError.invalidValue("children limit") }
            children.append(child)
        }
    }

    mutating func upsert(_ idea: BlueprintCatalogIdea) throws {
        let idea = Self.normalized(idea)
        try Self.validate(idea)
        if let index = ideas.firstIndex(where: { $0.key == idea.key }) {
            ideas[index] = idea
        } else {
            guard ideas.count < 100 else { throw CustomizationError.invalidValue("ideas limit") }
            ideas.append(idea)
        }
    }

    func applying(
        to entry: BlueprintCatalogEntry
    ) throws -> (tree: BlueprintExperienceTreeConfig, ideas: BlueprintIdeasConfig) {
        guard version == 1 else { throw CustomizationError.unsupportedVersion(version) }
        guard children.count <= 50, ideas.count <= 100 else {
            throw CustomizationError.invalidValue("customization count limit")
        }

        let modules = entry.definition.modules
        guard let sourceTree = modules.first(where: { $0.type == "experience_tree" })?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self) else {
            throw CustomizationError.missingTreeConfiguration
        }
        guard let sourceIdeas = modules.first(where: { $0.type == "ideas" })?
            .decodeConfiguration(BlueprintIdeasConfig.self) else {
            throw CustomizationError.missingIdeasConfiguration
        }
        if isEmpty { return (sourceTree, sourceIdeas) }

        try Self.requireUnique(sourceTree.children.map(\.key), name: "source child key")
        try Self.requireUnique(sourceIdeas.ideas.map(\.key), name: "source idea key")
        let normalizedChildren = children.map { Self.normalized($0) }
        let normalizedIdeas = ideas.map { Self.normalized($0) }
        try Self.requireUnique(normalizedChildren.map(\.key), name: "custom child key")
        try Self.requireUnique(normalizedIdeas.map(\.key), name: "custom idea key")

        var effectiveChildren = sourceTree.children
        for child in normalizedChildren {
            try Self.validate(child)
            if let index = effectiveChildren.firstIndex(where: { $0.key == child.key }) {
                effectiveChildren[index] = child
            } else {
                effectiveChildren.append(child)
            }
        }
        guard effectiveChildren.count <= 50 else {
            throw CustomizationError.invalidValue("effective children limit")
        }

        var effectiveIdeas = sourceIdeas.ideas
        var effectiveCategoryOrder = sourceIdeas.categoryOrder
        for idea in normalizedIdeas {
            try Self.validate(idea)
            if let index = effectiveIdeas.firstIndex(where: { $0.key == idea.key }) {
                effectiveIdeas[index] = idea
            } else {
                effectiveIdeas.append(idea)
            }
            if !effectiveCategoryOrder.contains(idea.category) {
                effectiveCategoryOrder.append(idea.category)
            }
        }
        guard effectiveIdeas.count <= 100 else {
            throw CustomizationError.invalidValue("effective ideas limit")
        }

        let childKeys = Set(effectiveChildren.map(\.key))
        for idea in effectiveIdeas {
            try Self.validate(idea)
            if case let .child(key) = idea.target, !childKeys.contains(key) {
                throw CustomizationError.invalidValue("idea target")
            }
        }
        for child in effectiveChildren { try Self.validate(child) }
        return (
            BlueprintExperienceTreeConfig(mainEventType: sourceTree.mainEventType, children: effectiveChildren),
            BlueprintIdeasConfig(categoryOrder: effectiveCategoryOrder, ideas: effectiveIdeas)
        )
    }

    private static func requireUnique(_ keys: [String], name: String) throws {
        guard Set(keys).count == keys.count else { throw CustomizationError.invalidValue("duplicate \(name)") }
    }

    private static func normalized(_ child: BlueprintCatalogChild) -> BlueprintCatalogChild {
        BlueprintCatalogChild(
            key: child.key.trimmingCharacters(in: .whitespacesAndNewlines),
            title: child.title.trimmingCharacters(in: .whitespacesAndNewlines),
            purpose: child.purpose,
            category: child.category,
            scheduleProposal: child.scheduleProposal
        )
    }

    private static func normalized(_ idea: BlueprintCatalogIdea) -> BlueprintCatalogIdea {
        let target: BlueprintTarget
        switch idea.target {
        case .main: target = .main
        case let .child(key): target = .child(key: key.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return BlueprintCatalogIdea(
            key: idea.key.trimmingCharacters(in: .whitespacesAndNewlines),
            title: idea.title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: idea.category,
            notes: idea.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target,
            configuration: idea.configuration
        )
    }

    private static func validate(_ child: BlueprintCatalogChild) throws {
        try validateKey(child.key)
        guard child.key != "main" else { throw CustomizationError.invalidValue("reserved child key") }
        guard validTitle(child.title) else { throw CustomizationError.invalidValue("child title") }
        guard ["planning_scouting", "part_of_event"].contains(child.purpose) else {
            throw CustomizationError.invalidValue("child purpose")
        }
        guard ["venue", "food_tasting", "photography", "honeymoon", "attire_fitting", "wedding_shower",
               "bachelor_bachelorette", "rehearsal", "ceremony", "reception", "other"].contains(child.category) else {
            throw CustomizationError.invalidValue("child category")
        }
        if let proposal = child.scheduleProposal {
            guard proposal.anchor == "main_start",
                  (-365...3_650).contains(proposal.dayOffset),
                  proposal.localTime.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
            else { throw CustomizationError.invalidValue("schedule proposal") }
        }
    }

    private static func validate(_ idea: BlueprintCatalogIdea) throws {
        try validateKey(idea.key)
        guard validTitle(idea.title) else { throw CustomizationError.invalidValue("idea title") }
        guard ["event", "registry", "link", "venue", "attire", "flowers", "food", "photography", "decor",
               "invitations", "honeymoon", "other"].contains(idea.category) else {
            throw CustomizationError.invalidValue("idea category")
        }
        if let notes = idea.notes,
           notes.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count > 2_000 {
            throw CustomizationError.invalidValue("idea notes")
        }
        if case let .child(key) = idea.target { try validateKey(key) }
        guard idea.configuration == ["version": .integer(1)] else {
            throw CustomizationError.invalidValue("idea configuration")
        }
    }

    private static func validateKey(_ key: String) throws {
        let scalars = key.unicodeScalars
        guard scalars.count <= 100,
              !key.isEmpty,
              key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              key.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil else {
            throw CustomizationError.invalidValue("stable key")
        }
    }

    private static func validTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.unicodeScalars.count
        return (1...120).contains(count)
    }
}
