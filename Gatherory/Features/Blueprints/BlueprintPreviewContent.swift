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
    let children: [BlueprintCatalogChild]
    let ideas: [BlueprintCatalogIdea]
    let guidance: [BlueprintCatalogInstruction]

    init?(entry: BlueprintCatalogEntry, customizations: BlueprintCustomization? = nil, eventName: String? = nil) {
        guard entry.definition.supportsCurrentSchema,
              let tree = entry.definition.modules.first(where: { $0.type == "experience_tree" })?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self),
              let ideas = entry.definition.modules.first(where: { $0.type == "ideas" })?
            .decodeConfiguration(BlueprintIdeasConfig.self) else { return nil }
        let effective = customizations.flatMap { try? $0.applying(to: entry) }
        if customizations != nil && effective == nil { return nil }
        children = effective?.tree.children ?? tree.children
        title = eventName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? entry.definition.blueprint.name
        summary = entry.discovery?.summary
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
        let childKeys = Set(lovedIdeas.compactMap { idea -> String? in
            guard case .child(let key) = idea.target else { return nil }
            return key
        })
        return Self(title: title, summary: summary,
                    children: children.filter { childKeys.contains($0.key) },
                    ideas: lovedIdeas, guidance: guidance)
    }

    private init(title: String, summary: String?, children: [BlueprintCatalogChild],
                 ideas: [BlueprintCatalogIdea], guidance: [BlueprintCatalogInstruction]) {
        self.title = title
        self.summary = summary
        self.children = children
        self.ideas = ideas
        self.guidance = guidance
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
                scheduleProposal: child.scheduleProposal
            )
        }
        return BlueprintPreviewEventContent(
            title: title, summary: summary, category: "event", children: children,
            ideas: ideas(), guidance: guidance(), scheduleProposal: nil
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
}
