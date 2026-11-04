import Foundation
import Testing
import SwiftData
@testable import Gatherory

private enum LiveSyncAcceptanceConfiguration {
    static let enabled = ProcessInfo.processInfo.environment["GATHERORY_LIVE_SYNC_ACCEPTANCE"] == "1"
    static let developmentOrigin = URL(string: "https://dev.gatherory.com")!
}

private struct PendingEntityKey: Hashable {
    let entityType: SyncEntityType
    let entityID: UUID
}

private func key(_ type: SyncEntityType, _ id: UUID) -> PendingEntityKey {
    PendingEntityKey(entityType: type, entityID: id)
}

/// Opt-in acceptance against the shared development API. This deliberately
/// uses two independent SwiftData stores and the production sync transport.
@MainActor
struct IdeaSchedulingLiveSyncTests {
    @Test(.enabled(if: LiveSyncAcceptanceConfiguration.enabled, "Set GATHERORY_LIVE_SYNC_ACCEPTANCE=1 and provide two dev bearer tokens."))
    func ideaVoteScheduleAndReconnectAcrossIndependentClients() async throws {
        let environment = ProcessInfo.processInfo.environment
        let hostToken = try #require(try token(for: "appreview@gatherory.test", environmentKey: "GATHERORY_LIVE_SYNC_HOST_TOKEN", environment: environment), "Missing host credential input.")
        let voterToken = try #require(try token(for: "coordinator@gatherory.test", environmentKey: "GATHERORY_LIVE_SYNC_VOTER_TOKEN", environment: environment), "Missing voter credential input.")
        try #require(!hostToken.isEmpty && !voterToken.isEmpty, "Both dev token inputs must be nonempty.")

        let hostAccount = try await account(for: hostToken)
        let voterAccount = try await account(for: voterToken)
        try #require(hostAccount.email.lowercased() == "appreview@gatherory.test", "Host token must belong to the seeded App Review fixture.")
        try #require(voterAccount.email.lowercased() == "coordinator@gatherory.test", "Voter token must belong to the seeded coordinator fixture.")
        try #require(hostAccount.id != voterAccount.id, "The two bearer tokens must resolve to different accounts.")

        let host = try LiveSyncClient(account: hostAccount, token: hostToken)
        let voter = try LiveSyncClient(account: voterAccount, token: voterToken)
        try await host.bootstrap()
        try await voter.bootstrap()

        let bootstrapRootID = try #require(sharedManagedRoot(host: host, voter: voter), "The seeded accounts need a shared root where App Review can manage and coordinator can contribute.")
        // Pull once after bootstrap so each account has the server's current
        // entity versions and cursor before any local acceptance mutation.
        try await host.synchronize(scopeID: bootstrapRootID)
        try await voter.synchronize(scopeID: bootstrapRootID)
        let sharedRootID = try #require(sharedManagedRoot(host: host, voter: voter), "The shared manager/contributor root must remain authorized after the initial pulls.")
        // An interrupted opt-in acceptance run can leave its fresh proposal on
        // dev. Recovery is explicit and validates ownership/title before using
        // the same bounded cleanup path; it never sweeps other test/user data.
        if let recoveryValue = environment["GATHERORY_LIVE_SYNC_RECOVERY_ID"] {
            let recoveryID = try #require(UUID(uuidString: recoveryValue))
            let recoveryWorkspace = try #require(host.workspace(scopeID: sharedRootID))
            if let recoveryIdea = recoveryWorkspace.ideas.first(where: { $0.id == recoveryID }) {
                try #require(recoveryIdea.title == "Live sync acceptance \(recoveryID.uuidString)")
                try #require(recoveryIdea.submittedByUserID == hostAccount.id)
                let recoveryEventID: UUID?
                if let value = environment["GATHERORY_LIVE_SYNC_RECOVERY_EVENT_ID"] {
                    let eventID = try #require(UUID(uuidString: value))
                    // This explicit ID comes from the failed run's receipt.
                    // Reject any surviving row that links it to different data.
                    let cached = try host.cachedArchive(scopeID: sharedRootID)
                    for event in recoveryWorkspace.timeline + (cached?.timeline ?? []) where event.id == eventID {
                        try #require(event.linkedIdeaID == recoveryID)
                    }
                    recoveryEventID = eventID
                } else {
                    recoveryEventID = nil
                }
                try await cleanup(ideaID: recoveryID, linkedEventID: recoveryEventID,
                                  host: host, voter: voter, scopeID: sharedRootID)
            }
            try #require(host.workspace(scopeID: sharedRootID)?.ideas.contains(where: { $0.id == recoveryID }) == false)
            try #require(voter.workspace(scopeID: sharedRootID)?.ideas.contains(where: { $0.id == recoveryID }) == false)
        }
        let ideaID = UUID()
        let proposedDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: .now)!
        let proposal = PlanningIdea(
            id: ideaID,
            eventID: sharedRootID,
            title: "Live sync acceptance \(ideaID.uuidString)",
            note: "Disposable acceptance record; removed by the test.",
            category: .event,
            submittedBy: hostAccount.displayName,
            submittedByUserID: hostAccount.id,
            configuration: .event(EventIdeaConfiguration(
                category: .other,
                purpose: .eventExperience,
                proposedDate: proposedDate,
                timeZoneIdentifier: "UTC",
                location: nil
            ))
        )

