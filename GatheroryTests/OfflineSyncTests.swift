import Foundation
import SwiftData
import Testing
@testable import Gatherory

struct OfflineSyncTests {
    @Test("Passive collaboration refresh yields to debounced edits; explicit refresh saves them")
    @MainActor
    func passiveRefreshYieldsToLocalEdits() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = SignOutSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        persistence.startObserving(library)
        await sync.activate(userID: "passive-refresh", seedData: false)
        await Task.yield()
        let workspace = PlanningWorkspace.newWorkspace(title: "Before", startsAt: .now, eventLocation: nil, imageData: nil)
        library.add(workspace)
        try persistence.saveChanges(in: library)
        await sync.synchronize()
        // Drain observation callbacks from setup before making the test edit.
        await Task.yield()
        try persistence.saveChanges(in: library)
        workspace.title = "Unsaved local edit"
        // Observation schedules the debounce on the next main-actor turn.
        for _ in 0..<100 {
            if persistence.hasUnsavedLocalChanges { break }
            await Task.yield()
        }
        #expect(persistence.hasUnsavedLocalChanges)
        let pulls = transport.pullCount
        let pushes = transport.payloads.count
        await sync.refreshCollaboration(passively: true)
        #expect(transport.pullCount == pulls)
        #expect(transport.payloads.count == pushes)
        #expect(persistence.hasUnsavedLocalChanges)
        #expect(library.selectedWorkspace === workspace)
        await sync.refreshCollaboration()
        #expect(!persistence.hasUnsavedLocalChanges)
        #expect(transport.payloads.contains { String(data: $0, encoding: .utf8)?.contains("Unsaved local edit") == true })
        try await sync.prepareForSignOut(keepingPendingChanges: true)
    }

    @Test("Skipping event creation survives account switches without creating data or skipping another account")
    @MainActor
    func skipEventCreation() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let first = UUID().uuidString
        let second = UUID().uuidString
        defer {
            UserDefaults.standard.removeObject(forKey: "accountOnboardingComplete.\(first)")
            UserDefaults.standard.removeObject(forKey: "accountOnboardingComplete.\(second)")
        }
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: SignOutSyncTransport(), usesRemoteAccountState: true)
        await sync.activate(userID: first, seedData: false)
        #expect(sync.accountOnboardingState == .needsOnboarding)
        sync.markOnboardingCompletedLocally()
        #expect(sync.accountOnboardingState == .complete)
        #expect(library.workspaces.isEmpty)
        #expect(try persistence.pendingScopeIDs().isEmpty)
        await sync.activate(userID: second, seedData: false)
        #expect(sync.accountOnboardingState == .needsOnboarding)
        await sync.activate(userID: first, seedData: false)
        #expect(sync.accountOnboardingState == .complete)
        #expect(library.workspaces.isEmpty)
    }

    @Test("A clean account can sign out after a failed refresh without losing its saved data")
    @MainActor
    func cleanSignOutAfterFailedRefresh() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = SignOutSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        await sync.activate(userID: "host", seedData: false)
        library.add(PlanningWorkspace.newWorkspace(title: "Saved", startsAt: .now, eventLocation: nil, imageData: nil))
        try persistence.flushForAccountTransition(library)
        await sync.synchronize()
        #expect(try persistence.pendingScopeIDs().isEmpty)
        transport.failPull = true
        await sync.synchronize()
        #expect(sync.lastError != nil)
        try await sync.prepareForSignOut(keepingPendingChanges: false)
        #expect(persistence.activeUserID == nil)
        await sync.activate(userID: "collaborator", seedData: false)
        #expect(library.workspaces.isEmpty)
        try await sync.prepareForSignOut(keepingPendingChanges: false)
        await sync.activate(userID: "host", seedData: false)
        #expect(library.workspaces.first?.title == "Saved")
    }

    @Test("Final sign-out uploads pending edits without requiring a successful refresh")
    @MainActor
    func signOutDoesNotPull() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = SignOutSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        await sync.activate(userID: "host", seedData: false)
        library.add(PlanningWorkspace.newWorkspace(title: "Final edit", startsAt: .now, eventLocation: nil, imageData: nil))
        transport.failPull = true
        try await sync.prepareForSignOut(keepingPendingChanges: false)
        #expect(persistence.activeUserID == nil)
        #expect(!transport.payloads.isEmpty)
        persistence.activate(userID: "host", in: library)
        #expect(try persistence.pendingScopeIDs().isEmpty)
    }

    @Test("Sync diagnostics preserve typed and legacy server error identifiers")
    func diagnosticErrorEnvelopes() {
        let media = SyncDiagnostics.serverFailure(in: Data(#"{"ok":false,"error":{"code":"MEDIA_FORBIDDEN","errorId":"reference","userMessage":"Private message"}}"#.utf8))
        #expect(media.code == "MEDIA_FORBIDDEN")
        #expect(media.errorID == "reference")
        let sync = SyncDiagnostics.serverFailure(in: Data(#"{"error":"SYNC_SCOPE_NOT_FOUND","errorId":"sync-reference"}"#.utf8))
        #expect(sync.code == "SYNC_SCOPE_NOT_FOUND")
        #expect(sync.errorID == "sync-reference")
        #expect(SyncDiagnostics.serverFailure(in: Data("not json".utf8)).code == nil)
    }

    @Test("A cancelled pull cannot apply its late response during account teardown")
    @MainActor
    func cancelledPullDoesNotApply() async throws {
        let transport = SignOutSyncTransport()
        transport.holdNextPull = true
        let applier = EmptyRemoteChangeApplier()
        let coordinator = OfflineSyncCoordinator(store: BatchOutboxStore(mutations: []), transport: transport, remoteApplier: applier)
        let task = Task { try await coordinator.synchronize(scopeID: UUID()) }
        while transport.resumePull == nil { await Task.yield() }
        task.cancel()
        transport.resumePull?.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(applier.appliedPages == 0)
    }

    @Test("Final sign-out sync joins a pending push and flushes the latest local edits")
    @MainActor
    func finalSyncWaitsAndFlushes() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = SignOutSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        await sync.activate(userID: "host", seedData: false)
        let workspace = PlanningWorkspace.newWorkspace(title: "Before", startsAt: .now, eventLocation: nil, imageData: nil)
        library.add(workspace)
        try persistence.flushForAccountTransition(library)
        transport.holdNextPush = true
        let background = Task { await sync.synchronize() }
        while transport.resumePush == nil { await Task.yield() }
        workspace.title = "Latest edit before sign out"
        let finalSync = Task { try await sync.prepareForSignOut(keepingPendingChanges: false) }
        await Task.yield()
        #expect(persistence.activeUserID == "host")
        transport.resumePush?.resume()
        transport.resumePush = nil
        await background.value
        try await finalSync.value
        #expect(persistence.activeUserID == nil)
        #expect(library.workspaces.isEmpty)
        persistence.activate(userID: "host", in: library)
        #expect(try persistence.pendingScopeIDs().isEmpty)
        #expect(transport.payloads.contains { String(data: $0, encoding: .utf8)?.contains("Latest edit before sign out") == true })
    }

    @Test("Offline sign-out keeps pending changes isolated until the same account returns")
    @MainActor
    func failedFinalSyncPreservesOutbox() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = SignOutSyncTransport()
        let sync = WorkspaceCloudSyncController(persistence: persistence, library: library,
            baseURL: URL(string: "https://example.invalid")!, transport: transport, usesRemoteAccountState: true)
        await sync.activate(userID: "host", seedData: false)
        library.add(PlanningWorkspace.newWorkspace(title: "Offline event", startsAt: .now, eventLocation: nil, imageData: nil))
        transport.failPush = true
        await #expect(throws: URLError.self) {
            try await sync.prepareForSignOut(keepingPendingChanges: false)
        }
        #expect(persistence.activeUserID == "host")
        #expect(try !persistence.pendingScopeIDs().isEmpty)
        try await sync.prepareForSignOut(keepingPendingChanges: true)
        persistence.activate(userID: "guest", in: library)
        #expect(library.workspaces.isEmpty)
        #expect(try persistence.pendingScopeIDs().isEmpty)
        persistence.activate(userID: "host", in: library)
        #expect(library.workspaces.first?.title == "Offline event")
        #expect(try !persistence.pendingScopeIDs().isEmpty)
    }

    @Test("Returning to an account preserves its matching cover cache during bootstrap")
    @MainActor
    func bootstrapPreservesAccountArtwork() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "host")
        let bytes = Data([1, 2, 3])
        let workspace = PlanningWorkspace.newWorkspace(title: "Host event", startsAt: .now, eventLocation: nil, imageData: bytes)
        workspace.mainEventMediaAssetID = UUID()
        func snapshot(_ workspace: PlanningWorkspace) throws -> RemoteWorkspaceSnapshot {
            RemoteWorkspaceSnapshot(scopeID: workspace.mainEventID,
                payload: try JSONEncoder().encode(WorkspaceArchiveV1(workspace: workspace)), serverVersion: 1, updatedAt: .now)
        }
        try persistence.applyBootstrap([snapshot(workspace)], to: library)
        workspace.mainEventImageData = nil
        persistence.activate(userID: "guest", in: library)
        try persistence.applyBootstrap([snapshot(workspace)], to: library)
        #expect(library.workspaces.first?.mainEventImageData == nil)
        persistence.activate(userID: "host", in: library)
        try persistence.applyBootstrap([snapshot(workspace)], to: library)
        #expect(library.workspaces.first?.mainEventImageData == bytes)
        workspace.mainEventMediaAssetID = UUID()
        try persistence.applyBootstrap([snapshot(workspace)], to: library)
        #expect(library.workspaces.first?.mainEventImageData == nil)
        workspace.mainEventMediaAssetID = nil
        try persistence.applyBootstrap([snapshot(workspace)], to: library)
        #expect(library.workspaces.first?.mainEventImageData == nil)
    }

    @Test("Media upload completion keeps its queued workspace and child event after a context switch")
    @MainActor
    func mediaUploadContextSwitch() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let first = PlanningWorkspace.newWorkspace(title: "First workspace", startsAt: .now, eventLocation: nil, imageData: Data([0xFF, 0xD8, 0xFF, 0x01]))
        let second = PlanningWorkspace.newWorkspace(title: "Second workspace", startsAt: .now, eventLocation: nil, imageData: Data([0xFF, 0xD8, 0xFF, 0x02]))
        let child = TimelineItem(title: "First workspace child", category: .other, scheduledAt: .now, location: "", participantIDs: [], parentEventID: first.mainEventID, imageData: Data([0xFF, 0xD8, 0xFF, 0x03]))
        first.timeline.append(child)
        library.add(first)
        library.add(second)
        try persistence.prepareMediaTransfers(from: library)
        defer {
            for transfer in (try? persistence.pendingMediaTransfers()) ?? [] {
                try? persistence.completeMediaTransfer(transfer.id)
            }
        }
        let transfers = try persistence.pendingMediaTransfers(scopeID: first.mainEventID)
        let mainTransfer = try #require(transfers.first { $0.entityID == first.mainEventID })
        let childTransfer = try #require(transfers.first { $0.entityID == child.id })
        #expect(childTransfer.scopeID == first.mainEventID)
        #expect(childTransfer.scopeID != child.id)
        library.open(second)
        let coordinator = WorkspaceMediaSyncCoordinator(persistence: persistence, library: library, transport: R2MediaTransport(baseURL: URL(string: "https://example.invalid")!))
        let mainAssetID = UUID()
        let childAssetID = UUID()
        #expect(try coordinator.completeUploadedMedia(mainAssetID, for: mainTransfer))
        #expect(try coordinator.completeUploadedMedia(childAssetID, for: childTransfer))
        #expect(first.mainEventMediaAssetID == mainAssetID)
        #expect(first.timeline.first { $0.id == child.id }?.mediaAssetID == childAssetID)
        #expect(second.mainEventMediaAssetID == nil)
        #expect(library.selectedWorkspaceID == second.mainEventID)
        #expect(try persistence.pendingMediaTransfers(scopeID: first.mainEventID).isEmpty)
        #expect(try persistence.pendingMediaTransfers(scopeID: second.mainEventID).count == 1)
    }

    @Test("Bootstrap carries the account onboarding state")
    func bootstrapAccountStateDecoding() throws {
        let response = try JSONDecoder().decode(
            SyncBootstrapResponse.self,
            from: Data(
                #"{"account":{"hasCompletedOnboarding":true},"snapshots":[]}"#.utf8
            )
        )

        #expect(response.account?.hasCompletedOnboarding == true)
        #expect(response.snapshots.isEmpty)
    }

    @Test("Bootstrap remains compatible while older servers roll forward")
    func legacyBootstrapDecoding() throws {
        let response = try JSONDecoder().decode(
            SyncBootstrapResponse.self,
            from: Data(#"{"snapshots":[]}"#.utf8)
        )

        #expect(response.account == nil)
        #expect(response.snapshots.isEmpty)
    }

    @Test("Retry delay grows exponentially and respects its cap")
    func retryBackoff() {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let policy = SyncRetryPolicy(initialDelay: 5, maximumDelay: 20)

        #expect(policy.nextAttemptDate(after: 1, from: origin) == origin.addingTimeInterval(5))
        #expect(policy.nextAttemptDate(after: 2, from: origin) == origin.addingTimeInterval(10))
        #expect(policy.nextAttemptDate(after: 3, from: origin) == origin.addingTimeInterval(20))
        #expect(policy.nextAttemptDate(after: 8, from: origin) == origin.addingTimeInterval(20))
    }

    @Test("Encoded drafts preserve the stable mutation identity")
    func mutationDraftEncoding() throws {
        struct Payload: Codable, Sendable {
            let title: String
        }

        let mutationID = UUID()
        let workspaceID = UUID()
        let ideaID = UUID()
        let draft = try SyncMutationDraft(
            id: mutationID,
            scopeID: workspaceID,
            entityType: .idea,
            entityID: ideaID,
            operation: .update,
            payload: Payload(title: "Garden ceremony"),
            baseVersion: 4
        )
        let decoded = try JSONDecoder().decode(Payload.self, from: draft.payload)

        #expect(draft.id == mutationID)
        #expect(draft.scopeID == workspaceID)
        #expect(draft.entityID == ideaID)
        #expect(draft.baseVersion == 4)
        #expect(decoded.title == "Garden ceremony")

        let pending = PendingMutation(
            id: draft.id,
            scopeID: draft.scopeID,
            entityType: draft.entityType,
            entityID: draft.entityID,
            operation: draft.operation,
            payload: draft.payload,
            baseVersion: draft.baseVersion,
            createdAt: draft.createdAt
        )
        let envelope = PendingMutationSnapshot(pending)
        #expect(envelope.payloadSchemaVersion == 1)
    }

    @Test("A workspace and its outbox mutation persist in one local store")
    @MainActor
    func workspacePersistenceRoundTrip() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        persistence.startObserving(library)

        let workspace = PlanningWorkspace.newWorkspace(
            title: "Lake weekend",
            startsAt: Date(timeIntervalSinceReferenceDate: 900_000_000),
            eventLocation: EventLocation(
                address: "Lake Michigan",
                shortAddress: "Lake Michigan"
            ),
            imageData: Data([0x47, 0x41]),
            budgetCap: 8_500
        )
        library.add(workspace)
        persistence.flush(library)

        let restoredLibrary = persistence.restoreLibrary(seedData: false)
        let restored = try #require(restoredLibrary.workspaces.first)
        #expect(restored.mainEventID == workspace.mainEventID)
        #expect(restored.title == "Lake weekend")
        #expect(restored.workspaceBudgetCap == 8_500)
        #expect(restored.mainEventImageData == Data([0x47, 0x41]))

        let context = ModelContext(persistence.container)
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let mutation = try #require(mutations.first { $0.entityType == .workspace })
        let participantMutation = try #require(
            mutations.first { $0.entityType == .participant }
        )
        let participationMutation = try #require(
            mutations.first { $0.entityType == .eventParticipation }
        )
        #expect(mutations.count == 3)
        #expect(mutation.scopeID == workspace.mainEventID)
        #expect(mutation.entityType == .workspace)
        #expect(mutation.operation == .create)
        #expect(participantMutation.operation == .create)
        #expect(participationMutation.operation == .create)

        let remoteArchive = try JSONDecoder().decode(
            WorkspaceArchiveV1.self,
            from: mutation.payload
        )
        #expect(remoteArchive.mainEventImageData == nil)
        let payloadObject = try #require(
            JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any]
        )
        #expect(payloadObject["mainEventStartsAt"] != nil)
        #expect(payloadObject["weddingDate"] == nil)

        try persistence.prepareMediaTransfers(from: library)
        let mediaTransfer = try #require(persistence.pendingMediaTransfers().first)
        #expect(mediaTransfer.scopeID == workspace.mainEventID)
        #expect(mediaTransfer.entityID == workspace.mainEventID)
        #expect(mediaTransfer.contentType == "image/jpeg")
        try persistence.completeMediaTransfer(mediaTransfer.id)
    }

    @Test("Repeated workspace edits coalesce into the pending create")
    @MainActor
    func workspaceMutationCoalescing() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Dinner",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )

        library.add(workspace)
        persistence.flush(library)
        workspace.title = "Dinner downtown"
        persistence.flush(library)

        let context = ModelContext(persistence.container)
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let mutation = try #require(mutations.first { $0.entityType == .workspace })
        let archive = try JSONDecoder().decode(WorkspaceArchiveV1.self, from: mutation.payload)

        #expect(mutations.count == 3)
        #expect(mutation.operation == .create)
        #expect(archive.title == "Dinner downtown")
    }

    @Test("Idea edits enqueue an independently synchronized record")
    @MainActor
    func ideaMutationUsesEntityBoundary() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Collaborative dinner",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        library.add(workspace)
        persistence.flush(library)

        let context = ModelContext(persistence.container)
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
            context.delete(mutation)
        }
        try context.save()

        let idea = PlanningIdea(
            title: "Garden menu",
            note: "Seasonal dishes",
            category: .food,
            submittedBy: "You"
        )
        workspace.addIdea(idea)
        persistence.flush(library)

        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        let ideaMutation = try #require(
            mutations.first { $0.entityType == .idea && $0.entityID == idea.id }
        )
        #expect(mutations.contains { $0.entityType == .workspace })
        #expect(ideaMutation.operation == .create)
        #expect(
            try JSONDecoder().decode(PlanningIdea.self, from: ideaMutation.payload).title
                == "Garden menu"
        )
    }

    @Test("Switching accounts never exposes another account's local workspaces")
    @MainActor
    func workspacePersistenceIsAccountScoped() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "user-a")
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Private to A",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )

        library.add(workspace)
        persistence.flush(library)
        persistence.activate(userID: "user-b", in: library)
        #expect(library.workspaces.isEmpty)

        persistence.activate(userID: "user-a", in: library)
        #expect(library.workspaces.map(\.mainEventID) == [workspace.mainEventID])

        let context = ModelContext(persistence.container)
        let record = try #require(
            context.fetch(FetchDescriptor<WorkspaceRecord>()).first
        )
        let mutation = try #require(
            context.fetch(FetchDescriptor<PendingMutation>())
                .first { $0.entityType == .workspace }
        )
        #expect(record.ownerUserID == "user-a")
        #expect(mutation.ownerUserID == "user-a")
    }

    @Test("Server bootstrap restores an account workspace and its version")
    @MainActor
    func remoteBootstrapRestoresWorkspace() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "server-user")
        let workspace = PlanningWorkspace.newWorkspace(
            title: "From PostgreSQL",
            startsAt: Date(timeIntervalSinceReferenceDate: 920_000_000),
            eventLocation: nil,
            imageData: nil
        )
        let payload = try JSONEncoder().encode(WorkspaceArchiveV1(workspace: workspace))

        try persistence.applyBootstrap(
            [
                RemoteWorkspaceSnapshot(
                    scopeID: workspace.mainEventID,
                    payload: payload,
                    serverVersion: 7,
                    updatedAt: .now
                )
            ],
            to: library
        )

        #expect(library.workspaces.map(\.title) == ["From PostgreSQL"])
        let context = ModelContext(persistence.container)
        let record = try #require(
            context.fetch(FetchDescriptor<WorkspaceRecord>()).first
        )
        #expect(record.ownerUserID == "server-user")
        #expect(record.serverVersion == 7)
    }

    @Test("A shared workspace can be cached independently for two accounts")
    @MainActor
    func sharedWorkspaceCacheIsAccountScoped() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "user-a")
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Shared wedding",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        let payload = try JSONEncoder().encode(WorkspaceArchiveV1(workspace: workspace))
        let snapshot = RemoteWorkspaceSnapshot(
            scopeID: workspace.mainEventID,
            payload: payload,
            serverVersion: 1,
            updatedAt: .now
        )

        try persistence.applyBootstrap([snapshot], to: library)
        persistence.activate(userID: "user-b", in: library)
        try persistence.applyBootstrap([snapshot], to: library)

        let records = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.id == workspace.mainEventID }
        #expect(records.count == 2)
        #expect(Set(records.compactMap(\.ownerUserID)) == ["user-a", "user-b"])
    }

    @Test("Outbox leasing only claims the active account's mutations")
    @MainActor
    func outboxLeasingIsAccountScoped() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let context = ModelContext(persistence.container)
        let scopeID = UUID()
        let userAMutation = PendingMutation(
            scopeID: scopeID,
            entityType: .workspace,
            entityID: scopeID,
            operation: .update,
            payload: Data("a".utf8),
            ownerUserID: "user-a"
        )
        let userBMutation = PendingMutation(
            scopeID: scopeID,
            entityType: .workspace,
            entityID: scopeID,
            operation: .update,
            payload: Data("b".utf8),
            ownerUserID: "user-b"
        )
        context.insert(userAMutation)
        context.insert(userBMutation)
        try context.save()

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        let claimed = try await store.claimReadyMutations(
            scopeID: scopeID,
            ownerUserID: "user-b",
            limit: 50,
            at: .now,
            leaseDuration: 60
        )

        #expect(claimed.map(\.id) == [userBMutation.id])
    }

    @Test("A sync run drains every ready outbox batch before pulling")
    @MainActor
    func synchronizationDrainsAllBatches() async throws {
        let scopeID = UUID()
        let mutations = (0..<55).map { index in
            PendingMutationSnapshot(
                PendingMutation(
                    scopeID: scopeID,
                    entityType: .idea,
                    entityID: UUID(),
                    operation: .update,
                    payload: Data("{\"index\":\(index)}".utf8),
                    createdAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                    ownerUserID: "sync-user"
                )
            )
        }
        let store = BatchOutboxStore(mutations: mutations)
        let transport = RecordingSyncTransport()
        let applier = EmptyRemoteChangeApplier()
        let coordinator = OfflineSyncCoordinator(
            store: store,
            transport: transport,
            remoteApplier: applier,
            batchSize: 50,
            ownerUserID: "sync-user"
        )

        let summary = try await coordinator.synchronize(scopeID: scopeID)
        let batchSizes = transport.batchSizes()
        let remainingCount = store.remainingCount()

        #expect(summary.pushed == 55)
        #expect(summary.acknowledged == 55)
        #expect(batchSizes == [50, 5])
        #expect(remainingCount == 0)
    }

    @Test("A rejected mutation keeps its safe failure code for the account UI")
    @MainActor
    func rejectedMutationReportsAttentionCode() async throws {
        let scopeID = UUID()
        let mutation = PendingMutationSnapshot(
            PendingMutation(
                scopeID: scopeID,
                entityType: .idea,
                entityID: UUID(),
                operation: .update,
                payload: Data("{}".utf8),
                ownerUserID: "sync-user"
            )
        )
        let store = AttentionOutboxStore(mutation: mutation)
        let transport = RejectedSyncTransport(mutationID: mutation.id)
        let coordinator = OfflineSyncCoordinator(
            store: store,
            transport: transport,
            remoteApplier: EmptyRemoteChangeApplier(),
            ownerUserID: "sync-user"
        )

        let summary = try await coordinator.synchronize(scopeID: scopeID)

        #expect(summary.requiresAttention == 1)
        #expect(summary.attentionFailureCode == "SCOPE_WRITE_FORBIDDEN")
        #expect(store.attentionCode == "SCOPE_WRITE_FORBIDDEN")
    }

    @Test("A capability upgrade response retries without dropping the durable outbox entry")
    @MainActor
    func upgradeRequiredRetainsOutbox() async throws {
        let scopeID = UUID()
        let mutation = PendingMutationSnapshot(PendingMutation(
            scopeID: scopeID, entityType: .workspace, entityID: scopeID,
            operation: .update, payload: Data("{}".utf8), ownerUserID: "sync-user"
        ))
        let store = BatchOutboxStore(mutations: [mutation])
        let coordinator = OfflineSyncCoordinator(
            store: store,
            transport: UpgradeRequiredSyncTransport(),
            remoteApplier: EmptyRemoteChangeApplier(),
            ownerUserID: "sync-user"
        )

        await #expect(throws: CloudSyncFailure.self) {
            try await coordinator.synchronize(scopeID: scopeID)
        }
        #expect(store.remainingCount() == 1)
    }

    @Test("A scoped read-only rejection refreshes authority while retaining attention")
    @MainActor
    func scopedReadOnlyPullsWithoutDiscardingDraft() async throws {
        let scopeID = UUID()
        let mutation = PendingMutationSnapshot(PendingMutation(
            scopeID: scopeID, entityType: .idea, entityID: UUID(),
            operation: .update, payload: Data("{}".utf8), ownerUserID: "sync-user"
        ))
        let store = AttentionOutboxStore(mutation: mutation)
        let transport = ScopedAccessFailureTransport(mutationID: mutation.id, failureCode: "SCOPE_READ_ONLY")
        let applier = RevocationTrackingApplier()
        let coordinator = OfflineSyncCoordinator(
            store: store, transport: transport, remoteApplier: applier, ownerUserID: "sync-user"
        )

        let summary = try await coordinator.synchronize(scopeID: scopeID)

        #expect(summary.attentionFailureCode == "SCOPE_READ_ONLY")
        #expect(store.attentionCode == "SCOPE_READ_ONLY")
        #expect(transport.pullCount == 1)
        #expect(applier.appliedPages == 1)
        #expect(applier.clearCount == 0)
    }

    @Test("A generic pull 403 never clears a cached scope")
    @MainActor
    func genericForbiddenPullPreservesScope() async throws {
        let transport = ScopedAccessFailureTransport(pullFailure: .forbidden("EVENT_PERMISSION_REQUIRED"))
        let applier = RevocationTrackingApplier()
        let coordinator = OfflineSyncCoordinator(
            store: BatchOutboxStore(mutations: []), transport: transport,
            remoteApplier: applier, ownerUserID: "sync-user"
        )

        await #expect(throws: CloudSyncFailure.self) {
            try await coordinator.synchronize(scopeID: UUID())
        }
        #expect(applier.clearCount == 0)
        #expect(applier.appliedPages == 0)
    }

    @Test("A legacy mismatched workspace outbox batch is regenerated with fresh IDs")
    @MainActor
    func repairsWorkspaceScopeMismatchBeforeSync() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "sync-user")
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Repair me",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        library.add(workspace)
        persistence.flush(library)

        let context = ModelContext(persistence.container)
        let corruptScopeID = UUID()
        let originalIDs = try context.fetch(FetchDescriptor<PendingMutation>()).map(\.id)
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
            mutation.scopeID = corruptScopeID
        }
        try context.save()

        #expect(try persistence.repairWorkspaceScopeMismatches(from: library) == 1)

        let repaired = try context.fetch(FetchDescriptor<PendingMutation>())
        let workspaceMutation = try #require(
            repaired.first { $0.entityType == .workspace }
        )
        let payload = try JSONDecoder().decode(
            WorkspaceArchiveV1.self,
            from: workspaceMutation.payload
        )

        #expect(repaired.allSatisfy { $0.scopeID == workspace.mainEventID })
        #expect(workspaceMutation.entityID == workspace.mainEventID)
        #expect(payload.mainEventID == workspace.mainEventID)
        #expect(Set(repaired.map(\.id)).isDisjoint(with: Set(originalIDs)))
    }

    @Test("A rejected workspace bootstrap batch self-heals into a sendable dependency order")
    @MainActor
    func rejectedWorkspaceBootstrapBatchSelfHeals() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "sync-user")
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Repair and send",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        workspace.addIdea(
            PlanningIdea(
                title: "Garden menu",
                note: "Seasonal dishes",
                category: .food,
                submittedBy: "You"
            )
        )
        library.add(workspace)
        persistence.flush(library)

        let context = ModelContext(persistence.container)
        let originalIDs = try context.fetch(FetchDescriptor<PendingMutation>()).map(\.id)
        let workspaceMutation = try #require(
            context.fetch(FetchDescriptor<PendingMutation>())
                .first { $0.entityType == .workspace }
        )
        // This mirrors the server-side validation failure: the workspace
        // payload names the real scope, but the mutation entity does not.
        workspaceMutation.entityID = UUID()
        workspaceMutation.state = .requiresAttention
        workspaceMutation.lastFailureCode = "WORKSPACE_SCOPE_MISMATCH"
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.id != workspaceMutation.id {
            mutation.state = .requiresAttention
            mutation.lastFailureCode = "SYNC_SCOPE_NOT_FOUND"
        }
        try context.save()

        #expect(try persistence.repairWorkspaceScopeMismatches(from: library) == 1)

        let repaired = try context.fetch(FetchDescriptor<PendingMutation>())
        #expect(repaired.allSatisfy { $0.state == .pending })
        #expect(Set(repaired.map(\.id)).isDisjoint(with: Set(originalIDs)))

        let store = SwiftDataSyncStore(modelContainer: persistence.container)
        let claimed = try await store.claimReadyMutations(
            scopeID: workspace.mainEventID,
            ownerUserID: "sync-user",
            limit: 50,
            at: .now,
            leaseDuration: 60
        )
        #expect(claimed.first?.entityType == .workspace)
        #expect(Array(claimed.map(\.entityType).prefix(2)) == [.workspace, .participant])
        #expect(claimed.allSatisfy {
            $0.scopeID == workspace.mainEventID &&
                ($0.entityType != .workspace || $0.entityID == workspace.mainEventID)
        })
    }

    @Test("A missing server scope is re-created from local child mutations")
    @MainActor
    func missingServerScopeSelfHeals() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "sync-user")
        persistence.startObserving(library)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Recreate scope",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil
        )
        library.add(workspace)
        persistence.flush(library)

        let context = ModelContext(persistence.container)
        // Simulate a scope that was acknowledged once, then erased by a
        // server reset: only its later child writes remain to be retried.
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
            if mutation.entityType == .workspace {
                context.delete(mutation)
            } else {
                mutation.state = .requiresAttention
                mutation.lastFailureCode = "SYNC_SCOPE_NOT_FOUND"
            }
        }
        try context.save()

        #expect(try persistence.repairWorkspaceScopeMismatches(from: library) == 1)

        let rebuilt = try context.fetch(FetchDescriptor<PendingMutation>())
        let workspaceMutation = try #require(
            rebuilt.first { $0.entityType == .workspace }
        )
        #expect(workspaceMutation.operation == .create)
        #expect(workspaceMutation.scopeID == workspace.mainEventID)
        #expect(workspaceMutation.entityID == workspace.mainEventID)
        #expect(rebuilt.allSatisfy { $0.state == .pending })
    }

    @Test("Account deletion purges workspaces and offline sync state")
    @MainActor
    func accountDeletionPurgesLocalData() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        persistence.startObserving(library)
        library.add(
            PlanningWorkspace.newWorkspace(
                title: "Delete me",
                startsAt: .now,
                eventLocation: nil,
                imageData: nil
            )
        )
        persistence.flush(library)

        try persistence.purgeAllLocalData(from: library)

        let context = ModelContext(persistence.container)
        #expect(library.workspaces.isEmpty)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SyncCheckpoint>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AppliedSyncEnvelope>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMediaTransfer>()).isEmpty)
    }

    @Test("A workspace survives closing and reopening the on-disk store")
    @MainActor
    func workspaceSurvivesStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GatheroryPersistence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // SwiftData may retain SQLite file descriptors past the lexical scope.
        // The simulator clears its temporary container; deleting the directory
        // here can unlink an active WAL and produce a false integrity warning.
        let storeURL = directory.appending(path: "Gatherory.store")
        let workspaceID: UUID

        do {
            let persistence = try WorkspacePersistenceController(storeURL: storeURL)
            let library = persistence.restoreLibrary(seedData: false)
            let workspace = PlanningWorkspace.newWorkspace(
                title: "Persisted wedding",
                startsAt: Date(timeIntervalSinceReferenceDate: 910_000_000),
                eventLocation: EventLocation(
                    address: "100 Woodward Avenue, Detroit, MI",
                    shortAddress: "Detroit, MI",
                    placeName: "Gatherory Hall"
                ),
                imageData: Data([0x01, 0x02, 0x03]),
                budgetCap: 25_000
            )
            workspaceID = workspace.mainEventID
            library.add(workspace)
            persistence.flush(library)
            #expect(persistence.lastError == nil)
        }

        do {
            let reopenedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
            let restoredLibrary = reopenedPersistence.restoreLibrary(seedData: false)
            let restored = try #require(restoredLibrary.workspaces.first)

            #expect(reopenedPersistence.lastError == nil)
            #expect(restored.mainEventID == workspaceID)
            #expect(restored.title == "Persisted wedding")
            #expect(restored.mainEventLocation?.placeName == "Gatherory Hall")
            #expect(restored.workspaceBudgetCap == 25_000)
            #expect(restored.mainEventImageData == Data([0x01, 0x02, 0x03]))

            let context = ModelContext(reopenedPersistence.container)
            let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            #expect(mutations.count == 3)
            #expect(mutations.allSatisfy { $0.scopeID == workspaceID })
        }
    }

    @Test("A deleted workspace stays deleted and leaves a durable tombstone")
    @MainActor
    func workspaceDeletionPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GatheroryDeletion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // Leave this in the simulator's temporary container for the OS to
        // reclaim after the test process releases SwiftData's SQLite handles.
        let storeURL = directory.appending(path: "Gatherory.store")
        let workspaceID: UUID

        do {
            let persistence = try WorkspacePersistenceController(storeURL: storeURL)
            let library = persistence.restoreLibrary(seedData: false)
            let workspace = PlanningWorkspace.newWorkspace(
                title: "Temporary event",
                startsAt: .now,
                eventLocation: nil,
                imageData: nil
            )
            workspaceID = workspace.mainEventID
            library.add(workspace)
            persistence.flush(library)

            // Simulate acknowledgement of the create before the later deletion.
            let context = ModelContext(persistence.container)
            for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
                context.delete(mutation)
            }
            try context.save()

            library.remove(workspace)
            persistence.flush(library)
        }

        do {
            let reopenedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
            let restoredLibrary = reopenedPersistence.restoreLibrary(seedData: false)
            #expect(restoredLibrary.workspaces.isEmpty)

            let context = ModelContext(reopenedPersistence.container)
            let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            let tombstone = try #require(mutations.first)

            #expect(records.isEmpty)
            #expect(mutations.count == 1)
            #expect(tombstone.scopeID == workspaceID)
            #expect(tombstone.operation == .delete)
            #expect(tombstone.payload.isEmpty)
        }
    }
}

