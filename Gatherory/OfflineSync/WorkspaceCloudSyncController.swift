import Foundation
import Observation
import PostHog

enum AccountOnboardingState: Equatable, Sendable {
    case signedOut
    case resolving
    case needsOnboarding
    case complete
    case unavailable
}

@MainActor
final class WorkspaceRemoteChangeApplier: RemoteChangeApplying {
    private let persistence: WorkspacePersistenceController
    private let library: WorkspaceLibrary

    init(
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary
    ) {
        self.persistence = persistence
        self.library = library
    }

    func currentCursor(for scopeID: UUID) async throws -> String? {
        try persistence.currentCursor(for: scopeID)
    }

    func apply(_ page: SyncPullPage, to scopeID: UUID) async throws {
        try persistence.applyRemotePage(page, scopeID: scopeID, to: library)
    }
}

@MainActor
@Observable
final class WorkspaceCloudSyncController {
    private(set) var isSynchronizing = false
    private(set) var lastError: Error?
    private(set) var lastMediaError: Error?
    private(set) var hasPendingMediaUploads = false
    private(set) var pendingChangeScopeIDs: Set<UUID> = []
    private(set) var pendingPhotoScopeIDs: Set<UUID> = []
    private(set) var confirmedSyncScopeIDs: Set<UUID> = []
    private(set) var photoAttentionScopeIDs: Set<UUID> = []
    private(set) var activeSyncScopeID: UUID?
    private(set) var failedSyncScopeID: UUID?
    private(set) var cannotReadSaveState = false
    private(set) var lastSuccessfulSyncAt: Date?
    private(set) var accountOnboardingState: AccountOnboardingState = .signedOut

    @ObservationIgnored private let persistence: WorkspacePersistenceController
    @ObservationIgnored private let library: WorkspaceLibrary
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private var activeUserID: String?
    @ObservationIgnored private var hasBootstrappedUserID: String?
    @ObservationIgnored private var scheduledTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherSync = false

    init(
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary,
        baseURL: URL?
    ) {
        self.persistence = persistence
        self.library = library
        self.baseURL = baseURL

        persistence.onPendingMutations = { [weak self] in
            self?.schedule(trigger: .mutationCreated)
        }
    }

    func activate(userID: String?, seedData: Bool) async {
        guard activeUserID != userID else {
            if userID != nil {
                await synchronize(trigger: .appBecameActive)
            } else {
                accountOnboardingState = .signedOut
            }
            return
        }

        scheduledTask?.cancel()
        scheduledTask = nil
        activeUserID = userID
        hasBootstrappedUserID = nil
        needsAnotherSync = false
        lastError = nil
        lastMediaError = nil
        hasPendingMediaUploads = false
        pendingChangeScopeIDs = []
        pendingPhotoScopeIDs = []
        confirmedSyncScopeIDs = []
        photoAttentionScopeIDs = []
        activeSyncScopeID = nil
        failedSyncScopeID = nil
        accountOnboardingState = userID == nil
            ? .signedOut
            : AppRuntimeConfiguration.usesRemoteAccountState ? .resolving : .needsOnboarding
        persistence.activate(userID: userID, in: library, seedData: seedData)

        guard let userID else { return }
        guard AppRuntimeConfiguration.usesRemoteAccountState else {
            accountOnboardingState = library.workspaces.isEmpty ? .needsOnboarding : .complete
            return
        }
        guard baseURL != nil else {
            accountOnboardingState = hasConfirmedOnboarding(for: userID)
                ? .complete
                : .unavailable
            return
        }
        await synchronize(trigger: .appBecameActive)
    }

    func markOnboardingCompletedLocally() {
        guard let userID = activeUserID else { return }
        accountOnboardingState = .complete
        setConfirmedOnboarding(true, for: userID)
    }