        var linkedEventID: UUID?
        do {
            // The test creates only fresh entity IDs. Existing idea/event fields
            // are never edited; the new records are deleted in cleanup below.
            let hostIdeaWorkspace = try #require(host.workspace(scopeID: sharedRootID))
            try host.assertPendingMutations(scopeID: sharedRootID, allowed: [])
            hostIdeaWorkspace.addIdea(proposal)
            try host.persistence.saveChanges(in: host.library)
            let ideaWriteKeys: Set<PendingEntityKey> = [
                key(.workspace, sharedRootID), key(.idea, ideaID)
            ]
            try host.assertPendingMutations(scopeID: sharedRootID, allowed: ideaWriteKeys)
            try await host.synchronize(scopeID: sharedRootID, allowed: ideaWriteKeys)

            try await voter.synchronize(scopeID: sharedRootID)
            let voterIdeaWorkspace = try #require(voter.workspace(scopeID: sharedRootID))
            let voterProposal = try #require(voterIdeaWorkspace.ideas.first { $0.id == ideaID }, "The newly created idea should arrive through a real server pull.")
            try #require(voterIdeaWorkspace.canRespond(to: voterProposal), "Coordinator must retain permission to respond to the new idea.")

            // Save while the second client is idle, then reconnect by running
            // its normal outbox/pull coordinator against the real endpoint.
            voterIdeaWorkspace.decide(.maybe, on: voterProposal)
            try voter.assertPendingMutations(scopeID: sharedRootID, allowed: [])
            try voter.persistence.saveChanges(in: voter.library)
            try #require(voterIdeaWorkspace.response(on: voterProposal) == .maybe, "The offline local response should be durable before sync.")
            let responseKey: Set<PendingEntityKey> = [key(.ideaResponse, IdeaResponse.identifier(ideaID: ideaID, userID: voterAccount.id))]
            try voter.assertPendingMutations(scopeID: sharedRootID, allowed: responseKey)
            try await voter.synchronize(scopeID: sharedRootID, allowed: responseKey)

            try await host.synchronize(scopeID: sharedRootID)
            let hostWorkspace = try #require(host.workspace(scopeID: sharedRootID))
            let hostProposal = try #require(hostWorkspace.ideas.first { $0.id == ideaID })
            let voterResponse = hostWorkspace.ideaResponses.first {
                $0.ideaID == ideaID && $0.userID == voterAccount.id
            }
            try #require(voterResponse?.choice == .maybe, "The host should pull the contributor's independently stored preference.")
            let request = try #require(hostWorkspace.makeScheduleRequest(for: hostProposal), "App Review host should be allowed to schedule this proposal.")
            let configuration = try #require(hostProposal.eventConfiguration)
            let previousParticipationIDs = Set(hostWorkspace.eventParticipations.map(\.id))
            linkedEventID = hostWorkspace.confirmScheduleEventIdea(request, configuration: configuration)
            try #require(linkedEventID != nil, "The schedule command should create exactly one linked Home event.")
            let scheduledEventID = try #require(linkedEventID)
            let scheduledEvent = try #require(hostWorkspace.timeline.first { $0.id == scheduledEventID })
            try host.assertPendingMutations(scopeID: sharedRootID, allowed: [])
            try host.persistence.saveChanges(in: host.library)
            // Saving normalizes the archive and materializes participation
            // rows for the newly scheduled event. Derive the allowlist from
            // those exact new rows, then verify they match the event's people.
            let newParticipations = hostWorkspace.eventParticipations.filter {
                $0.eventID == scheduledEventID && !previousParticipationIDs.contains($0.id)
            }
            try #require(
                Set(newParticipations.map(\.memberID)) == Set(scheduledEvent.participantIDs),
                "Scheduling should persist participation rows only for the linked event's participants."
            )
            let scheduleWriteKeys = Set(newParticipations.map { key(.eventParticipation, $0.id) }).union([
                key(.workspace, sharedRootID), key(.idea, ideaID), key(.event, scheduledEventID)
            ])
            try host.assertPendingMutations(scopeID: sharedRootID, allowed: scheduleWriteKeys)
            try await host.synchronize(scopeID: sharedRootID, allowed: scheduleWriteKeys)

