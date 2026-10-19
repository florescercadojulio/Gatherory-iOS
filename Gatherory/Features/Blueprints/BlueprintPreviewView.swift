import SwiftUI

/// Workspace-style browsing with explicitly saved, personal inclusion choices.
struct BlueprintPreviewView: View {
    let entry: BlueprintCatalogEntry
    var sharedToken: String? = nil
    var usesSavedPreview = false
    var hasPendingInstallation = false
    var allowsRepeatInstallation = false
    var installedSource: BlueprintSetupDraft? = nil
    var installedTemplateID: UUID? = nil
    var personalSource: BlueprintPersonalRecord? = nil
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.currentUserAccount) private var account
    @State private var showsSetup = false
    @State private var installationOwnerID: String?
    @State private var installationCompleted = false
    @State private var selectedTab = WorkspaceTab.home
    @State private var navigation = BlueprintPreviewNavigation()
    @State private var ideasScope = BlueprintPreviewScope.all
    @State private var session: BlueprintPreviewSession?
    @State private var saveError: String?
    @State private var loadFailed = false
    @State private var confirmsClose = false
    @State private var confirmsCustomize = false
    @State private var editorRoute: BlueprintPreviewEditorRoute?
    @State private var generation = UUID()
    @State private var alreadyInstalled = false
    @State private var savedPersonalSource: BlueprintPersonalRecord?
    @State private var isSavingPersonal = false

    private var content: BlueprintPreviewContent? { session?.content }
    private var isInstalledPreview: Bool {
        BlueprintLibraryActionPolicy.blocksInlineInstall(isInstalled: alreadyInstalled,
                                               explicitCreateWorkspace: allowsRepeatInstallation)
    }
    private var eventEditorAction: ((BlueprintPreviewEventID) -> Void)? {
        return { editEvent($0) }
    }
    private var draftSaveAction: (() -> Void)? {
        guard session?.isDirty == true else { return nil }
        return { saveDraft() }
    }

    var body: some View {
        Group {
            if let content, session?.ownerID == account?.id {
                WorkspaceTabShell(selection: $selectedTab, showsManage: false) {
                    navigationRoot(content: content, tab: .home) {
                        BlueprintWorkspaceHomeView(
                            content: content.homeContent(responses: session?.responses ?? [:]),
                            category: (session?.entry ?? entry).browseCategories.first ?? .events,
                            usesSavedPreview: usesSavedPreview,
                            onEditEvent: eventEditorAction
                        ) { id in
                            navigation.homeEvent = id
                        }
                    }
                } ideas: {
                    navigationRoot(content: content, tab: .ideas) {
                        BlueprintWorkspaceIdeasView(ideas: content.ideas(in: ideasScope), responses: session?.responses ?? [:]) { idea in
                            openEditor(.idea(idea))
                        }
                    }
                } decide: {
                    navigationRoot(content: content, tab: .decide) {
                        BlueprintWorkspaceDecideView(
                            content: content, scope: $navigation.decisionScope,
                            responses: session?.responses ?? [:],
                            onSaveDraft: draftSaveAction
                        ) { choice, key in
                            session?.decide(choice, key: key)
                            if !loadFailed { saveError = nil }
                        }
                    }
                } manage: {
                    EmptyView()
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
        .tint(AppTheme.ColorToken.accent)
        .disabled(isSavingPersonal)
        .interactiveDismissDisabled(session?.isDirty == true)
        .task(id: account?.id) { loadSession() }
        .onChange(of: selectedTab) { _, tab in
            if tab == .ideas { ideasScope = .all }
        }
        .safeAreaInset(edge: .bottom) {
            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(.red)
                    .padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .confirmationDialog(BlueprintCopy.previewUnsavedTitle, isPresented: $confirmsClose, titleVisibility: .visible) {
            Button(BlueprintCopy.saveDraft) { saveDraft { closePreview() } }
            Button(BlueprintCopy.discardPreviewChanges, role: .destructive) { closePreview() }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .confirmationDialog(BlueprintCopy.confirmInstallTitle, isPresented: $confirmsCustomize, titleVisibility: .visible) {
            Button(reviewTitle) {
                guard !isInstalledPreview, let account, session?.ownerID == account.id else { return }
                installationOwnerID = account.id
                do {
                    let pending = try BlueprintInstallationIntentStore().pending(ownerUserID: account.id)
                    if hasPendingInstallation || !pending.isEmpty { showsSetup = true }
                    else { saveDraft { showsSetup = true } }
                } catch { saveError = BlueprintCopy.previewSaveFailed }
            }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: {
            Text(BlueprintCopy.confirmInstallMessage)
        }
        .sheet(isPresented: $showsSetup, onDismiss: {
            if installationCompleted { closePreview() }
            else { loadSession() }
        }) {
            NavigationStack {
                BlueprintSetupView(
                    catalogKey: sharedToken == nil ? (session?.entry ?? entry).catalogKey : nil,
                    sharedToken: sharedToken,
                    returnsToPreview: true,
                    installationOwnerID: installationOwnerID,
                    onInstallationCompleted: { installationCompleted = true },
                    onClose: { showsSetup = false }
                )
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

    private func navigationRoot<Content: View>(
        content: BlueprintPreviewContent, tab: WorkspaceTab,
        @ViewBuilder screen: () -> Content
    ) -> some View {
        NavigationStack {
            screen()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .appClearNavigationBar()
                .toolbar {
                    if tab == .home {
                        ToolbarItem(placement: .topBarLeading) {
                            closeButton
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            if session?.isDirty == true { saveDraftButton }
                            editingMenu(content)
                        }
                    } else if tab == .ideas {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            closeButton
                            scopeMenu(content)
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button("Add Idea", systemImage: "plus") { openEditor(.idea(nil)) }
                                .labelStyle(.iconOnly)
                                .disabled(content.ideas.count >= 100 || hasPendingInstallation || loadFailed)
                        }
                    }
                }
        }
    }

    private var saveDraftButton: some View {
        Button(BlueprintCopy.saveDraft, systemImage: "checkmark") { saveDraft() }
            .labelStyle(.iconOnly)
    }

    private func scopeMenu(_ content: BlueprintPreviewContent) -> some View {
        Menu {
            Picker(AppCopy.Tab.ideas, selection: $ideasScope) {
                Text("All").tag(BlueprintPreviewScope.all)
                Text(content.title).tag(BlueprintPreviewScope.main)
                ForEach(content.children) { child in
                    Text(child.title).tag(BlueprintPreviewScope.child(child.key))
                }
            }
            if session?.isDirty == true {
                Divider()
                Button(BlueprintCopy.saveDraft, systemImage: "checkmark") { saveDraft() }
            }
        } label: {
            Label(scopeTitle(content), systemImage: "line.3.horizontal.decrease").lineLimit(1)
        }
    }

    private var reviewTitle: String {
        hasPendingInstallation ? BlueprintCopy.retryInstall
            : BlueprintCopy.previewInstall
    }

    private func editingMenu(_ content: BlueprintPreviewContent) -> some View {
        Menu {
            Section {
                if case .child(let key) = navigation.homeScope, let child = content.children.first(where: { $0.key == key }) {
                    Button(AppCopy.Common.edit, systemImage: "pencil") { openEditor(.child(child)) }
                } else {
                    Button("Event name", systemImage: "pencil") { openEditor(.name) }
                    Button("Date and Time", systemImage: "calendar") { openEditor(.dateTime) }
                }
                Button("Add Sub-event", systemImage: "calendar.badge.plus") { openEditor(.child(nil)) }
                    .disabled(content.children.count >= 50)
            }
            .disabled(hasPendingInstallation || loadFailed)
            if !isInstalledPreview {
                Divider()
                Button(reviewTitle, systemImage: "checklist") { openReview() }
            }
        } label: {
            Label(AppCopy.Common.edit, systemImage: "ellipsis").labelStyle(.iconOnly)
        }
    }

    private func openReview() {
        guard !isInstalledPreview else { return }
        confirmsCustomize = true
    }

    private func editEvent(_ id: BlueprintPreviewEventID) {
        switch id {
        case .main: openEditor(.name)
        case .child(let key):
            if let child = content?.children.first(where: { $0.key == key }) { openEditor(.child(child)) }
        }
    }

    private func openEditor(_ item: BlueprintPreviewEditorRoute.Item) {
        guard let account, session?.ownerID == account.id, !loadFailed, !hasPendingInstallation else { return }
        do {
            guard try BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty else {
                saveError = BlueprintCopy.finishPreviousInstall
                return
            }
            editorRoute = BlueprintPreviewEditorRoute(item: item, ownerID: account.id, generation: generation)
        } catch { saveError = BlueprintCopy.previewSaveFailed }
    }

    private func saveEditor(_ route: BlueprintPreviewEditorRoute, edit: (inout BlueprintPreviewSession) throws -> Void) {
        guard route.ownerID == account?.id, route.generation == generation,
              session?.ownerID == route.ownerID, !loadFailed, !hasPendingInstallation else { return }
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

    @ViewBuilder
    private func editorSheet(_ route: BlueprintPreviewEditorRoute) -> some View {
        if case .dateTime = route.item, let values = session?.mainEventValues {
            EventDateTimeEditorView(startsAt: values.startsAt, endsAt: nil, isAllDay: false,
                                    timeZoneIdentifier: values.timeZoneIdentifier, supportsExtendedSchedule: false) { date, _, _, zone in
                saveEditor(route) { current in
                    var updated = current.mainEventValues
                    updated.startsAt = date
                    updated.timeZoneIdentifier = zone
                    try current.editMainEvent(updated, confirmsDate: true)
                }
            }
        } else {
            NavigationStack {
                switch route.item {
                case .name:
                    BlueprintPreviewNameEditor(name: session?.mainEventValues.name ?? "") { name in
                        saveEditor(route) { current in
                            var updated = current.mainEventValues
                            updated.name = name
                            try current.editMainEvent(updated)
                        }
                    }
                case .child(let child):
                    BlueprintChildDraftEditor(child: child) { child in
                        saveEditor(route) { try $0.editChild(child) }
                    }
                case .idea(let idea):
                    BlueprintIdeaDraftEditor(idea: idea, children: content?.children ?? [], initialTarget: newIdeaTarget) { idea in
                        saveEditor(route) { try $0.editIdea(idea) }
                    }
                case .dateTime: EmptyView()
                }
            }
        }
    }

    private var newIdeaTarget: BlueprintTarget {
        let scope = selectedTab == .ideas ? ideasScope
            : selectedTab == .home ? navigation.homeScope : navigation.decisionScope
        return if case .child(let key) = scope { .child(key: key) } else { .main }
    }

    private func scopeTitle(_ content: BlueprintPreviewContent) -> String {
        switch ideasScope {
        case .all: String(localized: "All")
        case .main: content.title
        case .child(let key): content.children.first { $0.key == key }?.title ?? BlueprintCopy.allIdeas
        }
    }

    private var closeButton: some View {
        WorkspaceLibraryToolbarButton(
            action: {
                if session?.isDirty == true { confirmsClose = true }
                else { closePreview() }
            },
            title: BlueprintCopy.libraryTitle,
            hint: BlueprintCopy.returnToTemplates
        )
    }

    private func loadSession() {
        if session?.ownerID != account?.id {
            navigation = BlueprintPreviewNavigation()
            ideasScope = .all
            selectedTab = .home
        }
        generation = UUID()
        editorRoute = nil
        guard let account else { session = nil; return }
        do {
            if installedSource != nil { alreadyInstalled = true }
            else {
                alreadyInstalled = try BlueprintLibraryCache().load(ownerID: account.id)
                    .contains { $0.catalogKey == entry.catalogKey }
            }
            let store = BlueprintSetupDraftStore()
            let saved: BlueprintSetupDraft?
            if let sharedToken { saved = try store.load(ownerUserID: account.id, shareToken: sharedToken) }
            else { saved = try store.load(ownerUserID: account.id, catalogKey: entry.catalogKey) }
            session = BlueprintPreviewSession(
                ownerID: account.id, entry: entry, shareToken: sharedToken, savedDraft: saved,
                defaultEventName: entry.definition.experienceDefaults.type == "wedding"
                    ? BlueprintCopy.defaultEventName(for: account.displayName) : entry.definition.blueprint.name,
                sourceDraft: installedSource
            )
            loadFailed = false
            saveError = nil
        } catch {
            alreadyInstalled = true // A failed history read must not offer a duplicate install.
            session = BlueprintPreviewSession(ownerID: account.id, entry: entry, shareToken: sharedToken, savedDraft: nil,
                                             defaultEventName: entry.definition.blueprint.name)
            loadFailed = true
            saveError = BlueprintCopy.draftLoadFailed
        }
    }

    private func saveDraft(then completion: @escaping () -> Void = {}) {
        guard let account, session?.ownerID == account.id else { return }
        guard !loadFailed else { saveError = BlueprintCopy.draftLoadFailed; return }
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
                defer { isSavingPersonal = false }
                do {
                    guard self.account?.id == account.id else { return }
                    let pending = try !BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty
                    try stagedSession.save(to: BlueprintSetupDraftStore(), hasPendingInstallation: pending || hasPendingInstallation)
                    let transport = PostgresSyncTransport(baseURL: baseURL)
                    let saved = try await transport.savePersonalBlueprint(
                        id: personalSource.id,
                        expectedVersion: personalSource.draftVersion,
                        content: payload
                    )
                    guard self.account?.id == account.id else { return }
                    try BlueprintPersonalLibraryStore().upsert(saved, ownerID: account.id)
                    self.savedPersonalSource = saved
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
                    working.customizations = nil
                    try drafts.save(working)
                    self.session = BlueprintPreviewSession(ownerID: account.id, entry: saved.catalogEntry,
                        shareToken: nil, savedDraft: working, defaultEventName: saved.catalogEntry.definition.blueprint.name)
                    self.saveError = nil
                    completion()
                } catch { self.saveError = BlueprintCopy.previewSaveFailed }
            }
            return
        }
        do {
            let pending = try !BlueprintInstallationIntentStore().pending(ownerUserID: account.id).isEmpty
            try session?.save(to: BlueprintSetupDraftStore(), hasPendingInstallation: pending || hasPendingInstallation)
            if let installedTemplateID, let saved = session?.draft {
                try BlueprintLibraryCache().updateSource(saved, installationID: installedTemplateID, ownerID: account.id)
            }
            saveError = nil
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
    var onEdit: (() -> Void)? = nil
    private var category: IdeaCategory { IdeaCategory(rawValue: idea.category) ?? .other }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        IdeaDetailScreen(content: IdeaDetailContent(preview: idea)) {
            EmptyView()
        } footer: {
            EmptyView()
        } details: {
            IdeaCategoryDetailContent(idea: IdeaDetailContent(preview: idea))
        } artwork: {
            MediaArtwork(
                imageData: nil, symbol: category.symbol,
                colors: category.artworkColors, accent: category.artworkAccent,
                ambientBlurRadius: 10,
                progressiveBlurRadius: reduceTransparency ? 0 : 22,
                blurStart: 0.40
            )
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
