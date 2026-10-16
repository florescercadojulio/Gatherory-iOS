import Foundation

/// Read-only catalog projection. Browsing must never manufacture a workspace,
/// choose installation dates, or persist a setup draft.
struct BlueprintPreviewContent {
    let title: String
    let summary: String?
    let children: [BlueprintCatalogChild]
    let ideas: [BlueprintCatalogIdea]
    let guidance: [BlueprintCatalogInstruction]

    init?(entry: BlueprintCatalogEntry) {
        guard entry.definition.supportsCurrentSchema,
              let tree = entry.definition.modules.first(where: { $0.type == "experience_tree" })?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self),
              let ideas = entry.definition.modules.first(where: { $0.type == "ideas" })?
            .decodeConfiguration(BlueprintIdeasConfig.self) else { return nil }
        children = tree.children
        title = entry.definition.blueprint.name
        summary = entry.discovery?.summary
        self.ideas = ideas.ideas
        guidance = entry.definition.modules.filter { $0.type == "instructions" }.flatMap {
            $0.decodeConfiguration(BlueprintInstructionsConfig.self)?.sections ?? []
        }
    }

    func ideas(for childKey: String? = nil) -> [BlueprintCatalogIdea] {
        ideas.filter { matches($0.target, childKey: childKey) }
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

struct BlueprintPreviewEventContent {
    let title: String
    let summary: String?
    let category: String
    let children: [BlueprintCatalogChild]
    let ideas: [BlueprintCatalogIdea]
    let guidance: [BlueprintCatalogInstruction]
    let scheduleProposal: BlueprintScheduleProposal?
}
