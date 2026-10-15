import Foundation

enum BlueprintCaptureLink {
    /// Sharing an immutable publication is not editing the source event.
    /// Hosts/managers must still be able to revoke links after an event ends.
    @MainActor
    static func sharingURL(baseURL: URL?, workspace: PlanningWorkspace) -> URL? {
        guard !workspace.isMainEventDeleted, workspace.showsPlanningInterface,
              let member = workspace.currentViewerMember(for: .main),
              member.participantRole == .host ||
                (member.participantRole == .collaborator && member.planningPermission == .manage),
              let baseURL else { return nil }
        return url(baseURL: baseURL, eventID: workspace.mainEventID)
    }

    static func editorURL(baseURL: URL, templateID: UUID) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil, components.host != nil else { return nil }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, "blueprints", templateID.uuidString.lowercased()]
            .filter { !$0.isEmpty }.joined(separator: "/")
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// A card represents its own root (including a child-only projection), not
    /// the last selected event inside it. This is navigation only, never a save.
    @MainActor
    static func workspaceURL(baseURL: URL?, workspace: PlanningWorkspace) -> URL? {
        guard workspace.showsPlanningInterface,
              workspace.canManageInvitations(for: .main),
              let baseURL else { return nil }
        return url(baseURL: baseURL, eventID: workspace.mainEventID)
    }

    static func url(baseURL: URL, eventID: UUID) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else { return nil }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, "blueprints/capture"].filter { !$0.isEmpty }.joined(separator: "/")
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.queryItems = [URLQueryItem(name: "eventId", value: eventID.uuidString.lowercased())]
        return components.url
    }
}
