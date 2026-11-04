#if DEBUG
import Foundation
import Observation

/// Account-free fixture for checking how public, collection, personal, and
/// shared Blueprint previews expose different actions.
@MainActor
enum BlueprintPreviewActionsVisualFixture {
    enum Context: String, Equatable, Sendable {
        case discovery
        case collection
        case personal
        case sharedLink = "shared"
        case movieNight
    }

    /// A single in-memory session shared by preview and library presentation.
    /// Keeping the action store here lets a bookmark made in discovery appear
    /// in Saved without reading or writing any real account files.
    @MainActor @Observable
    final class State {
        let entry: BlueprintCatalogEntry
        let context: Context
        let actionStore: BlueprintActionStore
        let personalSource: BlueprintPersonalRecord?
        let draftStore: BlueprintSetupDraftStore
        private let installationCache: BlueprintLibraryCache
        var savedDraft: BlueprintSetupDraft?
        var workingDraft: BlueprintSetupDraft?

        private var didPrepareActions = false
        private var didSeedSetupDraft = false
        private var setupPersistence: WorkspacePersistenceController?
        private var setupCoordinator: BlueprintInstallationCoordinator?
        private var installationLibrary: WorkspaceLibrary?
        private var fixtureScopeID = UUID()
        private var fixtureArchive: Data?

        fileprivate init(ownerID: String, source: BlueprintCatalogEntry, context: Context) {
            let initialViewerState: BlueprintViewerState? = switch context {
            case .discovery, .movieNight: BlueprintViewerState()
            case .collection: BlueprintViewerState(bookmarked: true)
            case .personal, .sharedLink: nil
            }
            let entry = Self.copy(source,
                                  catalogKey: context == .movieNight ? source.catalogKey
                                    : context == .personal ? "visual_personal" : "\(source.catalogKey)-visual-1",
                                  viewerState: initialViewerState,
                                  discoveryContext: context == .discovery
                                    ? BlueprintDiscoveryContext(exposureId: "visual-preview-actions", expiresAt: .now.addingTimeInterval(3_600))
                                    : nil)
            self.entry = entry
            self.context = context

            let transport = BlueprintPreviewActionsVisualTransport(entry: entry,
                initialState: initialViewerState ?? BlueprintViewerState())
            self.actionStore = BlueprintActionStore(ownerID: ownerID, transport: transport)
            self.personalSource = context == .personal
                ? BlueprintPersonalRecord(id: BlueprintPreviewActionsVisualFixture.personalRecordID, draftVersion: 1,
                                          publishedRevision: entry.revision, listedRevision: nil,
                                          creatorName: "You", activeShareLinkCount: 0, catalogEntry: entry)
                : nil

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gatherory-blueprint-preview-actions-\(UUID().uuidString)", isDirectory: true)
            self.draftStore = BlueprintSetupDraftStore(directoryURL: directory)
            self.installationCache = BlueprintLibraryCache(directoryURL: directory.appendingPathComponent("history"))
            let initialDraft = context == .personal ? Self.makeSavedDraft(ownerID: ownerID, entry: entry) : nil
            self.savedDraft = initialDraft
            self.workingDraft = initialDraft
            if let initialDraft { try? draftStore.save(initialDraft) }
        }

        /// Loads the real store through its normal transport contract exactly
        /// once. Measurement remains disabled in the fixture transport.
        func prepareActions() async {
            guard !didPrepareActions else { return }
            didPrepareActions = true
            await actionStore.loadPreferences()
            await actionStore.loadMeasurementSetting()
        }

        func saveWorkingDraft(_ draft: BlueprintSetupDraft) throws {
            if didSeedSetupDraft, let existing = try reloadSavedDraft() {
                // Reopening Use must keep SetupView's confirmed dates and request identity.
                workingDraft = existing
                return
            }
            try draftStore.save(draft)
            savedDraft = draft
            workingDraft = draft
        }

        func reloadSavedDraft() throws -> BlueprintSetupDraft? {
            guard let loaded = try draftStore.load(ownerUserID: actionStore.ownerID,
                                                  catalogKey: entry.catalogKey)
            else { return savedDraft }
            savedDraft = loaded
            workingDraft = loaded
            return loaded
        }