            try await voter.synchronize(scopeID: sharedRootID)
            let voterWorkspace = try #require(voter.workspace(scopeID: sharedRootID))
            let remoteIdea = try #require(voterWorkspace.ideas.first { $0.id == ideaID }, "The scheduled idea should remain in the voter projection.")
            try #require(voterWorkspace.response(on: remoteIdea) == .maybe, "Scheduling must preserve the independent voter response.")
            try #require(remoteIdea.status == .chosen, "The voter should receive the scheduled idea state.")
            try #require(voterWorkspace.timeline.filter { $0.linkedIdeaID == ideaID }.count == 1, "The reconnect should deliver exactly one linked Home event.")
            try await voter.synchronize(scopeID: sharedRootID)
            try #require(voterWorkspace.timeline.filter { $0.linkedIdeaID == ideaID }.count == 1, "A repeated reconnect must not duplicate the scheduled event.")
        } catch {
            do {
                try await cleanup(ideaID: ideaID, linkedEventID: linkedEventID, host: host, voter: voter, scopeID: sharedRootID)
            } catch {
                Issue.record("Cleanup did not confirm deletion of temporary idea \(ideaID), linked event \(linkedEventID?.uuidString ?? "not-created"), in root \(sharedRootID).")
            }
            throw error
        }

        do {
            try await cleanup(ideaID: ideaID, linkedEventID: linkedEventID, host: host, voter: voter, scopeID: sharedRootID)
        } catch {
            Issue.record("Cleanup did not confirm deletion of temporary idea \(ideaID), linked event \(linkedEventID?.uuidString ?? "not-created"), in root \(sharedRootID).")
            throw error
        }
    }

    private func account(for token: String) async throws -> UserAccount {
        let store = AcceptanceTokenStore(token: token)
        let client = BetterAuthClient(
            baseURL: LiveSyncAcceptanceConfiguration.developmentOrigin,
            tokenStore: store,
            accountCache: AcceptanceAccountCache()
        )
        let account = try await client.restoreSession()
        return try #require(account, "The supplied dev bearer token must resolve to a valid session.")
    }

    /// A protected file avoids putting bearer tokens in runner arguments or
    /// environment diagnostics. CI may alternatively inject its own tokens.
    private func token(for email: String, environmentKey: String, environment: [String: String]) throws -> String? {
        if let value = environment[environmentKey] { return value }
        guard let path = environment["GATHERORY_LIVE_SYNC_CREDENTIAL_FILE"] else { return nil }
        struct Credential: Decodable { let token: String }
        return try JSONDecoder().decode([String: Credential].self, from: Data(contentsOf: URL(fileURLWithPath: path)))[email]?.token
    }

    private func sharedManagedRoot(host: LiveSyncClient, voter: LiveSyncClient) -> UUID? {
        let voterRoots = Set(voter.library.workspaces.map(\.mainEventID))
        return host.library.workspaces.first { workspace in
            guard voterRoots.contains(workspace.mainEventID), workspace.canManageInvitations(for: .main),
                  let voterWorkspace = voter.library.workspaces.first(where: { $0.mainEventID == workspace.mainEventID }),
                  let voterMember = voterWorkspace.currentViewerMember(for: .main) else { return false }
            return voterMember.invitationStatus == .active
                && voterMember.participantRole == .collaborator
                && voterMember.planningPermission == .contribute
        }?.mainEventID
    }

    private func cleanup(
        ideaID: UUID,
        linkedEventID: UUID?,
        host: LiveSyncClient,
        voter: LiveSyncClient,
        scopeID: UUID
    ) async throws {
        let initialHostWorkspace = try #require(host.workspace(scopeID: scopeID), "Host root must remain available through cleanup.")
        var knownEventIDs = Set(initialHostWorkspace.timeline.filter { $0.linkedIdeaID == ideaID }.map(\.id))
            .union(linkedEventID.map { [$0] } ?? [])
        // The persisted server projection can still contain tombstone source
        // rows that normalization has removed from the live model.
        let cachedArchive = try host.cachedArchive(scopeID: scopeID)
        knownEventIDs.formUnion(cachedArchive?.timeline.filter { $0.linkedIdeaID == ideaID }.map(\.id) ?? [])
        var knownParticipationIDs = Set(initialHostWorkspace.eventParticipations
            .filter { knownEventIDs.contains($0.eventID) }
            .map(\.id))
        knownParticipationIDs.formUnion((cachedArchive?.eventParticipations ?? [])
            .filter { knownEventIDs.contains($0.eventID) }.map(\.id))
        print("LIVE_ACCEPTANCE_CLEANUP linked_events=\(knownEventIDs) participation_ids=\(knownParticipationIDs)")
        let settleKeys: Set<PendingEntityKey> = Set([key(.workspace, scopeID), key(.idea, ideaID)])
            .union(knownEventIDs.map { key(.event, $0) })
            .union(knownParticipationIDs.map { key(.eventParticipation, $0) })
        try await host.synchronize(scopeID: scopeID, allowed: settleKeys)

        var currentHostWorkspace = try #require(host.workspace(scopeID: scopeID))
        knownEventIDs.formUnion(currentHostWorkspace.timeline.filter { $0.linkedIdeaID == ideaID }.map(\.id))
        knownParticipationIDs.formUnion(currentHostWorkspace.eventParticipations
            .filter { knownEventIDs.contains($0.eventID) }
            .map(\.id))
        if let committedIdea = currentHostWorkspace.ideas.first(where: { $0.id == ideaID }),
           committedIdea.status == .chosen {
            // Reopen only this test-created idea. Its ordinary lifecycle path
            // removes its linked Home event and scoped participation rows,
            // allowing the contributor to retract their response while open.
            currentHostWorkspace.updateIdea(committedIdea, status: .new)
            try host.assertPendingMutations(scopeID: scopeID, allowed: [])
            try host.persistence.saveChanges(in: host.library)
            let reopenKeys = Set(knownEventIDs.map { key(.event, $0) })
                .union(knownParticipationIDs.map { key(.eventParticipation, $0) })
                .union([key(.workspace, scopeID), key(.idea, ideaID)])
            try host.assertPendingMutations(scopeID: scopeID, allowed: reopenKeys)
            try await host.synchronize(scopeID: scopeID, allowed: reopenKeys)
        }

        let responseID = IdeaResponse.identifier(ideaID: ideaID, userID: voter.account.id)
        let responseKey: Set<PendingEntityKey> = [key(.ideaResponse, responseID)]
        try await voter.synchronize(scopeID: scopeID)
        let voterWorkspace = try #require(voter.workspace(scopeID: scopeID), "Voter root must remain available through cleanup.")
        let hasLiveResponse = voterWorkspace.ideaResponses.contains {
            $0.ideaID == ideaID && $0.userID == voter.account.id && $0.choice != nil
        }
        let voterIdeaIsOpen = voterWorkspace.ideas.first { $0.id == ideaID }
            .map { [.new, .maybe, .shortlisted].contains($0.status) } ?? false
        if hasLiveResponse && voterIdeaIsOpen {
            try voter.enqueueResponseRetraction(ideaID: ideaID, scopeID: scopeID)
            try await voter.synchronize(scopeID: scopeID, allowed: responseKey)
        }

        // Pull the contributor-owned nil-choice update before removing the
        // temporary idea from the host's compatibility archive.
        try await host.synchronize(scopeID: scopeID)
        currentHostWorkspace = try #require(host.workspace(scopeID: scopeID))
        knownEventIDs.formUnion(currentHostWorkspace.timeline.filter { $0.linkedIdeaID == ideaID }.map(\.id))
        knownParticipationIDs.formUnion(currentHostWorkspace.eventParticipations
            .filter { knownEventIDs.contains($0.eventID) }
            .map(\.id))
        let archive = WorkspaceArchiveV1(workspace: currentHostWorkspace)
        var cleanedArchive = archive
        cleanedArchive.ideas.removeAll { $0.id == ideaID }
        cleanedArchive.timeline.removeAll { knownEventIDs.contains($0.id) }
        knownParticipationIDs.formUnion((cleanedArchive.eventParticipations ?? [])
            .filter { knownEventIDs.contains($0.eventID) }
            .map(\.id))
        cleanedArchive.eventParticipations?.removeAll {
            knownEventIDs.contains($0.eventID) || knownParticipationIDs.contains($0.id)
        }
        try host.assertPendingMutations(scopeID: scopeID, allowed: [])
        host.library.upsert(cleanedArchive.makeWorkspace())
        try host.persistence.saveChanges(in: host.library)

        let cleanupMutationKeys = Set(knownEventIDs.map { key(.event, $0) })
            .union(knownParticipationIDs.map { key(.eventParticipation, $0) })
            .union([key(.workspace, scopeID), key(.idea, ideaID)])
        try host.assertPendingMutations(scopeID: scopeID, allowed: cleanupMutationKeys)
        try await host.synchronize(scopeID: scopeID, allowed: cleanupMutationKeys)

        try await voter.synchronize(scopeID: scopeID)
        let remaining = try #require(voter.workspace(scopeID: scopeID), "Voter root must remain available for cleanup verification.")
        try #require(!remaining.ideas.contains { $0.id == ideaID }, "The server-confirmed cleanup pull should remove the temporary idea.")
        try #require(!remaining.timeline.contains { $0.linkedIdeaID == ideaID }, "The server-confirmed cleanup pull should remove the temporary linked event.")
        try #require(!remaining.eventParticipations.contains {
            knownEventIDs.contains($0.eventID) || knownParticipationIDs.contains($0.id)
        }, "The server-confirmed cleanup pull should remove the temporary event's participation rows.")
        try #require(!remaining.ideaResponses.contains { $0.ideaID == ideaID && $0.userID == voter.account.id && $0.choice != nil }, "The coordinator's response should be retracted on the server.")
    }
}

