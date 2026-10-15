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

private enum PostHogSyncLogCapture {
    static func started(trigger: SyncTrigger) {
        PostHogSDK.shared.logger?.info("workspace_sync_started", attributes: [
            "trigger": trigger.rawValue
        ])
    }

    static func completed(trigger: SyncTrigger) {
        PostHogSDK.shared.logger?.info("workspace_sync_completed", attributes: [
            "trigger": trigger.rawValue
        ])
    }

    static func failed(trigger: SyncTrigger, stage: String, error: Error) {
        PostHogSDK.shared.logger?.error("workspace_sync_failed", attributes: [
            "trigger": trigger.rawValue,
            "stage": stage,
            "error_type": String(describing: type(of: error))
        ])
    }
}

@MainActor
final class WorkspaceRemoteChangeApplier: RemoteChangeApplying {
    private let persistence: WorkspacePersistenceController
    private let library: WorkspaceLibrary
    private let ownerUserID: String?

    init(
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary
    ) {
        self.persistence = persistence
        self.library = library
        self.ownerUserID = persistence.activeUserID
    }

    func currentCursor(for scopeID: UUID) async throws -> String? {
        try persistence.currentCursor(for: scopeID)
    }

    func apply(_ page: SyncPullPage, to scopeID: UUID) async throws {
        try Task.checkCancellation()
        guard persistence.activeUserID == ownerUserID else { throw CancellationError() }
        try persistence.applyRemotePage(page, scopeID: scopeID, to: library)
    }

