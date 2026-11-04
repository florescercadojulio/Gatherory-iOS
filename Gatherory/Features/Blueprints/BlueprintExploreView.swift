import SwiftUI
import UIKit

struct BlueprintExploreView: View {
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blueprintPreviewPresented) private var previewPresented
    @Namespace private var blueprintTransition
    @State private var model: BlueprintDiscoveryModel
    @State private var feed: BlueprintCatalogFeedModel
    @State private var ideaFeed = IdeaDiscoveryFeedModel()
    @State private var additionStore: IdeaDiscoveryAdditionStore
    @State private var discoveryContextStore: BlueprintDiscoveryContextStore
    @State private var adSession: ExploreAdSession
    @State private var actions: BlueprintActionStore?
    private let discoveryContextDefaults: UserDefaults
    @State private var query = ""
    @State private var isSearchActive = false
    @State private var navigation = BlueprintDiscoveryNavigation()
    @State private var isAccountPresented = false
    @State private var selectedIdea: IdeaDiscoveryEntry?
    @State private var exploreKind: ExploreContentKind = .all
    @State private var isShowingSearchPrimer = false
    @State private var searchPrimerAccountID = ""
    @State private var tourFinishRevision = 0
#if DEBUG
    @State private var searchVisualFixture: BlueprintSearchVisualFixture?
    @State private var discoveryRequestCount = 0
    @State private var discoveryFirstPageRequests = 0
    @State private var lastDiscoveryRequestContext: BlueprintDiscoveryRequestContext? = nil
    @State private var ideaFixturePageRequests = 0
