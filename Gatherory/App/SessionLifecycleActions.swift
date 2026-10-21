import Foundation

/// Installs the retention actions used by every sign-in provider and exit
/// path. Authentication owns credentials; these hooks own data and service
/// teardown while the old credential is still available.
@MainActor struct SessionLifecycleActions {
    let authentication: AuthenticationSession
    let library: WorkspaceLibrary
    let persistence: WorkspacePersistenceController
    let cloudSync: WorkspaceCloudSyncController
    let guestInvitations: GuestInvitationStore
    let notifications: NotificationController
    var imageSafety: ImageSafetyStore?

    func install() {
        let library = library
        let persistence = persistence
        let cloudSync = cloudSync
        let guestInvitations = guestInvitations
        let notifications = notifications
        authentication.prepareForGuestAuthentication = { [weak authentication] in
            guard let authentication, authentication.isGuestMode else { return }
            guard !authentication.guestDiscardNeedsAttention else { throw AuthenticationFailure.guestDataUnavailable }
            try persistence.saveChanges(in: library)
        }
        authentication.prepareForGuestDiscard = { profile in
            await notifications.detachCurrentIdentity()
            await guestInvitations.activate(account: nil)
            try guestInvitations.purgeCache(profileID: profile.id)
            try persistence.discardLocalGuest(profile, in: library)
        }
        authentication.prepareForSignOut = { keepingPendingChanges in
            try await cloudSync.prepareForSignOut(keepingPendingChanges: keepingPendingChanges)
            await notifications.detachCurrentIdentity()
            await guestInvitations.activate(account: nil)
        }
        authentication.prepareForAccountDeletion = { accountID in
            await cloudSync.suspendForAccountDeletion(accountID: accountID)
            await notifications.detachCurrentIdentity()
            await guestInvitations.deactivateDeletedAccount(accountID)
        }
        authentication.resumeAfterFailedAccountDeletion = { [weak authentication] account in
            guard let authentication, !authentication.deletionCleanup.blocksEntry,
                  authentication.currentUser?.id == account.id else { return }
            cloudSync.resumeAfterFailedAccountDeletion(accountID: account.id)
            await guestInvitations.activate(account: account)
            await notifications.activate(identity: authentication.notificationPrincipal)
        }
        let cleanup = AccountDeletionLocalCleanup(
            library: library, persistence: persistence, cloudSync: cloudSync,
            guestInvitations: guestInvitations, notifications: notifications,
            imageSafety: imageSafety
        )
        authentication.deletionCleanup.removeLocalData = { [weak authentication] accountID in
            guard let authentication else { throw AuthenticationFailure.serviceUnavailable }
            let canRemoveCredential = authentication.currentUser == nil || authentication.currentUser?.id == accountID
            authentication.clearAccountForDeviceCleanup(accountID: accountID)
            try await cleanup.remove(accountID: accountID, canRemoveSessionCredential: canRemoveCredential)
        }
    }
}