    func clearForbiddenScope(_ scopeID: UUID) async throws -> Bool {
        guard persistence.activeUserID == ownerUserID else { throw CancellationError() }
        return try persistence.clearScopedWorkspaceAfterWriteForbidden(scopeID: scopeID, from: library)
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

    /// Creates an account-scoped blueprint client for the authenticated
    /// workspace currently managed by this controller.
    func makeBlueprintInstallationCoordinator() -> BlueprintInstallationCoordinator? {
        guard let baseURL,
              let activeUserID,
              persistence.activeUserID == activeUserID else { return nil }
        return BlueprintInstallationCoordinator(
            baseURL: baseURL,
            persistence: persistence,
            library: library
        )
    }

    @ObservationIgnored private let persistence: WorkspacePersistenceController
    @ObservationIgnored private let library: WorkspaceLibrary
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private let injectedTransport: (any WorkspaceSnapshotTransport)?
    @ObservationIgnored private let usesRemoteAccountState: Bool
    @ObservationIgnored private var activationRevision = UUID()
    @ObservationIgnored private var activeUserID: String?
    @ObservationIgnored private var hasBootstrappedUserID: String?
    @ObservationIgnored private var scheduledTask: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherSync = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var isPreparingSignOut = false

    init(
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary,
        baseURL: URL?,
        transport: (any WorkspaceSnapshotTransport)? = nil,
        usesRemoteAccountState: Bool? = nil
    ) {
        self.persistence = persistence
        self.library = library
        self.baseURL = baseURL
        self.injectedTransport = transport
        self.usesRemoteAccountState = usesRemoteAccountState ?? AppRuntimeConfiguration.usesRemoteAccountState

        persistence.onPendingMutations = { [weak self] in
            self?.schedule(trigger: .mutationCreated)
        }
    }

    func activate(userID: String?, seedData: Bool) async {
        let revision = UUID()
        activationRevision = revision
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
        // Join cancellation before replacing the graph, including A -> B -> A.
        syncTask?.cancel()
        await syncTask?.value
        guard !Task.isCancelled, activationRevision == revision else { return }
        SyncDiagnostics.record("sync_account_changed", fields: [
            "previous_account": SyncDiagnostics.accountKey(activeUserID),
            "next_account": SyncDiagnostics.accountKey(userID)
        ])
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
            : usesRemoteAccountState ? .resolving : .needsOnboarding
        persistence.activate(userID: userID, in: library, seedData: seedData)

        guard let userID else { return }
        guard usesRemoteAccountState else {
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
        guard activeUserID != nil, !isPreparingSignOut else { return }
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            await self.synchronize(trigger: trigger)
        }
    }

    func synchronize(trigger: SyncTrigger = .manual) async {
        guard !isPreparingSignOut else { return }
        await runJoinedSync(trigger: trigger)
    }

    /// Refresh the shared roster and responses without racing debounced local edits.
    func refreshCollaboration(passively: Bool = false) async {
        guard activeUserID != nil, usesRemoteAccountState, !isPreparingSignOut,
              !isSynchronizing, !Task.isCancelled else { return }
        if passively {
            // Let the debounced local save and its mutation-triggered sync run.
            // A timer must not force whole-library serialization on the UI actor.
            guard !persistence.hasUnsavedLocalChanges else { return }
        } else {
            do {
                try persistence.saveChanges(in: library)
            } catch {
                lastError = error
                SyncDiagnostics.record("collaboration_refresh_save_failed", error: error)
                return
            }
        }
        await synchronize(trigger: .backgroundRefresh)
    }

    private func runJoinedSync(trigger: SyncTrigger) async {
        if let syncTask {
            needsAnotherSync = true
            await syncTask.value
            return
        }
        let task = Task {
            defer { self.syncTask = nil }
            await self.performSync(trigger: trigger)
        }
        syncTask = task
        await task.value
    }

    func prepareForSignOut(keepingPendingChanges: Bool) async throws {
        isPreparingSignOut = true
        defer { isPreparingSignOut = false }
        scheduledTask?.cancel()
        scheduledTask = nil
        // Offline connections must not trap the user on the progress screen.
        // Capture debounced edits BEFORE an old pull can replace the graph.
        if activeUserID != nil { try persistence.flushForAccountTransition(library) }
        syncTask?.cancel()
        var timedOut = false
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            timedOut = true
            self.syncTask?.cancel()
        }
        defer { deadline.cancel() }
        await syncTask?.value
        if timedOut { throw URLError(.timedOut) }
        guard activeUserID != nil else { return }
        try persistence.flushForAccountTransition(library)
        if !keepingPendingChanges, usesRemoteAccountState {
            try persistence.prepareFinalSyncRetry()
            // A clean account must not be trapped by an unrelated bootstrap or
            // refresh failure. Read the durable outboxes, not a stale UI flag.
            let needsUpload = try !persistence.pendingScopeIDs().isEmpty || persistence.hasPendingMediaTransfers()
            SyncDiagnostics.record("sign_out_sync_checked", fields: ["needs_upload": String(needsUpload)])
            if needsUpload { await runJoinedSync(trigger: .manual) }
            if timedOut { throw URLError(.timedOut) }
            refreshSaveState()
            if needsUpload, let lastError { throw lastError }
            guard !cannotReadSaveState,
                  pendingChangeScopeIDs.isEmpty, !hasPendingMediaUploads else {
                if let lastMediaError { throw lastMediaError }
                throw CloudSyncFailure.server("SIGN_OUT_SYNC_PENDING")
            }
        }
        // Unsent records stay account-scoped on disk when explicitly skipped.
        await activate(userID: nil, seedData: false)
    }

