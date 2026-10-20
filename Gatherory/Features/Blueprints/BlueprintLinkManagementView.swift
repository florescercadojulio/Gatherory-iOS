import SwiftUI

enum BlueprintLinkManagementMode: String, Identifiable {
    case share
    case manage

    var id: Self { self }

    var title: String {
        switch self {
        case .share: BlueprintCopy.shareTemplate
        case .manage: BlueprintCopy.manageTemplateLinks
        }
    }
}

struct BlueprintLinkManagementRequest: Identifiable {
    let id = UUID()
    let eventID: UUID
    let mode: BlueprintLinkManagementMode
    let captureURL: URL
    let workspace: PlanningWorkspace
}

private enum PendingTemplateListing: Identifiable {
    case publish(Int)
    case unlist(Int)

    var id: String {
        switch self {
        case .publish(let revision): "publish-\(revision)"
        case .unlist(let revision): "unlist-\(revision)"
        }
    }
}

private struct CreatorNameCandidate: Identifiable {
    let templateID: UUID
    let revision: Int
    let initialName: String
    var id: UUID { templateID }
}

struct BlueprintLinkManagementView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss

    let eventID: UUID
    let workspace: PlanningWorkspace
    let mode: BlueprintLinkManagementMode
    let captureURL: URL

    @State private var store: BlueprintLinkManagementStore?
    @State private var pendingReplacementTemplateID: UUID?
    @State private var pendingRevokeID: UUID?
    @State private var pendingListing: PendingTemplateListing?
    @State private var creatorNameCandidate: CreatorNameCandidate?
    @State private var isShowingNativeCreation = false

    private var accountID: String? { authentication.currentUser?.id }
    private var hasManagePermission: Bool {
        BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL,
            workspace: workspace
        ) != nil
    }

    private var loadIdentity: String { "\(eventID)|\(accountID ?? "")" }

    private var content: some View {
        Group {
            if !hasManagePermission {
                ContentUnavailableView(
                    BlueprintCopy.templateLinksUnavailable,
                    systemImage: "lock",
                    description: Text(BlueprintCopy.lostTemplatePermission)
                )
            } else if accountID == nil {
                ContentUnavailableView(
                    BlueprintCopy.signInRequired,
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(BlueprintCopy.templateLinkSignIn)
                )
            } else if let store {
                linkList(store)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var body: some View {
        content
        .navigationTitle(BlueprintCopy.shareTemplate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let store, !store.templates.isEmpty, hasManagePermission,
                   let template = selectedTemplate(in: store) {
                    Menu {
                        if !template.retired, template.publishedRevision != nil,
                           store.createdURL != nil || hasActiveLinks(store) {
                            Button(BlueprintCopy.replaceShareLink, systemImage: "arrow.triangle.2.circlepath") {
                                pendingReplacementTemplateID = store.selectedTemplateID
                            }
                            .disabled(!store.canCreate)
                        }

                        let activeLinks = store.links.filter { $0.revokedAt == nil }
                        if activeLinks.count == 1, let link = activeLinks.first {
                            Button(BlueprintCopy.revokeShareLink, systemImage: "xmark.circle", role: .destructive) {
                                pendingRevokeID = link.id
                            }
                        } else if !activeLinks.isEmpty {
                            Menu(BlueprintCopy.revokeShareLink, systemImage: "xmark.circle") {
                                ForEach(activeLinks) { link in
                                    Button(linkMenuTitle(link), role: .destructive) {
                                        pendingRevokeID = link.id
                                    }
                                    .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                                }
                            }
                        }

                        if !template.retired, let revision = template.publishedRevision {
                            if let listedRevision = template.listedRevision {
                                Button(BlueprintCopy.removeFromSearch, systemImage: "globe") {
                                    pendingListing = .unlist(listedRevision)
                                }
                            } else {
                                Button(BlueprintCopy.listInSearch, systemImage: "globe") {
                                    if template.creatorName != nil {
                                        pendingListing = .publish(revision)
                                    } else {
                                        creatorNameCandidate = CreatorNameCandidate(
                                            templateID: template.id, revision: revision, initialName: ""
                                        )
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(BlueprintCopy.manageSharing, systemImage: "ellipsis")
                    }
                    .disabled(store.isLoading || store.isMutating)
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
            pendingRevokeID = nil
            pendingReplacementTemplateID = nil
            pendingListing = nil
            creatorNameCandidate = nil
            dismiss()
        }
        .onChange(of: store?.selectedTemplateID) { _, _ in
            pendingRevokeID = nil
            pendingReplacementTemplateID = nil
            pendingListing = nil
            creatorNameCandidate = nil
        }
        .onChange(of: hasManagePermission) { _, allowed in
            if !allowed {
                store?.invalidate()
                store = nil
                pendingRevokeID = nil
                pendingReplacementTemplateID = nil
                pendingListing = nil
                creatorNameCandidate = nil
                dismiss()
            }
        }
        .onDisappear {
            guard !isShowingNativeCreation else { return }
            store?.invalidate()
            store = nil
            pendingRevokeID = nil
            pendingReplacementTemplateID = nil
            pendingListing = nil
            creatorNameCandidate = nil
        }
        .sheet(item: $creatorNameCandidate) { candidate in
            BlueprintCreatorNameSheet(
                initialName: candidate.initialName,
                isSubmitting: store?.isMutating == true,
                onPublish: { name in
                    guard let store, hasManagePermission,
                          store.selectedTemplateID == candidate.templateID,
                          store.templates.first(where: { $0.id == candidate.templateID })?.publishedRevision == candidate.revision else {
                        creatorNameCandidate = nil
                        return
                    }
                    creatorNameCandidate = nil
                    Task { await store.setDiscoverable(true, creatorName: name) }
                },
                onCancel: { creatorNameCandidate = nil }
            )
        }
        .confirmationDialog(
            BlueprintCopy.confirmReplaceShareLinkTitle,
            isPresented: Binding(
                get: { pendingReplacementTemplateID != nil },
                set: { if !$0 { pendingReplacementTemplateID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(BlueprintCopy.replaceShareLink) {
                guard let templateID = pendingReplacementTemplateID, let store,
                      templateID == store.selectedTemplateID else { return }
                pendingReplacementTemplateID = nil
                Task { await createLink(store) }
            }
            Button("Cancel", role: .cancel) { pendingReplacementTemplateID = nil }
        } message: {
            Text(BlueprintCopy.confirmReplaceShareLinkMessage)
        }
        .confirmationDialog(
            BlueprintCopy.confirmRevokeTitle,
            isPresented: revokeConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button(BlueprintCopy.revoke, role: .destructive) {
                guard let linkID = pendingRevokeID else { return }
                pendingRevokeID = nil
                Task { await revoke(linkID) }
            }
            Button("Cancel", role: .cancel) { pendingRevokeID = nil }
        } message: {
            Text(BlueprintCopy.confirmRevokeMessage)
        }
        .confirmationDialog(
            pendingListingTitle,
            isPresented: listingConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            switch pendingListing {
            case .publish:
                Button(BlueprintCopy.listInSearch) { confirmListingChange() }
            case .unlist:
                Button(BlueprintCopy.removeFromSearch, role: .destructive) { confirmListingChange() }
            case nil:
                EmptyView()
            }
            Button("Cancel", role: .cancel) { pendingListing = nil }
        } message: {
            Text(pendingListingMessage)
        }
    }

    private var revokeConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingRevokeID != nil },
            set: { if !$0 { pendingRevokeID = nil } }
        )
    }

    private var listingConfirmationIsPresented: Binding<Bool> {
        Binding(get: { pendingListing != nil }, set: { if !$0 { pendingListing = nil } })
    }

    private var pendingListingTitle: String {
        if case .publish = pendingListing { return BlueprintCopy.confirmListInSearchTitle }
        return BlueprintCopy.confirmRemoveFromSearchTitle
    }

    private var pendingListingMessage: String {
        if case .publish = pendingListing { return BlueprintCopy.confirmListInSearchMessage }
        return BlueprintCopy.confirmRemoveFromSearchMessage
    }

    private func confirmListingChange() {
        guard let pendingListing, let store, let templateID = store.selectedTemplateID else { return }
        let shouldPublish: Bool
        let confirmedRevision: Int?
        switch pendingListing {
        case .publish(let revision):
            shouldPublish = true
            confirmedRevision = revision
        case .unlist(let revision):
            shouldPublish = false
            confirmedRevision = revision
        }
        self.pendingListing = nil
        if shouldPublish,
           store.templates.first(where: { $0.id == templateID })?.creatorName == nil {
            creatorNameCandidate = CreatorNameCandidate(
                templateID: templateID,
                revision: confirmedRevision ?? -1,
                initialName: ""
            )
            return
        }
        Task {
            guard store.selectedTemplateID == templateID else { return }
            if shouldPublish {
                guard store.templates.first(where: { $0.id == templateID })?.publishedRevision == confirmedRevision else { return }
            } else {
                guard store.templates.first(where: { $0.id == templateID })?.listedRevision == confirmedRevision else { return }
            }
            await store.setDiscoverable(shouldPublish)
        }
    }

    @ViewBuilder
    private func linkList(_ store: BlueprintLinkManagementStore) -> some View {
        List {
            if store.templates.isEmpty {
                if store.isLoading {
                    Section {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } else if store.errorMessage != nil {
                    retrySection(store)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(BlueprintCopy.noCapturedTemplates)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(BlueprintCopy.captureBeforeSharing)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                isShowingNativeCreation = true
                            } label: {
                                Text(BlueprintCopy.createTemplateTitle)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isLoading || store.isMutating || !hasManagePermission)

                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.standard)
                    }
                }
            } else {
                templateSection(store)

                if let template = selectedTemplate(in: store) {
                    shareSection(template, store: store)
                } else if store.templates.count > 1 {
                    Section {
                        ContentUnavailableView(
                            BlueprintCopy.chooseTemplate,
                            systemImage: "square.stack.3d.up",
                            description: Text(BlueprintCopy.chooseTemplateHint)
                        )
                    }
                }

                if store.errorMessage != nil || store.createRequiresRefresh {
                    retrySection(store)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await refresh(store) }
        .navigationDestination(isPresented: $isShowingNativeCreation) {
            BlueprintCreateShareView(
                eventID: eventID,
                workspace: workspace,
                startsWithReview: true,
                onClose: { dismiss() }
            )
            .navigationBarBackButtonHidden(true)
        }
    }

    private func templateSection(_ store: BlueprintLinkManagementStore) -> some View {
        Section {
            if store.templates.count > 1 {
                Picker(BlueprintCopy.chooseTemplate, selection: selectionBinding(store)) {
                    Text(BlueprintCopy.chooseTemplate).tag(nil as UUID?)
                    ForEach(store.templates) { template in
                        Text(template.title).tag(Optional(template.id))
                    }
                }
                .disabled(store.isLoading || store.isMutating)
            } else if let template = store.templates.first {
                Text(template.title)
                    .font(.headline)
            }

            if let template = selectedTemplate(in: store) {
                if let creatorName = template.creatorName, !creatorName.isEmpty {
                    Text(BlueprintCopy.creatorByline(creatorName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if template.retired {
                    Label(BlueprintCopy.retiredTemplate, systemImage: "archivebox")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            if store.templates.count > 1 {
                Text(BlueprintCopy.chooseTemplate)
            }
        }
    }

    @ViewBuilder
    private func shareSection(_ template: BlueprintManagedTemplate, store: BlueprintLinkManagementStore) -> some View {
        Section {
            if store.createdURL == nil, !template.retired, store.errorMessage == nil {
                BlueprintSharingStatusBadges(
                    activeShareLinkCount: template.activeShareLinkCount,
                    listedRevision: template.listedRevision
                )
            }
            if template.retired || template.publishedRevision == nil {
                Text(template.retired ? BlueprintCopy.retiredCannotShare : BlueprintCopy.noPublishedTemplate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let url = store.createdURL {
                if store.accountID == accountID, hasManagePermission {
                    BlueprintShareQRCodeView(
                        url: url,
                        baseURL: AppRuntimeConfiguration.authenticationBaseURL,
                        templateTitle: template.title,
                        creatorName: template.creatorName,
                        activeShareLinkCount: store.errorMessage == nil ? template.activeShareLinkCount : nil,
                        listedRevision: store.errorMessage == nil ? template.listedRevision : nil,
                        isRetired: template.retired
                    )
                    .disabled(store.isLoading || store.isMutating)
                }
            } else if store.isLoading || !store.hasLoadedLinks {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.standard)
            } else if store.createRequiresRefresh {
                EmptyView() // Recovery stays visible below the QR or empty state.
            } else if hasActiveLinks(store) {
                Text(BlueprintCopy.savedLinkUnavailable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(BlueprintCopy.shareTemplateExplanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await createLink(store) }
                } label: {
                    if store.isMutating {
                        ProgressView(BlueprintCopy.creatingShareLink)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(BlueprintCopy.createShareLink, systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canCreate || !hasManagePermission)
            }
        }
    }

    private func linkMenuTitle(_ link: BlueprintManagedShareLink) -> String {
        let date = link.createdAt.formatted(date: .abbreviated, time: .shortened)
        let revision = String.localizedStringWithFormat(BlueprintCopy.publishedRevision, Int64(link.revision))
        return "\(date) · \(revision)"
    }

    @ViewBuilder
    private func retrySection(_ store: BlueprintLinkManagementStore) -> some View {
        Section {
            Text(store.errorMessage ?? (store.createRequiresRefresh
                ? BlueprintCopy.shareLinkCreationUncertain
                : BlueprintCopy.shareLinksLoadFailed))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if store.credentialSaveFailed, !store.createRequiresRefresh {
                Button(BlueprintCopy.retrySavingShareLink) { store.retrySavingLink() }
                    .disabled(store.isLoading || store.isMutating || !hasManagePermission)
            } else {
                Button(store.createRequiresRefresh ? BlueprintCopy.refreshLinks : BlueprintCopy.retry) {
                    Task { await refresh(store) }
                }
                .disabled(store.isLoading || store.isMutating || !hasManagePermission)
            }
        }
    }

    private func selectionBinding(_ store: BlueprintLinkManagementStore) -> Binding<UUID?> {
        Binding(
            get: { store.selectedTemplateID },
            set: { value in
                guard !store.isLoading, !store.isMutating else { return }
                pendingRevokeID = nil
                Task { await store.select(templateID: value) }
            }
        )
    }

    private func selectedTemplate(in store: BlueprintLinkManagementStore) -> BlueprintManagedTemplate? {
        guard let selectedTemplateID = store.selectedTemplateID else {
            return store.templates.count == 1 ? store.templates.first : nil
        }
        return store.templates.first { $0.id == selectedTemplateID }
    }

    private func loadInitialState() async {
        guard hasManagePermission, let accountID,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }

        if store?.accountID != accountID || store?.eventID != eventID {
            store?.invalidate()
            let authentication = authentication
            store = BlueprintLinkManagementStore(
                eventID: eventID,
                accountID: accountID,
                transport: PostgresSyncTransport(baseURL: baseURL),
                credentialStore: KeychainBlueprintShareLinkCredentialStore(),
                currentAccountID: { authentication.currentUser?.id }
            )
        }
        guard let store else { return }
        await refresh(store)
    }

    private func refresh(_ store: BlueprintLinkManagementStore) async {
        guard hasManagePermission, accountID == store.accountID else { return }
        await store.loadTemplates()
        guard store.errorMessage == nil ||
                (store.credentialSaveFailed && store.errorMessage == BlueprintCopy.shareLinkSaveFailed) else { return }
        guard hasManagePermission, accountID == store.accountID, !Task.isCancelled else { return }
        if store.templates.isEmpty {
            // Load and verify the source before showing the explicit create/share action.
            isShowingNativeCreation = true
            return
        }
        if store.selectedTemplateID == nil, store.templates.count == 1,
           let templateID = store.templates.first?.id {
            await store.select(templateID: templateID)
        } else if store.selectedTemplateID != nil {
            await store.loadLinks()
        }
    }

    private func hasActiveLinks(_ store: BlueprintLinkManagementStore) -> Bool {
        store.links.contains { $0.revokedAt == nil }
    }

    private func createLink(_ store: BlueprintLinkManagementStore) async {
        guard hasManagePermission, accountID == store.accountID else { return }
        await store.create()
    }

    private func revoke(_ linkID: UUID) async {
        guard hasManagePermission, let store, accountID == store.accountID else { return }
        await store.revoke(linkID: linkID)
    }

}
