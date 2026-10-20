import SwiftUI

struct BlueprintCreateShareView: View {
    private struct PendingSearchChange {
        let templateID: UUID
        let revision: Int
        let shouldPublish: Bool
    }
    private struct PendingReplacement {
        let templateID: UUID
        let revision: Int
        let hasLiveURL: Bool
    }
    private struct PendingCreatorNameChange: Identifiable {
        let templateID: UUID
        let revision: Int
        var id: UUID { templateID }
    }

    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID
    let workspace: PlanningWorkspace
    var publishesToSearch = false
    var createsShareLink = true
    var startsWithReview = false
    var onClose: (() -> Void)? = nil

    @State private var store: BlueprintCreateShareStore?
    @State private var isShowingReview = false
    @State private var didAttemptInitialReview = false
    @State private var pendingRevokeID: UUID?
    @State private var pendingSearchChange: PendingSearchChange?
    @State private var pendingCreatorNameChange: PendingCreatorNameChange?
    @State private var pendingReplacement: PendingReplacement?

    private var accountID: String? { authentication.currentUser?.id }
    private var canManageSource: Bool {
        BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL,
            workspace: workspace
        ) != nil
    }
    private var loadIdentity: String { "\(eventID)|\(accountID ?? "")" }
    private var title: String {
        guard store?.created == nil else { return BlueprintCopy.templateReady }
        return createsShareLink ? BlueprintCopy.shareTemplate : BlueprintCopy.saveBlueprint
    }

    var body: some View {
        Group {
            if !canManageSource {
                ContentUnavailableView(
                    BlueprintCopy.templateLinksUnavailable,
                    systemImage: "lock",
                    description: Text(BlueprintCopy.templateCreationPermissionLost)
                )
            } else if accountID == nil {
                ContentUnavailableView(
                    BlueprintCopy.signInRequired,
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(BlueprintCopy.templateLinkSignIn)
                )
            } else if let store {
                if startsWithReview, store.isLoading || store.isReviewing {
                    ProgressView(BlueprintCopy.preparingTemplateReview)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if startsWithReview {
                    if store.sourceReloadRequired || store.source == nil {
                        preparationRetryView(store)
                    } else {
                        reviewView(store)
                    }
                } else if isShowingReview && !store.sourceReloadRequired {
                    reviewView(store)
                } else {
                    selectionView(store)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Close") {
                    if let onClose { onClose() }
                    else { dismiss() }
                }
            }
        }
        .task(id: loadIdentity) {
            await loadInitialState()
        }
        .onChange(of: authentication.currentUser?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            pendingSearchChange = nil
            pendingCreatorNameChange = nil
            pendingReplacement = nil
            store?.invalidate()
            store = nil
            dismiss()
        }
        .onChange(of: canManageSource) { _, allowed in
            guard !allowed else { return }
            pendingSearchChange = nil
            pendingCreatorNameChange = nil
            pendingReplacement = nil
            store?.invalidate()
            store = nil
            dismiss()
        }
        .onChange(of: store?.sourceReloadRequired) { _, required in
            if required == true { isShowingReview = false }
        }
        .onDisappear {
            pendingRevokeID = nil
            pendingSearchChange = nil
            pendingCreatorNameChange = nil
            pendingReplacement = nil
            store?.invalidate()
            store = nil
        }
        .confirmationDialog(
            BlueprintCopy.confirmRevokeTitle,
            isPresented: revokeConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button(BlueprintCopy.revoke, role: .destructive) {
                guard let linkID = pendingRevokeID, let store else { return }
                pendingRevokeID = nil
                Task { await store.revokeCreatedLink(linkID) }
            }
            Button("Cancel", role: .cancel) { pendingRevokeID = nil }
        } message: {
            Text(BlueprintCopy.confirmRevokeMessage)
        }
        .confirmationDialog(
            pendingSearchChange?.shouldPublish == true
                ? BlueprintCopy.confirmListInSearchTitle
                : BlueprintCopy.confirmRemoveFromSearchTitle,
            isPresented: searchVisibilityConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            if let pendingSearchChange {
                Button(
                    pendingSearchChange.shouldPublish ? BlueprintCopy.listInSearch : BlueprintCopy.removeFromSearch,
                    role: pendingSearchChange.shouldPublish ? nil : .destructive
                ) {
                    self.pendingSearchChange = nil
                    guard let store,
                          store.created?.templateId == pendingSearchChange.templateID,
                          store.created?.revision == pendingSearchChange.revision else { return }
                    Task { await store.setDiscoverable(pendingSearchChange.shouldPublish) }
                }
            }
            Button("Cancel", role: .cancel) { pendingSearchChange = nil }
        } message: {
            Text(pendingSearchChange?.shouldPublish == true
                ? BlueprintCopy.confirmListInSearchMessage
                : BlueprintCopy.confirmRemoveFromSearchMessage)
        }
        .sheet(item: $pendingCreatorNameChange) { candidate in
            BlueprintCreatorNameSheet(
                isSubmitting: store?.isCreating == true,
                onPublish: { name in
                    guard let store, canManageSource,
                          store.created?.templateId == candidate.templateID,
                          store.created?.revision == candidate.revision,
                          !store.requiresLinkRefresh else {
                        pendingCreatorNameChange = nil
                        return
                    }
                    pendingCreatorNameChange = nil
                    Task { await store.setDiscoverable(true, creatorName: name) }
                },
                onCancel: { pendingCreatorNameChange = nil }
            )
        }
        .confirmationDialog(
            BlueprintCopy.confirmReplaceShareLinkTitle,
            isPresented: Binding(
                get: { pendingReplacement != nil },
                set: { if !$0 { pendingReplacement = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(BlueprintCopy.replaceShareLink) {
                guard let pendingReplacement, let store,
                      canManageSource,
                      store.created?.templateId == pendingReplacement.templateID,
                      store.created?.revision == pendingReplacement.revision else {
                    self.pendingReplacement = nil
                    return
                }
                guard pendingReplacement.hasLiveURL ? store.canReplaceShareLink : store.canCreate else {
                    self.pendingReplacement = nil
                    return
                }
                self.pendingReplacement = nil
                Task {
                    if pendingReplacement.hasLiveURL { await store.replaceShareLink() }
                    else { await store.createAndShare() }
                }
            }
            Button("Cancel", role: .cancel) { pendingReplacement = nil }
        } message: {
            Text(BlueprintCopy.confirmReplaceShareLinkMessage)
        }
    }

    private func selectionView(_ store: BlueprintCreateShareStore) -> some View {
        List {
            if store.isLoading, store.source == nil {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if let source = store.source {
                Section {
                    Text(BlueprintCopy.templateCaptureExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(source.source.event.title)
                        .font(.headline)
                } header: {
                    Text(BlueprintCopy.sourceEvent)
                }

                Section {
                    TextField(BlueprintCopy.templateName, text: nameBinding(store))
                        .disabled(!store.canEdit || store.sourceReloadRequired)
                } header: {
                    Text(BlueprintCopy.templateDetails)
                }

                if !source.source.children.isEmpty {
                    Section {
                        ForEach(source.source.children, id: \.id) { child in
                            Toggle(isOn: childBinding(child.id, store: store)) {
                                Text(child.title)
                            }
                            .disabled(!store.canEdit || store.sourceReloadRequired)
                        }
                    } header: {
                        Text(BlueprintCopy.captureChildren)
                    } footer: {
                        Text(BlueprintCopy.sourceDatesNotCopied)
                    }
                }

                let visibleIdeas = source.source.ideas.filter {
                    $0.eventId == source.source.event.id || store.selectedChildIDs.contains($0.eventId)
                }
                if !visibleIdeas.isEmpty {
                    Section {
                        ForEach(visibleIdeas, id: \.id) { idea in
                            Toggle(isOn: ideaBinding(idea.id, store: store)) {
                                sourceRecordLabel(
                                    title: idea.title,
                                    category: localizedIdeaCategory(idea.category),
                                    context: contextTitle(for: idea.eventId, source: source)
                                )
                            }
                            .disabled(!store.canEdit || store.sourceReloadRequired)
                        }

                        if store.selectedIdeaIDs.contains(where: { id in
                            visibleIdeas.first(where: { $0.id == id })?.notes?.isEmpty == false
                        }) {
                            Toggle(BlueprintCopy.includeIdeaNotes, isOn: notesBinding(store))
                                .disabled(!store.canEdit || store.sourceReloadRequired)
                        }
                    } header: {
                        Text(BlueprintCopy.captureIdeas)
                    }
                }

                let visibleInstructions = source.source.instructions.filter {
                    $0.eventId == source.source.event.id || store.selectedChildIDs.contains($0.eventId)
                }
                if !visibleInstructions.isEmpty {
                    Section {
                        ForEach(visibleInstructions, id: \.id) { instruction in
                            Toggle(isOn: instructionBinding(instruction.id, store: store)) {
                                sourceRecordLabel(
                                    title: instruction.title,
                                    category: localizedAudience(instruction.audience),
                                    context: contextTitle(for: instruction.eventId, source: source)
                                )
                            }
                            .disabled(!store.canEdit || store.sourceReloadRequired)
                        }
                    } header: {
                        Text(BlueprintCopy.captureGuidance)
                    }
                }

                if !store.eligibleTodos.isEmpty {
                    Section {
                        ForEach(store.eligibleTodos) { todo in
                            Toggle(isOn: todoBinding(todo.id, store: store)) {
                                sourceRecordLabel(title: todo.title, category: nil,
                                    context: contextTitle(for: todo.eventId, source: source))
                            }
                            .disabled(!store.canEdit || store.sourceReloadRequired)
                        }
                    } header: {
                        Text(TodoCopy.title)
                    } footer: {
                        Text(BlueprintCopy.todoCopyExplanation)
                    }
                }

                if createsShareLink || publishesToSearch {
                    Section {
                        if publishesToSearch {
                            Text(BlueprintCopy.templateSearchPublicationExplanation)
                        } else {
                            Text(BlueprintCopy.unlistedSharingExplanation)
                        }
                        Text(BlueprintCopy.templatePrivacyExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(publishesToSearch ? BlueprintCopy.searchPublication : BlueprintCopy.shareTemplate)
                    }
                } else {
                    Section {
                        Text(BlueprintCopy.templatePrivacyExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.sourceReloadRequired {
                    Section {
                        Text(BlueprintCopy.templateCreationSourceChanged)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button(BlueprintCopy.reloadEvent) {
                            Task { await store.load() }
                        }
                        .disabled(store.isLoading)
                    }
                } else if let message = store.errorMessage {
                    Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                }
            } else if store.errorMessage != nil {
                Section {
                    Text(store.errorMessage ?? BlueprintCopy.templateCreationLoadFailed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(BlueprintCopy.retry) { Task { await loadSourceAndMaybeReview(store) } }
                        .disabled(store.isLoading || !store.canEdit)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(BlueprintCopy.reviewTemplate) {
                    Task {
                        await store.review()
                        if store.reviewed != nil { isShowingReview = true }
                    }
                }
                .disabled(!store.canReview || store.isReviewing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isReviewing {
                ProgressView(BlueprintCopy.preparingTemplateReview)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .background(.bar)
            }
        }
    }

    private func reviewView(_ store: BlueprintCreateShareStore) -> some View {
        Group {
            if let createdURL = store.createdURL, store.created != nil {
                shareSuccessView(createdURL, store: store)
            } else if createsShareLink, store.created != nil {
                linkRecoveryView(store)
            } else if store.source != nil {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.reviewed?.content.name ?? store.name)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            if store.created == nil {
                                Text(reviewSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Label(BlueprintCopy.blueprintSavedExplanation, systemImage: "checkmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.created == nil, !store.eligibleTodos.isEmpty {
                        Section {
                            Toggle(BlueprintCopy.includeTodos, isOn: includeTodosBinding(store))
                                .disabled(!store.canEdit || store.sourceReloadRequired)
                        } footer: {
                            Text(BlueprintCopy.todoCopyExplanation)
                        }
                    }
                    if let message = store.errorMessage {
                        Section {
                            Text(message).font(.subheadline).foregroundStyle(.secondary)
                            if store.reviewed == nil {
                                Button(BlueprintCopy.retry) { Task { await store.review() } }
                                    .disabled(!store.canReview)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                preparationRetryView(store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.created != nil, createsShareLink {
                    if store.requiresLinkRefresh || store.errorMessage == BlueprintCopy.shareLinkStorageFailed {
                        Button(BlueprintCopy.refreshLinks) {
                            Task { await store.refreshCreatedLinks() }
                        }
                        .disabled(store.isLoading || store.isCreating)
                    } else {
                        sharingActionsMenu(store)
                    }
                } else if store.created != nil, !createsShareLink, store.errorMessage != nil {
                    Button(BlueprintCopy.retry) { Task { await store.createAndShare() } }
                        .disabled(store.isBusy || !canManageSource)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isCreating {
                Group {
                    if store.created == nil {
                        ProgressView(BlueprintCopy.creatingTemplate)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
                .background(.bar)
            } else if store.created == nil, store.reviewed != nil {
                Button {
                    Task { await store.createAndShare() }
                } label: {
                    Text(createsShareLink ? BlueprintCopy.createShareLink : BlueprintCopy.saveBlueprint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .disabled(!store.canCreate)
            } else if createsShareLink,
                      store.created != nil,
                      store.createdURL == nil,
                      !store.requiresLinkRefresh,
                      !store.createdLinks.contains(where: { $0.revokedAt == nil }) {
                Button {
                    Task { await store.createAndShare() }
                } label: {
                    Text(BlueprintCopy.createShareLink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .disabled(!store.canCreate)
            }
        }
    }

    private var reviewSummary: String {
        if !createsShareLink { return BlueprintCopy.reviewPrivateSummary }
        if publishesToSearch { return BlueprintCopy.templateSearchPublicationExplanation }
        return BlueprintCopy.reviewSharingSummary
    }

    private func preparationRetryView(_ store: BlueprintCreateShareStore) -> some View {
        let message = store.sourceReloadRequired
            ? BlueprintCopy.templateCreationSourceChanged
            : (store.errorMessage ?? BlueprintCopy.templateCreationReviewFailed)
        return ContentUnavailableView {
            Label(message, systemImage: "exclamationmark.triangle")
        } description: {
            Text(store.sourceReloadRequired ? BlueprintCopy.templateCreationSourceChanged : BlueprintCopy.templateCreationLoadFailed)
        } actions: {
            Button(store.sourceReloadRequired ? BlueprintCopy.reloadEvent : BlueprintCopy.retry) {
                Task { await retryInitialPreparation() }
            }
            .disabled(store.isBusy || !canManageSource || accountID == nil)
        }
    }

    private func retryInitialPreparation() async {
        guard canManageSource, accountID != nil else { return }
        store?.invalidate()
        store = nil
        didAttemptInitialReview = false
        isShowingReview = false
        await loadInitialState()
    }

    private func linkRecoveryView(_ store: BlueprintCreateShareStore) -> some View {
        List {
            Section {
                Label(BlueprintCopy.templateReady, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                Text(store.errorMessage ?? recoveryMessage(store))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .privacySensitive()
    }

    private func recoveryMessage(_ store: BlueprintCreateShareStore) -> String {
        if store.requiresLinkRefresh { return BlueprintCopy.templateCreationLinkUncertain }
        if store.createdLinks.contains(where: { $0.revokedAt == nil }) { return BlueprintCopy.savedLinkUnavailable }
        return BlueprintCopy.shareTemplateExplanation
    }

    private func shareSuccessView(_ url: URL, store: BlueprintCreateShareStore) -> some View {
        List {
            if store.accountID == accountID, canManageSource {
                Section {
                    BlueprintShareQRCodeView(
                        url: url,
                        baseURL: AppRuntimeConfiguration.authenticationBaseURL,
                        templateTitle: store.reviewed?.content.name,
                        creatorName: store.publicCreatorName,
                        activeShareLinkCount: (store.errorMessage == nil || store.errorMessage == BlueprintCopy.shareLinkSaveFailed)
                            && store.createdLinks.contains(where: { $0.revokedAt == nil }) ? 1 : nil,
                        listedRevision: store.errorMessage == nil ? store.listedRevision : nil
                    )
                }
            }
            if store.credentialSaveFailed {
                Section {
                    Text(BlueprintCopy.shareLinkSaveFailed)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(BlueprintCopy.retrySavingShareLink) { store.retrySavingLink() }
                        .disabled(store.isBusy || !canManageSource)
                }
            }
            if let message = store.errorMessage,
               message != BlueprintCopy.shareLinkSaveFailed {
                Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .privacySensitive()
        .accessibilityIdentifier("blueprint.createShare.success")
    }

    @ViewBuilder
    private func sharingActionsMenu(_ store: BlueprintCreateShareStore) -> some View {
        Menu {
            if let created = store.created,
               store.createdURL != nil || store.createdLinks.contains(where: { $0.revokedAt == nil }) {
                Button(BlueprintCopy.replaceShareLink) {
                    pendingReplacement = PendingReplacement(
                        templateID: created.templateId,
                        revision: created.revision,
                        hasLiveURL: store.createdURL != nil
                    )
                }
                .disabled(store.isBusy || store.requiresLinkRefresh || !canManageSource ||
                    (store.createdURL != nil ? !store.canReplaceShareLink : !store.canCreate))
            }

            if let created = store.created {
                Button(store.listedRevision == nil ? BlueprintCopy.listInSearch : BlueprintCopy.removeFromSearch) {
                    if store.listedRevision == nil && store.publicCreatorName == nil {
                        pendingCreatorNameChange = PendingCreatorNameChange(
                            templateID: created.templateId, revision: created.revision
                        )
                    } else {
                        pendingSearchChange = PendingSearchChange(
                            templateID: created.templateId,
                            revision: created.revision,
                            shouldPublish: store.listedRevision == nil
                        )
                    }
                }
                .disabled(store.isBusy || store.requiresLinkRefresh || !canManageSource)
            }

            let activeLinks = store.createdLinks.filter { $0.revokedAt == nil }
            if activeLinks.count == 1, let link = activeLinks.first {
                Button(BlueprintCopy.revokeShareLink, role: .destructive) {
                    pendingRevokeID = link.id
                }
            } else if !activeLinks.isEmpty {
                Menu(BlueprintCopy.revokeShareLink) {
                    ForEach(activeLinks) { link in
                        Button {
                            pendingRevokeID = link.id
                        } label: {
                            Text(link.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .disabled(store.isBusy || !canManageSource)
                    }
                }
            }
        } label: {
            Label(BlueprintCopy.manageSharing, systemImage: "ellipsis")
        }
        .disabled(store.isBusy || !canManageSource)
    }

    private var revokeConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRevokeID != nil },
            set: { if !$0 { pendingRevokeID = nil } }
        )
    }

    private var searchVisibilityConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingSearchChange != nil },
            set: { if !$0 { pendingSearchChange = nil } }
        )
    }

    private func localizedIdeaCategory(_ rawValue: String) -> String? {
        IdeaCategory(rawValue: rawValue)?.title
    }

    private func localizedAudience(_ rawValue: String) -> String? {
        switch rawValue {
        case "event_participants": BlueprintCopy.audienceEventParticipants
        case "planning_only": BlueprintCopy.audiencePlanningOnly
        default: nil
        }
    }

    private func sourceRecordLabel(title: String, category: String?, context: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let category, !category.isEmpty {
                Text(category).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(context).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func contextTitle(for eventID: UUID, source: BlueprintCaptureSourceResponse) -> String {
        if eventID == source.source.event.id { return BlueprintCopy.mainEvent }
        return source.source.children.first(where: { $0.id == eventID })?.title ?? BlueprintCopy.mainEvent
    }

    private func nameBinding(_ store: BlueprintCreateShareStore) -> Binding<String> {
        Binding(get: { store.name }, set: { store.setName($0) })
    }

    private func childBinding(_ id: UUID, store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(
            get: { store.selectedChildIDs.contains(id) },
            set: { store.setChild(id, included: $0) }
        )
    }

    private func ideaBinding(_ id: UUID, store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(
            get: { store.selectedIdeaIDs.contains(id) },
            set: { store.setIdea(id, included: $0) }
        )
    }

    private func instructionBinding(_ id: UUID, store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(
            get: { store.selectedInstructionIDs.contains(id) },
            set: { store.setInstruction(id, included: $0) }
        )
    }

    private func notesBinding(_ store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(get: { store.includeIdeaNotes }, set: { store.setIncludeIdeaNotes($0) })
    }

    private func todoBinding(_ id: UUID, store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(get: { store.selectedTodoIDs.contains(id) }, set: { store.setTodo(id, included: $0) })
    }

    private func includeTodosBinding(_ store: BlueprintCreateShareStore) -> Binding<Bool> {
        Binding(get: { !store.selectedTodoIDs.isEmpty }, set: { included in
            store.setIncludeTodos(included)
            Task { await store.review() }
        })
    }

    private func loadInitialState() async {
        guard canManageSource, let accountID,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        if store?.accountID != accountID || store?.eventID != eventID {
            store?.invalidate()
            didAttemptInitialReview = false
            isShowingReview = false
            let authentication = authentication
            store = BlueprintCreateShareStore(
                eventID: eventID,
                accountID: accountID,
                transport: PostgresSyncTransport(baseURL: baseURL),
                publishesToSearch: publishesToSearch,
                createsShareLink: createsShareLink,
                credentialStore: KeychainBlueprintShareLinkCredentialStore(),
                currentAccountID: { authentication.currentUser?.id }
            )
        }
        guard let store else { return }
        await loadSourceAndMaybeReview(store)
    }

    private func loadSourceAndMaybeReview(_ store: BlueprintCreateShareStore) async {
        await store.load()
        guard !Task.isCancelled, canManageSource, accountID == store.accountID,
              startsWithReview,
              !didAttemptInitialReview,
              store.source != nil,
              store.reviewed == nil,
              store.created == nil else { return }

        didAttemptInitialReview = true
        await store.review()
        if store.reviewed != nil { isShowingReview = true }
    }
}