@MainActor
private final class BatchOutboxStore: SyncOutboxStore {
    private var mutations: [PendingMutationSnapshot]

    init(mutations: [PendingMutationSnapshot]) {
        self.mutations = mutations
    }

    func claimReadyMutations(
        scopeID: UUID,
        ownerUserID: String?,
        limit: Int,
        at date: Date,
        leaseDuration: TimeInterval
    ) -> [PendingMutationSnapshot] {
        Array(mutations.filter { $0.scopeID == scopeID }.prefix(limit))
    }

    func acknowledge(_ results: [SyncPushResult]) {
        let acknowledged = Set(results.map(\.mutationID))
        mutations.removeAll { acknowledged.contains($0.id) }
    }

    func retry(
        _ mutationIDs: Set<UUID>,
        failureCode: String,
        at date: Date,
        policy: SyncRetryPolicy
    ) {}

    func requireAttention(_ mutationIDs: Set<UUID>, failureCode: String) {}

    func remainingCount() -> Int {
        mutations.count
    }
}

@MainActor
private struct UpgradeRequiredSyncTransport: SyncTransport {
    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        throw CloudSyncFailure.clientUpgradeRequired(SyncClientCapabilities.upgradeRequiredCode)
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        .init(changes: [], nextCursor: cursor, hasMore: false)
    }
}

