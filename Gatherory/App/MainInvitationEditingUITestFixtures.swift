import Foundation

/// Deterministic data for the focused invitation UI checks; never live event data.
enum MainInvitationEditingUITestFixtures {
    static func applyMapCoordinates(to workspace: PlanningWorkspace) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-MainInvitationMapUITest"),
              workspace.title.hasPrefix("Alex & Jordan"),
              var location = workspace.mainEventLocation else { return }
        location.latitude = 42.2808
        location.longitude = -83.7430
        workspace.mainEventLocation = location
        #endif
    }

    static var isGuestEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-MainInvitationGuestUITest")
        #else
        false
        #endif
    }
}