        /// Supplies the existing SetupView path with an explicitly unconfirmed draft.
        /// The UI fixture never turns suggested dates into confirmed dates for the user.
        func prepareSetupDraftForDirectInstall() throws {
            guard context == .discovery || context == .personal || context == .movieNight else { return }
            let children = entry.definition.modules.first { $0.type == "experience_tree" }?
                .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
            let ideas = entry.definition.modules.first { $0.type == "ideas" }?
                .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
            if didSeedSetupDraft, try reloadSavedDraft() != nil {
                BlueprintSetupFixtureURLProtocol.configure(childKeys: children.map(\.key))
                return
            }
            let draft = BlueprintSetupDraft(ownerUserID: actionStore.ownerID, entry: entry,
                requestID: UUID(), eventName: context == .movieNight ? entry.definition.blueprint.name : "My celebration",
                startsAt: Date(timeIntervalSince1970: 1_798_200_000),
                timeZoneIdentifier: "America/Detroit", selectedChildren: Set(children.prefix(1).map(\.key)),
                selectedIdeas: Set(ideas.map(\.key)), confirmedDates: [:])
            try draftStore.save(draft)
            savedDraft = draft
            workingDraft = draft
            didSeedSetupDraft = true
            BlueprintSetupFixtureURLProtocol.configure(childKeys: children.map(\.key))
        }

        func makeSetupDraftStore() -> BlueprintSetupDraftStore { draftStore }

