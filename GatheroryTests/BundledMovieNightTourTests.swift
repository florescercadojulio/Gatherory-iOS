import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct BundledMovieNightTourTests {
    @Test("The local blueprint creates the expected owned plan and captures its real idea IDs")
    func factoryMapsBundledContent() throws {
        let account = account("movie-owner")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 13))!
        let result = try BundledMovieNightTour.makeWorkspace(
            account: account, localJSON: blueprintJSON, today: today,
            timeZoneIdentifier: "America/Detroit"
        )
        let workspace = result.planningWorkspace
        #expect(workspace.title == "Movie Night")
        #expect(workspace.members.count == 1)
        #expect(workspace.members[0].userID == account.id)
        #expect(workspace.members[0].participantRole == .host)
        #expect(workspace.members[0].planningPermission == .manage)
        let mainHostParticipation = try #require(workspace.eventParticipations.first(where: {
            $0.eventID == workspace.mainEventID && $0.memberID == workspace.members[0].id
        }))
        #expect(mainHostParticipation.role == .host)
        #expect(mainHostParticipation.planningPermission == .manage)
        #expect(workspace.timeline.count == 1)
        #expect(workspace.timeline[0].title == "Snacks & catch-up")
        #expect(workspace.timeline[0].purpose == .eventExperience)
        #expect(workspace.timeline[0].status == .approved)
        #expect(workspace.timeline[0].schedulingState == .scheduled)
        #expect(workspace.timeline[0].scheduledAt == calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17)))
        #expect(workspace.availableEventContexts.contains(.subevent(workspace.timeline[0].id)))
        let childParticipation = try #require(workspace.eventParticipations.first(where: {
            $0.eventID == workspace.timeline[0].id
        }))
        #expect(childParticipation.memberID == workspace.members[0].id)
        #expect(workspace.ideas.count == 4)
        #expect(Set(workspace.ideas.map(\.title)) == Set(["Watch the movie", "Popcorn bar", "Pizza", "Blanket corner"]))
        #expect(workspace.ideas.first(where: { $0.id == result.eventIdeaID })?.title == "Watch the movie")
        #expect(workspace.ideas.first(where: { $0.id == result.snackIdeaID })?.title == "Popcorn bar")
        #expect(workspace.ideas.allSatisfy { $0.status == .new && $0.submittedByUserID == account.id })
        let watchIdea = try #require(workspace.ideas.first(where: { $0.id == result.eventIdeaID }))
        #expect(watchIdea.eventConfiguration?.purpose == .eventExperience)
        #expect(watchIdea.eventConfiguration?.proposedDate == nil)
        #expect(workspace.canScheduleEventIdea(watchIdea))
        #expect(workspace.makeScheduleRequest(for: watchIdea) != nil)
    }

    @Test("Tour receipts follow stable blueprint keys when display titles change")
    func targetIDsFollowBlueprintKeys() throws {
        let account = account("movie-key-mapping")
        let source = try #require(String(data: blueprintJSON, encoding: .utf8))
        let renamedJSON = source.replacingOccurrences(of: "Watch the movie", with: "Choose a film")
            .replacingOccurrences(of: "Popcorn bar", with: "Snack toppings")
        let result = try BundledMovieNightTour.makeWorkspace(
            account: account, localJSON: Data(renamedJSON.utf8)
        )
        #expect(result.planningWorkspace.ideas.first(where: { $0.id == result.eventIdeaID })?.title == "Choose a film")
        #expect(result.planningWorkspace.ideas.first(where: { $0.id == result.snackIdeaID })?.title == "Snack toppings")
    }

    @Test("The app bundle contains the local Movie Night blueprint")
    func loadsBundledBlueprintResource() throws {
        let result = try BundledMovieNightTour.makeBundledWorkspace(account: account("movie-bundle"))
        #expect(result.planningWorkspace.title == "Movie Night")
        #expect(result.planningWorkspace.ideas.contains(where: { $0.id == result.eventIdeaID }))
        #expect(result.planningWorkspace.ideas.contains(where: { $0.id == result.snackIdeaID }))
    }

    @Test("Starting saves an offline workspace and its account-scoped outbox, and replay preserves edits")
    func durableOfflineStartAndReplay() throws {
        let account = account("movie-owner")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        let defaults = try #require(UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)"))
        let store = MovieNightTourStore(defaults: defaults)
        let first = try MovieNightTourCoordinator.startOrResume(
            account: account, library: library, persistence: persistence,
            store: store, localJSON: blueprintJSON
        )
        #expect(library.selectedWorkspace?.mainEventID == first.mainEventID)
        let receipt = try #require(store.progress(accountID: account.id))
        #expect(receipt.installedWorkspaceID == first.mainEventID)
        #expect(first.ideas.contains(where: { $0.id == receipt.snackIdeaID && $0.title == "Popcorn bar" }))
        #expect(first.ideas.contains(where: { $0.id == receipt.eventIdeaID && $0.title == "Watch the movie" }))
        let context = ModelContext(persistence.container)
        let outbox = try context.fetch(FetchDescriptor<PendingMutation>())
        let workspaceCreates = outbox.filter {
            $0.scopeID == first.mainEventID && $0.entityType == .workspace
        }
        let ownedWorkspaceMutations = workspaceCreates.filter { $0.ownerUserID == account.id }
        #expect(ownedWorkspaceMutations.contains(where: { $0.operation == .create }))
        let participantCreates = outbox.filter {
            $0.scopeID == first.mainEventID && $0.entityType == .participant
        }
        let ownedParticipantMutations = participantCreates.filter { $0.ownerUserID == account.id }
        #expect(ownedParticipantMutations.contains(where: { $0.operation == .create }))

        first.title = "My edited movie night"
        try persistence.saveChanges(in: library)
        let replayed = try MovieNightTourCoordinator.startOrResume(
            account: account, library: library, persistence: persistence,
            store: store, localJSON: blueprintJSON
        )
        #expect(replayed === first)
        #expect(replayed.title == "My edited movie night")
        #expect(store.progress(accountID: account.id)?.installedWorkspaceID == first.mainEventID)
    }

    @Test("Love, approve, and schedule persist the real actions and survive an offline relaunch")
    func realActionsPersistAcrossRelaunch() throws {
        let account = account("movie-actions")
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatherory-movie-tour-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(atPath: storeURL.path + "-shm")
            try? FileManager.default.removeItem(atPath: storeURL.path + "-wal")
        }
        let persistence = try WorkspacePersistenceController(storeURL: storeURL)
        let library = WorkspaceLibrary()
        persistence.activate(userID: account.id, in: library, seedData: false)
        let defaults = try #require(UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)"))
        let store = MovieNightTourStore(defaults: defaults)
        let workspace = try MovieNightTourCoordinator.startOrResume(
            account: account, library: library, persistence: persistence, store: store
        )
        let progress = try #require(store.progress(accountID: account.id))
        let snackIdea = try #require(workspace.ideas.first(where: { $0.id == progress.snackIdeaID }))
        let eventIdea = try #require(workspace.ideas.first(where: { $0.id == progress.eventIdeaID }))

        workspace.decide(.love, on: snackIdea)
        #expect(workspace.response(on: snackIdea) == .love)
        let approval = try #require(workspace.makeIdeaApprovalRequest(for: snackIdea))
        #expect(workspace.confirmIdeaApproval(approval))
        #expect(workspace.ideas.first(where: { $0.id == snackIdea.id })?.status == .chosen)

        let scheduleRequest = try #require(workspace.makeScheduleRequest(for: eventIdea))
        var schedule = try #require(eventIdea.eventConfiguration)
        schedule.proposedDate = workspace.mainEventStartsAt.addingTimeInterval(86_400)
        let linkedEventID = try #require(workspace.confirmScheduleEventIdea(scheduleRequest, configuration: schedule))
        #expect(workspace.timeline.count == 2)
        #expect(workspace.timeline.contains(where: { $0.id == linkedEventID && $0.linkedIdeaID == eventIdea.id }))

        try persistence.saveChanges(in: library)
        store.advance(accountID: account.id, to: .schedule)
        let resumed = try MovieNightTourCoordinator.startOrResume(
            account: account, library: library, persistence: persistence, store: store
        )
        #expect(resumed === workspace)
        #expect(resumed.timeline.count == 2)
        #expect(store.progress(accountID: account.id)?.installedWorkspaceID == workspace.mainEventID)

        let originalOutbox = try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.scopeID == workspace.mainEventID && $0.ownerUserID == account.id }
        #expect(originalOutbox.contains(where: { $0.entityType == .ideaResponse }))
        #expect(originalOutbox.contains(where: { $0.entityType == .event && $0.operation == .create }))
        let originalMutationIDs = Set(originalOutbox.map(\.id))

        let relaunchedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let relaunchedLibrary = WorkspaceLibrary()
        relaunchedPersistence.activate(userID: account.id, in: relaunchedLibrary, seedData: false)
        relaunchedLibrary.configureViewer(account)
        let restored = try #require(relaunchedLibrary.workspaces.first {
            $0.mainEventID == workspace.mainEventID
        })
        #expect(restored.timeline.count == 2)
        #expect(Set(restored.timeline.map(\.id)) == Set(workspace.timeline.map(\.id)))
        #expect(restored.timeline.contains(where: { $0.id == linkedEventID && $0.linkedIdeaID == eventIdea.id }))
        #expect(restored.ideaResponses.contains(where: { $0.ideaID == snackIdea.id && $0.choice == .love }))
        #expect(restored.ideas.first(where: { $0.id == snackIdea.id })?.status == .chosen)
        #expect(restored.ideas.first(where: { $0.id == eventIdea.id })?.status == .chosen)
        let restoredOutbox = try ModelContext(relaunchedPersistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.scopeID == workspace.mainEventID && $0.ownerUserID == account.id }
        #expect(Set(restoredOutbox.map(\.id)) == originalMutationIDs)
    }

    @Test("A missing target or deleted root starts a new local tour without changing the old plan")
    func missingTargetAndDeletedRootStartFreshCopies() throws {
        let owner = account("movie-repair")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        let store = MovieNightTourStore(defaults: try #require(
            UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)")
        ))
        let original = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        let originalProgress = try #require(store.progress(accountID: owner.id))
        original.title = "Keep customized original"
        original.rollbackBlueprintIdeaImport(id: try #require(originalProgress.snackIdeaID), previousExpenses: original.eventExpenses)
        try persistence.saveChanges(in: library)

        let repaired = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        #expect(repaired.mainEventID != original.mainEventID)
        #expect(original.title == "Keep customized original")
        #expect(!original.ideas.contains(where: { $0.id == originalProgress.snackIdeaID }))
        #expect(store.progress(accountID: owner.id)?.installedWorkspaceID == repaired.mainEventID)

        repaired.isMainEventDeleted = true
        let replacement = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        #expect(replacement.mainEventID != repaired.mainEventID)
        #expect(repaired.isMainEventDeleted)
        #expect(library.workspaces.contains(where: { $0.mainEventID == original.mainEventID }))
        #expect(library.workspaces.contains(where: { $0.mainEventID == repaired.mainEventID }))
    }

    @Test("Malformed local blueprint data fails before changing the library or outbox")
    func malformedBlueprintDoesNotMutate() throws {
        let owner = account("movie-malformed")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        let store = MovieNightTourStore(defaults: try #require(
            UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)")
        ))

        #expect(throws: BundledMovieNightTour.FactoryError.self) {
            try MovieNightTourCoordinator.startOrResume(
                account: owner, library: library, persistence: persistence,
                store: store, localJSON: Data("not json".utf8)
            )
        }
        #expect(library.workspaces.isEmpty)
        #expect(library.selectedWorkspace == nil)
        #expect(store.progress(accountID: owner.id) == nil)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    @Test("A tour receipt for another account never opens that account's plan")
    func accountIsolation() throws {
        let accountA = account("movie-a")
        let accountB = account("movie-b")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: accountA.id)
        let defaults = try #require(UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)"))
        let store = MovieNightTourStore(defaults: defaults)
        let first = try MovieNightTourCoordinator.startOrResume(
            account: accountA, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        persistence.activate(userID: accountB.id, in: library, seedData: false)
        let second = try MovieNightTourCoordinator.startOrResume(
            account: accountB, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        #expect(first.mainEventID != second.mainEventID)
        #expect(library.selectedWorkspace?.mainEventID == second.mainEventID)
        #expect(store.progress(accountID: accountA.id)?.installedWorkspaceID == first.mainEventID)
        #expect(store.progress(accountID: accountB.id)?.installedWorkspaceID == second.mainEventID)
    }

    @Test("Replaying a completed tour creates a fresh lesson without changing the completed plan")
    func completedTourStartsFreshCopy() throws {
        let owner = account("movie-repeat")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        let defaults = try #require(UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)"))
        let store = MovieNightTourStore(defaults: defaults)
        let completedPlan = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        completedPlan.title = "Completed and customized"
        try persistence.saveChanges(in: library)
        store.advance(accountID: owner.id, to: .completed)

        let replay = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        #expect(replay.mainEventID != completedPlan.mainEventID)
        #expect(completedPlan.title == "Completed and customized")
        #expect(library.workspaces.contains(where: { $0.mainEventID == completedPlan.mainEventID }))
        #expect(store.progress(accountID: owner.id)?.installedWorkspaceID == replay.mainEventID)
    }

    @Test("Resume requires the current account to remain linked to the host participant")
    func resumeChecksCurrentParticipantIdentity() throws {
        let owner = account("movie-authority")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        let store = MovieNightTourStore(defaults: try #require(
            UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)")
        ))
        let plan = try MovieNightTourCoordinator.startOrResume(
            account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
        )
        plan.members[0].userID = "another-account"

        #expect(throws: MovieNightTourCoordinator.StartError.self) {
            try MovieNightTourCoordinator.startOrResume(
                account: owner, library: library, persistence: persistence, store: store, localJSON: blueprintJSON
            )
        }
        #expect(library.selectedWorkspace?.mainEventID == plan.mainEventID)
    }

    @Test("A failed local transaction removes the uncommitted tour from the library")
    func failedSaveRollsBackNewTour() throws {
        let owner = account("movie-save-failure")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        let defaults = try #require(UserDefaults(suiteName: "BundledMovieNightTourTests-\(UUID().uuidString)"))
        let store = MovieNightTourStore(defaults: defaults)
        let previouslySelected = PlanningWorkspace.newWorkspace(
            title: "Keep selected", startsAt: .now, eventLocation: nil, imageData: nil, owner: owner
        )
        library.add(previouslySelected)
        let invalid = PlanningWorkspace.newWorkspace(
            title: "Invalid preexisting local edit", startsAt: .now,
            eventLocation: nil, imageData: nil, owner: owner
        )
        invalid.mainEventStartsAt = Date(timeIntervalSinceReferenceDate: .infinity)
        library.add(invalid, openAfterAdding: false)

        #expect(throws: EncodingError.self) {
            try MovieNightTourCoordinator.startOrResume(
                account: owner, library: library, persistence: persistence,
                store: store, localJSON: blueprintJSON
            )
        }
        #expect(library.workspaces.count == 2)
        #expect(library.workspaces.contains(where: { $0 === invalid }))
        #expect(library.selectedWorkspace?.mainEventID == previouslySelected.mainEventID)
        #expect(store.progress(accountID: owner.id) == nil)
        let context = ModelContext(persistence.container)
        #expect(try context.fetch(FetchDescriptor<WorkspaceRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
    }

    private func account(_ id: String) -> UserAccount {
        UserAccount(id: id, email: "\(id)@example.test", displayName: "Movie Host", role: .planner,
                    authenticationProvider: .password, createdAt: .now)
    }

    private var blueprintJSON: Data {
        Data(#"""
        {
          "catalogKey":"movie_night","revision":1,"contentHash":"offline-test",
          "definition":{
            "$schema":"https://gatherory.com/schemas/experience-blueprint-v1.json",
            "kind":"experience_blueprint","schemaVersion":1,
            "blueprint":{"id":"movie_night","revision":1,"name":"Movie Night"},
            "experienceDefaults":{"type":"custom"},"roles":[],
            "modules":[
              {"key":"event_tree","type":"experience_tree","version":2,"required":true,"config":{"mainEventType":"custom","children":[{"key":"snacks_catch_up","title":"Snacks & catch-up","purpose":"part_of_event","category":"other","scheduleProposal":{"anchor":"main_start","dayOffset":0,"localTime":"17:00"}}]}},
              {"key":"starter_ideas","type":"ideas","version":2,"required":true,"config":{"categoryOrder":["event","food","other"],"ideas":[
                {"key":"watch_movie","title":"Watch the movie","category":"event","notes":"Choose together.","target":{"kind":"main"},"configuration":{"version":1}},
                {"key":"popcorn_bar","title":"Popcorn bar","category":"food","notes":"Pick toppings.","target":{"kind":"main"},"configuration":{"version":1}},
                {"key":"pizza","title":"Pizza","category":"food","target":{"kind":"main"},"configuration":{"version":1}},
                {"key":"blanket_corner","title":"Blanket corner","category":"other","notes":"Get cozy.","target":{"kind":"main"},"configuration":{"version":1}}
              ]}},
              {"key":"guest_guidance","type":"instructions","version":1,"required":true,"config":{"sections":[]}}
            ]
          }
        }
        """#.utf8)
    }
}
