import Foundation
import SwiftData
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct IdeaEventImportTests {
    @Test("Adding a public idea durably saves its independent archive copy and idea outbox record")
    func durableArchiveAndOutboxReload() async throws {
        let fixture = try makeFixture()
        let image = Data([0xff, 0xd8, 0x01, 0x02, 0xff, 0xd9])
        let ideaID = UUID()

        let result = try await IdeaEventImport.add(
            entry: entry(), destination: .main, workspace: fixture.workspace,
            library: fixture.library, persistence: fixture.persistence,
            accountID: fixture.account.id, accountGeneration: fixture.generation,
            ideaID: ideaID, loadImage: { _ in image }
        )

        guard case .added(let added) = result else {
            Issue.record("Expected a new idea import")
            return
        }
        #expect(added.id == ideaID)
        #expect(added.imageData == image)
        #expect(added.mediaAssetID == nil)
        #expect(added.submittedBy == fixture.account.displayName)
        #expect(added.submittedByUserID == fixture.account.id)

        let context = ModelContext(fixture.persistence.container)
        let record = try #require(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first { $0.id == fixture.workspace.mainEventID })
        let savedArchive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload)
        let archivedIdea = try #require(savedArchive.ideas.first { $0.id == ideaID })
        #expect(archivedIdea.imageData == image)
        #expect(archivedIdea.mediaAssetID == nil)
        #expect(archivedIdea.estimatedCost == nil)
        #expect(archivedIdea.status == .new)
        #expect(savedArchive.ideaResponses?.isEmpty != false)
        #expect(savedArchive.todos?.isEmpty != false)
        #expect(savedArchive.timeline.isEmpty)
        #expect(savedArchive.eventExpenses.isEmpty)

        let ideaMutations = try context.fetch(FetchDescriptor<PendingMutation>()).filter {
            $0.ownerUserID == fixture.account.id && $0.entityType == .idea && $0.entityID == ideaID
        }
        let mutation = try #require(ideaMutations.first)
        #expect(ideaMutations.count == 1)
        #expect(mutation.operation == .create)
        let syncIdea = try WorkspaceArchiveCodec().decode(PlanningIdea.self, from: mutation.payload)
        #expect(syncIdea.id == ideaID)
        #expect(syncIdea.imageData == nil)
        #expect(syncIdea.submittedByUserID == fixture.account.id)

        let relaunched = fixture.persistence.restoreLibrary(seedData: false, ownerUserID: fixture.account.id)
        relaunched.configureViewer(fixture.account)
        let restoredWorkspace = try #require(relaunched.workspaces.first { $0.mainEventID == fixture.workspace.mainEventID })
        let restoredIdea = try #require(restoredWorkspace.ideas.first { $0.id == ideaID })
        #expect(restoredWorkspace !== fixture.workspace)
        #expect(restoredIdea.imageData == image)
        #expect(restoredIdea.submittedBy == fixture.account.displayName)
    }

    @Test("A failed cover fetch makes no archive or outbox change")
    func failedImageFetchDoesNotCopy() async throws {
        let fixture = try makeFixture()
        let before = try persistedState(fixture)
        var imageLoads = 0

        await #expect {
            try await IdeaEventImport.add(
                entry: entry(), destination: .main, workspace: fixture.workspace,
                library: fixture.library, persistence: fixture.persistence,
                accountID: fixture.account.id, accountGeneration: fixture.generation,
                ideaID: UUID(), loadImage: { _ in
                    imageLoads += 1
                    throw ImportFailure.image
                }
            )
        } throws: { error in
            if case ImportFailure.image = error { return true }
            return false
        }

        #expect(imageLoads == 1)
        #expect(fixture.workspace.ideas.isEmpty)
        let after = try persistedState(fixture)
        #expect(after.0 == before.0)
        #expect(after.1 == before.1)
        #expect(try ideaMutations(fixture).isEmpty)
    }

    @Test("A permission change while the cover loads prevents the import")
    func permissionChangeDuringImageLoad() async throws {
        let fixture = try makeFixture()
        let viewerID = fixture.workspace.members[0].id
        let otherHost = WorkspaceMember(name: "Other host", participantRole: .host, initials: "OH")
        fixture.workspace.members.append(otherHost)
        fixture.workspace.addParticipant(otherHost.id, to: .main)
        #expect(fixture.workspace.updateParticipant(viewerID, role: .collaborator,
                                                   planningPermission: .contribute, in: .main))
        let gate = SuspendedImageLoader()
        let task = beginImport(fixture, gate: gate)
        await gate.waitUntilStarted()
        #expect(fixture.workspace.updateParticipant(viewerID, role: .collaborator,
                                                   planningPermission: .viewOnly, in: .main))
        await gate.finish(Data([0x01]))

        await expectInvalidated(task)
        #expect(fixture.workspace.ideas.isEmpty)
        #expect(try ideaMutations(fixture).isEmpty)
    }

    @Test("Removing the destination workspace while the cover loads prevents the import")
    func removedWorkspaceDuringImageLoad() async throws {
        let fixture = try makeFixture()
        let gate = SuspendedImageLoader()
        let task = beginImport(fixture, gate: gate)
        await gate.waitUntilStarted()
        fixture.library.remove(fixture.workspace)
        await gate.finish(Data([0x01]))

        await expectInvalidated(task)
        #expect(fixture.workspace.ideas.isEmpty)
        #expect(try ideaMutations(fixture).isEmpty)
    }

    @Test("An A to B to A switch while the cover loads invalidates the original account generation")
    func accountGenerationChangeDuringImageLoad() async throws {
        let fixture = try makeFixture()
        let gate = SuspendedImageLoader()
        let task = beginImport(fixture, gate: gate)
        await gate.waitUntilStarted()
        fixture.persistence.activate(userID: "account-b", in: fixture.library)
        fixture.persistence.activate(userID: fixture.account.id, in: fixture.library)
        await gate.finish(Data([0x01]))

        await expectInvalidated(task)
        #expect(fixture.workspace.ideas.isEmpty)
        #expect(fixture.library.workspaces.first { $0.mainEventID == fixture.workspace.mainEventID } !== fixture.workspace)
        #expect(try ideaMutations(fixture).isEmpty)
    }

    @Test("Cancelling while the cover loads leaves the workspace untouched")
    func cancellationDuringImageLoad() async throws {
        let fixture = try makeFixture()
        let gate = SuspendedImageLoader()
        let task = beginImport(fixture, gate: gate)
        await gate.waitUntilStarted()
        task.cancel()
        await gate.finish(Data([0x01]))

        await #expect {
            try await task.value
        } throws: { error in
            error is CancellationError
        }
        #expect(fixture.workspace.ideas.isEmpty)
        #expect(try ideaMutations(fixture).isEmpty)
    }

    @Test("Retrying one add operation persists one idea under its stable UUID")
    func sameOperationRetryIsIdempotent() async throws {
        let fixture = try makeFixture()
        let ideaID = UUID()
        var saves = 0

        let first = try await IdeaEventImport.add(
            entry: entry(), destination: .main, workspace: fixture.workspace,
            library: fixture.library, persistence: fixture.persistence,
            accountID: fixture.account.id, accountGeneration: fixture.generation,
            ideaID: ideaID, loadImage: { _ in Data([0x01]) }
        )
        if case .added = first { saves += 1 }
        let retry = try await IdeaEventImport.add(
            entry: entry(), destination: .main, workspace: fixture.workspace,
            library: fixture.library, persistence: fixture.persistence,
            accountID: fixture.account.id, accountGeneration: fixture.generation,
            ideaID: ideaID, loadImage: { _ in Data([0x01]) }
        )

        guard case .alreadyAdded(let existing) = retry else {
            Issue.record("Expected the retry to resolve to the original copy")
            return
        }
        #expect(existing.id == ideaID)
        #expect(saves == 1)
        #expect(fixture.workspace.ideas.filter { $0.id == ideaID }.count == 1)
        #expect(try ideaMutations(fixture).count == 1)
    }

    private func makeFixture() throws -> Fixture {
        let account = UserAccount(
            id: "idea-import-owner",
            email: "owner@example.test",
            displayName: "Morgan Host",
            role: .planner,
            authenticationProvider: .password,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        library.configureViewer(account)
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Weekend",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            eventLocation: nil,
            imageData: nil,
            owner: account
        )
        library.add(workspace)
        try persistence.saveChanges(in: library)
        return Fixture(
            account: account,
            persistence: persistence,
            library: library,
            workspace: workspace,
            generation: persistence.activeUserGeneration
        )
    }

    private func entry() -> IdeaDiscoveryEntry {
        IdeaDiscoveryEntry(
            id: "birthday-party:3:activity_ideas",
            sourceBlueprintId: "birthday_party",
            sourceVersion: 3,
            sourceTitle: "Birthday Party",
            creator: BlueprintCreatorMetadata(displayName: "Gatherory"),
            idea: BlueprintCatalogIdea(
                key: "activity_ideas",
                title: "Choose activities",
                category: "other",
                notes: "Collect activities everyone can enjoy.",
                target: .main,
                configuration: ["version": .integer(1)]
            ),
            coverAssetId: UUID(uuidString: "A0A0A0A0-0000-4000-8000-000000000001"),
            coverImageURL: "https://cdn.gatherory.com/explore/covers/birthday-party/\(String(repeating: "b", count: 64))/card.jpg"
        )
    }

    private func beginImport(_ fixture: Fixture, gate: SuspendedImageLoader) -> Task<BlueprintIdeaImportResult, Error> {
        Task {
            try await IdeaEventImport.add(
                entry: entry(), destination: .main, workspace: fixture.workspace,
                library: fixture.library, persistence: fixture.persistence,
                accountID: fixture.account.id, accountGeneration: fixture.generation,
                ideaID: UUID(), loadImage: { _ in await gate.load() }
            )
        }
    }

    private func expectInvalidated(_ task: Task<BlueprintIdeaImportResult, Error>) async {
        await #expect {
            try await task.value
        } throws: { error in
            if case CloudSyncFailure.invalidSession = error { return true }
            return false
        }
    }

    private func persistedState(_ fixture: Fixture) throws -> (Data?, Set<PendingMutationSnapshot>) {
        let context = ModelContext(fixture.persistence.container)
        let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first { $0.id == fixture.workspace.mainEventID }
        let mutations = Set(try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == fixture.account.id }
            .map(PendingMutationSnapshot.init))
        return (record?.payload, mutations)
    }

    private func ideaMutations(_ fixture: Fixture) throws -> [PendingMutation] {
        try ModelContext(fixture.persistence.container).fetch(FetchDescriptor<PendingMutation>()).filter {
            $0.ownerUserID == fixture.account.id && $0.entityType == .idea
        }
    }

    private struct Fixture {
        let account: UserAccount
        let persistence: WorkspacePersistenceController
        let library: WorkspaceLibrary
        let workspace: PlanningWorkspace
        let generation: UUID
    }

    private enum ImportFailure: Error {
        case image
    }
}

private actor SuspendedImageLoader {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var result: CheckedContinuation<Data?, Never>?

    func load() async -> Data? {
        await withCheckedContinuation { continuation in
            result = continuation
            started = true
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(_ data: Data?) {
        result?.resume(returning: data)
        result = nil
    }
}
