import Foundation

nonisolated enum BlueprintPreviewEventID: Hashable, Identifiable, Sendable {
    case main
    case child(String)
    var id: Self { self }
}

enum BlueprintPreviewScope: Hashable {
    case all, main, child(String)
}

/// Read-only catalog projection. Browsing must never manufacture a workspace,
/// choose installation dates, or persist a setup draft.
struct BlueprintPreviewContent {
    let title: String
    let summary: String?
    let creatorName: String?
    let children: [BlueprintCatalogChild]
    let ideas: [BlueprintCatalogIdea]
    let guidance: [BlueprintCatalogInstruction]
    let todos: [BlueprintTodoDefinition]
    let coverAssetID: UUID?
    let publicCoverImageURL: String?
    let publicChildCoverImageURLs: [String: String]
    let publicIdeaCoverImageURLs: [String: String]
    private let customizedChildKeys: Set<String>

    init?(entry: BlueprintCatalogEntry, customizations: BlueprintCustomization? = nil, eventName: String? = nil,
          creatorNameOverride: String? = nil) {
        guard entry.definition.supportsCurrentSchema,
              let tree = entry.definition.modules.first(where: { $0.type == "experience_tree" })?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self),
              let ideas = entry.definition.modules.first(where: { $0.type == "ideas" })?
            .decodeConfiguration(BlueprintIdeasConfig.self) else { return nil }
        let effective = customizations.flatMap { try? $0.applying(to: entry) }
        if customizations != nil && effective == nil { return nil }
        children = effective?.tree.children ?? tree.children
        customizedChildKeys = Set(customizations?.children.map(\.key) ?? [])
        let childKeys = Set(children.map(\.key))
        let sourceTodos = entry.definition.modules.first { $0.type == "todos" }?
            .decodeConfiguration(BlueprintTodosConfig.self)?.todos ?? []
        todos = sourceTodos.filter { todo in
            switch todo.target {
            case .main: true
            case .child(let key): childKeys.contains(key)
            }
        }
        let overridesCover = customizations?.overridesCover == true
        coverAssetID = overridesCover ? customizations?.coverAssetId : entry.definition.presentation?.coverAssetID
        publicCoverImageURL = overridesCover ? nil : BlueprintPublicCoverURL.validated(entry.discovery?.coverImageURL)?.absoluteString
        let coverImages = entry.discovery?.coverImages
        var childCoverURLs: [String: String] = [:]
        for child in children {
            guard !child.coverAssetIdWasProvided || child.coverAssetId != nil,
                  let url = BlueprintPublicCoverURL.validated(coverImages?.children[child.key])?.absoluteString else { continue }
            childCoverURLs[child.key] = url
        }
        publicChildCoverImageURLs = childCoverURLs
        var ideaCoverURLs: [String: String] = [:]
        for idea in (effective?.ideas.ideas ?? ideas.ideas) {
            guard !idea.coverAssetIdWasProvided || idea.coverAssetId != nil,
                  let url = BlueprintPublicCoverURL.validated(coverImages?.ideas[idea.key])?.absoluteString else { continue }
            ideaCoverURLs[idea.key] = url
        }
        publicIdeaCoverImageURLs = ideaCoverURLs
        title = eventName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? entry.definition.blueprint.name
        summary = entry.discovery?.summary
        creatorName = creatorNameOverride ?? entry.creator?.displayName
        self.ideas = effective?.ideas.ideas ?? ideas.ideas
        guidance = entry.definition.modules.filter { $0.type == "instructions" }.flatMap {
            $0.decodeConfiguration(BlueprintInstructionsConfig.self)?.sections ?? []
        }
    }

    func ideas(for childKey: String? = nil) -> [BlueprintCatalogIdea] {
        ideas.filter { matches($0.target, childKey: childKey) }
    }

    var eventIDs: [BlueprintPreviewEventID] { [.main] + children.map { .child($0.key) } }

    /// Home projects the proposed plan, not the full catalog. Ideas/Decide must keep
    /// using the unfiltered content so undiscovered activities remain reachable.
    func homeContent(responses: [String: DecisionChoice]) -> Self {
        let lovedIdeas = ideas.filter { responses[$0.key] == .love }
        let lovedChildKeys = Set(lovedIdeas.compactMap { idea -> String? in
            guard case .child(let key) = idea.target else { return nil }
            return key
        })
        let taskChildKeys = Set(todos.compactMap { todo -> String? in
            guard case .child(let key) = todo.target else { return nil }
            return key
        })
        let childKeys = lovedChildKeys.union(taskChildKeys).union(customizedChildKeys)
        return Self(title: title, summary: summary, creatorName: creatorName, coverAssetID: coverAssetID,
                    publicCoverImageURL: publicCoverImageURL,
                    publicChildCoverImageURLs: publicChildCoverImageURLs,
                    publicIdeaCoverImageURLs: publicIdeaCoverImageURLs,
                    customizedChildKeys: customizedChildKeys,
                    children: children.filter { childKeys.contains($0.key) },
                    ideas: lovedIdeas, guidance: guidance,
                    todos: todos.filter { todo in
                        switch todo.target {
                        case .main: true
                        case .child(let key): childKeys.contains(key)
                        }
                    })
    }

    private init(title: String, summary: String?, creatorName: String?, coverAssetID: UUID?, publicCoverImageURL: String?,
                 publicChildCoverImageURLs: [String: String], publicIdeaCoverImageURLs: [String: String],
                 customizedChildKeys: Set<String>, children: [BlueprintCatalogChild],
                 ideas: [BlueprintCatalogIdea], guidance: [BlueprintCatalogInstruction],
                 todos: [BlueprintTodoDefinition]) {
        self.title = title
        self.coverAssetID = coverAssetID
        self.publicCoverImageURL = publicCoverImageURL
        self.publicChildCoverImageURLs = publicChildCoverImageURLs
        self.publicIdeaCoverImageURLs = publicIdeaCoverImageURLs
        self.customizedChildKeys = customizedChildKeys
        self.summary = summary
        self.creatorName = creatorName
        self.children = children
        self.ideas = ideas
        self.guidance = guidance
        self.todos = todos
    }

    func ideas(in scope: BlueprintPreviewScope) -> [BlueprintCatalogIdea] {
        switch scope {
        case .all: ideas
        case .main: ideas()
        case .child(let key): ideas(for: key)
        }
    }

    func event(for id: BlueprintPreviewEventID) -> BlueprintPreviewEventContent? {
        switch id {
        case .main: event()
        case .child(let key): event(for: key)
        }
    }

    func guidance(for childKey: String? = nil) -> [BlueprintCatalogInstruction] {
        guidance.filter { matches($0.target, childKey: childKey) }
    }

    /// A child is a leaf preview, not a doorway back into parent/sibling content.
    func event(for childKey: String? = nil) -> BlueprintPreviewEventContent? {
        if let childKey {
            guard let child = children.first(where: { $0.key == childKey }) else { return nil }
            return BlueprintPreviewEventContent(
                title: child.title, summary: nil, category: child.category,
                children: [], ideas: ideas(for: childKey), guidance: guidance(for: childKey),
                scheduleProposal: child.scheduleProposal,
                todos: todos.filter { $0.target == .child(key: childKey) },
                coverAssetID: child.coverAssetId,
                publicCoverImageURL: publicChildCoverImageURLs[child.key],
                publicIdeaCoverImageURLs: publicIdeaCoverImageURLs
            )
        }
        return BlueprintPreviewEventContent(
            title: title, summary: summary, category: "event", children: children,
            ideas: ideas(), guidance: guidance(), scheduleProposal: nil,
            todos: todos.filter { $0.target == .main },
            coverAssetID: coverAssetID, publicCoverImageURL: publicCoverImageURL,
            publicIdeaCoverImageURLs: publicIdeaCoverImageURLs
        )
    }

    private func matches(_ target: BlueprintTarget, childKey: String?) -> Bool {
        switch (target, childKey) {
        case (.main, nil): true
        case let (.child(key), .some(selected)): key == selected
        default: false
        }
    }
}

/// Browsing Home must never silently narrow the decision queue.
struct BlueprintPreviewNavigation {
    var homeEvent: BlueprintPreviewEventID = .main
    var decisionScope: BlueprintPreviewScope = .all

    var homeScope: BlueprintPreviewScope {
        switch homeEvent {
        case .main: .main
        case .child(let key): .child(key)
        }
    }
}

struct BlueprintPreviewEventContent {
    let title: String
    let summary: String?
    let category: String
    let children: [BlueprintCatalogChild]
    let ideas: [BlueprintCatalogIdea]
    let guidance: [BlueprintCatalogInstruction]
    let scheduleProposal: BlueprintScheduleProposal?
    var todos: [BlueprintTodoDefinition] = []
    var coverAssetID: UUID? = nil
    var publicCoverImageURL: String? = nil
    var publicIdeaCoverImageURLs: [String: String] = [:]
}
