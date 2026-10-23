import SwiftUI

struct BlueprintLibrarySetupRoute: Identifiable {
    let id = UUID()
    let ownerID: String
    let catalogKey: String?
    let shareToken: String?
    var createsWorkspace = false

    var installationOwnerID: String? { createsWorkspace ? ownerID : nil }

    static func workspace(from draft: BlueprintSetupDraft, ownerID: String) -> Self? {
        guard !ownerID.isEmpty, draft.ownerUserID == ownerID else { return nil }
        return Self(ownerID: ownerID, catalogKey: draft.entry.catalogKey,
                    shareToken: draft.shareToken, createsWorkspace: true)
    }
}

private struct BlueprintLibraryDraftRoute: Identifiable {
    let id = UUID()
    let ownerID: String
    let draft: BlueprintSetupDraft
    var isInstalled = false
    var installationID: UUID? = nil
    var personalSource: BlueprintPersonalRecord? = nil
}

/// Personal template activity. Draft and history files never enter workspace sync.
struct BlueprintLibraryView: View {
    let ownerID: String
    let actionStore: BlueprintActionStore?
    let onExplore: () -> Void
    let onCreate: () -> Void
    var isActive = true
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.currentUserAccount) private var account
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.blueprintPreviewPresented) private var presentationActive
    @State private var model: BlueprintLibraryModel
    @State private var recovery = BlueprintSetupRecovery(drafts: [], hasPendingInstallation: false, loadFailed: false)
    @State private var setupRoute: BlueprintLibrarySetupRoute?
    @State private var draftRoute: BlueprintLibraryDraftRoute?
    @State private var selectedPrimaryCollection: BlueprintLibraryPrimaryCollection = .yours
    private let primaryCollectionPreferenceStore = BlueprintLibraryPrimaryCollectionPreferenceStore()
    @State private var wasActive = false
    @State private var deletion: BlueprintUsedTemplate?
    @State private var draftDeletion: BlueprintSetupDraft?
    @State private var personalDeletion: BlueprintPersonalRecord?
    @State private var personalRecords: [BlueprintPersonalRecord] = []
    @State private var personalLoading = true
    @State private var hasResolvedPersonalRecords = false
    @State private var personalLoadFailed = false
    @State private var personalCacheFailed = false
    @State private var publishCandidate: BlueprintPersonalRecord?
    @State private var unlistCandidate: BlueprintPersonalRecord?
    @State private var personalVisibilityMutationTokens: [UUID: UUID] = [:]
    @State private var visibilityGeneration = UUID()
    @State private var creatorNameCandidate: BlueprintPersonalRecord?
    @State private var actionFailed = false
#if DEBUG
    private let visualFixture: BlueprintLibraryVisualFixture.State?
    private let previewActionsFixture: BlueprintPreviewActionsVisualFixture.State?