@MainActor
private final class RecordingSyncTransport: SyncTransport {
    private var pushedBatches: [[UUID]] = []

    func push(_ mutations: [PendingMutationSnapshot]) -> SyncPushResponse {
        pushedBatches.append(mutations.map(\.id))
        return SyncPushResponse(
            results: mutations.map {
                SyncPushResult(
                    mutationID: $0.id,
                    disposition: .applied,
                    serverVersion: 1,
                    failureCode: nil
                )
            }
        )
    }

    func pull(scopeID: UUID, after cursor: String?) -> SyncPullPage {
        SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
    }

    func batchSizes() -> [Int] {
        pushedBatches.map(\.count)
    }
}

@MainActor
private final class AttentionOutboxStore: SyncOutboxStore {
    private var mutation: PendingMutationSnapshot?
    private(set) var attentionCode: String?

    init(mutation: PendingMutationSnapshot) {
        self.mutation = mutation
    }

    func claimReadyMutations(
        scopeID: UUID,
        ownerUserID: String?,
        limit: Int,
        at date: Date,
        leaseDuration: TimeInterval
    ) -> [PendingMutationSnapshot] {
        guard let mutation, mutation.scopeID == scopeID else { return [] }
        self.mutation = nil
        return [mutation]
    }

    func acknowledge(_ results: [SyncPushResult]) {}