@MainActor
private final class LiveSyncClient {
    let account: UserAccount
    let persistence: WorkspacePersistenceController
    let library: WorkspaceLibrary
    private let transport: PostgresSyncTransport
    private let coordinator: OfflineSyncCoordinator

    init(account: UserAccount, token: String) throws {
        self.account = account
        persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        library = WorkspaceLibrary()
        persistence.activate(userID: account.id, in: library, seedData: false)
        library.configureViewer(account)
        transport = PostgresSyncTransport(
            baseURL: LiveSyncAcceptanceConfiguration.developmentOrigin,
            tokenStore: AcceptanceTokenStore(token: token)
        )
        coordinator = OfflineSyncCoordinator(
            store: SwiftDataSyncStore(modelContainer: persistence.container),
            transport: transport,
            remoteApplier: WorkspaceRemoteChangeApplier(persistence: persistence, library: library),
            ownerUserID: account.id
        )
    }

    func bootstrap() async throws {
        let response = try await transport.bootstrap()
        try persistence.applyBootstrap(response.snapshots, entities: response.entitySnapshots, to: library)
        library.configureViewer(account)
    }

    func workspace(scopeID: UUID) -> PlanningWorkspace? {
        library.workspaces.first { $0.mainEventID == scopeID }
    }

    func cachedArchive(scopeID: UUID) throws -> WorkspaceArchiveV1? {
        let context = ModelContext(persistence.container)
        guard let record = try context.fetch(FetchDescriptor<WorkspaceRecord>()).first(where: {
            $0.id == scopeID && $0.ownerUserID == account.id
        }) else { return nil }
        return try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload)
    }

    func assertPendingMutations(scopeID: UUID, allowed: Set<PendingEntityKey>, file: StaticString = #fileID, line: UInt = #line) throws {
        let context = ModelContext(persistence.container)
        let actual = try Set(context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.scopeID == scopeID && $0.ownerUserID == account.id }
            .map { key($0.entityType, $0.entityID) })
        try #require(actual.isSubset(of: allowed), "Refusing to send unexpected pending mutations for this development fixture at \(file):\(line).")
    }

    func enqueueResponseRetraction(ideaID: UUID, scopeID: UUID) throws {
        let context = ModelContext(persistence.container)
        let response = IdeaResponse(ideaID: ideaID, userID: account.id, choice: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        context.insert(PendingMutation(
            scopeID: scopeID,
            entityType: .ideaResponse,
            entityID: response.id,
            operation: .update,
            payload: try encoder.encode(response),
            baseVersion: nil,
            ownerUserID: account.id
        ))
        try context.save()
    }

    func synchronize(scopeID: UUID, allowed: Set<PendingEntityKey> = []) async throws {
        try assertPendingMutations(scopeID: scopeID, allowed: allowed)
        let summary = try await coordinator.synchronize(scopeID: scopeID, trigger: .manual)
        try #require(summary.attentionFailureCode == nil, "The development server rejected a live acceptance mutation.")
        try assertPendingMutations(scopeID: scopeID, allowed: [])
    }
}

private struct AcceptanceTokenStore: SessionTokenStore {
    let token: String

    func read() throws -> String? { token }
    func save(_ token: String) throws {}
    func delete() {}
}

private struct AcceptanceAccountCache: ValidatedAccountCache {
    func account(matching token: String) throws -> UserAccount? { nil }
    func save(_ account: UserAccount, matching token: String) throws {}
    func clear() {}
}
