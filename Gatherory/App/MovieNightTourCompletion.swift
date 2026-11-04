import Foundation

/// Removes only the account's exact Movie Night practice workspace after the
/// completion prompt. The normal persistence diff stages its workspace delete
/// and outbox changes in one transaction.
@MainActor
enum MovieNightTourCompletion {
    enum RemovalError: Error, Equatable {
        case wrongAccount
        case receiptMismatch
        case workspaceNotFound
        case unavailable
    }

    static func removePracticeWorkspace(
        account: UserAccount,
        workspaceID: UUID,
        library: WorkspaceLibrary,
        persistence: WorkspacePersistenceController,
        store: MovieNightTourStore? = nil
    ) throws {
        guard persistence.activeUserID == account.id else { throw RemovalError.wrongAccount }
        let store = store ?? MovieNightTourStore()
        guard store.progress(accountID: account.id)?.installedWorkspaceID == workspaceID else {
            throw RemovalError.receiptMismatch
        }
        guard let workspace = library.workspaces.first(where: { $0.mainEventID == workspaceID }) else {
            throw RemovalError.workspaceNotFound
        }

        library.configureViewer(account)
        guard let viewer = workspace.currentViewerMember(for: .main),
              viewer.userID == account.id,
              viewer.participantRole == .host,
              viewer.planningPermission == .manage,
              viewer.invitationStatus == .active,
              !workspace.isScopedEvent,
              !workspace.isInvitationProjection,
              !workspace.isMainEventDeleted,
              !workspace.currentMainEventStatus.isReadOnly,
              workspace.eventRemovalAction(for: .main) == .deleteMainEvent else {
            throw RemovalError.unavailable
        }

        let previousWorkspaces = library.workspaces
        let previouslySelected = library.selectedWorkspace
        library.remove(workspace)
        do {
            try persistence.saveChanges(in: library)
        } catch {
            library.replaceAll(with: previousWorkspaces)
            if let previouslySelected,
               library.workspaces.contains(where: { $0.mainEventID == previouslySelected.mainEventID }) {
                library.open(previouslySelected)
            }
            throw error
        }

        // Keep the receipt as a completed account-scoped lesson so re-entry can
        // start another copy. Mark it complete only after the delete commits.
        store.advance(accountID: account.id, to: .completed)
    }
}