    func retry(
        _ mutationIDs: Set<UUID>,
        failureCode: String,
        at date: Date,
        policy: SyncRetryPolicy
    ) {}

    func requireAttention(_ mutationIDs: Set<UUID>, failureCode: String) {
        attentionCode = failureCode
    }
}

@MainActor
private final class RejectedSyncTransport: SyncTransport {
    private let mutationID: UUID

    init(mutationID: UUID) {
        self.mutationID = mutationID
    }

    func push(_ mutations: [PendingMutationSnapshot]) -> SyncPushResponse {
        SyncPushResponse(
            results: [
                SyncPushResult(
                    mutationID: mutationID,
                    disposition: .rejected,
                    serverVersion: nil,
                    failureCode: "SCOPE_WRITE_FORBIDDEN"
                )
            ]
        )
    }

    func pull(scopeID: UUID, after cursor: String?) -> SyncPullPage {
        SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
    }
}

@MainActor
private final class EmptyRemoteChangeApplier: RemoteChangeApplying {
    var appliedPages = 0
    func currentCursor(for scopeID: UUID) -> String? { nil }
    func apply(_ page: SyncPullPage, to scopeID: UUID) { appliedPages += 1 }
}

@MainActor
private final class ScopedAccessFailureTransport: SyncTransport {
    private let mutationID: UUID?
    private let failureCode: String?
    private let pullFailure: CloudSyncFailure?
    private(set) var pullCount = 0

