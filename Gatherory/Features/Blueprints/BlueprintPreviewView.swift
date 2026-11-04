import SwiftUI

private struct BlueprintPreviewSetupRoute: Identifiable {
    let id = UUID()
    let ownerID: String
}

/// Workspace-style browsing with explicitly saved, personal inclusion choices.
struct BlueprintPreviewView: View {
    let entry: BlueprintCatalogEntry
    var presentationContext: BlueprintPreviewPresentation.Context = .discovery
    var actionStore: BlueprintActionStore? = nil
    var sharedToken: String? = nil
    var usesSavedPreview = false
    var hasPendingInstallation = false
    var allowsRepeatInstallation = false
    var installedSource: BlueprintSetupDraft? = nil
    var installedTemplateID: UUID? = nil
    var personalSource: BlueprintPersonalRecord? = nil
    var onClose: (() -> Void)? = nil
    var onInstalledWorkspace: ((UUID) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentUserAccount) private var account
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var setupRoute: BlueprintPreviewSetupRoute?
    @State private var pendingInstallationDetected = false
    @State private var installationCompleted = false
    @State private var session: BlueprintPreviewSession?
    @State private var saveError: String?
    @State private var loadFailed = false
    @State private var confirmsClose = false
    @State private var editorRoute: BlueprintPreviewEditorRoute?
    @State private var generation = UUID()
    @State private var alreadyInstalled = false
    @State private var savedPersonalSource: BlueprintPersonalRecord?
    @State private var isSavingPersonal = false
    @State private var needsPersonalSaveRetry = false
    @State private var saveConfirmationID: UUID?

    private var coverSource: BlueprintCoverSource {
        let source = session?.entry ?? entry
        return BlueprintCoverSource(catalogKey: source.catalogKey, revision: source.revision, shareToken: sharedToken)
    }

    private var hasUnsavedChanges: Bool { session?.isDirty == true || needsPersonalSaveRetry }
    private var hasActivePendingInstallation: Bool { hasPendingInstallation || pendingInstallationDetected }
    private var usesLibraryVisualFixture: Bool {
#if DEBUG
        BlueprintLibraryVisualFixture.load(ownerID: account?.id ?? "") != nil
#else
        false
#endif
    }
    private var presentation: BlueprintPreviewPresentation {
        .resolve(requested: presentationContext, currentAccountID: account?.id,
                 actionStoreOwnerID: actionStore?.ownerID,
                 hasInstalledSource: installedSource != nil, hasPersonalSource: personalSource != nil,
                 hasSharedToken: sharedToken != nil)
    }
    private var allowsPublicActions: Bool { presentation.showsPreferenceActions && entry.viewerState != nil }
    private var viewerState: BlueprintViewerState {
        let state = actionStore?.ownerID == account?.id ? actionStore?.states[entry.catalogKey] : nil
        return state ?? entry.viewerState ?? .init()
    }

    private var content: BlueprintPreviewContent? { session?.content }
    private var isInstalledPreview: Bool {
        BlueprintLibraryActionPolicy.blocksInlineInstall(isInstalled: alreadyInstalled,
                                               explicitCreateWorkspace: allowsRepeatInstallation)
    }
    private var mainEventSchedule: String? {
        guard let values = session?.confirmedMainEventValues else { return nil }
        return values.startsAt.formatted(Date.FormatStyle(
            date: .abbreviated, time: .shortened,
            timeZone: TimeZone(identifier: values.timeZoneIdentifier) ?? .autoupdatingCurrent
        ))
    }

    private var draftSaveAction: (() -> Void)? {
        guard presentation.allowsDraftSaving, hasUnsavedChanges else { return nil }
        return { saveDraft() }
    }