#endif
    private let searchVisualFixtureEnabled: Bool
    private let discoverySessionFixtureEnabled: Bool
    private let adsScrollVerificationEnabled: Bool
    private let ideaDiscoveryFixtureEnabled: Bool
    private let ideaPagingFixtureEnabled: Bool
    @FocusState private var isFocused: Bool
    private let ownerID: String
    private let tourSelection: (() -> Void)?
    private let bundledMovieNightEntry: BlueprintCatalogEntry?
    let isActive: Bool

    init(ownerID: String, isActive: Bool = true, tourSelection: (() -> Void)? = nil) {
        self.ownerID = ownerID
        self.isActive = isActive
        self.tourSelection = tourSelection
        bundledMovieNightEntry = MovieNightTourExplorePolicy.bundledEntry()
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let adsVerificationEnabled = arguments.contains("-BlueprintAdsScrollVerification")
        let ideaFixtureEnabled = arguments.contains("-IdeaDiscoveryVisualFixture")
        let ideaPagingFixture = arguments.contains("-IdeaDiscoveryPagingFixture")
        let sessionFixtureEnabled = arguments.contains("-BlueprintDiscoverySessionFixture")
        let fixtureEnabled = arguments.contains("-BlueprintSearchVisualFixture") || adsVerificationEnabled || sessionFixtureEnabled || ideaFixtureEnabled || ideaPagingFixture
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
        ideaDiscoveryFixtureEnabled = ideaFixtureEnabled
        ideaPagingFixtureEnabled = ideaPagingFixture
        _searchVisualFixture = State(initialValue: fixtureEnabled ? BlueprintSearchVisualFixture.load() : nil)
#else
        searchVisualFixtureEnabled = false
        discoverySessionFixtureEnabled = false
        adsScrollVerificationEnabled = false
        ideaDiscoveryFixtureEnabled = false
        ideaPagingFixtureEnabled = false
        let localDefaults = UserDefaults.standard
#endif
        _model = State(initialValue: BlueprintDiscoveryModel(ownerID: ownerID))
        _feed = State(initialValue: BlueprintCatalogFeedModel(ownerID: ownerID))
        _additionStore = State(initialValue: IdeaDiscoveryAdditionStore(ownerID: ownerID, defaults: localDefaults))
        _discoveryContextStore = State(initialValue: BlueprintDiscoveryContextStore(
            accountID: ownerID, defaults: localDefaults
        ))
        discoveryContextDefaults = localDefaults
        // A local opaque scope keeps the ad inventory isolated without sending
        // an account, category, query, or event value to the ad SDK.
        _adSession = State(initialValue: ExploreAdSession(scopeID: UUID().uuidString))
    }

    private var mode: BlueprintSearchMode { navigation.mode(isFocused: isSearchActive || isFocused, query: query) }
    private var isGuidedTour: Bool { tourSelection != nil }
    private var guidedSelectionKey: String? {
        isGuidedTour && bundledMovieNightEntry != nil ? MovieNightTourExplorePolicy.catalogKey : nil
    }
    private var guidedSearchPresentation: Binding<Bool> {
        Binding(get: { isSearchActive }, set: { if !isGuidedTour { isSearchActive = $0 } })
    }
    private var guidedQuery: Binding<String> {
        Binding(get: { query }, set: { if !isGuidedTour { query = $0 } })
    }
    private var accountStateID: String { String(describing: cloudSync.accountOnboardingState) }
    private var contextualPrimerCheckID: String {
        "\(ownerID)|\(isActive)|\(accountStateID)|\(tourFinishRevision)"
    }
    private var addedIdeaSourceIDs: Set<String> {
        Set(ideaFeed.ideas.compactMap { additionStore.isAdded($0, in: workspaceLibrary) ? $0.id : nil })
    }
    private var catalogTaskID: String {
        "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(isGuidedTour)|\(mode)|\(query)|\(exploreKind.rawValue)"
    }
    private var ideaTaskID: String { "\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(isGuidedTour)|\(query)|\(exploreKind.rawValue)" }
    private var adTaskID: String {
        "\(ownerID)|\(isGuidedTour)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(mode)|\(exploreKind.rawValue)|\(navigation.selection?.entry.id ?? "")|\(selectedIdea?.id ?? "")|\(previewPresented.wrappedValue)|\(isAccountPresented)"
    }
    private var actionsTaskID: String {
        "actions|\(ownerID)|\(isActive)|\(scenePhase == .active)|\(accountStateID)|\(isGuidedTour)"
    }
    private var measurementIsActive: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && selectedIdea == nil && !previewPresented.wrappedValue && !isAccountPresented
            && !searchVisualFixtureEnabled && !isGuidedTour
    }
    private var localHistoryIsActive: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && selectedIdea == nil && !previewPresented.wrappedValue && !isAccountPresented && mode == .browse && exploreKind != .ideas
            && !ownerID.isEmpty && !isGuidedTour && (!searchVisualFixtureEnabled || discoverySessionFixtureEnabled)
    }
    private var feedAdsAreEligible: Bool {
        isActive && scenePhase == .active && navigation.selection == nil
            && selectedIdea == nil && !previewPresented.wrappedValue && !isAccountPresented
            && !isGuidedTour
            && ExploreAdFeedPolicy.allowsAds(content: exploreKind, mode: mode)
            && (!searchVisualFixtureEnabled || adsScrollVerificationEnabled)
    }
    private var feedAdLayoutIsEnabled: Bool {
        ExploreAdFeedPolicy.allowsAds(content: exploreKind, mode: mode)
            && (!searchVisualFixtureEnabled || adsScrollVerificationEnabled)
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
        Group {
            if exploreKind == .ideas {
                IdeaDiscoveryGrid(entries: ideaFeed.ideas, isLoading: ideaFeed.isLoading,
                                      loadFailed: ideaFeed.loadFailed,
                                      hasLoadedFirstPage: ideaFeed.hasLoadedFirstPage,
                                      shouldAutoAdvanceEmptyPage: ideaFeed.shouldAutoAdvanceEmptyPage,
                                      nextCursor: ideaFeed.nextCursor,
                                      onSelect: { selectedIdea = $0 },
                                      onLoadMore: { Task { await loadMoreIdeas() } },
                                      onRetry: { Task { await refreshIdeas() } },
                                      onRefresh: { await refreshIdeas() },
                                      addedSourceIDs: addedIdeaSourceIDs,
                                      adSession: feedAdLayoutIsEnabled ? adSession : nil,
                                      transitionNamespace: blueprintTransition,
                                      scope: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .all : .search(query))
            } else {
                pagedGrid(source: mode == .recent ? .recent : .results,
                          itemsHeader: mode == .recent ? AnyView(recentHeading) : nil)
            }
        }
        .sheet(item: $selectedIdea) { entry in
            let capturedOwnerID = ownerID
            let capturedStoreGeneration = additionStore.callbackGeneration
            let capturedAccountGeneration = persistence.activeUserGeneration
            IdeaDiscoveryDetailView(entry: entry,
                isAdded: additionStore.isAdded(entry, in: workspaceLibrary),
                onAdded: { receipt in
                    guard ownerID == capturedOwnerID,
                          additionStore.callbackGeneration == capturedStoreGeneration,
                          persistence.activeUserID == capturedOwnerID,
                          persistence.activeUserGeneration == capturedAccountGeneration,
                          receipt.accountID == capturedOwnerID else { return }
                    additionStore.record(receipt)
                })
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if navigation.selection == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(String(localized: "Explore content", defaultValue: "Explore content"), selection: $exploreKind) {
                            ForEach(ExploreContentKind.allCases) { kind in Text(kind.title).tag(kind) }
                        }
                        if mode == .browse {
                            Divider()
                            Button(ExploreCopy.refresh, systemImage: "arrow.clockwise") {
                                Task {
                                    if exploreKind != .blueprints { await refreshIdeas() }
                                    if exploreKind != .ideas { await refreshPagedSurface(startNewDiscoverySession: true) }
                                }
                            }
                            .disabled(exploreKind == .ideas ? ideaFeed.isLoading : feed.isLoading)
                            .accessibilityIdentifier("blueprint.discovery.refresh")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(exploreKind.title).font(.headline)
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }
                    }
                    .disabled(isGuidedTour)
                    .accessibilityIdentifier("explore.content.filter")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    AccountToolbarButton(blueprintActionStore: actions,
                        onPresentationChange: { isAccountPresented = $0 },
                        onDismiss: { Task { await refreshAfterAccountPresentation() } })
                    .disabled(isGuidedTour)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ExploreAdvertisingPrivacyButton(session: adSession)
                        .disabled(isGuidedTour)
                }
            }
        }
        .searchable(
            text: guidedQuery,
            isPresented: guidedSearchPresentation,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: ExploreCopy.search
        )
        .searchFocused($isFocused)
        .background {
            GuidedExploreSearchFieldLock(isLocked: isGuidedTour)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onSubmit(of: .search) { Task { await submitSearch() } }
        .onChange(of: isSearchActive) { _, active in
            if !active {
                query = ""
                isFocused = false
            }
        }
        .onChange(of: isGuidedTour) { _, guided in
            guard guided else { return }
            query = ""
            isSearchActive = false
            isFocused = false
            exploreKind = .all
            navigation = BlueprintDiscoveryNavigation()
        }
    }

    private var previewSurface: some View {
        contentSurface
        .fullScreenCover(isPresented: $isShowingSearchPrimer) {
            SearchPrimer {
                ContextualPrimerStore().markSeen(.search, accountID: searchPrimerAccountID)
                isShowingSearchPrimer = false
            }
        }
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
            presentSearchPrimerIfNeeded()
        }
        .onChange(of: accountStateID) { _, _ in
            handleAccountStateChange()
            presentSearchPrimerIfNeeded()
        }
        .onChange(of: isActive) { _, active in
            if active { presentSearchPrimerIfNeeded() }
        }
        .task(id: contextualPrimerCheckID) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            presentSearchPrimerIfNeeded()
        }
        .onChange(of: isShowingSearchPrimer) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                ContextualPrimerStore().markSeen(.search, accountID: searchPrimerAccountID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextualPrimerTourDidFinish)) { notification in
            guard notification.userInfo?["accountID"] as? String == ownerID else { return }
            tourFinishRevision += 1
        }
    }

    private func presentSearchPrimerIfNeeded() {
        guard ContextualPrimerPolicy.shouldPresent(
            hasSeenPrimer: ContextualPrimerStore().hasSeen(.search, accountID: ownerID),
            isTabActive: isActive,
            accountState: cloudSync.accountOnboardingState
        ) else { return }
        searchPrimerAccountID = ownerID
        isShowingSearchPrimer = true
    }

    private var lifecycleSurface: some View {
        previewSurface
        .task(id: actionsTaskID) { await loadActionsForCurrentAccount() }
        .task(id: catalogTaskID) { await loadCatalogForCurrentSurface() }
        .task(id: ideaTaskID) { await loadIdeasForCurrentSurface() }
        .task(id: adTaskID) { await prepareAdSessionIfNeeded() }
        .onDisappear {
            if navigation.selection != nil || selectedIdea != nil || previewPresented.wrappedValue || isAccountPresented {
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
            if ideaPagingFixtureEnabled {
                Text("")
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Idea paging audit")
                    .accessibilityIdentifier("idea.discovery.paging.audit")
                    .accessibilityValue(ideaPagingAuditValue)
                    .allowsHitTesting(false)
            }
        }
#endif
    }

#if DEBUG
    private var ideaPagingAuditValue: String {
        let value: [String: Int] = ["requestCount": ideaFixturePageRequests, "loadedCount": ideaFeed.ideas.count]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

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
        if isGuidedTour {
            if focused { isFocused = false }
            if isSearchActive { isSearchActive = false }
            return
        }
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
        ideaFeed.invalidate(ownerID: newOwnerID)
        additionStore.switchAccount(to: newOwnerID)
        selectedIdea = nil
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
        ideaFeed.invalidate(ownerID: ownerID)
        additionStore.invalidateCallbacks()
        additionStore.switchAccount(to: ownerID)
        selectedIdea = nil
        resetAdSession()
        actions?.resetForAccountChange()
        actions = nil
    }

    private func loadActionsForCurrentAccount() async {
        guard !isGuidedTour else { return }
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
        guard isActive, scenePhase == .active, navigation.selection == nil, exploreKind != .ideas else { return }
        if mode == .results {
            let scope = BlueprintCatalogFeedScope.search(query)
            if feed.scope != scope { feed.activate(scope) }
            do { try await Task.sleep(nanoseconds: 275_000_000) } catch { return }
            guard !Task.isCancelled else { return }
        }
        if mode == .browse, !ownerID.isEmpty, !isGuidedTour {
            let priorSessionID = discoveryContextStore.session?.sessionId
            let current = discoveryContextStore.beginOrResumeSession()
            if priorSessionID != nil, current?.sessionId != priorSessionID, feed.hasLoadedFirstPage {
                await refreshPagedSurface()
                return
            }
        }
        await loadCurrentSurface()
    }

    private func loadIdeasForCurrentSurface() async {
        guard exploreKind != .blueprints, isActive, scenePhase == .active else { return }
        ideaFeed.activate(query: query, ownerID: ownerID)
        guard !Task.isCancelled else { return }
        do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
        guard !Task.isCancelled, exploreKind != .blueprints, isActive, scenePhase == .active else { return }
        if !ideaFeed.hasLoadedFirstPage || ideaFeed.loadFailed {
            await ideaFeed.loadNextPage(fetch: fetchIdeasPage)
        }
    }

    private func loadMoreIdeas() async {
        guard exploreKind != .blueprints, isActive, scenePhase == .active else { return }
        await ideaFeed.loadNextPage(fetch: fetchIdeasPage)
    }

    private func refreshIdeas() async {
        guard !isGuidedTour else { return }
        guard exploreKind != .blueprints, isActive, scenePhase == .active else { return }
        ideaFeed.activate(query: query, ownerID: ownerID)
        await ideaFeed.refresh(fetch: fetchIdeasPage)
    }

    private func fetchIdeasPage(cursor: String?, query: String?) async throws -> IdeaDiscoveryResponse {
#if DEBUG
        if ideaPagingFixtureEnabled {
            ideaFixturePageRequests += 1
            return IdeaDiscoveryVisualFixture.pagingPage(cursor: cursor, query: query)
        }
        if ideaDiscoveryFixtureEnabled { return IdeaDiscoveryVisualFixture.page(cursor: cursor, query: query) }
#endif
        guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
            throw CloudSyncFailure.invalidSession
        }
        return try await coordinator.ideaCatalogPage(cursor: cursor, limit: IdeaDiscoveryFeedModel.pageSize, query: query)
    }

    private func prepareAdSessionIfNeeded() async {
        if navigation.selection != nil || selectedIdea != nil || previewPresented.wrappedValue || isAccountPresented {
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
                    .disabled(isGuidedTour)
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
            let visibleEntries = mode == .results ? candidateEntries : candidateEntries.filter {
                !(actions?.states[$0.catalogKey]?.notInterested ?? $0.viewerState?.notInterested ?? false)
            }
            entries = isGuidedTour
                ? MovieNightTourExplorePolicy.merge(bundled: bundledMovieNightEntry, catalogEntries: visibleEntries)
                : visibleEntries
        }
        let isLoading = isRecent ? model.loading : feed.isLoading
        let waitsForMixedFirstPage = !isRecent && exploreKind == .all
            && (!(feed.hasLoadedFirstPage || feed.loadFailed)
                || !(ideaFeed.hasLoadedFirstPage || ideaFeed.loadFailed))
        let isExhausted = isRecent || feed.isExhausted
        let loadFailed = isRecent ? model.loadFailed : feed.loadFailed
        let scope = isRecent ? BlueprintCatalogFeedScope.all : (feed.scope ?? .all)
        let exposureStore = discoveryContextStore
        let exposureGeneration = exposureStore.callbackGeneration
        let exposureAccountID = ownerID

        let resolvedHeader = itemsHeader
        let ideaFooter: AnyView? = exploreKind == .all && !isRecent ? AnyView(
            Group {
                if ideaFeed.shouldAutoAdvanceEmptyPage {
                    ProgressView().task(id: ideaFeed.nextCursor) { await loadMoreIdeas() }
                } else if ideaFeed.isLoading {
                    ProgressView()
                } else if ideaFeed.loadFailed {
                    VStack(spacing: 8) {
                        Text(String(localized: "More ideas couldn't load.", defaultValue: "More ideas couldn't load."))
                            .font(.footnote).foregroundStyle(AppTheme.ColorToken.textSecondary)
                        Button(String(localized: "Retry", defaultValue: "Retry")) { Task { await loadMoreIdeas() } }
                            .disabled(isGuidedTour)
                    }
                }
            }
        ) : nil
        return BlueprintPagedCatalogGrid(
            entries: entries,
            ideaEntries: ideaFeed.ideas,
            addedIdeaSourceIDs: addedIdeaSourceIDs,
            showsIdeas: exploreKind == .all && !isRecent,
            projectionIsReady: isGuidedTour || !waitsForMixedFirstPage,
            source: source,
            transitionNamespace: blueprintTransition,
            scope: scope,
            adSession: !isRecent && feedAdLayoutIsEnabled && !isGuidedTour ? adSession : nil,
            isLoading: isLoading || waitsForMixedFirstPage,
            isExhausted: isExhausted,
            loadFailed: loadFailed,
            onSelect: { open($0, source: source, entries: entries) },
            onSelectIdea: { selectedIdea = $0 },
            onIdeaLoadMore: { Task { await loadMoreIdeas() } },
            guidedSelectionKey: guidedSelectionKey,
            onGuidedSelection: { _ in tourSelection?() },
            guidedTourActive: isGuidedTour,
            onLoadMore: { if !isRecent { Task { await loadNextPage() } } },
            onRetry: {
                Task {
                    if isRecent { await loadRecentCatalog() }
                    else { await refreshPagedSurface() }
                }
            },
            actionStore: actions,
            itemsHeader: resolvedHeader,
            itemsFooter: ideaFooter,
            measurementIsActive: !isRecent && measurementIsActive,
            localExposureIsActive: !isRecent && localHistoryIsActive,
            measurementScopeID: measurementScopeID,
            onMeaningfulExposure: mode == .browse && !isRecent && !isGuidedTour ? { catalogKey in
                exposureStore.recordSeen(catalogKey: catalogKey, accountID: exposureAccountID,
                                         generation: exposureGeneration)
            } : nil
        )
        .overlay {
            let allHasIdeaContent = exploreKind == .all
                && (waitsForMixedFirstPage || ideaFeed.isLoading || ideaFeed.loadFailed || !ideaFeed.ideas.isEmpty)
            if !isLoading && entries.isEmpty && !allHasIdeaContent {
                ContentUnavailableView(
                    loadFailed ? ExploreCopy.unavailable : (isRecent ? ExploreCopy.noRecents : (mode == .results ? ExploreCopy.noResults : ExploreCopy.emptyCategory)),
                    systemImage: loadFailed ? "wifi.exclamationmark" : "magnifyingglass",
                    description: Text(loadFailed ? ExploreCopy.connection : (isRecent ? ExploreCopy.recentsHint : (mode == .results ? ExploreCopy.tryAnotherSearch : ExploreCopy.checkBack)))
                )
                .allowsHitTesting(false)
            }
        }
        .refreshable {
            guard !isGuidedTour else { return }
            if isRecent { await loadRecentCatalog() }
            else {
                if exploreKind == .all { await refreshIdeas() }
                await refreshPagedSurface(startNewDiscoverySession: mode == .browse)
            }
        }
    }

    private func submitSearch() async {
        guard !isGuidedTour else { return }
        isSearchActive = true
        guard mode == .results else { return }
        if exploreKind != .blueprints { await refreshIdeas() }
        guard exploreKind != .ideas else { return }
        let requestedScope = BlueprintCatalogFeedScope.search(query)
        if feed.scope != requestedScope { feed.activate(requestedScope) }
        await feed.refresh(fetch: fetchPage)
    }

    private func open(_ entry: BlueprintCatalogEntry, source: BlueprintCatalogSource,
                      entries: [BlueprintCatalogEntry]) {
        guard !isGuidedTour else { return }
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
        guard !isGuidedTour else { return }
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
        let context = isGuidedTour || query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
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
            if !isGuidedTour,
               query?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
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

/// SwiftUI's searchable modifier has no disabled parameter in the current SDK.
/// Lock the native search field itself while keeping its regular Explore chrome
/// visible during the guided selection step.
private struct GuidedExploreSearchFieldLock: UIViewRepresentable {
    let isLocked: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        applyLock(isLocked, from: view, coordinator: context.coordinator)
        DispatchQueue.main.async {
            self.applyLock(isLocked, from: view, coordinator: context.coordinator)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.restore()
    }

    private func applyLock(_ isLocked: Bool, from view: UIView, coordinator: Coordinator) {
        guard let searchBar = currentSearchBar(for: view) else {
            coordinator.restore()
            return
        }
        coordinator.setLocked(isLocked, searchBar: searchBar)
    }

    private func currentSearchBar(for view: UIView) -> UISearchBar? {
        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController,
               navigationController.topViewController === viewController {
                return viewController.navigationItem.searchController?.searchBar
            }
            responder = current.next
        }
        return nil
    }

    final class Coordinator {
        private weak var searchBar: UISearchBar?
        private var previousSearchFieldEnabled: Bool?

        func setLocked(_ isLocked: Bool, searchBar newSearchBar: UISearchBar) {
            if searchBar !== newSearchBar {
                restore()
                searchBar = newSearchBar
            }
            let field = newSearchBar.searchTextField
            if isLocked {
                if previousSearchFieldEnabled == nil { previousSearchFieldEnabled = field.isEnabled }
                field.resignFirstResponder()
                field.isEnabled = false
            } else {
                restore()
            }
        }

        func restore() {
            if let previousSearchFieldEnabled, let searchBar {
                searchBar.searchTextField.isEnabled = previousSearchFieldEnabled
            }
            previousSearchFieldEnabled = nil
            searchBar = nil
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
