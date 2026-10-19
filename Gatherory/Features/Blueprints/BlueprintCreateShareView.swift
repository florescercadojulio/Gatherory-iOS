import SwiftUI

struct BlueprintCreateShareView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID
    let workspace: PlanningWorkspace
    var publishesToSearch = true

    @State private var store: BlueprintCreateShareStore?
    @State private var isShowingReview = false
    @State private var pendingRevokeID: UUID?

    private var accountID: String? { authentication.currentUser?.id }
    private var canManageSource: Bool {
        BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL,
            workspace: workspace
        ) != nil
    }
    private var loadIdentity: String { "\(eventID)|\(accountID ?? "")" }
    private var title: String {
        guard isShowingReview else { return publishesToSearch ? BlueprintCopy.createTemplateTitle : BlueprintCopy.saveBlueprint }
        return store?.created == nil ? BlueprintCopy.reviewTemplate : BlueprintCopy.templateReady
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
                if isShowingReview && !store.sourceReloadRequired { reviewView(store) }
                else { selectionView(store) }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                if isShowingReview, let store, store.canEdit {
                    Button(BlueprintCopy.editTemplate) { isShowingReview = false }
                }
            }
        }
        .task(id: loadIdentity) {
            await loadInitialState()
        }
        .onChange(of: authentication.currentUser?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            store?.invalidate()
            store = nil
            dismiss()
        }
        .onChange(of: canManageSource) { _, allowed in
            guard !allowed else { return }
            store?.invalidate()
            store = nil
            dismiss()
        }
        .onChange(of: store?.sourceReloadRequired) { _, required in
            if required == true { isShowingReview = false }
        }
        .onDisappear {
            pendingRevokeID = nil
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(child.title)
                                    if !child.purpose.isEmpty {
                                        Text(child.purpose)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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

                Section {
                    Text(BlueprintCopy.templateSearchPublicationExplanation)
                    Text(BlueprintCopy.templatePrivacyExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(BlueprintCopy.searchPublication)
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
                    Button(BlueprintCopy.retry) { Task { await store.load() } }
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
            } else if let reviewed = store.reviewed {
                List {
                    if store.created != nil {
                        Section {
                            Label(BlueprintCopy.templateReady, systemImage: "checkmark.circle.fill")
                                .font(.headline)
                            Text(publishesToSearch ? BlueprintCopy.templateListedExplanation : BlueprintCopy.blueprintSavedExplanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Text(reviewed.content.name)
                            .font(.headline)
                        if !reviewed.content.description.isEmpty {
                            Text(reviewed.content.description)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(BlueprintCopy.templateDetails)
                    }

                    if !reviewed.content.children.isEmpty {
                        Section {
                            ForEach(reviewed.content.children, id: \.key) { child in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(child.title)
                                    if !child.purpose.isEmpty {
                                        Text(child.purpose).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if let category = localizedIdeaCategory(child.category) {
                                        Text(category).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    if let proposal = child.scheduleProposal {
                                        Text(String.localizedStringWithFormat(
                                            BlueprintCopy.scheduleProposalExplanation,
                                            proposal.localTime,
                                            Int64(proposal.dayOffset)
                                        ))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            Text(BlueprintCopy.captureChildren)
                        }
                    }

                    if !reviewed.content.ideas.isEmpty {
                        Section {
                            ForEach(reviewed.content.ideas, id: \.key) { idea in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(idea.title)
                                    if let category = localizedIdeaCategory(idea.category) {
                                        Text(category).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    if let note = idea.notes, !note.isEmpty {
                                        Text(note).font(.body)
                                    }
                                    Text(contextTitle(for: idea.target, reviewed: reviewed))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            Text(BlueprintCopy.captureIdeas)
                        }
                    }

                    if !reviewed.content.instructions.isEmpty {
                        Section {
                            ForEach(reviewed.content.instructions, id: \.key) { instruction in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(instruction.title)
                                    Text(instruction.body)
                                    if let audience = localizedAudience(instruction.audience) {
                                        Text(audience)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(contextTitle(for: instruction.target, reviewed: reviewed))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            Text(BlueprintCopy.captureGuidance)
                        }
                    }

                    Section {
                        if publishesToSearch { Text(BlueprintCopy.templateSearchPublicationExplanation) }
                        Text(BlueprintCopy.templatePrivacyExplanation)
                        Text(BlueprintCopy.selectedTextMayBePersonal)
                        Text(BlueprintCopy.independentTemplateCopies)
                    } header: {
                        Text(BlueprintCopy.beforeYouShare)
                    }

                    createdLinksSection(store)

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
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView(
                    BlueprintCopy.templateCreationReviewFailed,
                    systemImage: "exclamationmark.triangle",
                    description: Text(BlueprintCopy.templateCreationReviewFailed)
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.created != nil, store.requiresLinkRefresh {
                    Button(BlueprintCopy.refreshLinks) {
                        Task { await store.refreshCreatedLinks() }
                    }
                    .disabled(store.isLoading || store.isCreating)
                } else if publishesToSearch, store.created != nil, store.createdURL == nil {
                    Button(BlueprintCopy.retryCreateShareLink) {
                        Task { await store.createAndShare() }
                    }
                    .disabled(!store.canCreate || store.isCreating)
                } else if !publishesToSearch, store.created != nil, store.errorMessage != nil {
                    Button(BlueprintCopy.retry) { Task { await store.createAndShare() } }
                        .disabled(store.isBusy)
                } else if store.created == nil {
                    Button(publishesToSearch ? BlueprintCopy.publishToSearch : BlueprintCopy.saveBlueprint) {
                        Task { await store.createAndShare() }
                    }
                    .disabled(!store.canCreate || store.isCreating)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isCreating {
                ProgressView(BlueprintCopy.creatingTemplate)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                    .background(.bar)
            }
        }
    }

    private func shareSuccessView(_ url: URL, store: BlueprintCreateShareStore) -> some View {
        List {
            Section {
                Label(BlueprintCopy.templateReady, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                Text(BlueprintCopy.templateListedExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ShareLink(
                    item: url,
                    subject: Text(store.reviewed?.content.name ?? BlueprintCopy.shareTemplate),
                    message: Text(BlueprintCopy.independentTemplateCopies)
                ) {
                    Label(BlueprintCopy.shareTemplate, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy || !canManageSource)
                .privacySensitive()
            }

            Section {
                Text(BlueprintCopy.templatePrivacyExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(BlueprintCopy.selectedTextMayBePersonal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(BlueprintCopy.independentTemplateCopies)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text(BlueprintCopy.beforeYouShare)
            }

            if store.requiresLinkRefresh {
                Section {
                    Text(BlueprintCopy.templateCreationLinkUncertain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(BlueprintCopy.refreshLinks) {
                        Task { await store.refreshCreatedLinks() }
                    }
                    .disabled(store.isLoading || store.isCreating)
                }
            } else if store.createdURL == nil {
                Section {
                    Text(store.errorMessage ?? BlueprintCopy.templateCreationLinkUncertain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(BlueprintCopy.retryCreateShareLink) {
                        Task { await store.createAndShare() }
                    }
                    .disabled(!store.canCreate || store.isCreating)
                }
            }

            createdLinksSection(store)
        }
        .listStyle(.insetGrouped)
        .privacySensitive()
        .accessibilityIdentifier("blueprint.createShare.success")
    }

    @ViewBuilder
    private func createdLinksSection(_ store: BlueprintCreateShareStore) -> some View {
        if !store.createdLinks.isEmpty {
            Section {
                ForEach(store.createdLinks) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.createdAt.formatted(date: .abbreviated, time: .shortened))
                            Text(String.localizedStringWithFormat(
                                BlueprintCopy.publishedRevision,
                                Int64(link.revision)
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            Label(
                                link.revokedAt == nil ? BlueprintCopy.activeShareLink : BlueprintCopy.revokedShareLink,
                                systemImage: link.revokedAt == nil ? "checkmark.circle.fill" : "slash.circle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if link.revokedAt == nil {
                            Button(BlueprintCopy.revokeShareLink, systemImage: "xmark.circle", role: .destructive) {
                                pendingRevokeID = link.id
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel(BlueprintCopy.revokeShareLink)
                            .disabled(store.isBusy || !canManageSource)
                        }
                    }
                }
            } header: {
                Text(BlueprintCopy.createdLinks)
            } footer: {
                Text(BlueprintCopy.existingLinksCannotBeRecovered)
            }
        }
    }

    private var revokeConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRevokeID != nil },
            set: { if !$0 { pendingRevokeID = nil } }
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

    private func contextTitle(for target: BlueprintCapturedContent.Target, reviewed: BlueprintCaptureReview) -> String {
        switch target.kind {
        case "main":
            return BlueprintCopy.mainEvent
        case "child":
            guard let key = target.key else { return BlueprintCopy.mainEvent }
            return reviewed.content.children.first(where: { $0.key == key })?.title ?? BlueprintCopy.mainEvent
        default:
            return BlueprintCopy.mainEvent
        }
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

    private func loadInitialState() async {
        guard canManageSource, let accountID,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        if store?.accountID != accountID || store?.eventID != eventID {
            store?.invalidate()
            let authentication = authentication
            store = BlueprintCreateShareStore(
                eventID: eventID,
                accountID: accountID,
                transport: PostgresSyncTransport(baseURL: baseURL),
                publishesToSearch: publishesToSearch,
                currentAccountID: { authentication.currentUser?.id }
            )
        }
        guard let store else { return }
        await store.load()
    }
}
