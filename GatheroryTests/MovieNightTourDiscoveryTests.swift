import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourDiscoveryTests {
    @Test("Discovery phase is durable, account-bound, and rejects empty or invalid preferences")
    func phaseLifecycleAndIsolation() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = MovieNightTourDiscoveryStore(defaults: defaults)
        let accountA = "discovery-a"
        let accountB = "discovery-b"

        #expect(store.phase(accountID: accountA) == nil)
        store.begin(accountID: "")
        store.openExplore(accountID: "")
        store.previous(accountID: "")
        store.clear(accountID: "")
        #expect(store.phase(accountID: "") == nil)

        defaults.set("unknown-phase", forKey: "movieNightTourDiscovery.\(accountA)")
        #expect(store.phase(accountID: accountA) == nil)
        store.openExplore(accountID: accountA)
        #expect(store.phase(accountID: accountA) == nil)

        store.begin(accountID: accountA)
        #expect(store.phase(accountID: accountA) == .chooseExplore)
        #expect(store.phase(accountID: accountB) == nil)
        #expect(MovieNightTourDiscoveryStore(defaults: defaults).phase(accountID: accountA) == .chooseExplore)
        store.openExplore(accountID: accountA)
        #expect(store.phase(accountID: accountA) == .chooseMovieNight)
        store.previous(accountID: accountA)
        #expect(store.phase(accountID: accountA) == .chooseExplore)
        store.clear(accountID: accountA)
        #expect(store.phase(accountID: accountA) == nil)
    }

    @Test("Beginning discovery writes only its account phase and creates no workspace or outbox")
    func beginDoesNotCreatePlanningData() throws {
        let account = makeAccount("discovery-begin")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        let store = MovieNightTourDiscoveryStore(defaults: try #require(UserDefaults(suiteName: suiteName)))

        store.begin(accountID: account.id)

        #expect(store.phase(accountID: account.id) == .chooseExplore)
        #expect(library.workspaces.isEmpty)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    @Test("Selecting Movie Night requires Explore, then saves one local plan and clears discovery")
    func selectionRequiresExploreAndInstallsLocalCopy() throws {
        let account = makeAccount("discovery-select")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        let discovery = MovieNightTourDiscoveryStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let tour = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName + "-tour")))

        #expect(throws: MovieNightTourDiscoveryCoordinator.EntryError.self) {
            try MovieNightTourDiscoveryCoordinator.selectMovieNight(
                account: account, library: library, persistence: persistence,
                discoveryStore: discovery, tourStore: tour
            )
        }
        #expect(library.workspaces.isEmpty)
        #expect(discovery.phase(accountID: account.id) == nil)

        discovery.begin(accountID: account.id)
        #expect(throws: MovieNightTourDiscoveryCoordinator.EntryError.self) {
            try MovieNightTourDiscoveryCoordinator.selectMovieNight(
                account: account, library: library, persistence: persistence,
                discoveryStore: discovery, tourStore: tour
            )
        }
        #expect(library.workspaces.isEmpty)
        #expect(discovery.phase(accountID: account.id) == .chooseExplore)

        discovery.openExplore(accountID: account.id)
        let workspace = try MovieNightTourDiscoveryCoordinator.selectMovieNight(
            account: account, library: library, persistence: persistence,
            discoveryStore: discovery, tourStore: tour
        )
        #expect(workspace.title == "Movie Night")
        #expect(library.selectedWorkspace?.mainEventID == workspace.mainEventID)
        #expect(discovery.phase(accountID: account.id) == nil)
        #expect(tour.progress(accountID: account.id)?.installedWorkspaceID == workspace.mainEventID)

        let outbox = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        let ownedCreates = outbox.filter {
            $0.scopeID == workspace.mainEventID && $0.ownerUserID == account.id
        }
        let workspaceCreates = ownedCreates.filter { $0.entityType == .workspace }
        #expect(workspaceCreates.contains(where: { $0.operation == .create }))
        let participantCreates = ownedCreates.filter { $0.entityType == .participant }
        #expect(participantCreates.contains(where: { $0.operation == .create }))
    }

    @Test("A failed local save keeps Movie Night selected for retry and leaves no orphan records")
    func failedSavePreservesEntryForRetry() throws {
        let account = makeAccount("discovery-retry")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        let discovery = MovieNightTourDiscoveryStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let tour = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName + "-tour")))
        let invalidWorkspace = PlanningWorkspace.newWorkspace(
            title: "Unsaved local edit", startsAt: .now,
            eventLocation: nil, imageData: nil, owner: account
        )
        invalidWorkspace.mainEventStartsAt = Date(timeIntervalSinceReferenceDate: .infinity)
        library.add(invalidWorkspace)
        discovery.begin(accountID: account.id)
        discovery.openExplore(accountID: account.id)

        #expect(throws: EncodingError.self) {
            try MovieNightTourDiscoveryCoordinator.selectMovieNight(
                account: account, library: library, persistence: persistence,
                discoveryStore: discovery, tourStore: tour
            )
        }
        #expect(discovery.phase(accountID: account.id) == .chooseMovieNight)
        #expect(tour.progress(accountID: account.id) == nil)
        #expect(library.workspaces.count == 1)
        #expect(library.workspaces.first === invalidWorkspace)
        let contextAfterFailure = ModelContext(persistence.container)
        #expect(try contextAfterFailure.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try contextAfterFailure.fetch(FetchDescriptor<PendingMutation>()).isEmpty)

        invalidWorkspace.mainEventStartsAt = .now
        let retry = try MovieNightTourDiscoveryCoordinator.selectMovieNight(
            account: account, library: library, persistence: persistence,
            discoveryStore: discovery, tourStore: tour
        )
        #expect(retry.title == "Movie Night")
        #expect(discovery.phase(accountID: account.id) == nil)
        #expect(tour.progress(accountID: account.id)?.installedWorkspaceID == retry.mainEventID)
    }

    @Test("The active account must match the selected discovery account")
    func accountMismatchDoesNotClearDiscovery() throws {
        let activeAccount = makeAccount("discovery-active")
        let selectedAccount = makeAccount("discovery-other")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: activeAccount.id)
        let discovery = MovieNightTourDiscoveryStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let tour = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName + "-tour")))
        discovery.begin(accountID: selectedAccount.id)
        discovery.openExplore(accountID: selectedAccount.id)

        #expect(throws: MovieNightTourCoordinator.StartError.self) {
            try MovieNightTourDiscoveryCoordinator.selectMovieNight(
                account: selectedAccount, library: library, persistence: persistence,
                discoveryStore: discovery, tourStore: tour
            )
        }
        #expect(discovery.phase(accountID: selectedAccount.id) == .chooseMovieNight)
        #expect(tour.progress(accountID: selectedAccount.id) == nil)
        #expect(library.workspaces.isEmpty)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    private var suiteName: String { "MovieNightTourDiscoveryTests-\(UUID().uuidString)" }

    private func makeAccount(_ id: String) -> UserAccount {
        UserAccount(
            id: id, email: "\(id)@example.test", displayName: "Movie Host",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
    }
}
