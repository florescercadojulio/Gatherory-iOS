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

    func remove(_ workspace: WeddingWorkspace) {
        workspaces.removeAll { $0.mainEventID == workspace.mainEventID }
        if selectedWorkspaceID == workspace.mainEventID {
            selectedWorkspaceID = nil
        }
    }

    func removeAll() {
        selectedWorkspaceID = nil
        workspaces.removeAll()
    }

    func replaceAll(with replacements: [WeddingWorkspace]) {
        workspaces = replacements
        if let selectedWorkspaceID,
           !replacements.contains(where: { $0.mainEventID == selectedWorkspaceID }) {
            self.selectedWorkspaceID = nil
        }
    }

    func upsert(_ workspace: WeddingWorkspace) {
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
}

extension WorkspaceLibrary {
    static func bootstrap(seedData: Bool = AppRuntimeConfiguration.seedsDevelopmentData) -> WorkspaceLibrary {
        seedData ? sample : WorkspaceLibrary()
    }

    static var sample: WorkspaceLibrary {
        WorkspaceLibrary(workspaces: [.sample, .secondarySample])
    }
}

extension WeddingWorkspace {
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
    ) -> WeddingWorkspace {
        let ownerName = owner?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = ownerName.flatMap { $0.isEmpty ? nil : $0 } ?? "You"
        let initials = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        let host = WeddingMember(
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

        return WeddingWorkspace(
            title: title,
            weddingDate: normalizedStart,
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
            title: "Maya & Theo’s Wedding",
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
