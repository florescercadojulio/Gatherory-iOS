import SwiftUI

struct BlueprintExploreView: View {
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blueprintPreviewPresented) private var previewPresented
    @Namespace private var blueprintTransition
    @State private var model: BlueprintDiscoveryModel
    @State private var feed: BlueprintCatalogFeedModel
    @State private var discoveryContextStore: BlueprintDiscoveryContextStore
    @State private var adSession: ExploreAdSession
    @State private var actions: BlueprintActionStore?
    private let discoveryContextDefaults: UserDefaults
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var navigation = BlueprintDiscoveryNavigation()
    @State private var isAccountPresented = false
#if DEBUG
    @State private var searchVisualFixture: BlueprintSearchVisualFixture?
    @State private var discoveryRequestCount = 0
    @State private var discoveryFirstPageRequests = 0
    @State private var lastDiscoveryRequestContext: BlueprintDiscoveryRequestContext? = nil
#endif
    private let searchVisualFixtureEnabled: Bool
    private let discoverySessionFixtureEnabled: Bool
    private let adsScrollVerificationEnabled: Bool
    @FocusState private var isFocused: Bool
    private let ownerID: String
    let isActive: Bool

    init(ownerID: String, isActive: Bool = true) {
        self.ownerID = ownerID
        self.isActive = isActive
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let adsVerificationEnabled = arguments.contains("-BlueprintAdsScrollVerification")
        let sessionFixtureEnabled = arguments.contains("-BlueprintDiscoverySessionFixture")
        let fixtureEnabled = arguments.contains("-BlueprintSearchVisualFixture") || adsVerificationEnabled || sessionFixtureEnabled
        let localDefaults: UserDefaults
        if sessionFixtureEnabled {
            guard let isolatedDefaults = UserDefaults(suiteName: "BlueprintDiscoverySessionFixture-\(UUID().uuidString)") else {
                preconditionFailure("Unable to create isolated discovery fixture storage")
            }
            localDefaults = isolatedDefaults
        } else {
            localDefaults = .standard
        }
        searchVisualFixtureEnabled = fixtureEnabled
        discoverySessionFixtureEnabled = sessionFixtureEnabled
        adsScrollVerificationEnabled = adsVerificationEnabled
        _searchVisualFixture = State(initialValue: fixtureEnabled ? BlueprintSearchVisualFixture.load() : nil)
#else
        searchVisualFixtureEnabled = false
        discoverySessionFixtureEnabled = false
        adsScrollVerificationEnabled = false
        let localDefaults = UserDefaults.standard
#endif
        _model = State(initialValue: BlueprintDiscoveryModel(ownerID: ownerID))
        _feed = State(initialValue: BlueprintCatalogFeedModel(ownerID: ownerID))
        _discoveryContextStore = State(initialValue: BlueprintDiscoveryContextStore(
            accountID: ownerID, defaults: localDefaults
        ))
        discoveryContextDefaults = localDefaults
        // A local opaque scope keeps the ad inventory isolated without sending
        // an account, category, query, or event value to the ad SDK.
        _adSession = State(initialValue: ExploreAdSession(scopeID: UUID().uuidString))
    }

    private var mode: BlueprintSearchMode { navigation.mode(isFocused: isSearchActive || isFocused, query: query) }
    private var accountStateID: String { String(describing: cloudSync.accountOnboardingState) }
    private var catalogTaskID: String {
        "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(mode)|\(query)"
    }
    private var adTaskID: String {
        "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(mode == .browse)|\(navigation.selection?.entry.id ?? "")|\(previewPresented.wrappedValue)|\(isAccountPresented)"
    }
    private var actionsTaskID: String {
        "actions|\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)"
    }
    private var measurementIsActive: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && !previewPresented.wrappedValue && !isAccountPresented && !searchVisualFixtureEnabled
    }
    private var localHistoryIsActive: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && !previewPresented.wrappedValue && !isAccountPresented && mode == .browse
            && !ownerID.isEmpty && (!searchVisualFixtureEnabled || discoverySessionFixtureEnabled)
    }
    private var feedAdsAreEligible: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && !previewPresented.wrappedValue && !isAccountPresented && mode == .browse
            && (!searchVisualFixtureEnabled || adsScrollVerificationEnabled)
    }
    private var feedAdLayoutIsEnabled: Bool {
        mode == .browse && (!searchVisualFixtureEnabled || adsScrollVerificationEnabled)
    }
    private var measurementScopeID: String {
        "\(catalogTaskID)|account:\(isAccountPresented)"
    }

    var body: some View {
        lifecycleSurface.alert(BlueprintCopy.actionUpdateFailed, isPresented: Binding(
            get: { actions?.error != nil },
            set: { if !$0 { actions?.clearError() } }
        )) {
            Button(AppCopy.Common.retry) { Task { await actions?.retryLastAction() } }
            Button(AppCopy.Common.cancel, role: .cancel) { actions?.clearError() }
        } message: {
            Text(actions?.error?.localizedDescription ?? BlueprintCopy.actionUpdateFailed)
        }
    }

    private var contentSurface: some View {
        pagedGrid(
            source: mode == .recent ? .recent : .results,
            itemsHeader: mode == .recent ? AnyView(recentHeading) : nil
        )
        .background(AppTheme.ColorToken.background)
        .navigationTitle(ExploreCopy.searchTitle)
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            if navigation.selection == nil {
                if mode == .browse {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(ExploreCopy.refresh, systemImage: "arrow.clockwise") {
                            Task { await refreshPagedSurface(startNewDiscoverySession: true) }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(feed.isLoading)
                        .accessibilityIdentifier("blueprint.discovery.refresh")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton(blueprintActionStore: actions,
                        onPresentationChange: { isAccountPresented = $0 },
                        onDismiss: { Task { await refreshAfterAccountPresentation() } })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ExploreAdvertisingPrivacyButton(session: adSession)
                }
            }
        }
        .searchable(
            text: $query,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: ExploreCopy.search
        )
        .searchFocused($isFocused)
        .onSubmit(of: .search) { Task { await submitSearch() } }
        .onChange(of: isSearchActive) { _, active in
            if !active {
                query = ""
                isFocused = false
            }
        }
    }

    private var previewSurface: some View {
        contentSurface
        .fullScreenCover(item: $navigation.selection, onDismiss: { handlePreviewDismissal() }) { selection in
            BlueprintPreviewView(entry: selection.entry, actionStore: actions)
                .navigationTransition(.zoom(sourceID: selection.id, in: blueprintTransition))
                .toolbar(.visible, for: .navigationBar)
                .onAppear { model.recordAccess(selection.entry) }
        }
        .onChange(of: navigation.selection?.id) { _, selected in
            handlePreviewSelectionChange(selected)
        }
        .onChange(of: isFocused) { _, focused in
            handleFocusChange(focused)
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase)
        }
        .onChange(of: isActive) { _, active in
            handleActiveChange(active)
        }
        .onChange(of: ownerID) { _, newOwnerID in
            handleOwnerChange(newOwnerID)
        }
        .onChange(of: accountStateID) { _, _ in
            handleAccountStateChange()
        }
    }

    private var lifecycleSurface: some View {
        previewSurface
        .task(id: actionsTaskID) { await loadActionsForCurrentAccount() }
        .task(id: catalogTaskID) { await loadCatalogForCurrentSurface() }
        .task(id: adTaskID) { await prepareAdSessionIfNeeded() }
        .onDisappear {
            if navigation.selection != nil || previewPresented.wrappedValue {
                adSession.suspendForCoveredPreview()
            } else { resetAdSession() }
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            if discoverySessionFixtureEnabled {
                Text("")
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Discovery session audit")
                    .accessibilityIdentifier("blueprint.discovery.session")
                    .accessibilityValue(discoverySessionAuditValue)
                    .allowsHitTesting(false)
            }
        }
#endif
    }

