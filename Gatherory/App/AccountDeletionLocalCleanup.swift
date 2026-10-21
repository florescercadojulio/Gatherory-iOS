import Foundation

/// Every cleanup uses the captured deleted ID. Failures in one cache must not
/// skip removal from the other stores; the journal retries all steps safely.
@MainActor struct AccountDeletionLocalCleanup {
    let library: WorkspaceLibrary
    let persistence: WorkspacePersistenceController
    let cloudSync: WorkspaceCloudSyncController
    let guestInvitations: GuestInvitationStore
    let notifications: NotificationController
    var imageSafety: ImageSafetyStore?
    var defaults: UserDefaults = .standard
    var removeSessionCredential: () throws -> Void = { try KeychainSessionTokenStore().deleteChecked() }
    var artifactCleanupSteps: [(String) throws -> Void]?

    func remove(accountID: String, canRemoveSessionCredential: Bool) async throws {
        // An in-memory fallback cannot stand in for cleaning the real disk store.
        var firstError: (any Error)? = persistence.storageInitializationError
        await cloudSync.deactivateDeletedAccount(accountID: accountID)
        try Task.checkCancellation()
        await guestInvitations.deactivateDeletedAccount(accountID)
        await notifications.forgetDeletedAccount(accountID)
        func attempt(_ operation: () throws -> Void) {
            do { try operation() } catch { if firstError == nil { firstError = error } }
        }
        if persistence.storageInitializationError == nil {
            attempt { try persistence.purgeLocalData(accountID: accountID, from: library) }
        }
        attempt { try guestInvitations.purgeCache(accountID: accountID) }
        let artifacts = artifactCleanupSteps ?? [
            { try KeychainBlueprintShareLinkCredentialStore().removeAll(accountID: $0) },
            { try BlueprintInstallationIntentStore().removeAll(accountID: $0) },
            { try BlueprintSetupDraftStore().removeAll(accountID: $0) },
            { try BlueprintLibraryCache().removeAll(accountID: $0) },
            { try BlueprintPersonalLibraryStore().removeAll(accountID: $0) },
            { try BlueprintLibraryVisibilityStore(defaults: defaults).removeAll(accountID: $0) },
            { try BlueprintLibraryCollectionPreferenceStore(defaults: defaults).removeAll(accountID: $0) },
            { try BlueprintRecentHistory(defaults: defaults).removeAll(accountID: $0) }
        ]
        for artifact in artifacts { attempt { try artifact(accountID) } }
        if canRemoveSessionCredential { attempt { try removeSessionCredential() } }
        imageSafety?.purge(accountID: accountID)
        defaults.removeObject(forKey: "accountOnboardingComplete.\(accountID)")
        if let firstError { throw firstError }
    }
}
