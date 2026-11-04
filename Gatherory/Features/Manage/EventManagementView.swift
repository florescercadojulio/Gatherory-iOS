import SwiftUI

enum EventManagementDestination: Hashable {
    case people
    case tasks
    case budget
    case settings
    case updates
    case guide
    case guests
    case collaborators
    case requests
}

/// Centralizes the exact-reference checks used by the event management view.
@MainActor
enum EventManagementAccess {
    static func canOpen(reference: EventReference, in workspace: PlanningWorkspace) -> Bool {
        guard workspace.showsPlanningInterface,
              !workspace.isInvitationProjection,
              workspace.canReadTodos(for: reference),
              workspace.currentViewerMember(for: reference)?.invitationStatus == .active,
              workspace.visibleEventContexts.contains(reference),
              ManageEventSummary(workspace: workspace, reference: reference) != nil else { return false }
        if case .subevent(let id) = reference {
            return workspace.timeline.contains {
                $0.id == id && $0.parentEventID == workspace.mainEventID && $0.status != .archived
            }
        }
        return reference == .main && !workspace.isMainEventDeleted
    }

    static func canOpen(
        reference: EventReference,
        in workspace: PlanningWorkspace,
        accountID: String?,
        localGuestProfileID: UUID?
    ) -> Bool {
        guard canOpen(reference: reference, in: workspace),
              let viewer = workspace.currentViewerMember(for: reference) else { return false }

        if let accountID {
            guard workspace.hasAuthenticatedViewer(accountID: accountID),
                  !workspace.isLocalGuestViewer,
                  viewer.userID == nil || viewer.userID == accountID else { return false }
            return true
        }

        guard let localGuestProfileID,
              workspace.isLocalGuestViewer,
              workspace.localGuestProfileID == localGuestProfileID else { return false }
        return true
    }

    static func destinations(reference: EventReference, in workspace: PlanningWorkspace) -> [EventManagementDestination] {
        guard canOpen(reference: reference, in: workspace) else { return [] }
        var result: [EventManagementDestination] = [.people]
        if workspace.canReadTodos(for: reference) { result.append(.tasks) }
        result.append(.budget)
        let canEdit = workspace.canEditTodos(for: reference)
        switch reference {
        case .main where workspace.canManageMainEvent && canEdit:
            result.append(.settings)
        case .subevent where canEdit:
            result.append(.settings)
        default:
            break
        }
        result.append(.updates)
        if !workspace.visibleGuides(for: reference).isEmpty { result.append(.guide) }
        result += [.guests, .collaborators]
        if workspace.canManageInvitations(for: reference) { result.append(.requests) }
        return result
    }

    static func canOpen(
        _ destination: EventManagementDestination,
        for reference: EventReference,
        in workspace: PlanningWorkspace
    ) -> Bool {
        destinations(reference: reference, in: workspace).contains(destination)
    }
}

@MainActor
struct EventManagementView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss

    let reference: EventReference
    private let initialDestination: EventManagementDestination?
    @State private var principalGeneration: UInt64?
    @State private var workspaceID: UUID?
    @State private var didCaptureScope = false

    init(reference: EventReference, initialDestination: EventManagementDestination? = nil) {
        self.reference = reference
        self.initialDestination = initialDestination
    }

    private var isCurrentScope: Bool {
        let accountID = authentication.currentUser?.id
        let localGuestProfileID = accountID == nil && authentication.isGuestMode
            ? authentication.localGuestProfile?.id
            : nil
        return didCaptureScope
            && !authentication.isSigningOut
            && principalGeneration == authentication.principalGeneration
            && workspaceID == workspace.mainEventID
            && EventManagementAccess.canOpen(
                reference: reference,
                in: workspace,
                accountID: accountID,
                localGuestProfileID: localGuestProfileID
            )
    }

    private var destinations: [EventManagementDestination] {
        EventManagementAccess.destinations(reference: reference, in: workspace)
    }

    private var title: String {
        switch reference {
        case .main: workspace.title
        case .subevent(let id): workspace.eventTitle(for: id)
        case .idea: ""
        }
    }

    var body: some View {
        Group {
            if isCurrentScope {
                if let initialDestination {
                    destinationView(initialDestination)
                } else {
                    ManageView(isActive: true, pinnedReference: reference)
                }
            } else if didCaptureScope {
                ContentUnavailableView("Event Unavailable", systemImage: "lock",
                    description: Text("This event is no longer available."))
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(isCurrentScope ? title : String(localized: "Manage"))
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .onAppear {
            guard !didCaptureScope else { return }
            didCaptureScope = true
            principalGeneration = authentication.principalGeneration
            workspaceID = workspace.mainEventID
            if let initialDestination {
                guard EventManagementAccess.canOpen(initialDestination, for: reference, in: workspace) else {
                    dismiss()
                    return
                }
            }
        }
        .onChange(of: isCurrentScope) { _, current in
            if didCaptureScope && !current { dismiss() }
        }
        .onChange(of: authentication.principalGeneration) { _, _ in dismiss() }
        .onChange(of: workspace.mainEventID) { _, _ in dismiss() }
        .onChange(of: workspace.visibleEventContexts) { _, references in
            if !references.contains(reference) { dismiss() }
        }
        .onChange(of: destinations) { _, allowed in
            if let initialDestination, !allowed.contains(initialDestination) { dismiss() }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: EventManagementDestination) -> some View {
        if !isCurrentScope || !destinations.contains(destination) {
            ContentUnavailableView("Event Unavailable", systemImage: "lock")
        } else {
            switch destination {
            case .people:
                EventPeopleView(reference: reference, section: .guests)
            case .guests: EventPeopleView(reference: reference, section: .guests)
            case .collaborators: EventPeopleView(reference: reference, section: .collaborators)
            case .requests: EventJoinRequestsView(eventID: eventID)
            case .tasks: ManageTodosView(reference: reference)
            case .budget: BudgetView(reference: reference)
            case .settings:
                switch reference {
                case .main:
                    WorkspaceSettingsView()
                case .subevent:
                    ManageView(isActive: true, pinnedReference: reference)
                case .idea:
                    ContentUnavailableView("Event Unavailable", systemImage: "lock")
                }
            case .updates: EventAnnouncementsView(eventID: eventID)
            case .guide: ExperienceGuidanceView(reference: reference)
            }
        }
    }

    private var eventID: UUID {
        switch reference {
        case .main: workspace.mainEventID
        case .subevent(let id): id
        case .idea: workspace.mainEventID
        }
    }
}
