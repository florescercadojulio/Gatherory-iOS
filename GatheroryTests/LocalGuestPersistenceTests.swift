import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct LocalGuestPersistenceTests {
    @Test("Local guest profile persistence validates names and keeps its stable device namespace")
    func profilePersistence() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let file = root.appending(path: "profile.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DeviceLocalGuestProfileStore(fileURL: file)
        let profile = LocalGuestProfile(displayName: "  Garden Guest  ")

        try store.save(profile)
        #expect(try store.load() == profile)
        #expect(profile.storageID == "device-guest:\(profile.id.uuidString.lowercased())")

        let pendingDiscard = LocalGuestProfile(
            id: profile.id,
            displayName: profile.displayName,
            discardPending: true
        )
        try store.save(pendingDiscard)
        #expect(try store.load()?.discardPending == true)
        let legacyProfile = try JSONSerialization.data(withJSONObject: [
            "id": profile.id.uuidString,
            "displayName": profile.displayName
        ])
        try legacyProfile.write(to: file, options: .atomic)
        #expect(try store.load()?.discardPending == nil)

        let invalid = LocalGuestProfile(displayName: "   ")
        #expect(throws: LocalGuestProfileStoreError.self) { try store.save(invalid) }
        #expect(!LocalGuestProfile(displayName: String(repeating: "e\u{301}", count: 41)).hasValidDisplayName)
        #expect(LocalGuestProfile(displayName: String(repeating: "🌿", count: 80)).hasValidDisplayName)
        try store.remove()
        #expect(try store.load() == nil)
    }

    @Test("Guest credential remains stable per profile and is a 32-byte base64url token")
    func guestCredentialToken() throws {
        let store = MemoryLocalGuestCredentialStore()
        let firstID = UUID()
        let secondID = UUID()
        let first = try store.loadOrCreateToken(profileID: firstID)
        #expect(first == (try store.loadOrCreateToken(profileID: firstID)))
        #expect(first.count == 43)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(LocalGuestCredentialToken.isValid(first))
        #expect(!LocalGuestCredentialToken.isValid("Ａ" + String(first.dropFirst())))
        #expect(!LocalGuestCredentialToken.isValid(String(first.dropLast())))
        #expect(!LocalGuestCredentialToken.isValid(String(repeating: "!", count: 43)))
        #expect(try store.loadOrCreateToken(profileID: secondID) != first)
        try store.removeSecret(profileID: firstID)
        #expect(store.tokens[firstID] == nil)
    }

    @Test("Local guest saves stay device-local without outbox or media transfers")
    func guestSavesDoNotEnqueueOrContactCloud() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = GuestNetworkGuardTransport()
        let cloudSync = WorkspaceCloudSyncController(
            persistence: persistence,
            library: library,
            baseURL: URL(string: "https://example.invalid")!,
            transport: transport,
            usesRemoteAccountState: true
        )
        await cloudSync.activate(userID: nil, seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        try persistence.activateLocalGuest(profile, in: library)
        let workspace = PlanningWorkspace.newLocalGuestWorkspace(
            title: "Garden dinner",
            startsAt: .now,
            eventLocation: nil,
            imageData: Data([0x01, 0x02]),
            guest: profile
        )
        library.add(workspace)
        try persistence.saveChanges(in: library)

        let context = ModelContext(persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.count == 1)
        #expect(records.first?.ownerUserID == profile.storageID)
        #expect(workspace.currentViewerMember?.participantRole == .host)
        #expect(workspace.isLocalGuestViewer)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMediaTransfer>()).isEmpty)
        await cloudSync.synchronize()
        #expect(transport.bootstrapCount == 0)
        #expect(transport.pushCount == 0)
        #expect(transport.pullCount == 0)
    }

    @Test("Authenticated cloud activation never adopts the guest workspace namespace")
    func accountActivationLeavesGuestRecordsOutOfTargetNamespace() async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let transport = GuestNetworkGuardTransport()
        let cloudSync = WorkspaceCloudSyncController(
            persistence: persistence,
            library: library,
            baseURL: URL(string: "https://example.invalid")!,
            transport: transport,
            usesRemoteAccountState: true
        )
        await cloudSync.activate(userID: nil, seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        try persistence.activateLocalGuest(profile, in: library)
        let guest = PlanningWorkspace.newLocalGuestWorkspace(
            title: "Guest source", startsAt: .now, eventLocation: nil, imageData: nil, guest: profile
        )
        library.add(guest)
        try persistence.saveChanges(in: library)

        await cloudSync.activate(userID: "target-account", seedData: false)

        let context = ModelContext(persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.contains { $0.ownerUserID == profile.storageID && $0.id == guest.mainEventID })
        #expect(!records.contains { $0.ownerUserID == "target-account" && $0.id == guest.mainEventID })
        #expect(library.workspaces.isEmpty)
        #expect(transport.bootstrapCount == 1)
        #expect(persistence.activeUserID == "target-account")
    }

    @Test("Guest import adds authenticated creates without replacing account data and is idempotent")
    func additiveImportAndRetry() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        let account = testAccount(id: "signed-in-account")
        try persistence.activateLocalGuest(profile, in: library)
        let guestWorkspace = PlanningWorkspace.newLocalGuestWorkspace(
            title: "Guest plan", startsAt: .now, eventLocation: nil, imageData: nil, guest: profile
        )
        let guestIdea = PlanningIdea(
            title: "Garden lights",
            note: "Warm color",
            category: .decor,
            submittedBy: profile.displayName,
            submittedByUserID: profile.storageID
        )
        guestWorkspace.addIdea(guestIdea)
        guestWorkspace.ideaResponses = [
            IdeaResponse(ideaID: guestIdea.id, userID: profile.storageID, choice: .love)
        ]
        guestWorkspace.notes = [
            EventNote(eventID: guestWorkspace.mainEventID, authorUserID: profile.storageID, body: "Guest note")
        ]
        guestWorkspace.replaceExpenses([
            EventExpense(
                eventID: guestWorkspace.mainEventID,
                title: "Lighting estimate",
                amount: 125,
                createdByUserID: profile.storageID
            )
        ], forEventID: guestWorkspace.mainEventID)
        library.add(guestWorkspace)
        try persistence.saveChanges(in: library)

        persistence.activate(userID: account.id, in: library, seedData: false)
        library.configureViewer(account)
        let context = ModelContext(persistence.container)
        #expect(try !context.fetch(FetchDescriptor<WorkspaceRecord>()).contains {
            $0.ownerUserID == account.id && $0.id == guestWorkspace.mainEventID
        })
        let accountWorkspace = PlanningWorkspace.newWorkspace(
            title: "Existing account plan", startsAt: .now, eventLocation: nil, imageData: nil, owner: account
        )
        library.add(accountWorkspace)
        try persistence.saveChanges(in: library)
        let existingAccountMutationIDs = Set(try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == account.id }.map(\.id))

        let first = try persistence.importLocalGuest(profile, into: account, in: library)
        #expect(!first.wasAlreadyImported)
        #expect(first.workspaceIDs == [guestWorkspace.mainEventID])
        #expect(Set(library.workspaces.map(\.mainEventID)) == [guestWorkspace.mainEventID, accountWorkspace.mainEventID])
        #expect(library.workspaces.first(where: { $0.mainEventID == guestWorkspace.mainEventID })?
            .members.first(where: { $0.participantRole == .host })?.userID == account.id)
        let importedWorkspace = try #require(library.workspaces.first { $0.mainEventID == guestWorkspace.mainEventID })
        #expect(importedWorkspace.ideas.first?.submittedByUserID == account.id)
        let importedResponse = try #require(importedWorkspace.ideaResponses.first)
        #expect(importedResponse.userID == account.id)
        #expect(importedResponse.id == IdeaResponse.identifier(ideaID: guestIdea.id, userID: account.id))
        #expect(importedWorkspace.notes.first?.authorUserID == account.id)
        #expect(importedWorkspace.eventExpenses.first?.createdByUserID == account.id)

        let accountMutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == account.id }
        #expect(existingAccountMutationIDs.isSubset(of: Set(accountMutations.map(\.id))))
        #expect(accountMutations.filter {
            $0.scopeID == guestWorkspace.mainEventID
                && $0.entityType == .workspace
                && $0.operation == .create
        }.count == 1)
        let responseMutation = try #require(accountMutations.first {
            $0.scopeID == guestWorkspace.mainEventID
                && $0.entityType == .ideaResponse
                && $0.operation == .create
        })
        let syncedResponse = try WorkspaceArchiveCodec().decode(IdeaResponse.self, from: responseMutation.payload)
        #expect(syncedResponse.userID == account.id)
        #expect(syncedResponse.id == IdeaResponse.identifier(ideaID: guestIdea.id, userID: account.id))
        let importedMutationPayloads = accountMutations.filter {
            $0.scopeID == guestWorkspace.mainEventID && $0.operation == .create
        }
        #expect(importedMutationPayloads.allSatisfy {
            String(data: $0.payload, encoding: .utf8)?.contains(profile.storageID) == false
        })
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .contains { $0.ownerUserID == profile.storageID && $0.id == guestWorkspace.mainEventID })

        let otherAccount = testAccount(id: "other-signed-in-account")
        persistence.activate(userID: otherAccount.id, in: library, seedData: false)
        library.configureViewer(otherAccount)
        #expect(throws: LocalGuestWorkspacePersistenceError.self) {
            try persistence.importLocalGuest(profile, into: otherAccount, in: library)
        }
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .contains { $0.ownerUserID == profile.storageID && $0.id == guestWorkspace.mainEventID })
        #expect(try !context.fetch(FetchDescriptor<WorkspaceRecord>()).contains {
            $0.ownerUserID == otherAccount.id && $0.id == guestWorkspace.mainEventID
        })
        #expect(try persistence.guestImportAccountID(profile) == account.id)

        persistence.activate(userID: account.id, in: library, seedData: false)
        library.configureViewer(account)
        let retry = try persistence.importLocalGuest(profile, into: account, in: library)
        #expect(retry.wasAlreadyImported)
        #expect(retry.workspaceIDs == first.workspaceIDs)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.ownerUserID == account.id && $0.id == guestWorkspace.mainEventID }.count == 1)
    }

    @Test("Empty guest import binds one account and safely retries only for that account")
    func emptyImportBindsTargetAccount() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        let firstAccount = testAccount(id: "first-target-account")
        let secondAccount = testAccount(id: "second-target-account")
        try persistence.activateLocalGuest(profile, in: library)
        persistence.activate(userID: firstAccount.id, in: library, seedData: false)
        library.configureViewer(firstAccount)

        let firstImport = try persistence.importLocalGuest(profile, into: firstAccount, in: library)
        #expect(firstImport.workspaceIDs.isEmpty)
        #expect(!firstImport.wasAlreadyImported)
        #expect(try persistence.guestImportAccountID(profile) == firstAccount.id)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<LocalGuestWorkspaceImportReceipt>())
            .filter { $0.guestProfileID == profile.id }.count == 1)

        persistence.activate(userID: secondAccount.id, in: library, seedData: false)
        library.configureViewer(secondAccount)
        #expect(throws: LocalGuestWorkspacePersistenceError.self) {
            try persistence.importLocalGuest(profile, into: secondAccount, in: library)
        }
        #expect(try persistence.guestImportAccountID(profile) == firstAccount.id)
        #expect(try context.fetch(FetchDescriptor<LocalGuestWorkspaceImportReceipt>())
            .filter { $0.guestProfileID == profile.id }.count == 1)

        persistence.activate(userID: firstAccount.id, in: library, seedData: false)
        library.configureViewer(firstAccount)
        let retry = try persistence.importLocalGuest(profile, into: firstAccount, in: library)
        #expect(retry.workspaceIDs.isEmpty)
        #expect(retry.wasAlreadyImported)
    }

    @Test("Workspace ID collision rejects import without changing either namespace")
    func collisionKeepsBothNamespaces() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        let account = testAccount(id: "collision-account")
        try persistence.activateLocalGuest(profile, in: library)
        let guest = PlanningWorkspace.newLocalGuestWorkspace(
            title: "Guest source", startsAt: .now, eventLocation: nil, imageData: nil, guest: profile
        )
        library.add(guest)
        try persistence.saveChanges(in: library)

        persistence.activate(userID: account.id, in: library, seedData: false)
        let collidingAccountCopy = WorkspaceArchiveV1(workspace: guest).makeWorkspace()
        collidingAccountCopy.title = "Account's existing plan"
        library.add(collidingAccountCopy)
        try persistence.saveChanges(in: library)
        let priorCount = library.workspaces.count

        #expect(throws: LocalGuestWorkspacePersistenceError.self) {
            try persistence.importLocalGuest(profile, into: account, in: library)
        }
        #expect(library.workspaces.count == priorCount)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .contains { $0.ownerUserID == profile.storageID && $0.id == guest.mainEventID })
        let expectedAccountPayload = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: collidingAccountCopy))
        let actualAccountPayload = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first { $0.ownerUserID == account.id && $0.id == guest.mainEventID }?.payload)
        #expect(actualAccountPayload == expectedAccountPayload)
        #expect(try context.fetch(FetchDescriptor<LocalGuestWorkspaceImportReceipt>()).isEmpty)
    }

    @Test("Guest discard after account activation removes only the guest namespace")
    func discardGuestNamespaceOnly() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let profile = LocalGuestProfile(displayName: "Local Planner")
        let account = testAccount(id: "discard-account")
        try persistence.activateLocalGuest(profile, in: library)
        let guest = PlanningWorkspace.newLocalGuestWorkspace(
            title: "Guest plan", startsAt: .now, eventLocation: nil, imageData: nil, guest: profile
        )
        library.add(guest)
        try persistence.saveChanges(in: library)

        persistence.activate(userID: account.id, in: library, seedData: false)
        library.configureViewer(account)
        let signedIn = PlanningWorkspace.newWorkspace(
            title: "Account plan", startsAt: .now, eventLocation: nil, imageData: nil, owner: account
        )
        library.add(signedIn)
        try persistence.saveChanges(in: library)
        try persistence.discardLocalGuest(profile, in: library)

        #expect(library.workspaces.map(\.mainEventID) == [signedIn.mainEventID])
        let context = ModelContext(persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(!records.contains { $0.ownerUserID == profile.storageID })
        #expect(records.contains { $0.ownerUserID == account.id && $0.id == signedIn.mainEventID })
        #expect(persistence.activeUserID == account.id)
    }

    private func testAccount(id: String) -> UserAccount {
        UserAccount(
            id: id,
            email: "planner@example.test",
            displayName: "Account Planner",
            role: .planner,
            authenticationProvider: .password,
            createdAt: .now
        )
    }
}

@MainActor
private final class GuestNetworkGuardTransport: WorkspaceSnapshotTransport, @unchecked Sendable {
    private(set) var bootstrapCount = 0
    private(set) var pushCount = 0
    private(set) var pullCount = 0

    func bootstrap() async throws -> SyncBootstrapResponse {
        bootstrapCount += 1
        return SyncBootstrapResponse(account: nil, snapshots: [])
    }

    func push(_ mutations: [PendingMutationSnapshot]) async throws -> SyncPushResponse {
        pushCount += 1
        return SyncPushResponse(results: [])
    }

    func pull(scopeID: UUID, after cursor: String?) async throws -> SyncPullPage {
        pullCount += 1
        return SyncPullPage(changes: [], nextCursor: cursor, hasMore: false)
    }
}