    init(mutationID: UUID? = nil, failureCode: String? = nil, pullFailure: CloudSyncFailure? = nil) {
        self.mutationID = mutationID
        self.failureCode = failureCode
        self.pullFailure = pullFailure
    }

    func push(_ mutations: [PendingMutationSnapshot]) -> SyncPushResponse {
        SyncPushResponse(results: mutations.map {
            SyncPushResult(
                mutationID: $0.id, disposition: .rejected,
                serverVersion: nil, failureCode: failureCode
            )
        })
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        pullCount += 1
        if let pullFailure { throw pullFailure }
        return SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
    }
}

@MainActor
private final class RevocationTrackingApplier: RemoteChangeApplying {
    var appliedPages = 0
    private(set) var clearCount = 0

    func currentCursor(for scopeID: UUID) -> String? { nil }
    func apply(_ page: SyncPullPage, to scopeID: UUID) { appliedPages += 1 }
    func clearForbiddenScope(_ scopeID: UUID) -> Bool {
        clearCount += 1
        return false
    }
}

@MainActor
private final class SignOutSyncTransport: WorkspaceSnapshotTransport {
    var pullCount = 0
    var failPull = false
    var holdNextPull = false
    var resumePull: CheckedContinuation<Void, Never>?
    var holdNextPush = false
    var failPush = false
    var resumePush: CheckedContinuation<Void, Never>?
    var payloads: [Data] = []
    func bootstrap() -> SyncBootstrapResponse { .init(account: nil, snapshots: []) }
    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        if holdNextPush {
            holdNextPush = false
            await withCheckedContinuation { resumePush = $0 }
        }
        if failPush { throw URLError(.notConnectedToInternet) }
        payloads.append(contentsOf: mutations.map(\.payload))
        return .init(results: mutations.map { .init(mutationID: $0.id, disposition: .applied, serverVersion: 1, failureCode: nil) })
    }
    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        pullCount += 1
        if failPull { throw CloudSyncFailure.server("SYNC_SCOPE_NOT_FOUND") }
        if holdNextPull {
            holdNextPull = false
            await withCheckedContinuation { resumePull = $0 }
        }
        return .init(changes: [], nextCursor: cursor, hasMore: false)
    }
}