    func retryInitialBootstrap() async {
        guard let userID = activeUserID else { return }
        // Do not let a pre-invitation bootstrap overwrite a later request to
        // discover newly granted planning scopes.
        while isSynchronizing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard activeUserID == userID else { return }
        }
        guard activeUserID == userID else { return }
        accountOnboardingState = .resolving
        hasBootstrappedUserID = nil
        await synchronize(trigger: .manual)
    }

    func schedule(trigger: SyncTrigger) {
        refreshSaveState()
        guard activeUserID != nil else { return }
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            await self.synchronize(trigger: trigger)
        }
    }

    func synchronize(trigger: SyncTrigger = .manual) async {
        guard let userID = activeUserID,
              let baseURL
        else { return }
        if isSynchronizing {
            // MainActor methods can be re-entered while the current network
            // request is suspended. Remember that new local work arrived so it
            // is not stranded merely because a sync was already in flight.
            needsAnotherSync = true
            return
        }

        isSynchronizing = true
        refreshSaveState()
        defer {
            isSynchronizing = false
            activeSyncScopeID = nil
            refreshSaveState()
        }

        PostHogSDK.shared.logger?.info("workspace_sync_started trigger=\(trigger.rawValue)")
        let transport = PostgresSyncTransport(baseURL: baseURL)
        syncPass: repeat {
            needsAnotherSync = false
            do {
                if hasBootstrappedUserID != userID {
                    let response = try await transport.bootstrap()
                    guard activeUserID == userID else { return }
                    try persistence.applyBootstrap(
                        response.snapshots,
                        entities: response.entitySnapshots,
                        to: library
                    )
                    let hasCompletedOnboarding =
                        response.account?.hasCompletedOnboarding == true ||
                        !response.snapshots.isEmpty ||
                        hasConfirmedOnboarding(for: userID) ||
                        !library.workspaces.isEmpty
                    accountOnboardingState = hasCompletedOnboarding
                        ? .complete
                        : .needsOnboarding
                    if hasCompletedOnboarding {
                        setConfirmedOnboarding(true, for: userID)
                    }
                    hasBootstrappedUserID = userID
                }

                try persistence.repairWorkspaceScopeMismatches(from: library)
                try persistence.prepareMediaTransfers(from: library)
                try persistence.sanitizePendingMediaMutations()
                let pendingScopes = try persistence.pendingScopeIDs()
                let scopes = Set(library.workspaces.map(\.mainEventID)).union(pendingScopes)
                let store = SwiftDataSyncStore(modelContainer: persistence.container)
                let applier = WorkspaceRemoteChangeApplier(
                    persistence: persistence,
                    library: library
                )
                let coordinator = OfflineSyncCoordinator(
                    store: store,
                    transport: transport,
                    remoteApplier: applier,
                    ownerUserID: userID
                )
                let mediaCoordinator = WorkspaceMediaSyncCoordinator(
                    persistence: persistence,
                    library: library,
                    transport: R2MediaTransport(baseURL: baseURL)
                )
                var mediaError: Error?

                for scopeID in scopes.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard activeUserID == userID else { return }
                    activeSyncScopeID = scopeID
                    refreshSaveState()
                    let syncSummary = try await coordinator.synchronize(
                        scopeID: scopeID,
                        trigger: trigger
                    )
                    if let failureCode = syncSummary.attentionFailureCode {
                        // A malformed legacy workspace mutation leaves the
                        // server without a scope, so its children are also
                        // rejected. The coordinator has now durably recorded
                        // those rejections; rebuild the batch immediately and
                        // retry in this same user-initiated sync pass.
                        if isRecoverableWorkspaceBootstrapFailure(failureCode),
                           try persistence.repairWorkspaceScopeMismatches(from: library) > 0 {
                            continue syncPass
                        }
                        throw CloudSyncFailure.server(failureCode)
                    }
                    let mediaSummary = try await mediaCoordinator.uploadPendingMedia(scopeID: scopeID)
                    if mediaSummary.deferredError != nil { photoAttentionScopeIDs.insert(scopeID) }
                    else { photoAttentionScopeIDs.remove(scopeID) }
                    mediaError = mediaError ?? mediaSummary.deferredError
                    if mediaSummary.changed {
                        // Asset ids are tiny entity updates. Push them
                        // immediately so canonical media placements never lag
                        // behind a completed R2 upload.
                        _ = try await coordinator.synchronize(
                            scopeID: scopeID,
                            trigger: .mutationCreated
                        )
                    }
                    await mediaCoordinator.downloadMissingMedia(scopeID: scopeID)
                    confirmedSyncScopeIDs.insert(scopeID)
                    if failedSyncScopeID == scopeID { failedSyncScopeID = nil }
                    refreshSaveState()
                }

                if let failureCode = try persistence.pendingSyncAttentionFailureCode() {
                    throw CloudSyncFailure.server(failureCode)
                }

                lastError = nil
                hasPendingMediaUploads = try persistence.hasPendingMediaTransfers()
                if let mediaError {
                    lastMediaError = mediaError
                } else if !hasPendingMediaUploads {
                    lastMediaError = nil
                }
                lastSuccessfulSyncAt = .now
                PostHogSDK.shared.logger?.info("workspace_sync_completed")
            } catch {
                failedSyncScopeID = activeSyncScopeID
                PostHogSDK.shared.logger?.error("workspace_sync_failed")
                lastError = error
                if hasBootstrappedUserID == nil {
                    accountOnboardingState = hasConfirmedOnboarding(for: userID) || !library.workspaces.isEmpty
                        ? .complete
                        : .unavailable
                }
                return
            }
        } while needsAnotherSync && activeUserID == userID
    }

    private func refreshSaveState() {
        do {
            pendingChangeScopeIDs = try persistence.pendingScopeIDs()
            pendingPhotoScopeIDs = try persistence.pendingMediaScopeIDs()
            hasPendingMediaUploads = !pendingPhotoScopeIDs.isEmpty
            cannotReadSaveState = false
        } catch { cannotReadSaveState = true }
    }

    private func hasConfirmedOnboarding(for userID: String) -> Bool {
        UserDefaults.standard.bool(forKey: onboardingCacheKey(for: userID))
    }

    private func setConfirmedOnboarding(_ isComplete: Bool, for userID: String) {
        let key = onboardingCacheKey(for: userID)
        if isComplete {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func onboardingCacheKey(for userID: String) -> String {
        "accountOnboardingComplete.\(userID)"
    }

    private func isRecoverableWorkspaceBootstrapFailure(_ code: String) -> Bool {
        code == "WORKSPACE_SCOPE_MISMATCH" || code == "SYNC_SCOPE_NOT_FOUND"
    }
}
