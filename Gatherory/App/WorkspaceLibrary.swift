import Foundation
import Observation

/// App-level state that owns the workspaces available to the signed-in person.
/// A workspace remains the source of truth for everything inside one event.
@Observable
final class WorkspaceLibrary {
    private(set) var workspaces: [PlanningWorkspace]
    private(set) var selectedWorkspaceID: UUID?
    private var viewerAccount: UserAccount?
    private var isViewerConfigured = false

    init(workspaces: [PlanningWorkspace] = []) {
        self.workspaces = workspaces
    }

    var selectedWorkspace: PlanningWorkspace? {
        guard let selectedWorkspaceID else { return nil }
        return workspaces.first { $0.mainEventID == selectedWorkspaceID }
    }

    func open(_ workspace: PlanningWorkspace) {
        guard workspaces.contains(where: { $0.mainEventID == workspace.mainEventID }) else { return }
        selectedWorkspaceID = workspace.mainEventID
    }

    func closeWorkspace() {
        selectedWorkspaceID = nil
    }

    func add(_ workspace: PlanningWorkspace, openAfterAdding: Bool = true) {
        guard !workspaces.contains(where: { $0.mainEventID == workspace.mainEventID }) else { return }
        if isViewerConfigured {
            workspace.configureViewer(viewerAccount)
        }
        workspaces.insert(workspace, at: 0)
        if openAfterAdding {
            selectedWorkspaceID = workspace.mainEventID
        }
    }

    func remove(_ workspace: PlanningWorkspace) {
        workspaces.removeAll { $0.mainEventID == workspace.mainEventID }
        if selectedWorkspaceID == workspace.mainEventID {
            selectedWorkspaceID = nil
        }
    }

    func removeAll() {
        selectedWorkspaceID = nil
        workspaces.removeAll()
    }

    func replaceAll(with replacements: [PlanningWorkspace]) {
        if isViewerConfigured {
            for workspace in replacements {
                workspace.configureViewer(viewerAccount)
            }
        }
        workspaces = replacements
        if let selectedWorkspaceID,
           !replacements.contains(where: { $0.mainEventID == selectedWorkspaceID }) {
            self.selectedWorkspaceID = nil
        }
    }

    func upsert(_ workspace: PlanningWorkspace) {
        if isViewerConfigured {
            workspace.configureViewer(viewerAccount)
        }
        if let index = workspaces.firstIndex(where: {
            $0.mainEventID == workspace.mainEventID
        }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }

    func remove(workspaceID: UUID) {
        workspaces.removeAll { $0.mainEventID == workspaceID }
        if selectedWorkspaceID == workspaceID {
            selectedWorkspaceID = nil
        }
    }

    func configureViewer(_ account: UserAccount?) {
        viewerAccount = account
        isViewerConfigured = true
        for workspace in workspaces {
            workspace.configureViewer(account)
        }
    }
}

extension WorkspaceLibrary {
    static func bootstrap(seedData: Bool = AppRuntimeConfiguration.seedsDevelopmentData) -> WorkspaceLibrary {
        seedData ? sample : WorkspaceLibrary()
    }

    static var sample: WorkspaceLibrary {
        let workspaces = [PlanningWorkspace.sample, .secondarySample]
        let developmentAccount = DevelopmentAccountFixtures.planner

        for workspace in workspaces {
            guard let hostIndex = workspace.members.firstIndex(where: {
                $0.participantRole == .host
            }) else { continue }
            workspace.members[hostIndex].userID = developmentAccount.id
            workspace.members[hostIndex].email = developmentAccount.email
            workspace.members[hostIndex].profileImageAssetName = developmentAccount.profileImageAssetName
            workspace.members[hostIndex].profileImageURL = developmentAccount.profileImageURL
        }

        return WorkspaceLibrary(workspaces: workspaces)
    }
}

extension PlanningWorkspace {
    static func newWorkspace(
        title: String,
        startsAt: Date,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        timeZoneIdentifier: String = TimeZone.autoupdatingCurrent.identifier,
        eventLocation: EventLocation?,
        imageData: Data?,
        budgetCap: Decimal? = nil,
        owner: UserAccount? = nil
    ) -> PlanningWorkspace {
        let ownerName = owner?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = ownerName.flatMap { $0.isEmpty ? nil : $0 } ?? "You"
        let initials = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        let host = WorkspaceMember(
            userID: owner?.id,
            name: displayName,
            participantRole: .host,
            initials: initials.isEmpty ? "Y" : initials,
            email: owner?.email,
            profileImageAssetName: owner?.profileImageAssetName,
            profileImageURL: owner?.profileImageURL,
            planningPermission: .manage
        )

        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        let normalizedStart = isAllDay ? calendar.startOfDay(for: startsAt) : startsAt
        let normalizedEnd = endsAt.map { end in
            let candidate = isAllDay ? calendar.startOfDay(for: end) : end
            return max(candidate, normalizedStart)
        }

        return PlanningWorkspace(
            title: title,
            mainEventStartsAt: normalizedStart,
            mainEventEndsAt: normalizedEnd,
            mainEventIsAllDay: isAllDay,
            mainEventTimeZoneIdentifier: timeZoneIdentifier,
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

    static var secondarySample: PlanningWorkspace {
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
        let maya = WorkspaceMember(
            name: "Maya",
            participantRole: .host,
            initials: "M",
            planningPermission: .manage
        )
        let theo = WorkspaceMember(
            name: "Theo",
            participantRole: .host,
            initials: "T",
            planningPermission: .manage
        )

        return PlanningWorkspace(
            title: "Maya & Theo’s Wedding",
            mainEventStartsAt: startsAt,
            mainEventLocation: venue,
            venueName: venue.title,
            location: venue.detail,
            eventMessage: "We can’t wait to celebrate with you.",
            planningMode: .openToIdeas,
            members: [maya, theo],
            ideas: [
                PlanningIdea(
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
