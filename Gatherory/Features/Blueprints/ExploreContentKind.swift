import Foundation

enum ExploreContentKind: String, CaseIterable, Identifiable {
    case all
    case blueprints
    case ideas

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "All", defaultValue: "All")
        case .blueprints: String(localized: "Blueprints", defaultValue: "Blueprints")
        case .ideas: String(localized: "Ideas", defaultValue: "Ideas")
        }
    }
}

/// Stable, content-qualified identities for the unified Explore masonry feed.
/// The projection operates on IDs so it can be tested without constructing
/// transport models and so view identity survives page appends.
nonisolated enum ExploreFeedIdentity: Equatable, Identifiable, Sendable {
    case blueprint(String)
    case idea(String)

    var id: String {
        switch self {
        case .blueprint(let value): "blueprint:\(value)"
        case .idea(let value): "idea:\(value)"
        }
    }
}

nonisolated enum ExploreFeedProjection {
    static func project(blueprintIDs: [String], ideaIDs: [String], ideasPerBlueprintInterval: Int = 4) -> [ExploreFeedIdentity] {
        let interval = max(ideasPerBlueprintInterval, 1)
        var seenBlueprints = Set<String>()
        var seenIdeas = Set<String>()
        let blueprints = blueprintIDs.filter { seenBlueprints.insert($0).inserted }
        let ideas = ideaIDs.filter { seenIdeas.insert($0).inserted }
        var result: [ExploreFeedIdentity] = []
        var ideaIndex = 0

        for (index, blueprintID) in blueprints.enumerated() {
            result.append(.blueprint(blueprintID))
            if (index + 1).isMultiple(of: interval), ideaIndex < ideas.count {
                result.append(.idea(ideas[ideaIndex]))
                ideaIndex += 1
            }
        }
        if ideaIndex < ideas.count {
            result.append(contentsOf: ideas[ideaIndex...].map(ExploreFeedIdentity.idea))
        }
        return result
    }
}

nonisolated struct ExploreFeedProjectionCache: Sendable {
    private(set) var context: String?
    private(set) var blueprintIDs: [String] = []
    private(set) var ideaIDs: [String] = []
    private(set) var identities: [ExploreFeedIdentity] = []

    mutating func update(context newContext: String, blueprintIDs newBlueprintIDs: [String], ideaIDs newIdeaIDs: [String]) {
        let blueprints = Self.unique(newBlueprintIDs)
        let ideas = Self.unique(newIdeaIDs)
        let isAppendOnly = context == newContext
            && Self.isPrefix(blueprintIDs, of: blueprints)
            && Self.isPrefix(ideaIDs, of: ideas)

        if !isAppendOnly {
            identities = ExploreFeedProjection.project(blueprintIDs: blueprints, ideaIDs: ideas)
        } else {
            let knownIDs = Set(identities.map(\.id))
            let additions = ExploreFeedProjection.project(blueprintIDs: blueprints, ideaIDs: ideas)
                .filter { !knownIDs.contains($0.id) }
            identities.append(contentsOf: additions)
        }

        context = newContext
        blueprintIDs = blueprints
        ideaIDs = ideas
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func isPrefix(_ prefix: [String], of values: [String]) -> Bool {
        values.count >= prefix.count && values.prefix(prefix.count).elementsEqual(prefix)
    }
}