#if DEBUG
    private var discoverySessionAuditValue: String {
        let value: [String: Any] = [
            "sessionId": discoveryContextStore.session?.sessionId.uuidString ?? "",
            "seenKeys": discoveryContextStore.liveSeenKeys,
            "contextSeenKeys": lastDiscoveryRequestContext?.seen.map(\.catalogKey) ?? [],
            "requestCount": discoveryRequestCount,
            "firstPageRequests": discoveryFirstPageRequests
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
#endif

    private func handlePreviewSelectionChange(_ selected: BlueprintPreviewTransitionID?) {
        if selected != nil { adSession.suspendForCoveredPreview() }
    }

    private func handlePreviewDismissal() {
        // Item selection becomes nil before the cover's dismissal completes.
        // Resume only after UIKit has actually uncovered the feed.
        previewPresented.wrappedValue = false
        adSession.resumeFromCoveredPreview()
        if navigation.restoresSearchFocus {
            isSearchActive = true
            query = navigation.retainedQuery ?? query
            if isFocused { navigation.completeReturn() }
            else { isFocused = true }
        } else {
            navigation.completeReturn()
        }
    }

    private func handleFocusChange(_ focused: Bool) {
        if focused {
            isSearchActive = true
            navigation.completeReturn()
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .background { discoveryContextStore.markAway() }
        if phase != .active { resetAdSession() }
    }

    private func handleActiveChange(_ active: Bool) {
        if !active { discoveryContextStore.markAway() }
        if !active { resetAdSession() }
    }

    private func handleOwnerChange(_ newOwnerID: String) {
        discoveryContextStore.invalidate()
        model = BlueprintDiscoveryModel(ownerID: newOwnerID)
        feed = BlueprintCatalogFeedModel(ownerID: newOwnerID)
        discoveryContextStore = BlueprintDiscoveryContextStore(
            accountID: newOwnerID, defaults: discoveryContextDefaults
        )
        resetAdSession()
        navigation = BlueprintDiscoveryNavigation()
        actions?.resetForAccountChange()
        actions = nil
        query = ""
        isSearchActive = false
        isFocused = false
    }

    private func handleAccountStateChange() {
        discoveryContextStore.invalidate()
        model = BlueprintDiscoveryModel(ownerID: ownerID)
        feed = BlueprintCatalogFeedModel(ownerID: ownerID)
        discoveryContextStore = BlueprintDiscoveryContextStore(
            accountID: ownerID, defaults: discoveryContextDefaults
        )
        resetAdSession()
        actions?.resetForAccountChange()
        actions = nil
    }

    private func loadActionsForCurrentAccount() async {
#if DEBUG
        if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: ownerID) {
            actions = fixture.actionStore
            await fixture.prepareActions()
            return
        }
#endif
        guard !searchVisualFixtureEnabled, isActive, scenePhase == .active, !ownerID.isEmpty,
              let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else { return }
        let store: BlueprintActionStore
        if let actions, actions.ownerID == ownerID {
            store = actions
        } else {
            store = BlueprintActionStore(ownerID: ownerID, transport: coordinator)
        }
        actions = store
        await store.loadPreferences()
        await store.loadMeasurementSetting()
        guard !Task.isCancelled, isActive, scenePhase == .active else { return }
    }

    private func loadCatalogForCurrentSurface() async {
        guard isActive, scenePhase == .active, navigation.selection == nil else { return }
        if mode == .results {
            let scope = BlueprintCatalogFeedScope.search(query)
            if feed.scope != scope { feed.activate(scope) }
            do { try await Task.sleep(nanoseconds: 275_000_000) } catch { return }
            guard !Task.isCancelled else { return }
        }
        if mode == .browse, !ownerID.isEmpty {
            let priorSessionID = discoveryContextStore.session?.sessionId
            let current = discoveryContextStore.beginOrResumeSession()
            if priorSessionID != nil, current?.sessionId != priorSessionID, feed.hasLoadedFirstPage {
                await refreshPagedSurface()
                return
            }
        }
        await loadCurrentSurface()
    }

    private func prepareAdSessionIfNeeded() async {
        if navigation.selection != nil || previewPresented.wrappedValue {
            adSession.suspendForCoveredPreview()
            return
        }
        guard feedAdsAreEligible else { resetAdSession(); return }
        adSession.resumeFromCoveredPreview()
        // The organic page can render while consent and SDK startup run.
        await adSession.prepare()
    }

    private var recentHeading: some View {
        HStack {
            Text(ExploreCopy.recent)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !model.recentEntries.isEmpty {
                Button(ExploreCopy.clear) { model.clearRecents() }
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pagedGrid(
        source: BlueprintCatalogSource,
        itemsHeader: AnyView? = nil
    ) -> some View {
        let isRecent = source == .recent
        let entries: [BlueprintCatalogEntry]
        if isRecent {
            entries = model.recentEntries
        } else {
            let candidateEntries = navigation.entries(for: source, fallback: feed.entries)
            entries = mode == .results ? candidateEntries : candidateEntries.filter {
                !(actions?.states[$0.catalogKey]?.notInterested ?? $0.viewerState?.notInterested ?? false)
            }
        }
        let isLoading = isRecent ? model.loading : feed.isLoading
        let isExhausted = isRecent || feed.isExhausted
        let loadFailed = isRecent ? model.loadFailed : feed.loadFailed
        let scope = isRecent ? BlueprintCatalogFeedScope.all : (feed.scope ?? .all)
        let exposureStore = discoveryContextStore
        let exposureGeneration = exposureStore.callbackGeneration
        let exposureAccountID = ownerID

        return BlueprintPagedCatalogGrid(
            entries: entries,
            source: source,
            transitionNamespace: blueprintTransition,
            scope: scope,
            adSession: !isRecent && feedAdLayoutIsEnabled ? adSession : nil,
            isLoading: isLoading,
            isExhausted: isExhausted,
            loadFailed: loadFailed,
            onSelect: { open($0, source: source, entries: entries) },
            onLoadMore: { if !isRecent { Task { await loadNextPage() } } },
            onRetry: {
                Task {
                    if isRecent { await loadRecentCatalog() }
                    else { await refreshPagedSurface() }
                }
            },
            actionStore: actions,
            itemsHeader: itemsHeader,
            measurementIsActive: !isRecent && measurementIsActive,
            localExposureIsActive: !isRecent && localHistoryIsActive,
            measurementScopeID: measurementScopeID,
            onMeaningfulExposure: mode == .browse && !isRecent ? { catalogKey in
                exposureStore.recordSeen(catalogKey: catalogKey, accountID: exposureAccountID,
                                         generation: exposureGeneration)
            } : nil
        )
        .overlay {
            if !isLoading && entries.isEmpty {
                ContentUnavailableView(
                    loadFailed ? ExploreCopy.unavailable : (isRecent ? ExploreCopy.noRecents : (mode == .results ? ExploreCopy.noResults : ExploreCopy.emptyCategory)),
                    systemImage: loadFailed ? "wifi.exclamationmark" : "magnifyingglass",
                    description: Text(loadFailed ? ExploreCopy.connection : (isRecent ? ExploreCopy.recentsHint : (mode == .results ? ExploreCopy.tryAnotherSearch : ExploreCopy.checkBack)))
                )
                .allowsHitTesting(false)
            }
        }
        .refreshable {
            if isRecent { await loadRecentCatalog() }
            else { await refreshPagedSurface(startNewDiscoverySession: mode == .browse) }
        }
    }

    private func submitSearch() async {
        isSearchActive = true
        guard mode == .results else { return }
        let requestedScope = BlueprintCatalogFeedScope.search(query)
        if feed.scope != requestedScope { feed.activate(requestedScope) }
        await feed.refresh(fetch: fetchPage)
    }

    private func open(_ entry: BlueprintCatalogEntry, source: BlueprintCatalogSource,
                      entries: [BlueprintCatalogEntry]) {
        if source != .recent, let actions { Task { await actions.record(.open, for: entry) } }
        previewPresented.wrappedValue = true
        navigation.open(entry, from: source, entries: entries, mode: mode, query: query)
    }

    private func resetAdSession() {
        adSession.reset()
        adSession = ExploreAdSession(scopeID: UUID().uuidString)
    }

    private func loadCurrentSurface() async {
        guard isActive, scenePhase == .active else { return }
        switch mode {
        case .browse:
            await activateAndLoad(.all)
        case .results:
            await activateAndLoad(.search(query))
        case .recent:
            if model.entries.isEmpty || model.loadFailed { await loadRecentCatalog() }
        }
    }

    private func activateAndLoad(_ scope: BlueprintCatalogFeedScope) async {
        if feed.scope != scope { feed.activate(scope) }
        if !feed.hasLoadedFirstPage || feed.loadFailed {
            await feed.loadNextPage(fetch: fetchPage)
        }
    }

    private func loadNextPage() async {
        guard isActive, scenePhase == .active else { return }
        await feed.loadNextPage(fetch: fetchPage)
    }

    private func refreshPagedSurface(startNewDiscoverySession: Bool = false) async {
        guard isActive, scenePhase == .active else { return }
        let scope: BlueprintCatalogFeedScope = mode == .results ? .search(query) : .all
        if feed.scope != scope { feed.activate(scope) }
        if mode == .browse, !ownerID.isEmpty {
            discoveryContextStore.beginOrResumeSession(forceNew: startNewDiscoverySession)
        }
        await feed.refresh(fetch: fetchPage)
    }

    private func refreshAfterAccountPresentation() async {
        guard !searchVisualFixtureEnabled, isActive, scenePhase == .active, !ownerID.isEmpty,
              let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else { return }
        let store: BlueprintActionStore
        if let actions, actions.ownerID == ownerID {
            store = actions
        } else {
            store = BlueprintActionStore(ownerID: ownerID, transport: coordinator)
            actions = store
        }
        let sessionIdentity = store.sessionIdentity
        await store.loadPreferences()
        await store.loadMeasurementSetting()
        guard !Task.isCancelled, isActive, scenePhase == .active,
              store.isCurrentSession(sessionIdentity), store.ownerID == ownerID else { return }
        if mode == .recent { await loadRecentCatalog() }
        else { await refreshPagedSurface() }
    }

    private func fetchPage(cursor: String?, category: String?, query: String?) async throws -> BlueprintCatalogResponse {
#if DEBUG
        if searchVisualFixtureEnabled {
            guard let searchVisualFixture else { throw BlueprintSearchVisualFixture.Failure.unavailable }
#if DEBUG
            if discoverySessionFixtureEnabled {
                discoveryRequestCount += 1
                if cursor == nil { discoveryFirstPageRequests += 1 }
                lastDiscoveryRequestContext = query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? nil
                    : discoveryContextStore.beginOrResumeSession()
            }
#endif
            return try searchVisualFixture.page(cursor: cursor, query: query)
        }
#endif
        guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
            throw CloudSyncFailure.invalidSession
        }
        let requestStore = discoveryContextStore
        let context = query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? nil
            : requestStore.beginOrResumeSession()
        do {
            return try await coordinator.catalogPage(
                cursor: cursor,
                limit: BlueprintCatalogFeedModel.pageSize,
                category: category,
                query: query,
                discoveryContext: context
            )
        } catch {
            if query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               let failure = error as? CloudSyncFailure,
               case .server("BLUEPRINT_CATALOG_CURSOR_STALE") = failure {
                requestStore.beginOrResumeSession(forceNew: true)
            }
            throw error
        }
    }

    private func loadRecentCatalog() async {
        guard isActive, scenePhase == .active else { return }
#if DEBUG
        if searchVisualFixtureEnabled {
            await model.load {
                guard let searchVisualFixture else { throw BlueprintSearchVisualFixture.Failure.unavailable }
                return searchVisualFixture.response
            }
            return
        }
#endif
        await model.load {
            guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
                throw CloudSyncFailure.invalidSession
            }
            return try await coordinator.catalog()
        }
    }
}

#if DEBUG
private struct BlueprintSearchVisualFixture {
    enum Failure: Error {
        case unavailable
        case invalidCursor
    }

    let response: BlueprintCatalogResponse

    static func load() -> Self? {
        guard let url = Bundle.main.url(
            forResource: "blueprint-search-visual-catalog.v1",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url),
           let source = try? JSONDecoder().decode(BlueprintCatalogResponse.self, from: data),
           let sample = source.entries.first else { return nil }

        let categories: [BlueprintBrowseCategory] = [.weddings, .birthdays, .trips, .dinnerParties, .cottageStays, .picnics]
        let titles = ["Wedding", "A garden wedding celebration with family and friends", "A weekend wedding by the lake"]
        let entries = (1...40).map { index in
            var definition = sample.definition
            if let encoded = try? JSONEncoder().encode(definition),
               var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any],
               var identity = object["blueprint"] as? [String: Any] {
                identity["name"] = titles[(index - 1) % titles.count]
                object["blueprint"] = identity
                if let data = try? JSONSerialization.data(withJSONObject: object),
                   let decoded = try? JSONDecoder().decode(ExperienceBlueprintDocument.self, from: data) {
                    definition = decoded
                }
            }
            return BlueprintCatalogEntry(
                catalogKey: "\(sample.catalogKey)-visual-\(index)",
                revision: sample.revision,
                contentHash: sample.contentHash,
                definition: definition,
                discovery: BlueprintDiscoveryMetadata(
                    categories: [categories[(index - 1) % categories.count].rawValue],
                    tags: sample.discovery?.tags ?? [], summary: sample.discovery?.summary ?? "",
                    coverImageURL: sample.discovery?.coverImageURL
                ),
                description: sample.description,
                creator: index.isMultiple(of: 3) ? .init(displayName: "Gatherory visual fixture") : nil,
                viewerState: ProcessInfo.processInfo.arguments.contains("-BlueprintPreviewActionsVisualFixture") ? .init() : nil,
                discoveryContext: nil
            )
        }
        return Self(response: BlueprintCatalogResponse(entries: entries))
    }

    func page(cursor: String?, query: String?) throws -> BlueprintCatalogResponse {
        let filteredEntries: [BlueprintCatalogEntry]
        guard let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            filteredEntries = response.entries
            return try page(filteredEntries, cursor: cursor)
        }
        filteredEntries = response.entries.filter { $0.matches(query: query) }
        return try page(filteredEntries, cursor: cursor)
    }

    private func page(_ entries: [BlueprintCatalogEntry], cursor: String?) throws -> BlueprintCatalogResponse {
        let pageIndex: Int
        switch cursor {
        case nil: pageIndex = 0
        case "blueprint-visual-v1-page-2": pageIndex = 1
        default: throw Failure.invalidCursor
        }
        let lowerBound = pageIndex * BlueprintCatalogFeedModel.pageSize
        guard lowerBound <= entries.count else { throw Failure.invalidCursor }
        let upperBound = min(lowerBound + BlueprintCatalogFeedModel.pageSize, entries.count)
        let nextCursor = upperBound < entries.count ? "blueprint-visual-v1-page-2" : nil
        return BlueprintCatalogResponse(
            entries: Array(entries[lowerBound..<upperBound]),
            nextCursor: nextCursor
        )
    }
}
#endif
