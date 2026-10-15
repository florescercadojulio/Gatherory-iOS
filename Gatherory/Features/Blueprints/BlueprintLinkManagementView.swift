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
    case unlist

    var id: String {
        switch self {
        case .publish(let revision): "publish-\(revision)"
        case .unlist: "unlist"
        }
    }
}

struct BlueprintLinkManagementView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let eventID: UUID
    let workspace: PlanningWorkspace
    let mode: BlueprintLinkManagementMode
    let captureURL: URL

    @State private var store: BlueprintLinkManagementStore?
    @State private var pendingRevokeID: UUID?
    @State private var pendingListing: PendingTemplateListing?
    @State private var isManagingLinks = false
    @State private var isShowingNativeCreation = false

    private var accountID: String? { authentication.currentUser?.id }
    private var visibleMode: BlueprintLinkManagementMode {
        isManagingLinks || (store?.createRequiresRefresh ?? false) ? .manage : mode
    }
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
        .navigationTitle(visibleMode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
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
            pendingListing = nil
            dismiss()
        }
        .onChange(of: store?.selectedTemplateID) { _, _ in
            pendingRevokeID = nil
            pendingListing = nil
        }
        .onChange(of: store?.createRequiresRefresh) { _, required in
            if required == true { isManagingLinks = true }
        }
        .onChange(of: hasManagePermission) { _, allowed in
            if !allowed {
                store?.invalidate()
                store = nil
                pendingRevokeID = nil
                pendingListing = nil
                dismiss()
            }
        }
        .onDisappear {
            guard !isShowingNativeCreation else { return }
            store?.invalidate()
            store = nil
            pendingRevokeID = nil
            pendingListing = nil
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
        case .unlist:
            shouldPublish = false
            confirmedRevision = nil
        }
        self.pendingListing = nil
        Task {
            guard store.selectedTemplateID == templateID else { return }
            if shouldPublish {
                guard store.templates.first(where: { $0.id == templateID })?.publishedRevision == confirmedRevision else { return }
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
                        ContentUnavailableView {
                            Label(BlueprintCopy.noCapturedTemplates, systemImage: "square.stack.3d.up")
                        } description: {
                            Text(BlueprintCopy.captureBeforeSharing)
                        } actions: {
                            VStack(spacing: AppTheme.Spacing.standard) {
                                Button(BlueprintCopy.createTemplateTitle, systemImage: "square.stack.3d.up.badge.plus") {
                                    isShowingNativeCreation = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.isLoading || store.isMutating || !hasManagePermission)

                                Button(BlueprintCopy.openTemplateEditor, systemImage: "safari") {
                                    openTemplateEditor()
                                }
                                .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                            }
                        }
                    }
                }
            } else {
                templateSection(store)

                if let template = selectedTemplate(in: store) {
                    if visibleMode == .share {
                        shareSection(template, store: store)
                    } else {
                        searchListingSection(template, store: store)
                        manageSection(template, store: store)
                    }
                } else if store.templates.count > 1 {
                    Section {
                        ContentUnavailableView(
                            BlueprintCopy.chooseTemplate,
                            systemImage: "square.stack.3d.up",
                            description: Text(BlueprintCopy.chooseTemplateHint)
                        )
                    }
                }

                if store.errorMessage != nil {
                    retrySection(store)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await refresh(store) }
        .navigationDestination(isPresented: $isShowingNativeCreation) {
            BlueprintCreateShareView(eventID: eventID, workspace: workspace)
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
                templateStatus(template)
                if template.retired {
                    Label(BlueprintCopy.retiredTemplate, systemImage: "archivebox")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if template.publishedRevision == nil {
                    Label(BlueprintCopy.draftTemplate, systemImage: "pencil")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button(BlueprintCopy.createTemplateTitle, systemImage: "square.stack.3d.up.badge.plus") {
                isShowingNativeCreation = true
            }
            .disabled(store.isLoading || store.isMutating || !hasManagePermission)
        } header: {
            Text(BlueprintCopy.chooseTemplate)
        }
    }

    @ViewBuilder
    private func shareSection(_ template: BlueprintManagedTemplate, store: BlueprintLinkManagementStore) -> some View {
        Section {
            Text(BlueprintCopy.shareTemplateExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(BlueprintCopy.manageTemplateLinks, systemImage: "link") {
                isManagingLinks = true
            }
            .disabled(store.isLoading || store.isMutating)

            if template.retired || template.publishedRevision == nil {
                Text(template.retired ? BlueprintCopy.retiredCannotShare : BlueprintCopy.noPublishedTemplate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(BlueprintCopy.openTemplateEditor, systemImage: "safari") {
                    openTemplateEditor()
                }
                .disabled(store.isLoading || store.isMutating)
            } else if let url = store.createdURL {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    Label(BlueprintCopy.newLinkReady, systemImage: "clock")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ShareLink(
                        item: url,
                        subject: Text(template.title),
                        message: Text(BlueprintCopy.shareTemplateExplanation)
                    ) {
                        Label(BlueprintCopy.shareNewLink, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(BlueprintCopy.shareNewLink)
                    .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                    .privacySensitive()
                }
                .privacySensitive()
            } else {
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

            Text(BlueprintCopy.shareLinkOffline)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func searchListingSection(_ template: BlueprintManagedTemplate, store: BlueprintLinkManagementStore) -> some View {
        if !template.retired, let revision = template.publishedRevision {
            Section {
                if let listedRevision = template.listedRevision {
                    Label(BlueprintCopy.listedInSearch, systemImage: "globe")
                        .font(.subheadline)
                    Text(String.localizedStringWithFormat(BlueprintCopy.publishedRevision, Int64(listedRevision)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(BlueprintCopy.removeFromSearch, role: .destructive) {
                        pendingListing = .unlist
                    }
                    .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                } else {
                    Label(BlueprintCopy.notListedInSearch, systemImage: "globe")
                        .font(.subheadline)
                    Button(BlueprintCopy.listInSearch) {
                        pendingListing = .publish(revision)
                    }
                    .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                }
            } header: {
                Text(BlueprintCopy.searchPublication)
            } footer: {
                Text(BlueprintCopy.listingDoesNotChangeLinks)
            }
        }
    }

    @ViewBuilder
    private func manageSection(_ template: BlueprintManagedTemplate, store: BlueprintLinkManagementStore) -> some View {
        Section {
            if mode == .share && !store.createRequiresRefresh {
                Button(BlueprintCopy.shareTemplate, systemImage: "square.and.arrow.up") {
                    isManagingLinks = false
                }
                .disabled(store.isLoading || store.isMutating)
            }

            Text(BlueprintCopy.existingLinksCannotBeRecovered)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !store.hasLoadedLinks && store.errorMessage == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else if store.hasLoadedLinks && store.links.isEmpty && store.errorMessage == nil {
                ContentUnavailableView(
                    BlueprintCopy.noLinksCreated,
                    systemImage: "link",
                    description: Text(BlueprintCopy.noLinksCreatedHint)
                )
            } else {
                ForEach(store.links) { link in
                    shareLinkRow(link, store: store)
                }
            }

            if !template.retired, template.publishedRevision != nil, store.createdURL == nil {
                Button {
                    Task { await createLink(store) }
                } label: {
                    if store.isMutating {
                        ProgressView(BlueprintCopy.creatingShareLink)
                    } else {
                        Label(BlueprintCopy.createShareLink, systemImage: "plus")
                    }
                }
                .disabled(!store.canCreate || !hasManagePermission)
            }

            if let url = store.createdURL {
                ShareLink(
                    item: url,
                    subject: Text(template.title),
                    message: Text(BlueprintCopy.shareTemplateExplanation)
                ) {
                    Label(BlueprintCopy.shareNewLink, systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(BlueprintCopy.shareNewLink)
                .disabled(store.isLoading || store.isMutating || !hasManagePermission)
                .privacySensitive()
                Text(BlueprintCopy.newLinkReady)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }

            Text(BlueprintCopy.shareLinkOffline)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(BlueprintCopy.manageTemplateLinks)
        }
    }

    private func shareLinkRow(_ link: BlueprintManagedShareLink, store: BlueprintLinkManagementStore) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(link.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Spacer()
                Label(
                    link.revokedAt == nil ? BlueprintCopy.activeShareLink : BlueprintCopy.revokedShareLink,
                    systemImage: link.revokedAt == nil ? "checkmark.circle.fill" : "slash.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Text(String.localizedStringWithFormat(BlueprintCopy.publishedRevision, Int64(link.revision)))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if link.revokedAt == nil {
                Button(BlueprintCopy.revokeShareLink, systemImage: "xmark.circle", role: .destructive) {
                    pendingRevokeID = link.id
                }
                .disabled(store.isLoading || store.isMutating || !hasManagePermission)
            }
        }
        .padding(.vertical, AppTheme.Spacing.compact)
    }

    @ViewBuilder
    private func retrySection(_ store: BlueprintLinkManagementStore) -> some View {
        Section {
            Text(store.errorMessage ?? (store.createRequiresRefresh
                ? BlueprintCopy.shareLinkCreationUncertain
                : BlueprintCopy.shareLinksLoadFailed))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(BlueprintCopy.retry) {
                Task { await refresh(store) }
            }
            .disabled(store.isLoading || store.isMutating || !hasManagePermission)
        }
    }

    private func templateStatus(_ template: BlueprintManagedTemplate) -> some View {
        Group {
            if let revision = template.publishedRevision {
                Text(String.localizedStringWithFormat(BlueprintCopy.publishedRevision, Int64(revision)))
            } else {
                Text(BlueprintCopy.draftTemplate)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
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
                currentAccountID: { authentication.currentUser?.id }
            )
        }
        guard let store else { return }
        await refresh(store)
    }

    private func refresh(_ store: BlueprintLinkManagementStore) async {
        guard hasManagePermission, accountID == store.accountID else { return }
        await store.loadTemplates()
        guard store.errorMessage == nil else { return }
        if store.selectedTemplateID == nil, store.templates.count == 1,
           let templateID = store.templates.first?.id {
            await store.select(templateID: templateID)
        } else if store.selectedTemplateID != nil {
            await store.loadLinks()
        }
    }

    private func createLink(_ store: BlueprintLinkManagementStore) async {
        guard hasManagePermission, accountID == store.accountID else { return }
        await store.create()
    }

    private func revoke(_ linkID: UUID) async {
        guard hasManagePermission, let store, accountID == store.accountID else { return }
        await store.revoke(linkID: linkID)
    }

    private func openTemplateEditor() {
        guard hasManagePermission else { return }
        if let templateID = store?.selectedTemplateID ?? (store?.templates.count == 1 ? store?.templates.first?.id : nil) {
            guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL,
                  let editorURL = BlueprintCaptureLink.editorURL(baseURL: baseURL, templateID: templateID) else { return }
            openURL(editorURL)
        } else {
            openURL(captureURL)
        }
    }
}