    private func performSync(trigger: SyncTrigger) async {
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

        let runID = UUID().uuidString
        var stage = "bootstrap"
        var diagnosticFields: [String: String] {
            ["run_id": runID, "account_key": SyncDiagnostics.accountKey(userID), "trigger": trigger.rawValue, "stage": stage,
             "signing_out": String(isPreparingSignOut),
             "scope_id": activeSyncScopeID?.uuidString ?? "none",
             "pending_scopes": String(pendingChangeScopeIDs.count),
             "pending_photo_scopes": String(pendingPhotoScopeIDs.count)]
        }
        SyncDiagnostics.record("workspace_sync_started", fields: diagnosticFields)
        PostHogSyncLogCapture.started(trigger: trigger)
        let transport: any WorkspaceSnapshotTransport = injectedTransport ?? PostgresSyncTransport(baseURL: baseURL)
        syncPass: repeat {
            needsAnotherSync = false
            do {
                if hasBootstrappedUserID != userID, !isPreparingSignOut {
                    stage = "bootstrap"
                    let response = try await transport.bootstrap()
                    try Task.checkCancellation()
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

                stage = "prepare_outbox"
                try persistence.repairWorkspaceScopeMismatches(from: library)
                try persistence.prepareMediaTransfers(from: library)
                try persistence.sanitizePendingMediaMutations()
                let pendingScopes = try persistence.pendingScopeIDs()
                let scopes = isPreparingSignOut
                    ? pendingScopes.union(try persistence.pendingMediaScopeIDs())
                    : Set(library.workspaces.map(\.mainEventID)).union(pendingScopes)
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
                    try Task.checkCancellation()
                    guard activeUserID == userID else { return }
                    activeSyncScopeID = scopeID
                    refreshSaveState()
                    stage = "push_pull"
                    let syncSummary = try await coordinator.synchronize(
                        scopeID: scopeID,
                        trigger: trigger,
                        pullRemoteChanges: !isPreparingSignOut
                    )
                    if syncSummary.scopeWasRevoked { continue }
                    if let failureCode = syncSummary.attentionFailureCode {
                        if failureCode == "SCOPE_WRITE_FORBIDDEN",
                           try persistence.clearScopedWorkspaceAfterWriteForbidden(
                            scopeID: scopeID,
                            from: library
                           ) {
                            continue
                        }
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
                    stage = "upload_media"
                    let mediaSummary = try await mediaCoordinator.uploadPendingMedia(scopeID: scopeID)
                    if let error = mediaSummary.deferredError {
                        SyncDiagnostics.record("workspace_media_failed", fields: diagnosticFields, error: error)
                    }
                    if mediaSummary.deferredError != nil { photoAttentionScopeIDs.insert(scopeID) }
                    else { photoAttentionScopeIDs.remove(scopeID) }
                    mediaError = mediaError ?? mediaSummary.deferredError
                    if mediaSummary.changed {
                        // Asset ids are tiny entity updates. Push them
                        // immediately so canonical media placements never lag
                        // behind a completed R2 upload.
                        stage = "publish_media"
                        let published = try await coordinator.synchronize(
                            scopeID: scopeID,
                            trigger: .mutationCreated,
                            pullRemoteChanges: !isPreparingSignOut
                        )
                        if let code = published.attentionFailureCode { throw CloudSyncFailure.server(code) }
                    }
                    // Signing out uploads local work, not a fresh offline photo
                    // library that is about to leave the screen.
                    stage = "download_media"
                    let downloads = isPreparingSignOut ? MediaUploadRunSummary()
                        : await mediaCoordinator.downloadMissingMedia(scopeID: scopeID)
                    if let error = downloads.deferredError {
                        SyncDiagnostics.record("workspace_media_failed", fields: diagnosticFields, error: error)
                    }
                    guard activeUserID == userID else { return }
                    if downloads.deferredError != nil { photoAttentionScopeIDs.insert(scopeID) }
                    mediaError = mediaError ?? downloads.deferredError
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
                SyncDiagnostics.record("workspace_sync_completed", fields: diagnosticFields)
                PostHogSyncLogCapture.completed(trigger: trigger)
            } catch {
                guard !Task.isCancelled else { return }
                failedSyncScopeID = activeSyncScopeID
                SyncDiagnostics.record("workspace_sync_failed", fields: diagnosticFields, error: error)
                PostHogSyncLogCapture.failed(trigger: trigger, stage: stage, error: error)
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