        /// Creates the production coordinator with a local protocol fixture. The
        /// fixture answers copy, schedule, installation receipt, and bootstrap using
        /// the same transport and import path as the app. Its audit stays local.
        func makeInstallationCoordinator(library: WorkspaceLibrary, account: UserAccount) -> BlueprintInstallationCoordinator? {
            guard account.id == actionStore.ownerID else { return nil }
            if let setupCoordinator, installationLibrary === library { return setupCoordinator }
            do {
                let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
                _ = persistence.restoreLibrary(seedData: false, ownerUserID: actionStore.ownerID)
                library.configureViewer(account)

                let workspace = PlanningWorkspace.newWorkspace(title: context == .movieNight ? entry.definition.blueprint.name : "My celebration",
                    startsAt: Date(timeIntervalSince1970: 1_798_200_000), timeZoneIdentifier: "America/Detroit",
                    eventLocation: nil, imageData: nil, owner: account)
                let children = entry.definition.modules.first { $0.type == "experience_tree" }?
                    .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
                workspace.timeline = children.prefix(1).map { child in
                    TimelineItem(title: child.title, category: TimelineCategory(rawValue: child.category) ?? .other,
                        purpose: child.purpose == "part_of_event" ? .eventExperience : .planning,
                        scheduledAt: Date(timeIntervalSince1970: 1_798_200_000),
                        location: "", timeZoneIdentifier: "America/Detroit", participantIDs: workspace.mainEventParticipantIDs,
                        parentEventID: workspace.mainEventID)
                }
                let ideas = entry.definition.modules.first { $0.type == "ideas" }?
                    .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
                for idea in ideas {
                    workspace.addIdea(PlanningIdea(eventID: workspace.mainEventID, title: idea.title, note: idea.notes ?? "",
                        category: IdeaCategory(rawValue: idea.category) ?? .other, submittedBy: account.displayName,
                        submittedByUserID: account.id))
                }
                fixtureScopeID = workspace.mainEventID
                fixtureArchive = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: workspace))
                BlueprintSetupFixtureURLProtocol.configure(entry: entry, scopeID: fixtureScopeID,
                    archive: fixtureArchive!, ownerID: account.id, displayName: account.displayName,
                    failFirstInstall: ProcessInfo.processInfo.arguments.contains("-BlueprintSetupFixtureRetryOnce"))

                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [BlueprintSetupFixtureURLProtocol.self]
                let session = URLSession(configuration: configuration)
                let transport = PostgresSyncTransport(baseURL: URL(string: "https://setup-fixture.invalid")!,
                    urlSession: session, tokenStore: BlueprintSetupFixtureTokenStore())
                let coordinator = BlueprintInstallationCoordinator(
                    baseURL: URL(string: "https://setup-fixture.invalid")!, persistence: persistence,
                    library: library,
                    intents: BlueprintInstallationIntentStore(directoryURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("gatherory-blueprint-setup-intents-\(UUID().uuidString)", isDirectory: true)),
                    setupDrafts: draftStore, transport: transport, libraryCache: installationCache)
                setupPersistence = persistence
                setupCoordinator = coordinator
                installationLibrary = library
                return coordinator
            } catch {
                return nil
            }
        }

        private static func copy(_ source: BlueprintCatalogEntry, catalogKey: String,
                                 viewerState: BlueprintViewerState?,
                                 discoveryContext: BlueprintDiscoveryContext?) -> BlueprintCatalogEntry {
            BlueprintCatalogEntry(catalogKey: catalogKey, revision: source.revision,
                                  contentHash: source.contentHash, definition: source.definition,
                                  discovery: source.discovery, description: source.description,
                                  creator: source.creator, viewerState: viewerState,
                                  discoveryContext: discoveryContext)
        }

        private static func makeSavedDraft(ownerID: String, entry: BlueprintCatalogEntry) -> BlueprintSetupDraft {
            let children = entry.definition.modules.first { $0.type == "experience_tree" }?
                .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
            let ideas = entry.definition.modules.first { $0.type == "ideas" }?
                .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
            return BlueprintSetupDraft(ownerUserID: ownerID, entry: entry, requestID: UUID(),
                                       eventName: "My celebration", startsAt: Date(timeIntervalSince1970: 1_798_200_000),
                                       timeZoneIdentifier: "America/Detroit",
                                       selectedChildren: Set(children.map(\.key)), selectedIdeas: Set(ideas.map(\.key)),
                                       confirmedDates: [:])
        }
    }

    static let personalRecordID = UUID(uuidString: "51000000-0000-4000-8000-000000000001")!

    private static var statesByOwner: [String: State] = [:]

    /// Returns a session-scoped fixture only for the explicit, isolated UI-test
    /// launch. Its catalog comes from the app's real bundled schema fixture.
    static func load(ownerID: String) -> State? {
        let arguments = ProcessInfo.processInfo.arguments
        let movieNightUITest = arguments.contains("-MovieNightOnboardingUITest")
        guard (arguments.contains("-BlueprintPreviewActionsVisualFixture") || movieNightUITest),
              AppRuntimeConfiguration.usesEphemeralDataStore,
              AppRuntimeConfiguration.environment == .development,
              AppRuntimeConfiguration.skipsAuthentication,
              !ownerID.isEmpty,
              movieNightUITest || AppRuntimeConfiguration.seedsDevelopmentData,
              let contextAndSource = fixtureContextAndSource(arguments: arguments, movieNightUITest: movieNightUITest)
        else { return nil }

        if let state = statesByOwner[ownerID] { return state }
        if movieNightUITest {
            // A fresh ephemeral fixture models a first-time account on each
            // launch; production progress remains durable and account-bound.
            MovieNightTourStore().clear(accountID: ownerID)
        }
        let state = State(ownerID: ownerID, source: contextAndSource.source, context: contextAndSource.context)
        statesByOwner[ownerID] = state
        return state
    }

    static func movieNightCatalogEntry(ownerID: String) -> BlueprintCatalogEntry? {
        guard ProcessInfo.processInfo.arguments.contains("-MovieNightOnboardingUITest"),
              let state = load(ownerID: ownerID), state.context == .movieNight else { return nil }
        return state.entry
    }

    private static func fixtureContextAndSource(
        arguments: [String], movieNightUITest: Bool
    ) -> (context: Context, source: BlueprintCatalogEntry)? {
        if movieNightUITest {
            guard let source = bundledMovieNightEntry() else { return nil }
            return (.movieNight, source)
        }
        guard let contextIndex = arguments.firstIndex(of: "-BlueprintPreviewFixtureContext"),
              arguments.indices.contains(contextIndex + 1),
              let context = Context(rawValue: arguments[contextIndex + 1]),
              context != .movieNight,
              let source = bundledCatalogEntry() else { return nil }
        return (context, source)
    }

    private static func bundledMovieNightEntry() -> BlueprintCatalogEntry? {
        guard let url = Bundle.main.url(forResource: "movie-night-blueprint.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(BlueprintCatalogEntry.self, from: data),
              entry.catalogKey == "movie_night" else { return nil }
        return entry
    }

    private static func bundledCatalogEntry() -> BlueprintCatalogEntry? {
        guard let url = Bundle.main.url(forResource: "blueprint-search-visual-catalog.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let response = try? JSONDecoder().decode(BlueprintCatalogResponse.self, from: data)
        else { return nil }
        return response.entries.first
    }
}

@MainActor
private final class BlueprintPreviewActionsVisualTransport: BlueprintActionsTransport {
    private let entry: BlueprintCatalogEntry
    private var states: [String: BlueprintViewerState]
    private var savedItems: [String: BlueprintSavedPreference] = [:]

    init(entry: BlueprintCatalogEntry, initialState: BlueprintViewerState) {
        self.entry = entry
        self.states = [entry.catalogKey: initialState]
        if initialState.liked || initialState.bookmarked || initialState.notInterested {
            savedItems[entry.catalogKey] = Self.preference(entry: entry, state: initialState)
        }
    }

    func update(_ mutation: BlueprintPreferenceMutation) async throws -> BlueprintPreferenceAcknowledgement {
        guard mutation.catalogKey == entry.catalogKey,
              mutation.revision == entry.revision,
              mutation.contentHash == entry.contentHash else { throw CloudSyncFailure.invalidResponse }
        let previous = states[mutation.catalogKey] ?? BlueprintViewerState()
        let next: BlueprintViewerState = switch mutation.kind {
        case .like:
            BlueprintViewerState(liked: mutation.enabled, bookmarked: previous.bookmarked,
                                 notInterested: previous.notInterested)
        case .bookmark:
            BlueprintViewerState(liked: previous.liked, bookmarked: mutation.enabled,
                                 notInterested: previous.notInterested)
        case .notInterested:
            BlueprintViewerState(liked: previous.liked, bookmarked: previous.bookmarked,
                                 notInterested: mutation.enabled)
        }
        states[mutation.catalogKey] = next
        if next.liked || next.bookmarked || next.notInterested {
            savedItems[mutation.catalogKey] = Self.preference(entry: entry, state: next)
        } else {
            savedItems.removeValue(forKey: mutation.catalogKey)
        }
        return BlueprintPreferenceAcknowledgement(requestId: mutation.requestId,
            catalogKey: mutation.catalogKey, revision: mutation.revision,
            contentHash: mutation.contentHash, liked: next.liked,
            bookmarked: next.bookmarked, notInterested: next.notInterested)
    }

    func preferences(cursor: String?) async throws -> BlueprintPreferencesPage {
        guard cursor == nil else { throw CloudSyncFailure.invalidResponse }
        return BlueprintPreferencesPage(items: savedItems.values.sorted { $0.catalogKey < $1.catalogKey })
    }

    func measurementSettings() async throws -> BlueprintMeasurementSettings {
        BlueprintMeasurementSettings(enabled: false)
    }

    func setMeasurementSettings(requestID: UUID, enabled: Bool) async throws -> BlueprintMeasurementSettings {
        BlueprintMeasurementSettings(enabled: false)
    }

    func record(_ signal: BlueprintMeasurementSignal) async throws { }

    private static func preference(entry: BlueprintCatalogEntry,
                                   state: BlueprintViewerState) -> BlueprintSavedPreference {
        BlueprintSavedPreference(catalogKey: entry.catalogKey, revision: entry.revision,
            contentHash: entry.contentHash, liked: state.liked, bookmarked: state.bookmarked,
            notInterested: state.notInterested,
            likeRevision: state.liked ? entry.revision : nil,
            likeContentHash: state.liked ? entry.contentHash : nil,
            bookmarkRevision: state.bookmarked ? entry.revision : nil,
            bookmarkContentHash: state.bookmarked ? entry.contentHash : nil,
            notInterestedRevision: state.notInterested ? entry.revision : nil,
            notInterestedContentHash: state.notInterested ? entry.contentHash : nil,
            likeAvailability: "available", bookmarkAvailability: "available",
            notInterestedAvailability: "available",
            entry: .init(name: entry.definition.blueprint.name,
                         coverImageURL: entry.discovery?.coverImageURL,
                         creatorName: entry.creator?.displayName))
    }
}

private struct BlueprintSetupFixtureTokenStore: SessionTokenStore {
    func read() throws -> String? { "isolated-blueprint-setup-fixture" }
    func save(_ token: String) throws { }
    func delete() { }
}

/// Local network fixture for the explicit SetupView UI fixture. All traffic is
/// handled in process and the journal is exposed through `auditSnapshot()`.
private final class BlueprintSetupFixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var childKeys: [String] = []
    nonisolated(unsafe) private static var entry: BlueprintCatalogEntry?
    nonisolated(unsafe) private static var ownerID = ""
    nonisolated(unsafe) private static var ownerDisplayName = ""
    nonisolated(unsafe) private static var scopeID = UUID()
    nonisolated(unsafe) private static var archive = Data()
    nonisolated(unsafe) private static var failFirstInstall = false
    nonisolated(unsafe) private static var installAttempts = 0
    nonisolated(unsafe) private static var firstFailedInstall: (requestID: String, body: Data, idempotencyKey: String)?
    nonisolated(unsafe) private static var audit: [[String: Any]] = []

    static func configure(childKeys: [String]) {
        lock.lock()
        self.childKeys = childKeys
        lock.unlock()
    }

    static func configure(entry: BlueprintCatalogEntry, scopeID: UUID, archive: Data,
                          ownerID: String, displayName: String, failFirstInstall: Bool) {
        lock.lock()
        self.entry = entry
        self.ownerID = ownerID
        self.ownerDisplayName = displayName
        self.scopeID = scopeID
        self.archive = archive
        self.failFirstInstall = failFirstInstall
        self.installAttempts = 0
        self.firstFailedInstall = nil
        self.audit = []
        self.childKeys = entry.definition.modules.first { $0.type == "experience_tree" }?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children.map(\.key) ?? []
        lock.unlock()
    }

    static func auditSnapshot() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return audit
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let result: (Int, Data?)
        switch path {
        case "/api/blueprints/schedule": result = (200, scheduleResponse())
        case "/api/blueprints/copies": result = (200, copyResponse())
        case "/api/blueprints/preview": result = (200, previewResponse())
        case "/api/blueprints/install": result = installResponse()
        case let path where path.hasPrefix("/api/blueprints/installations/"):
            result = (200, statusResponse())
        case "/api/sync/bootstrap": result = (200, bootstrapResponse())
        default: result = (503, nil)
        }
        let (status, body) = result
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }

    private func requestBodyData() -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }

    private func scheduleResponse() -> Data? {
        guard let input = requestBodyData(),
              let requestObject = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let mainEvent = requestObject["mainEvent"] as? [String: Any],
              let catalogKey = requestObject["catalogKey"] as? String,
              let revision = requestObject["revision"] as? Int,
              let contentHash = requestObject["contentHash"] as? String else { return nil }

        Self.lock.lock()
        let keys = Self.childKeys
        Self.lock.unlock()
        let formatter = ISO8601DateFormatter()
        let candidates: [String]
        if let startString = mainEvent["startsAt"] as? String,
           let start = formatter.date(from: startString) {
            candidates = [formatter.string(from: start.addingTimeInterval(3_600))]
        } else {
            candidates = []
        }
        let suggestions: [[String: Any]] = keys.map { key in
            ["key": key, "status": "suggested", "candidates": candidates]
        }
        let response: [String: Any] = ["catalogKey": catalogKey, "revision": revision,
            "contentHash": contentHash, "mainEvent": mainEvent, "suggestions": suggestions]
        return try? JSONSerialization.data(withJSONObject: response)
    }

    private func previewResponse() -> Data? {
        guard let input = requestBodyData(),
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let main = object["mainEvent"] as? [String: Any],
              let name = main["name"] as? String,
              let startsAt = main["startsAt"] as? String,
              let timeZone = main["timeZone"] as? String,
              let contentHash = object["contentHash"] as? String,
              let childrenInput = object["selectedChildren"] as? [[String: Any]],
              let ideaKeys = object["selectedIdeaKeys"] as? [String] else { return nil }
        Self.lock.lock()
        let source = Self.entry
        Self.audit.append(["operation": "preview", "requestId": object["requestId"] ?? "",
                           "mainEvent": main, "selectedChildren": childrenInput, "selectedIdeaKeys": ideaKeys])
        Self.lock.unlock()
        guard let source else { return nil }
        let children = source.definition.modules.first { $0.type == "experience_tree" }?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
        let ideas = source.definition.modules.first { $0.type == "ideas" }?
            .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
        let planChildren: [[String: Any]] = childrenInput.compactMap { selected in
            guard let key = selected["key"] as? String, let date = selected["startsAt"] as? String,
                  let child = children.first(where: { $0.key == key }) else { return nil }
            return ["sourceKey": key, "name": child.title,
                    "eventType": source.definition.experienceDefaults.type, "startsAt": date,
                    "timeZone": timeZone, "parentSourceKey": "main", "purpose": child.purpose,
                    "category": child.category, "planningStatus": "approved"]
        }
        let planIdeas: [[String: Any]] = ideaKeys.compactMap { key in
            guard let idea = ideas.first(where: { $0.key == key }) else { return nil }
            return ["sourceKey": key, "title": idea.title, "category": idea.category,
                    "notes": idea.notes ?? "", "targetSourceKey": "main", "configuration": [:], "status": "new"]
        }
        let categoryOrder = source.definition.modules.first { $0.type == "ideas" }?
            .decodeConfiguration(BlueprintIdeasConfig.self)?.categoryOrder ?? []
        let plan: [String: Any] = ["plannerVersion": 1, "experienceType": source.definition.experienceDefaults.type,
            "categoryOrder": categoryOrder,
            "main": ["sourceKey": "main", "name": name, "eventType": source.definition.experienceDefaults.type, "startsAt": startsAt,
                     "timeZone": timeZone, "parentSourceKey": NSNull(), "purpose": NSNull(),
                     "category": NSNull(), "planningStatus": NSNull()],
            "children": planChildren, "ideas": planIdeas, "instructions": [], "todos": [], "omissions": []]
        return try? JSONSerialization.data(withJSONObject: ["plan": plan, "contentHash": contentHash])
    }

    private func copyResponse() -> Data? {
        guard let input = requestBodyData(),
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let requestID = object["requestId"] as? String,
              let content = object["content"] as? [String: Any] else { return nil }
        guard let contentData = try? JSONSerialization.data(withJSONObject: content),
              let submitted = try? JSONDecoder().decode(BlueprintDraftContent.self, from: contentData) else { return nil }
        Self.lock.lock()
        guard let source = Self.entry else { Self.lock.unlock(); return nil }
        let catalogKey = "fixture-private-\(requestID.lowercased())"
        let definition = ExperienceBlueprintDocument(
            schema: source.definition.schema,
            kind: source.definition.kind,
            schemaVersion: source.definition.schemaVersion,
            blueprint: ExperienceBlueprintIdentity(id: source.definition.blueprint.id,
                revision: source.definition.blueprint.revision, name: submitted.name),
            experienceDefaults: source.definition.experienceDefaults,
            roles: source.definition.roles,
            modules: source.definition.modules,
            presentation: source.definition.presentation
        )
        let copied = BlueprintCatalogEntry(catalogKey: catalogKey, revision: 1,
            contentHash: source.contentHash, definition: definition, discovery: nil,
            description: submitted.description, creator: nil, viewerState: nil, discoveryContext: nil)
        let record = BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: 1,
            listedRevision: nil, creatorName: nil, activeShareLinkCount: 0, catalogEntry: copied)
        Self.audit.append(["operation": "copy", "requestId": requestID, "content": content,
                           "copiedCatalogKey": catalogKey, "copiedName": submitted.name,
                           "copiedDescription": submitted.description])
        NSLog("[BlueprintSetupFixture] %@", String(data: (try? JSONSerialization.data(withJSONObject: Self.audit.last ?? [:])) ?? Data(), encoding: .utf8) ?? "copy")
        Self.lock.unlock()
        return try? JSONEncoder().encode(record)
    }

    private func installResponse() -> (Int, Data?) {
        guard let input = requestBodyData(),
              let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let requestID = object["requestId"] as? String else { return (400, nil) }
        Self.lock.lock()
        Self.installAttempts += 1
        let attempt = Self.installAttempts
        let fail = Self.failFirstInstall && attempt == 1
        let idempotencyKey = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
        let idempotencyMatchesRequestID = idempotencyKey.lowercased() == requestID.lowercased()
        let exactBody = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        let retryMatches = Self.firstFailedInstall.map {
            $0.requestID == requestID && $0.body == exactBody && $0.idempotencyKey == idempotencyKey
                && idempotencyMatchesRequestID
        }
        if fail { Self.firstFailedInstall = (requestID, exactBody, idempotencyKey) }
        Self.audit.append(["operation": "install", "requestId": requestID, "attempt": attempt,
                           "body": object, "idempotencyKey": idempotencyKey,
                           "idempotencyMatchesRequestID": idempotencyMatchesRequestID,
                           "retryMatchesFailedAttempt": retryMatches.map { $0 as Any } ?? NSNull()])
        NSLog("[BlueprintSetupFixture] %@", String(data: (try? JSONSerialization.data(withJSONObject: Self.audit.last ?? [:])) ?? Data(), encoding: .utf8) ?? "install")
        Self.lock.unlock()
        if !idempotencyMatchesRequestID { return (400, Data("{}".utf8)) }
        if let retryMatches, !retryMatches { return (409, Data("{}".utf8)) }
        if !fail { applyInstallRequest(object) }
        return fail ? (503, Data("{}".utf8)) : (200, installationResult())
    }

    private func statusResponse() -> Data? {
        try? JSONSerialization.data(withJSONObject: ["state": "pending", "result": NSNull()])
    }

    private func installationResult() -> Data? {
        Self.lock.lock(); let scopeID = Self.scopeID; Self.lock.unlock()
        let value: [String: Any] = ["installationID": UUID().uuidString,
            "organizationID": "fixture-org", "scopeID": scopeID.uuidString]
        return try? JSONSerialization.data(withJSONObject: value)
    }

    private func bootstrapResponse() -> Data? {
        Self.lock.lock()
        let scopeID = Self.scopeID
        let archive = Self.archive
        Self.audit.append(["operation": "bootstrap", "scopeId": scopeID.uuidString])
        NSLog("[BlueprintSetupFixture] %@", String(data: (try? JSONSerialization.data(withJSONObject: Self.audit.last ?? [:])) ?? Data(), encoding: .utf8) ?? "bootstrap")
        Self.lock.unlock()
        let snapshot = RemoteWorkspaceSnapshot(scopeID: scopeID, payloadSchemaVersion: 1,
            payload: archive, serverVersion: 1, updatedAt: .now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(SyncBootstrapResponse(account: nil, snapshots: [snapshot], entities: []))
    }

    private func applyInstallRequest(_ object: [String: Any]) {
        guard let event = object["mainEvent"] as? [String: Any],
              let name = event["name"] as? String,
              let startString = event["startsAt"] as? String,
              let timeZone = event["timeZone"] as? String,
              let selectedChildren = object["selectedChildren"] as? [[String: Any]],
              let selectedIdeas = object["selectedIdeaKeys"] as? [String] else { return }
        let formatter = ISO8601DateFormatter()
        guard let start = formatter.date(from: startString) else { return }
        Self.lock.lock()
        let original = Self.archive
        let source = Self.entry
        let ownerID = Self.ownerID
        let ownerDisplayName = Self.ownerDisplayName
        Self.lock.unlock()
        guard var archive = try? WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: original),
              let source, !ownerID.isEmpty else { return }
        archive.title = name
        archive.mainEventStartsAt = start
        archive.mainEventTimeZoneIdentifier = timeZone
        let children = source.definition.modules.first { $0.type == "experience_tree" }?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self)?.children ?? []
        archive.timeline = selectedChildren.compactMap { selected in
            guard let key = selected["key"] as? String,
                  let child = children.first(where: { $0.key == key }),
                  let dateString = selected["startsAt"] as? String,
                  let date = formatter.date(from: dateString) else { return nil }
            return TimelineItem(title: child.title, category: TimelineCategory(rawValue: child.category) ?? .other,
                purpose: child.purpose == "part_of_event" ? .eventExperience : .planning,
                scheduledAt: date, location: "", timeZoneIdentifier: timeZone,
                participantIDs: archive.mainEventParticipantIDs, parentEventID: archive.mainEventID)
        }
        let ideas = source.definition.modules.first { $0.type == "ideas" }?
            .decodeConfiguration(BlueprintIdeasConfig.self)?.ideas ?? []
        archive.ideas = selectedIdeas.compactMap { key in
            guard let idea = ideas.first(where: { $0.key == key }) else { return nil }
            let category = IdeaCategory(rawValue: idea.category) ?? .other
            let configuration: IdeaConfiguration? = category == .event
                ? .event(EventIdeaConfiguration(category: .other, purpose: .planning,
                    proposedDate: nil, location: nil))
                : nil
            return PlanningIdea(eventID: archive.mainEventID, title: idea.title, note: idea.notes ?? "",
                category: category, submittedBy: ownerDisplayName, submittedByUserID: ownerID,
                configuration: configuration)
        }
        guard let updated = try? WorkspaceArchiveCodec().encode(archive) else { return }
        Self.lock.lock(); Self.archive = updated; Self.lock.unlock()
    }
}
#endif