#endif

    private var fixtureIsEnabled: Bool {
#if DEBUG
        visualFixture != nil || previewActionsFixture != nil
#else
        false
#endif
    }

    private var sourceInstallations: [BlueprintUsedTemplate] {
#if DEBUG
        if previewActionsFixture != nil { return [] }
        if let visualFixture { return visualFixture.installations }
#endif
        return model.installations
    }

    private var visibleInstallations: [BlueprintUsedTemplate] {
        let waitsForInitialOwnership = !hasResolvedPersonalRecords && personalLoading && personalRecords.isEmpty
        guard !waitsForInitialOwnership else { return [] }
        return sourceInstallations
    }

    private var visibleRecoveryDrafts: [BlueprintSetupDraft] {
        BlueprintLibraryProjection.visibleRecoveryDrafts(
            drafts: recovery.drafts, installations: sourceInstallations, ownerID: ownerID
        )
    }

    init(ownerID: String, isActive: Bool = true, actionStore: BlueprintActionStore? = nil,
         onExplore: @escaping () -> Void = {}, onCreate: @escaping () -> Void = {}) {
        self.ownerID = ownerID
        self.isActive = isActive
        self.actionStore = actionStore
        self.onExplore = onExplore
        self.onCreate = onCreate
        _selectedPrimaryCollection = State(initialValue:
            primaryCollectionPreferenceStore.collection(ownerID: ownerID) ?? .yours
        )
#if DEBUG
        let fixture = BlueprintLibraryVisualFixture.load(ownerID: ownerID)
        let actionsFixture = BlueprintPreviewActionsVisualFixture.load(ownerID: ownerID)
        visualFixture = fixture
        previewActionsFixture = actionsFixture
        _model = State(initialValue: BlueprintLibraryModel(ownerID: ownerID,
            loadsCachedInstallations: fixture == nil && actionsFixture == nil))
        if let actionsFixture {
            _selectedPrimaryCollection = State(initialValue: .yours)
            _personalRecords = State(initialValue: actionsFixture.personalSource.map { [$0] } ?? [])
            _recovery = State(initialValue: BlueprintSetupRecovery(
                drafts: actionsFixture.personalSource == nil ? actionsFixture.workingDraft.map { [$0] } ?? [] : [],
                hasPendingInstallation: false, loadFailed: false))
            _personalLoading = State(initialValue: false)
            _hasResolvedPersonalRecords = State(initialValue: true)
            return
        }
        if let fixture {
            _selectedPrimaryCollection = State(initialValue: .yours)
            _personalRecords = State(initialValue: fixture.personalRecords)
            _recovery = State(initialValue: fixture.recovery)
            _personalLoading = State(initialValue: false)
            _hasResolvedPersonalRecords = State(initialValue: true)
            return
        }
#else
        _model = State(initialValue: BlueprintLibraryModel(ownerID: ownerID))
#endif
        if ownerID.isEmpty {
            _personalRecords = State(initialValue: [])
            _personalCacheFailed = State(initialValue: false)
        } else {
            do {
                _personalRecords = State(initialValue: try BlueprintPersonalLibraryStore().load(ownerID: ownerID))
                _personalCacheFailed = State(initialValue: false)
            } catch {
                _personalRecords = State(initialValue: [])
                _personalCacheFailed = State(initialValue: true)
            }
        }
    }

    var body: some View {
        Group {
            if ownerID.isEmpty || account?.id != ownerID {
                ContentUnavailableView(BlueprintCopy.libraryTitle, systemImage: "square.stack.3d.up")
            } else {
                GeometryReader { viewport in
                let viewportWidth = LayoutDimensions.nonnegative(viewport.size.width)
                let horizontalInset = LayoutDimensions.nonnegative(AppTheme.Layout.screenHorizontal)
                let contentWidth = min(800, max(viewportWidth - 2 * horizontalInset, 0))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                        Picker(BlueprintCopy.libraryCollectionPickerLabel, selection: $selectedPrimaryCollection) {
                            Text(BlueprintCopy.libraryYours).tag(BlueprintLibraryPrimaryCollection.yours)
                            Text(BlueprintCopy.librarySaved).tag(BlueprintLibraryPrimaryCollection.saved)
                            Text(BlueprintCopy.libraryLiked).tag(BlueprintLibraryPrimaryCollection.liked)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(BlueprintCopy.libraryCollectionPickerLabel)
                        .accessibilityIdentifier("blueprint.library.collections")
                        .onChange(of: selectedPrimaryCollection) { _, collection in
                            primaryCollectionPreferenceStore.save(collection, ownerID: ownerID)
                            if collection == .yours { Task { await reload() } }
                        }

                        if selectedPrimaryCollection == .saved {
                            BlueprintPublicCollectionView(kind: .saved, actionStore: actionStore, onExplore: onExplore)
                        } else if selectedPrimaryCollection == .liked {
                            BlueprintPublicCollectionView(kind: .liked, actionStore: actionStore, onExplore: onExplore)
                        } else {
                        if recovery.hasPendingInstallation {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(BlueprintCopy.pendingInstall, systemImage: "arrow.clockwise")
                                    .font(.headline)
                                Text(BlueprintCopy.finishPreviousInstall)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button(BlueprintCopy.libraryContinueSetup, systemImage: "arrow.clockwise") {
                                    presentSetup(catalogKey: nil, shareToken: nil)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("blueprint.library.pending.continue")
                            }
                            .librarySurface()
                        }

                        yoursContent

                        if recovery.loadFailed || model.cacheFailed || personalCacheFailed {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(BlueprintCopy.libraryLocalReadFailed, systemImage: "exclamationmark.triangle")
                                Button(AppCopy.Common.retry) { Task { await reload() } }
                            }
                            .font(.footnote).librarySurface()
                        }
                        if model.refreshFailed || personalLoadFailed {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(BlueprintCopy.libraryRefreshFailed, systemImage: "wifi.exclamationmark")
                                Button(AppCopy.Common.retry) { Task { await reload() } }
                            }
                            .font(.footnote).librarySurface()
                        }
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.top, AppTheme.Layout.screenTop)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                    .frame(width: contentWidth + 2 * horizontalInset)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("blueprint.library.scroll")
                .appSoftScrollEdges()
                .refreshable { await refreshVisibleCollection() }
                }
            }
        }
        .background(AppTheme.ColorToken.background)
        .confirmationDialog(
            publishCandidate != nil ? BlueprintCopy.confirmListInSearchTitle
                : unlistCandidate != nil ? BlueprintCopy.confirmRemoveFromSearchTitle : "Delete Blueprint?",
                            isPresented: Binding(
            get: { deletion != nil || draftDeletion != nil || personalDeletion != nil || publishCandidate != nil || unlistCandidate != nil },
            set: { if !$0 { deletion = nil; draftDeletion = nil; personalDeletion = nil; publishCandidate = nil; unlistCandidate = nil } }
        ), titleVisibility: .visible) {
            if let publishCandidate {
                Button(BlueprintCopy.publishToSearch) { Task { await publishToSearch(publishCandidate) } }
                    .disabled(personalLoading || personalLoadFailed || personalVisibilityMutationTokens[publishCandidate.id] != nil)
            } else if let unlistCandidate {
                Button(BlueprintCopy.removeFromSearch, role: .destructive) {
                    Task { await removeFromSearch(unlistCandidate) }
                }
                .disabled(personalVisibilityMutationTokens[unlistCandidate.id] != nil)
            } else {
                Button("Delete Blueprint", role: .destructive) { deleteSelectedBlueprint() }
            }
            Button(AppCopy.Common.cancel, role: .cancel) {
                deletion = nil
                draftDeletion = nil
                personalDeletion = nil
                publishCandidate = nil
                unlistCandidate = nil
            }
        } message: {
            if publishCandidate != nil { Text(BlueprintCopy.confirmListInSearchMessage) }
            else if unlistCandidate != nil { Text(BlueprintCopy.confirmRemoveFromSearchMessage) }
            else if personalDeletion != nil { Text(BlueprintCopy.deletePersonalBlueprintMessage) }
            else { Text("This removes the blueprint from your library. Created workspaces will not be deleted.") }
        }
        .sheet(item: $creatorNameCandidate) { record in
            BlueprintCreatorNameSheet(
                onPublish: { name in Task { await publishToSearch(record, creatorName: name) } },
                onCancel: { creatorNameCandidate = nil }
            )
        }
        .alert("Unable to update blueprint", isPresented: $actionFailed) {
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .navigationTitle(BlueprintCopy.libraryTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            AdaptiveToolbarActions {
                AccountToolbarButton(avatarSize: 28, blueprintActionStore: actionStore)
                    .frame(width: 44, height: 44)
            }
        }
        .task(id: "\(isActive)|\(String(describing: cloudSync.accountOnboardingState))") {
            if isActive {
                if !wasActive {
                    wasActive = true
                }
                if !fixtureIsEnabled { await actionStore?.loadPreferences() }
                await reload()
            } else {
                wasActive = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isActive { Task { await reload() } }
        }
        .onChange(of: account?.id) { _, activeID in
            visibilityGeneration = UUID()
            personalVisibilityMutationTokens.removeAll()
            creatorNameCandidate = nil
            publishCandidate = nil
            unlistCandidate = nil
            if activeID != ownerID {
                model.invalidate()
                personalRecords = []
                hasResolvedPersonalRecords = false
                personalLoading = true
                personalLoadFailed = false
                personalCacheFailed = false
            }
        }
        .sheet(item: $setupRoute, onDismiss: {
            if account?.id == ownerID {
                presentationActive.wrappedValue = false
                Task { await reload() }
            }
        }) { route in
            if account?.id == route.ownerID {
                NavigationStack {
                    BlueprintSetupView(
                        catalogKey: route.catalogKey,
                        sharedToken: route.shareToken,
                        installationOwnerID: route.installationOwnerID,
                        onInstallationCompleted: { setupRoute = nil },
                        onClose: { setupRoute = nil }
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(item: $draftRoute, onDismiss: {
            if account?.id == ownerID {
                presentationActive.wrappedValue = false
                Task { await reload() }
            }
        }) { route in
            if account?.id == route.ownerID {
                BlueprintPreviewView(
                    entry: route.draft.entry,
                    presentationContext: .personal,
                    sharedToken: route.draft.shareToken,
                    usesSavedPreview: route.draft.shareToken != nil,
                    allowsRepeatInstallation: true,
                    installedSource: route.isInstalled ? route.draft : nil,
                    installedTemplateID: route.installationID,
                    personalSource: route.personalSource
                )
            }
        }
    }

    private var yoursContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if (model.loading || personalLoading) && visibleInstallations.isEmpty
                && personalRecords.isEmpty && visibleRecoveryDrafts.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if visibleInstallations.isEmpty && personalRecords.isEmpty && visibleRecoveryDrafts.isEmpty
                        && !personalLoading && !model.loading && !recovery.hasPendingInstallation {
                yoursEmptyState
            } else {
                AdaptiveMasonry(
                    columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                    spacing: 12,
                    layoutDirection: layoutDirection, minimumColumnWidth: 170
                ) {
                    ForEach(visibleRecoveryDrafts, id: \.requestID) { draft in
                        Button {
                            guard draft.ownerUserID == ownerID else { return }
                            presentDraft(draft)
                        } label: {
                            let preview = BlueprintPreviewContent(
                                entry: draft.entry,
                                customizations: draft.customizations,
                                eventName: draft.eventName
                            )
                            BlueprintLibraryTile(
                                category: draft.entry.browseCategories.first ?? .events,
                                title: draft.eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? draft.entry.definition.blueprint.name : draft.eventName,
                                subtitle: draft.entry.definition.blueprint.name,
                                detail: BlueprintLibraryProjection.hasSetupProgress(draft)
                                    ? BlueprintCopy.libraryContinueSetup : nil,
                                coverAssetID: preview?.coverAssetID,
                                publicCoverImageURL: preview?.publicCoverImageURL,
                                coverSource: BlueprintCoverSource(
                                    catalogKey: draft.entry.catalogKey,
                                    revision: draft.entry.revision,
                                    shareToken: draft.shareToken
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(recovery.hasPendingInstallation)
                        .accessibilityIdentifier(recoveryCardIdentifier(draft))
                        .contextMenu {
                            if BlueprintLibraryProjection.hasSetupProgress(draft) {
                                Button(BlueprintCopy.libraryContinueSetup, systemImage: "arrow.right") {
                                    presentSetup(catalogKey: draft.entry.catalogKey, shareToken: draft.shareToken)
                                }
                                .disabled(recovery.hasPendingInstallation)
                            }
                            Button(BlueprintCopy.createEvents, systemImage: "plus.square") { createWorkspace(from: draft) }
                                .disabled(recovery.hasPendingInstallation)
                            Button("Delete Blueprint", systemImage: "trash", role: .destructive) {
                                draftDeletion = draft
                            }
                        }
                    }
                    ForEach(visibleInstallations) { installation in
                        let source = try? installation.previewSource(ownerID: ownerID)
                        let experienceType = source?.entry.definition.experienceDefaults.type
                        let category = BlueprintLibraryCategoryFilter.usedTemplateCategory(
                            experienceType: experienceType
                        )
                        Button {
                            openBlueprint(installation)
                        } label: {
                            let preview = source.flatMap {
                                BlueprintPreviewContent(entry: $0.entry, customizations: $0.customizations,
                                                        eventName: $0.eventName)
                            }
                            BlueprintLibraryTile(
                                category: category,
                                title: installation.templateName,
                                subtitle: BlueprintCopy.libraryUsedFor(installation.eventName),
                                coverAssetID: preview?.coverAssetID,
                                publicCoverImageURL: preview?.publicCoverImageURL,
                                coverSource: source.map {
                                    BlueprintCoverSource(catalogKey: $0.entry.catalogKey,
                                                         revision: $0.entry.revision,
                                                         shareToken: $0.shareToken)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("blueprint.library.card.used.\(installation.id.uuidString)")
                        .contextMenu {
                            Button(BlueprintCopy.createEvents, systemImage: "plus.square") {
                                createWorkspace(from: installation)
                            }
                            .disabled(recovery.hasPendingInstallation)
                            Button("Delete Blueprint", systemImage: "trash", role: .destructive) {
                                deletion = installation
                            }
                        }
                        .accessibilityHint(BlueprintCopy.previewTitle)
                    }
                    ForEach(personalRecords) { record in
                        Button { openPersonalBlueprint(record) } label: {
                            let entry = record.catalogEntry
                            let preview = BlueprintPreviewContent(entry: entry)
                            BlueprintLibraryTile(
                                category: BlueprintLibraryCategoryFilter.usedTemplateCategory(
                                    experienceType: entry.definition.experienceDefaults.type
                                ),
                                title: entry.definition.blueprint.name,
                                subtitle: String(localized: "Your Blueprint"),
                                coverAssetID: preview?.coverAssetID,
                                publicCoverImageURL: preview?.publicCoverImageURL,
                                coverSource: BlueprintCoverSource(catalogKey: entry.catalogKey,
                                                                  revision: entry.revision),
                                creatorName: record.creatorName ?? record.catalogEntry.creator?.displayName,
                                activeShareLinkCount: record.activeShareLinkCount,
                                listedRevision: record.listedRevision,
                                showsSharingStatus: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("blueprint.library.card.personal.\(record.id.uuidString)")
                        .contextMenu {
                            Button(BlueprintCopy.createEvents, systemImage: "plus.square") {
                                createWorkspace(from: record)
                            }
                            .disabled(recovery.hasPendingInstallation)
                            Button("Delete Blueprint", systemImage: "trash", role: .destructive) {
                                personalDeletion = record
                            }
                            if record.listedRevision == nil {
                                Button(BlueprintCopy.publishToSearch, systemImage: "globe") {
                                    if record.creatorName.flatMap(BlueprintCreatorNameValidation.normalized) == nil {
                                        creatorNameCandidate = record
                                    } else {
                                        publishCandidate = record
                                    }
                                }
                                .disabled(personalLoading || personalLoadFailed || personalVisibilityMutationTokens[record.id] != nil)
                            } else {
                                Button(BlueprintCopy.removeFromSearch, systemImage: "globe.slash", role: .destructive) {
                                    unlistCandidate = record
                                }
                                .disabled(personalLoading || personalLoadFailed || personalVisibilityMutationTokens[record.id] != nil)
                            }
                        }
                        .accessibilityHint(BlueprintCopy.previewTitle)
                    }
                }
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func presentDraft(_ draft: BlueprintSetupDraft) {
        guard !ownerID.isEmpty, draft.ownerUserID == ownerID, account?.id == ownerID else { return }
        presentationActive.wrappedValue = true
        draftRoute = BlueprintLibraryDraftRoute(ownerID: ownerID, draft: draft)
    }

    private func recoveryCardIdentifier(_ draft: BlueprintSetupDraft) -> String {
#if DEBUG
        if previewActionsFixture?.workingDraft?.requestID == draft.requestID {
            return "blueprint.library.fixture.working"
        }
#endif
        return "blueprint.library.card.recovery.\(draft.requestID.uuidString)"
    }

    private func openBlueprint(_ installation: BlueprintUsedTemplate) {
        guard account?.id == ownerID else { return }
        guard !fixtureIsEnabled else { return }
        do {
            if let source = try installation.previewSource(ownerID: ownerID) {
                presentationActive.wrappedValue = true
                draftRoute = BlueprintLibraryDraftRoute(ownerID: ownerID, draft: source, isInstalled: true,
                                                       installationID: installation.id)
            } else {
                Task { await createWorkspaceFromCatalog(installation, previewOnly: true) }
            }
        } catch { actionFailed = true }
    }

    private func openPersonalBlueprint(_ record: BlueprintPersonalRecord) {
        guard account?.id == ownerID, personalRecords.contains(where: { $0.id == record.id }) else { return }
        do {
            let entry = record.catalogEntry
            let content = try BlueprintCustomization().applying(to: entry)
            let context = BlueprintSetupDateContext()
            let draft = BlueprintSetupDraft(ownerUserID: ownerID, entry: entry, requestID: UUID(),
                eventName: entry.definition.blueprint.name, startsAt: context.startsAt,
                timeZoneIdentifier: context.timeZoneIdentifier,
                selectedChildren: Set(content.tree.children.map(\.key)),
                selectedIdeas: Set(content.ideas.ideas.map(\.key)), confirmedDates: [:],
                mainDateConfirmed: false)
            presentationActive.wrappedValue = true
            draftRoute = BlueprintLibraryDraftRoute(ownerID: ownerID, draft: draft,
                                                    isInstalled: true, personalSource: record)
        } catch { actionFailed = true }
    }

    private func deleteSelectedBlueprint() {
        defer { deletion = nil; draftDeletion = nil; personalDeletion = nil }
        guard account?.id == ownerID, !fixtureIsEnabled else { return }
        if let deletion { model.removeFromLibrary(deletion) }
        if let record = personalDeletion {
            Task { await deletePersonalBlueprint(record) }
            return
        }
        if let draft = draftDeletion {
            do {
                guard !recovery.hasPendingInstallation,
                      try BlueprintInstallationIntentStore().pending(ownerUserID: ownerID).isEmpty else { return }
                try BlueprintSetupDraftStore().remove(ownerUserID: ownerID, catalogKey: draft.entry.catalogKey,
                                                     requestID: draft.requestID, shareToken: draft.shareToken)
                recovery = BlueprintSetupRecovery(
                    drafts: recovery.drafts.filter { $0.requestID != draft.requestID },
                    hasPendingInstallation: recovery.hasPendingInstallation, loadFailed: recovery.loadFailed)
            } catch { actionFailed = true }
        }
    }

    @MainActor
    private func deletePersonalBlueprint(_ record: BlueprintPersonalRecord) async {
        guard account?.id == ownerID,
              personalRecords.contains(where: { $0.id == record.id }),
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            actionFailed = true
            return
        }
        do {
            let transport: any BlueprintPersonalLibraryTransport = PostgresSyncTransport(baseURL: baseURL)
            try await transport.deletePersonalBlueprint(id: record.id)
            guard account?.id == ownerID else { return }
            for receipt in model.installations where receipt.catalogKey == record.catalogEntry.catalogKey {
                model.removeFromLibrary(receipt)
            }
            do {
                try BlueprintPersonalLibraryStore().remove(id: record.id, ownerID: ownerID)
            } catch {
                personalCacheFailed = true
                actionFailed = true
            }
            personalRecords.removeAll { $0.id == record.id }
        } catch { if account?.id == ownerID { actionFailed = true } }
    }

    @MainActor
    private func publishToSearch(_ record: BlueprintPersonalRecord, creatorName: String? = nil) async {
        guard !fixtureIsEnabled else { return }
        let expectedCreatorName = record.creatorName.flatMap(BlueprintCreatorNameValidation.normalized)
            ?? creatorName.flatMap(BlueprintCreatorNameValidation.normalized)
        publishCandidate = nil
        creatorNameCandidate = nil
        guard account?.id == ownerID, !personalLoading, !personalLoadFailed,
              personalVisibilityMutationTokens[record.id] == nil,
              record.listedRevision == nil,
              personalRecords.contains(where: { isCurrentPersonalRecord($0, matching: record) }),
              let expectedCreatorName,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            if account?.id == ownerID { actionFailed = true }
            return
        }
        let generation = visibilityGeneration
        let expectedVersion = record.draftVersion
        let expectedPublishedRevision = record.publishedRevision
        let expectedCatalogKey = record.catalogEntry.catalogKey
        let mutationToken = UUID()
        personalVisibilityMutationTokens[record.id] = mutationToken
        defer {
            if personalVisibilityMutationTokens[record.id] == mutationToken {
                personalVisibilityMutationTokens.removeValue(forKey: record.id)
            }
        }
        do {
            let transport = PostgresSyncTransport(baseURL: baseURL)
            let updated = try await transport.publishPersonalBlueprint(
                id: record.id,
                expectedVersion: expectedVersion,
                creatorName: expectedCreatorName
            )
            guard account?.id == ownerID, visibilityGeneration == generation,
                  !personalLoading, !personalLoadFailed,
                  BlueprintPersonalPublishAcknowledgement.isValid(
                    updated,
                    expectedID: record.id,
                    expectedCatalogKey: expectedCatalogKey,
                    expectedDraftVersion: expectedVersion,
                    previousPublishedRevision: expectedPublishedRevision,
                    expectedCreatorName: expectedCreatorName
                  ),
                  personalRecords.contains(where: { isCurrentPersonalRecord($0, matching: record) }) else {
                if account?.id == ownerID, visibilityGeneration == generation { actionFailed = true }
                return
            }
            personalRecords = personalRecords.map { $0.id == updated.id ? updated : $0 }
            do {
                try BlueprintPersonalLibraryStore().upsert(updated, ownerID: ownerID)
                personalCacheFailed = false
            } catch {
                personalCacheFailed = true
                actionFailed = true
            }
        } catch {
            if account?.id == ownerID, visibilityGeneration == generation { actionFailed = true }
        }
    }

    @MainActor
    private func removeFromSearch(_ record: BlueprintPersonalRecord) async {
        guard !fixtureIsEnabled else { return }
        unlistCandidate = nil
        guard account?.id == ownerID, !personalLoading, !personalLoadFailed,
              personalVisibilityMutationTokens[record.id] == nil,
              let expectedListedRevision = record.listedRevision,
              expectedListedRevision > 0,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL,
              personalRecords.contains(where: { isCurrentPersonalRecord($0, matching: record) }) else { return }

        let generation = visibilityGeneration
        let expectedVersion = record.draftVersion
        let expectedCatalogKey = record.catalogEntry.catalogKey
        let expectedPublishedRevision = record.publishedRevision
        let expectedCreatorName = record.creatorName
        let mutationToken = UUID()
        personalVisibilityMutationTokens[record.id] = mutationToken
        defer {
            if personalVisibilityMutationTokens[record.id] == mutationToken {
                personalVisibilityMutationTokens.removeValue(forKey: record.id)
            }
        }

        do {
            let transport = PostgresSyncTransport(baseURL: baseURL)
            let updated = try await transport.unlistPersonalBlueprint(
                id: record.id,
                expectedVersion: expectedVersion,
                expectedListedRevision: expectedListedRevision
            )
            guard account?.id == ownerID, visibilityGeneration == generation,
                  !personalLoading, !personalLoadFailed,
                  updated.id == record.id,
                  updated.catalogEntry.catalogKey == expectedCatalogKey,
                  updated.draftVersion == expectedVersion,
                  updated.publishedRevision == expectedPublishedRevision,
                  updated.creatorName == expectedCreatorName,
                  updated.listedRevision == nil,
                  personalRecords.contains(where: { isCurrentPersonalRecord($0, matching: record) }) else {
                if account?.id == ownerID, visibilityGeneration == generation { actionFailed = true }
                return
            }
            personalRecords = personalRecords.map { $0.id == updated.id ? updated : $0 }
            do {
                try BlueprintPersonalLibraryStore().upsert(updated, ownerID: ownerID)
                personalCacheFailed = false
            } catch {
                personalCacheFailed = true
                actionFailed = true
            }
        } catch {
            if account?.id == ownerID, visibilityGeneration == generation { actionFailed = true }
        }
    }

    private func isCurrentPersonalRecord(_ current: BlueprintPersonalRecord, matching expected: BlueprintPersonalRecord) -> Bool {
        current.id == expected.id
            && current.catalogEntry.catalogKey == expected.catalogEntry.catalogKey
            && current.draftVersion == expected.draftVersion
            && current.publishedRevision == expected.publishedRevision
            && current.listedRevision == expected.listedRevision
            && current.creatorName == expected.creatorName
    }

    private func createWorkspace(from record: BlueprintPersonalRecord) {
        guard !fixtureIsEnabled else { return }
        guard account?.id == ownerID, !recovery.hasPendingInstallation else { return }
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: ownerID).isEmpty else { return }
            let entry = record.catalogEntry
            let store = BlueprintSetupDraftStore()
            if let existing = try store.load(ownerUserID: ownerID, catalogKey: entry.catalogKey),
               existing.ownerUserID == ownerID,
               existing.entry.revision == entry.revision,
               existing.entry.contentHash == entry.contentHash {
                createWorkspace(from: existing)
                return
            }
            let content = try BlueprintCustomization().applying(to: entry)
            let context = BlueprintSetupDateContext()
            let draft = BlueprintSetupDraft(ownerUserID: ownerID, entry: entry, requestID: UUID(),
                eventName: entry.definition.blueprint.name, startsAt: context.startsAt,
                timeZoneIdentifier: context.timeZoneIdentifier,
                selectedChildren: Set(content.tree.children.map(\.key)),
                selectedIdeas: Set(content.ideas.ideas.map(\.key)), confirmedDates: [:],
                previewDecisions: Dictionary(uniqueKeysWithValues: content.ideas.ideas.map { ($0.key, .love) }),
                mainDateConfirmed: false)
            try store.save(draft)
            createWorkspace(from: draft)
        } catch { actionFailed = true }
    }

    private func createWorkspace(from installation: BlueprintUsedTemplate) {
        guard !fixtureIsEnabled else { return }
        guard account?.id == ownerID, !recovery.hasPendingInstallation else { return }
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: ownerID).isEmpty else { return }
            if let draft = try installation.workspaceDraft(ownerID: ownerID, store: BlueprintSetupDraftStore()) {
                createWorkspace(from: draft)
            } else {
                Task { await createWorkspaceFromCatalog(installation) }
            }
        } catch { actionFailed = true }
    }

    private func createWorkspace(from draft: BlueprintSetupDraft) {
        guard !fixtureIsEnabled else { return }
        guard account?.id == ownerID, draft.ownerUserID == ownerID, !recovery.hasPendingInstallation else { return }
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: ownerID).isEmpty else { return }
            presentationActive.wrappedValue = true
            setupRoute = BlueprintLibrarySetupRoute.workspace(from: draft, ownerID: ownerID)
        } catch { actionFailed = true }
    }

    private func createWorkspaceFromCatalog(_ installation: BlueprintUsedTemplate, previewOnly: Bool = false) async {
        guard account?.id == ownerID, let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else { return }
        do {
            let catalog = try await coordinator.catalog()
            guard account?.id == ownerID, !Task.isCancelled else { return }
            guard let entry = catalog.entries.first(where: {
                $0.catalogKey == installation.catalogKey && $0.revision == installation.revision
            }) else { actionFailed = true; return }
            let store = BlueprintSetupDraftStore()
            if !previewOnly, let existing = try store.load(ownerUserID: ownerID, catalogKey: entry.catalogKey) {
                createWorkspace(from: existing)
                return
            }
            let content = try BlueprintCustomization().applying(to: entry)
            let context = BlueprintSetupDateContext()
            let draft = BlueprintSetupDraft(ownerUserID: ownerID, entry: entry, requestID: UUID(),
                eventName: entry.definition.blueprint.name, startsAt: context.startsAt,
                timeZoneIdentifier: context.timeZoneIdentifier,
                selectedChildren: Set(content.tree.children.map(\.key)),
                selectedIdeas: Set(content.ideas.ideas.map(\.key)), confirmedDates: [:],
                previewDecisions: previewOnly ? nil : Dictionary(uniqueKeysWithValues: content.ideas.ideas.map { ($0.key, .love) }),
                mainDateConfirmed: false)
            if previewOnly {
                presentationActive.wrappedValue = true
                draftRoute = BlueprintLibraryDraftRoute(ownerID: ownerID, draft: draft, isInstalled: true,
                                                       installationID: installation.id)
                return
            }
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: ownerID).isEmpty else { return }
            try store.save(draft)
            createWorkspace(from: draft)
        } catch { if account?.id == ownerID { actionFailed = true } }
    }

    private var yoursEmptyState: some View {
        ContentUnavailableView {
            Label(BlueprintCopy.libraryYoursEmptyTitle, systemImage: "square.stack.3d.up")
        } description: {
            Text(BlueprintCopy.libraryYoursEmptyMessage)
        } actions: {
            VStack(spacing: AppTheme.Spacing.compact) {
                Button(BlueprintCopy.createTemplateTitle, action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("blueprint.library.create")
                Button(BlueprintCopy.exploreBlueprints, action: onExplore)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("blueprint.library.explore")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    private func presentSetup(catalogKey: String?, shareToken: String?) {
        guard !ownerID.isEmpty, account?.id == ownerID, !fixtureIsEnabled else { return }
        presentationActive.wrappedValue = true
        setupRoute = BlueprintLibrarySetupRoute(ownerID: ownerID, catalogKey: catalogKey, shareToken: shareToken)
    }

    private func reload() async {
        guard isActive, !ownerID.isEmpty, account?.id == ownerID else { return }
#if DEBUG
        if let fixture = previewActionsFixture {
            personalRecords = fixture.personalSource.map { [$0] } ?? []
            recovery = BlueprintSetupRecovery(
                drafts: fixture.personalSource == nil ? fixture.workingDraft.map { [$0] } ?? [] : [],
                hasPendingInstallation: false, loadFailed: false)
            personalLoading = false
            hasResolvedPersonalRecords = true
            return
        }
#endif
        guard !fixtureIsEnabled else { return }
        recovery = BlueprintSetupRecovery.load(
            ownerID: ownerID,
            readDrafts: { try BlueprintSetupDraftStore().all(ownerUserID: $0) },
            readPending: { try !BlueprintInstallationIntentStore().pending(ownerUserID: $0).isEmpty }
        )
        loadPersonalCache()
        await model.load {
            guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
                throw CloudSyncFailure.invalidSession
            }
            return try await coordinator.usedTemplates()
        }
        await refreshPersonalRecords()
    }

    private func refreshVisibleCollection() async {
        if selectedPrimaryCollection == .yours {
            await reload()
        } else {
            await actionStore?.loadPreferences()
        }
    }

    private func loadPersonalCache() {
        guard account?.id == ownerID, !ownerID.isEmpty else { return }
        do {
            personalRecords = try BlueprintPersonalLibraryStore().load(ownerID: ownerID)
            personalCacheFailed = false
        } catch {
            personalCacheFailed = true
        }
        personalLoading = true
    }

    @MainActor
    private func refreshPersonalRecords() async {
        // Avoid painting receipt cards that an initial ownership response will
        // immediately replace with personal blueprint cards. Later refreshes
        // retain the existing collection instead of returning to a spinner.
        defer {
            if account?.id == ownerID { hasResolvedPersonalRecords = true }
        }
        guard account?.id == ownerID, let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            personalLoadFailed = true
            personalLoading = false
            return
        }
        do {
            let transport: any BlueprintPersonalLibraryTransport = PostgresSyncTransport(baseURL: baseURL)
            let records = try await transport.listPersonalBlueprints()
            guard account?.id == ownerID else { return }
            try BlueprintPersonalLibraryStore().save(records, ownerID: ownerID)
            personalRecords = records
            personalLoadFailed = false
            personalCacheFailed = false
            personalLoading = false
        } catch {
            if account?.id == ownerID {
                personalLoadFailed = true
                personalLoading = false
            }
        }
    }
}

private extension View {
    func librarySurface() -> some View {
        padding(AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.surface, in: .rect(cornerRadius: AppTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .strokeBorder(AppTheme.ColorToken.hairline.opacity(0.35))
            }
    }
}

private struct BlueprintLibraryTile: View {
    let category: BlueprintBrowseCategory
    let title: String
    let subtitle: String
    var detail: String? = nil
    var coverAssetID: UUID? = nil
    var publicCoverImageURL: String? = nil
    var coverSource: BlueprintCoverSource? = nil
    var creatorName: String? = nil
    var activeShareLinkCount: Int? = nil
    var listedRevision: Int? = nil
    var showsSharingStatus = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BlueprintCoverArtwork(
                assetID: coverAssetID,
                publicImageURL: publicCoverImageURL,
                source: coverSource
            ) {
                ProgressiveArtwork(
                    symbol: category.symbol,
                    colors: category.artworkCategory.artworkColors,
                    accent: category.artworkCategory.artworkAccent,
                    ambientBlurRadius: 12,
                    progressiveBlurRadius: 0
                )
            }
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.22),
                    .init(color: .black.opacity(0.22), location: 0.50),
                    .init(color: .black.opacity(0.82), location: 1)
                ], startPoint: .top, endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).lineLimit(3)
                Text(subtitle).font(.subheadline.weight(.medium)).lineLimit(2)
                if let creatorName, !creatorName.isEmpty {
                    Text(BlueprintCopy.creatorByline(creatorName)).font(.caption).lineLimit(1)
                }
                if showsSharingStatus {
                    ZStack(alignment: .bottomLeading) {
                        // Reserve the largest status footprint before counts arrive,
                        // including the two-line layout at narrow text widths.
                        BlueprintSharingStatusBadges(activeShareLinkCount: 1, listedRevision: 1)
                            .hidden()
                            .accessibilityHidden(true)
                        BlueprintSharingStatusBadges(
                            activeShareLinkCount: activeShareLinkCount,
                            listedRevision: listedRevision
                        )
                        .opacity(activeShareLinkCount == nil && listedRevision == nil ? 0 : 1)
                        .accessibilityHidden(activeShareLinkCount == nil && listedRevision == nil)
                    }
                }
                if let detail { Text(detail).font(.caption).lineLimit(2) }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
        }
        .aspectRatio(category.catalogAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(.rect(cornerRadius: AppTheme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(.rect(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
}