    var body: some View {
        Group {
            if let content, session?.ownerID == account?.id {
                if presentation.allowsEditing {
                    navigationRoot {
                        BlueprintWorkspaceSingleScrollView(
                            content: content,
                            category: (session?.entry ?? entry).browseCategories.first ?? .events,
                            creatorName: content.creatorName,
                            mainEventSchedule: mainEventSchedule,
                            canEditContent: session?.ownerID == account?.id && !hasActivePendingInstallation && !loadFailed && !usesLibraryVisualFixture,
                            canAddEvent: content.children.count < 50 && !hasActivePendingInstallation && !loadFailed && !usesLibraryVisualFixture,
                            canAddIdea: content.ideas.count < 100 && !hasActivePendingInstallation && !loadFailed && !usesLibraryVisualFixture,
                            canCreateEvents: !isInstalledPreview && !loadFailed && session?.ownerID == account?.id && !usesLibraryVisualFixture,
                            createEventsTitle: workspaceActionTitle,
                            onEditEvent: { editEvent($0) },
                            onEditIdea: { openEditor(.idea($0)) },
                            onAddEvent: { openEditor(.child(nil)) },
                            onAddIdea: { openEditor(.idea(nil)) },
                            onCreateEvents: { openSetup() }
                        )
                    }
                } else {
                    navigationRoot {
                        BlueprintPublicPreviewView(
                            content: content,
                            category: (session?.entry ?? entry).browseCategories.first ?? .events
                        ) { _ in }
                    }
                }
            } else {
                NavigationStack {
                    Group {
                        if session == nil { ProgressView() }
                        else { ContentUnavailableView(BlueprintCopy.loadFailed, systemImage: "square.stack.3d.up.slash") }
                    }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { closeButton }
                        }
                }
            }
        }
        .environment(\.blueprintCoverSource, coverSource)
        .tint(AppTheme.ColorToken.accent)
        .disabled(isSavingPersonal)
        .interactiveDismissDisabled(hasUnsavedChanges || isSavingPersonal)
        .task(id: account?.id) { loadSession() }
        .safeAreaInset(edge: .bottom) {
            if let saveError {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if loadFailed { loadSession() }
                        else { saveDraft() }
                    } label: {
                        Text(AppCopy.Common.retry)
                            .font(.footnote.weight(.semibold))
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityElement(children: .contain)
            }
        }
        .appHaptic(.success, trigger: saveConfirmationID) { _, confirmationID in
            confirmationID != nil
        }
        .onChange(of: saveError) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
        .task(id: editorRoute == nil ? saveConfirmationID : nil) {
            guard editorRoute == nil, let confirmationID = saveConfirmationID else { return }
            AccessibilityNotification.Announcement(BlueprintCopy.previewSaved).post()
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, saveConfirmationID == confirmationID else { return }
            saveConfirmationID = nil
        }
        .confirmationDialog(BlueprintCopy.previewUnsavedTitle, isPresented: $confirmsClose, titleVisibility: .visible) {
            Button(BlueprintCopy.saveDraft) { saveDraft { closePreview() } }
            Button(BlueprintCopy.discardPreviewChanges, role: .destructive) { closePreview() }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .alert(BlueprintCopy.actionUpdateFailed, isPresented: Binding(
            get: { actionStore?.ownerID == account?.id && actionStore?.error != nil },
            set: { if !$0, actionStore?.ownerID == account?.id { actionStore?.clearError() } }
        )) {
            Button(AppCopy.Common.retry) { Task { await actionStore?.retryLastAction() } }
            Button(AppCopy.Common.cancel, role: .cancel) { actionStore?.clearError() }
        } message: {
            Text(actionStore?.error?.localizedDescription ?? BlueprintCopy.actionUpdateFailed)
        }
        .sheet(item: $setupRoute, onDismiss: {
            if installationCompleted { closePreview() }
            else { loadSession() }
        }) { route in
            NavigationStack {
                if account?.id == route.ownerID {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-BlueprintSetupDateConfirmationFixture"),
                   let ownerID = account?.id,
                   let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: ownerID) {
                    BlueprintSetupView(
                        catalogKey: sharedToken == nil ? (session?.entry ?? entry).catalogKey : nil,
                        sharedToken: sharedToken,
                        returnsToPreview: true,
                        installationOwnerID: route.ownerID,
                        onInstallationCompleted: { installationCompleted = true },
                        onInstalledWorkspace: onInstalledWorkspace,
                        onClose: { setupRoute = nil },
                        setupDraftStore: fixture.makeSetupDraftStore(),
                        installationCoordinatorFactory: {
                            guard let account, account.id == route.ownerID else { return nil }
                            return fixture.makeInstallationCoordinator(library: workspaceLibrary, account: account)
                        }
                    )
                } else {
                    BlueprintSetupView(
                        catalogKey: sharedToken == nil ? (session?.entry ?? entry).catalogKey : nil,
                        sharedToken: sharedToken,
                        returnsToPreview: true,
                        installationOwnerID: route.ownerID,
                        onInstallationCompleted: { installationCompleted = true },
                        onInstalledWorkspace: onInstalledWorkspace,
                        onClose: { setupRoute = nil }
                    )
                }
#else
                BlueprintSetupView(
                    catalogKey: sharedToken == nil ? (session?.entry ?? entry).catalogKey : nil,
                    sharedToken: sharedToken,
                    returnsToPreview: true,
                    installationOwnerID: route.ownerID,
                    onInstallationCompleted: { installationCompleted = true },
                    onInstalledWorkspace: onInstalledWorkspace,
                    onClose: { setupRoute = nil }
                )
#endif
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editorRoute) { route in
            if route.ownerID == account?.id, route.generation == generation {
                editorSheet(route)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func navigationRoot<Content: View>(@ViewBuilder screen: () -> Content) -> some View {
        NavigationStack {
            screen()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .appClearNavigationBar()
                .overlay(alignment: .top) {
                    saveFeedback
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        closeButton
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if allowsPublicActions {
                            Button {
                                updatePreference(.like, enabled: !viewerState.liked)
                            } label: {
                                Image(systemName: viewerState.liked ? "heart.fill" : "heart")
                            }
                            .accessibilityLabel(viewerState.liked ? BlueprintCopy.unlike : BlueprintCopy.like)
                            .accessibilityIdentifier("blueprint.preview.like")
                            Button {
                                updatePreference(.bookmark, enabled: !viewerState.bookmarked)
                            } label: {
                                Image(systemName: viewerState.bookmarked ? "bookmark.fill" : "bookmark")
                            }
                            .accessibilityLabel(viewerState.bookmarked ? BlueprintCopy.removeBookmark : BlueprintCopy.saveBookmark)
                            .accessibilityIdentifier("blueprint.preview.bookmark")
                        }
                        if allowsPublicActions || (presentation.showsUseInMore && !isInstalledPreview) {
                            publicActionsMenu
                        }
                        if presentation.allowsEditing, hasUnsavedChanges {
                            saveDraftButton
                        }
                    }
                    if !presentation.allowsEditing && !isInstalledPreview && presentation.showsProminentUse {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(workspaceActionTitle) { openSetup() }
                                .buttonStyle(.borderedProminent)
                                .foregroundStyle(AppTheme.ColorToken.onAccent)
                                .accessibilityIdentifier("blueprint.preview.use")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var saveFeedback: some View {
        if editorRoute == nil, saveError == nil, isSavingPersonal || saveConfirmationID != nil {
            HStack(spacing: AppTheme.Spacing.compact) {
                if isSavingPersonal {
                    ProgressView().controlSize(.small)
                    Text(BlueprintCopy.previewSaving)
                } else {
                    Label(BlueprintCopy.previewSaved, systemImage: "checkmark.circle.fill")
                }
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, AppTheme.Spacing.compact)
            .allowsHitTesting(false)
        }
    }

    private var saveDraftButton: some View {
        Button(BlueprintCopy.previewSaveChanges, systemImage: "checkmark") { saveDraft() }
            .labelStyle(.titleOnly)
            .accessibilityIdentifier("blueprint.preview.saveChanges")
    }

    private var publicActionsMenu: some View {
        Menu {
            if presentation.showsUseInMore, !isInstalledPreview {
                Button(workspaceActionTitle, systemImage: "square.stack.3d.up") { openSetup() }
                    .accessibilityIdentifier("blueprint.preview.use")
            }
            if allowsPublicActions {
                Button(role: .destructive) {
                    updatePreference(.notInterested, enabled: !viewerState.notInterested)
                } label: {
                    Label(viewerState.notInterested ? BlueprintCopy.undoNotInterested : BlueprintCopy.notInterested,
                          systemImage: "eye.slash")
                }
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel(BlueprintCopy.blueprintActions)
        .accessibilityIdentifier("blueprint.preview.more")
    }

    private func updatePreference(_ kind: BlueprintPreferenceKind, enabled: Bool) {
        guard allowsPublicActions, let actionStore, actionStore.ownerID == account?.id else { return }
        Task { _ = await actionStore.set(kind, enabled: enabled, for: entry) }
    }

    private var workspaceActionTitle: String {
        hasActivePendingInstallation ? BlueprintCopy.retryCreateEvents
            : presentation.allowsEditing ? BlueprintCopy.use : BlueprintCopy.previewInstall
    }

    private func openSetup() {
        guard !usesLibraryVisualFixture else { return }
        guard !isInstalledPreview, let account, session?.ownerID == account.id else { return }
        guard !loadFailed else { saveError = BlueprintCopy.draftLoadFailed; return }
#if DEBUG
        if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: account.id) {
            if ProcessInfo.processInfo.arguments.contains("-BlueprintSetupDateConfirmationFixture") {
                do {
                    try fixture.prepareSetupDraftForDirectInstall()
                    setupRoute = BlueprintPreviewSetupRoute(ownerID: account.id)
                } catch { saveError = BlueprintCopy.previewSaveFailed }
                return
            }
            do {
                let draft = try BlueprintPreviewWorkingCopy.prepare(
                    ownerID: account.id, entry: entry, shareToken: sharedToken,
                    defaultEventName: entry.definition.blueprint.name, store: fixture.draftStore,
                    hasPendingInstallation: hasActivePendingInstallation
                )
                try fixture.saveWorkingDraft(draft)
                closePreview()
            } catch { saveError = BlueprintCopy.previewSaveFailed }
            return
        }
#endif
        do {
            let pending = try BlueprintInstallationIntentStore().pending(ownerUserID: account.id)
            if hasActivePendingInstallation || !pending.isEmpty { setupRoute = BlueprintPreviewSetupRoute(ownerID: account.id) }
            else if presentation.allowsEditing { saveDraft { setupRoute = BlueprintPreviewSetupRoute(ownerID: account.id) } }
            else {
                _ = try BlueprintPreviewWorkingCopy.prepare(
                    ownerID: account.id, entry: entry, shareToken: sharedToken,
                    defaultEventName: entry.definition.experienceDefaults.type == "wedding"
                        ? BlueprintCopy.defaultEventName(for: account.displayName) : entry.definition.blueprint.name,
                    store: BlueprintSetupDraftStore(), hasPendingInstallation: false
                )
                setupRoute = BlueprintPreviewSetupRoute(ownerID: account.id)
            }
        } catch { saveError = BlueprintCopy.previewSaveFailed }
    }

    private func editEvent(_ id: BlueprintPreviewEventID) {
        switch id {
        case .main: openEditor(.mainEvent)
        case .child(let key):
            if let child = content?.children.first(where: { $0.key == key }) { openEditor(.child(child)) }
        }
    }

    private func openEditor(_ item: BlueprintPreviewEditorRoute.Item) {
        guard presentation.allowsEditing else { return }
        guard !usesLibraryVisualFixture else { return }
        guard let account, session?.ownerID == account.id, !loadFailed, !hasActivePendingInstallation else { return }
        saveConfirmationID = nil
#if DEBUG
        if BlueprintPreviewActionsVisualFixture.load(ownerID: account.id) != nil {
            editorRoute = BlueprintPreviewEditorRoute(item: item, ownerID: account.id, generation: generation)
            return
        }
#endif
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty else {
                saveError = BlueprintCopy.finishPreviousInstall
                return
            }
            editorRoute = BlueprintPreviewEditorRoute(item: item, ownerID: account.id, generation: generation)
        } catch { saveError = BlueprintCopy.previewSaveFailed }
    }

    private func saveEditor(_ route: BlueprintPreviewEditorRoute, edit: (inout BlueprintPreviewSession) throws -> Void) {
        guard presentation.allowsEditing else { return }
        guard route.ownerID == account?.id, route.generation == generation,
              session?.ownerID == route.ownerID, !loadFailed, !hasActivePendingInstallation else { return }
#if DEBUG
        if BlueprintPreviewActionsVisualFixture.load(ownerID: route.ownerID) != nil {
            do {
                if var current = session {
                    try edit(&current)
                    session = current
                    saveDraft()
                }
            } catch { saveError = BlueprintCopy.customizationInvalid }
            return
        }
#endif
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: route.ownerID).isEmpty else {
                saveError = BlueprintCopy.finishPreviousInstall
                return
            }
            if var current = session {
                try edit(&current)
                session = current
                saveDraft()
            }
        } catch { saveError = BlueprintCopy.customizationInvalid }
    }

    private func editorSheet(_ route: BlueprintPreviewEditorRoute) -> some View {
        NavigationStack {
            switch route.item {
            case .mainEvent:
                if let values = session?.mainEventValues {
                    BlueprintMainEventDraftEditor(values: values, coverAssetID: content?.coverAssetID,
                                                 publicCoverImageURL: content?.publicCoverImageURL) { values, coverID, confirmsDate, coverWasRemoved in
                        saveEditor(route) { current in
                            try current.editMainEvent(values, confirmsDate: confirmsDate)
                            if coverWasRemoved || coverID != current.content?.coverAssetID {
                                current.editCoverAssetID(coverID)
                            }
                        }
                    }
                }
            case .child(let child):
                BlueprintChildDraftEditor(child: child, publicCoverImageURL: child.flatMap { content?.publicChildCoverImageURLs[$0.key] }) { child in
                    saveEditor(route) { try $0.editChild(child) }
                }
            case .idea(let idea):
                BlueprintIdeaDraftEditor(idea: idea, children: content?.children ?? [],
                                         publicCoverImageURL: idea.flatMap { content?.publicIdeaCoverImageURLs[$0.key] },
                                         initialTarget: newIdeaTarget) { idea in
                    saveEditor(route) { try $0.editIdea(idea) }
                }
            }
        }
        .environment(\.blueprintCoverSource, coverSource)
    }

    private var newIdeaTarget: BlueprintTarget {
        .main
    }

    private var closeButton: some View {
        Group {
            if presentation.context == .discovery || presentation.context == .personal {
                Button(AppCopy.Common.back, systemImage: "chevron.backward", action: requestClose)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: AppTheme.Layout.minimumTouchTarget,
                           minHeight: AppTheme.Layout.minimumTouchTarget)
            } else {
                WorkspaceLibraryToolbarButton(
                    action: requestClose,
                    title: BlueprintCopy.libraryTitle,
                    hint: BlueprintCopy.returnToTemplates
                )
            }
        }
        .accessibilityIdentifier("blueprint.preview.close")
    }

    private func requestClose() {
        if hasUnsavedChanges { confirmsClose = true }
        else { closePreview() }
    }

    private func loadSession() {
        if setupRoute?.ownerID != account?.id { setupRoute = nil }
        if session?.ownerID != account?.id {
            pendingInstallationDetected = false
            savedPersonalSource = nil
        }
        generation = UUID()
        isSavingPersonal = false
        needsPersonalSaveRetry = false
        saveConfirmationID = nil
        editorRoute = nil
        guard let account else { session = nil; pendingInstallationDetected = false; return }
        do {
            let pending = try BlueprintInstallationIntentStore().pending(ownerUserID: account.id)
            pendingInstallationDetected = hasPendingInstallation || !pending.isEmpty
        } catch {
            pendingInstallationDetected = true
        }
#if DEBUG
        if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: account.id) {
            session = BlueprintPreviewSession(
                ownerID: account.id, entry: entry, shareToken: sharedToken,
                savedDraft: presentation.allowsEditing ? fixture.workingDraft ?? fixture.savedDraft : nil,
                defaultEventName: entry.definition.blueprint.name,
                sourceDraft: presentation.allowsEditing ? installedSource : nil,
                creatorName: personalSource?.creatorName
            )
            alreadyInstalled = installedSource != nil || personalSource != nil
            loadFailed = false
            saveError = nil
            return
        }
        if let fixture = BlueprintLibraryVisualFixture.load(ownerID: account.id) {
            let saved = fixture.recovery.drafts.first {
                $0.ownerUserID == account.id && $0.entry.catalogKey == entry.catalogKey && $0.shareToken == sharedToken
            }
            alreadyInstalled = installedSource != nil
            session = BlueprintPreviewSession(
                ownerID: account.id, entry: entry, shareToken: sharedToken,
                savedDraft: presentation.allowsEditing ? saved : nil, defaultEventName: entry.definition.blueprint.name,
                sourceDraft: presentation.allowsEditing ? installedSource : nil, creatorName: personalSource?.creatorName
            )
            loadFailed = false
            saveError = nil
            return
        }
#endif
        do {
            if installedSource != nil { alreadyInstalled = true }
            else {
                alreadyInstalled = try BlueprintLibraryCache().load(ownerID: account.id)
                    .contains { $0.catalogKey == entry.catalogKey }
            }
            if !presentation.allowsEditing {
                // Discovery reads the public plan, never an account's private
                // saved customizations or personal Decide responses.
                session = BlueprintPreviewSession(ownerID: account.id, entry: entry, shareToken: sharedToken,
                    savedDraft: nil, defaultEventName: entry.definition.blueprint.name)
                loadFailed = false
                saveError = nil
                return
            }
            let store = BlueprintSetupDraftStore()
            let saved: BlueprintSetupDraft?
            if let sharedToken { saved = try store.load(ownerUserID: account.id, shareToken: sharedToken) }
            else { saved = try store.load(ownerUserID: account.id, catalogKey: entry.catalogKey) }
            session = BlueprintPreviewSession(
                ownerID: account.id, entry: entry, shareToken: sharedToken, savedDraft: saved,
                defaultEventName: entry.definition.experienceDefaults.type == "wedding"
                    ? BlueprintCopy.defaultEventName(for: account.displayName) : entry.definition.blueprint.name,
                sourceDraft: installedSource,
                creatorName: (savedPersonalSource ?? personalSource)?.creatorName
            )
            if saved != nil, let personalSource = savedPersonalSource ?? personalSource, let session {
                needsPersonalSaveRetry = try personalSource.editedContent(from: session) != personalSource.draftContent
            }
            loadFailed = false
            saveError = nil
        } catch {
            alreadyInstalled = true // A failed history read must not offer a duplicate install.
            session = BlueprintPreviewSession(ownerID: account.id, entry: entry, shareToken: sharedToken, savedDraft: nil,
                                             defaultEventName: entry.definition.blueprint.name,
                                             creatorName: (savedPersonalSource ?? personalSource)?.creatorName)
            loadFailed = true
            saveError = BlueprintCopy.draftLoadFailed
        }
    }

    private func saveDraft(then completion: @escaping () -> Void = {}) {
        guard presentation.allowsDraftSaving else { return }
        guard !usesLibraryVisualFixture else { return }
        guard let account, session?.ownerID == account.id else { return }
        guard !loadFailed else { saveError = BlueprintCopy.draftLoadFailed; return }
        guard !isSavingPersonal else { return }
#if DEBUG
        if let fixture = BlueprintPreviewActionsVisualFixture.load(ownerID: account.id) {
            do {
                try session?.save(to: fixture.draftStore, hasPendingInstallation: hasActivePendingInstallation)
                if let saved = session?.draft { try fixture.saveWorkingDraft(saved) }
                saveConfirmationID = UUID()
                completion()
            } catch { saveError = BlueprintCopy.previewSaveFailed }
            return
        }
#endif
        let saveGeneration = generation
        saveConfirmationID = nil
        saveError = nil
        if let personalSource = savedPersonalSource ?? personalSource {
            guard !isSavingPersonal, let session else { return }
            let payload: BlueprintDraftContent
            do { payload = try personalSource.editedContent(from: session) }
            catch { saveError = BlueprintCopy.previewSaveFailed; return }
            var stagedSession = session
            isSavingPersonal = true
            guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
                saveError = BlueprintCopy.previewSaveFailed
                isSavingPersonal = false
                return
            }
            Task {
                defer {
                    if self.generation == saveGeneration { isSavingPersonal = false }
                }
                do {
                    guard self.account?.id == account.id, self.generation == saveGeneration else { return }
                    let pending = try !BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty
                    try stagedSession.save(to: BlueprintSetupDraftStore(), hasPendingInstallation: pending || hasActivePendingInstallation)
                    let transport = PostgresSyncTransport(baseURL: baseURL)
                    let saved = try await transport.savePersonalBlueprint(
                        id: personalSource.id,
                        expectedVersion: personalSource.draftVersion,
                        content: payload
                    )
                    guard self.account?.id == account.id, self.generation == saveGeneration else { return }
                    // Retain the acknowledged revision even if the local cache
                    // fails, so Retry never reuses an obsolete server version.
                    self.savedPersonalSource = saved
                    try BlueprintPersonalLibraryStore().upsert(saved, ownerID: account.id)
                    // A published save is a new immutable revision, never a mutation of a copy.
                    guard var working = stagedSession.draft else { throw CloudSyncFailure.invalidResponse }
                    let drafts = BlueprintSetupDraftStore()
                    guard try drafts.load(ownerUserID: account.id, catalogKey: working.entry.catalogKey)?.requestID == working.requestID,
                          try BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty else {
                        throw BlueprintPreviewSession.SaveError.draftChanged
                    }
                    if working.entry.contentHash != saved.catalogEntry.contentHash {
                        working.copyRequestID = nil
                        working.copyEntry = nil
                    }
                    working.entry = saved.catalogEntry
                    // Keep explicit Home inclusion after the server folds edits
                    // into its new catalog entry. Use the acknowledged child values.
                    let editedChildKeys = Set(stagedSession.customizations.children.map(\.key))
                    let explicitChildren = saved.draftContent.children.filter { editedChildKeys.contains($0.key) }
                    working.customizations = explicitChildren.isEmpty ? nil
                        : BlueprintCustomization(children: explicitChildren)
                    try drafts.save(working)
                    self.session = BlueprintPreviewSession(ownerID: account.id, entry: saved.catalogEntry,
                        shareToken: nil, savedDraft: working, defaultEventName: saved.catalogEntry.definition.blueprint.name,
                        creatorName: saved.creatorName)
                    self.needsPersonalSaveRetry = false
                    self.saveError = nil
                    self.saveConfirmationID = UUID()
                    completion()
                } catch {
                    guard self.account?.id == account.id, self.generation == saveGeneration else { return }
                    // The local snapshot may already be written. Keep its request ID
                    // so retry can continue without conflicting with our own save.
                    if stagedSession.draft != nil { self.session = stagedSession }
                    self.needsPersonalSaveRetry = true
                    self.saveError = BlueprintCopy.previewSaveFailed
                }
            }
            return
        }
        do {
            let pending = try !BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty
            try session?.save(to: BlueprintSetupDraftStore(), hasPendingInstallation: pending || hasActivePendingInstallation)
            if let installedTemplateID, let saved = session?.draft {
                try BlueprintLibraryCache().updateSource(saved, installationID: installedTemplateID, ownerID: account.id)
            }
            saveError = nil
            saveConfirmationID = UUID()
            completion()
        } catch {
            saveError = BlueprintCopy.previewSaveFailed
        }
    }

    private func closePreview() {
        if let onClose { onClose() } else { dismiss() }
    }
}

/// The same idea reading screen used by a live workspace, with authored content only.
struct BlueprintIdeaPreview: View {
    let idea: BlueprintCatalogIdea
    var publicImageURL: String? = nil
    var onEdit: (() -> Void)? = nil
    private var category: IdeaCategory { IdeaCategory(rawValue: idea.category) ?? .other }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        IdeaDetailScreen(content: IdeaDetailContent(preview: idea), collapsesLongText: true) {
            EmptyView()
        } footer: {
            EmptyView()
        } details: {
            IdeaNotesCard(note: idea.notes ?? "", category: category, collapsesLongText: true)
        } artwork: {
            BlueprintCoverArtwork(assetID: idea.coverAssetId, publicImageURL: publicImageURL) {
                MediaArtwork(
                    imageData: nil, symbol: category.symbol,
                    colors: category.artworkColors, accent: category.artworkAccent,
                    ambientBlurRadius: 10,
                    progressiveBlurRadius: reduceTransparency ? 0 : 22,
                    blurStart: 0.40
                )
            }
        }
        .textSelection(.enabled)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            if let onEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppCopy.Common.edit, systemImage: "pencil", action: onEdit).labelStyle(.iconOnly)
                }
            }
        }
    }
}
