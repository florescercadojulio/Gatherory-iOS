import Foundation

/// A read-only projection of the signed-in user's writable event destinations.
/// It keeps collection/search rules out of the SwiftUI navigation layer.
@MainActor
enum IdeaImportWorkspaceProjection {
    struct Workspace: Identifiable {
        let workspace: PlanningWorkspace
        let id: UUID
        let title: String
        let imageData: Data?
        let destinations: [Destination]
    }

    struct Destination: Identifiable {
        let workspace: PlanningWorkspace
        let reference: EventReference
        let id: UUID
        let title: String
        let imageData: Data?
    }

    static func workspaces(
        in workspaces: [PlanningWorkspace],
        accountID: String?,
        search: String,
        sourceCategory: String
    ) -> [Workspace] {
        guard let accountID else { return [] }
        let query = normalized(search)
        return workspaces.compactMap { workspace in
            guard let projection = project(
                workspace,
                accountID: accountID,
                search: query,
                sourceCategory: sourceCategory
            ) else { return nil }
            return projection
        }
    }

    static func workspace(
        in workspaces: [PlanningWorkspace],
        mainEventID: UUID,
        accountID: String?,
        search: String,
        sourceCategory: String
    ) -> Workspace? {
        guard let accountID,
              let candidate = workspaces.first(where: { $0.mainEventID == mainEventID }) else { return nil }
        return project(candidate, accountID: accountID, search: normalized(search), sourceCategory: sourceCategory)
    }

    private static func project(
        _ workspace: PlanningWorkspace,
        accountID: String,
        search: String,
        sourceCategory: String
    ) -> Workspace? {
        let mainDestination: Destination?
        if workspace.currentViewerMember(for: .main)?.userID == accountID,
           BlueprintIdeaImport.canAdd(to: .main, in: workspace) {
            mainDestination = Destination(
                workspace: workspace,
                reference: .main,
                id: workspace.mainEventID,
                title: workspace.title,
                imageData: workspace.mainEventImageData
            )
        } else {
            mainDestination = nil
        }

        var children: [Destination] = []
        if sourceCategory != IdeaCategory.event.rawValue, !workspace.isScopedEvent {
            children = workspace.timeline.compactMap { child in
                let reference = EventReference.subevent(child.id)
                guard workspace.currentViewerMember(for: reference)?.userID == accountID,
                      BlueprintIdeaImport.canAdd(to: reference, in: workspace) else { return nil }
                return Destination(
                    workspace: workspace,
                    reference: reference,
                    id: child.id,
                    title: child.title,
                    imageData: child.imageData
                )
            }
        }

        let allDestinations = mainDestination.map { [$0] + children } ?? children
        guard !allDestinations.isEmpty else { return nil }
        guard search.isEmpty || matches(workspace.title, query: search)
                || allDestinations.contains(where: { matches($0.title, query: search) }) else { return nil }

        return Workspace(
            workspace: workspace,
            id: workspace.mainEventID,
            title: workspace.title,
            imageData: workspace.mainEventImageData,
            destinations: allDestinations
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func matches(_ value: String, query: String) -> Bool {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedStandardContains(query)
    }
}
