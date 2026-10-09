import Foundation
import Observation

/// App-level state that owns the workspaces available to the signed-in person.
/// A workspace remains the source of truth for everything inside one event.
@Observable
final class WorkspaceLibrary {
    private(set) var workspaces: [WeddingWorkspace]
    private(set) var selectedWorkspaceID: UUID?

    init(workspaces: [WeddingWorkspace] = []) {
        self.workspaces = workspaces
    }

    var selectedWorkspace: WeddingWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.mainEventID == selectedWorkspaceID }
    }

    func open(_ workspace: WeddingWorkspace) {
        guard workspaces.contains(where: { $0.mainEventID == workspace.mainEventID }) else { return }
        selectedWorkspaceID = workspace.mainEventID
    }

    func closeWorkspace() {
        selectedWorkspaceID = nil
    }

    func add(_ workspace: WeddingWorkspace, openAfterAdding: Bool = true) {
        guard !workspaces.contains(where: { $0.mainEventID == workspace.mainEventID }) else { return }
        workspaces.insert(workspace, at: 0)
        if openAfterAdding {
            selectedWorkspaceID = workspace.mainEventID
        }
    }
}

extension WorkspaceLibrary {
    static var sample: WorkspaceLibrary {
        WorkspaceLibrary(workspaces: [.sample, .secondarySample])
    }
}

extension WeddingWorkspace {
    static func newWorkspace(
        title: String,
        startsAt: Date,
        eventLocation: EventLocation?,
        imageData: Data?,
        budgetCap: Decimal? = nil
    ) -> WeddingWorkspace {
        let host = WeddingMember(
            name: "You",
            participantRole: .host,
            initials: "Y",
            planningPermission: .manage
        )

        return WeddingWorkspace(
            title: title,
            weddingDate: startsAt,
            mainEventLocation: eventLocation,
            mainEventImageData: imageData,
            venueName: eventLocation?.title ?? "",
            location: eventLocation?.detail ?? "",
            dressCode: "",
            eventMessage: "",
            planningMode: .openToIdeas,
            members: [host],
            ideas: [],
            timeline: [],
            workspaceBudgetCap: budgetCap,
            registry: []
        )
    }

    static var secondarySample: WeddingWorkspace {
        let calendar = Calendar.current
        let startsAt = calendar.date(byAdding: .day, value: 96, to: .now) ?? .now
        let venue = EventLocation(
            address: "Detroit, Michigan",
            shortAddress: "Detroit, MI",
            placeName: "The Conservatory",
            locationName: "The Conservatory",
            latitude: 42.3314,
            longitude: -83.0458
        )
        let maya = WeddingMember(
            name: "Maya",
            participantRole: .host,
            initials: "M",
            planningPermission: .manage
        )
        let theo = WeddingMember(
            name: "Theo",
            participantRole: .host,
            initials: "T",
            planningPermission: .manage
        )

        return WeddingWorkspace(
            title: "Maya & Theo",
            weddingDate: startsAt,
            mainEventLocation: venue,
            venueName: venue.title,
            location: venue.detail,
            eventMessage: "We can’t wait to celebrate with you.",
            planningMode: .openToIdeas,
            members: [maya, theo],
            ideas: [
                WeddingIdea(
                    title: "Conservatory ceremony",
                    note: "An indoor garden setting with room for dinner and dancing.",
                    category: .venue,
                    submittedBy: "Maya & Theo",
                    status: .chosen
                )
            ],
            timeline: [],
            workspaceBudgetCap: 12_000,
            registry: []
        )
    }
}
