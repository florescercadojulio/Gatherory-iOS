import SwiftUI

enum IdeaImportCopy {
    static var title: String { String(localized: "ideaDiscovery.addToEvent", defaultValue: "Add to Event") }
    static var choose: String { String(localized: "ideaDiscovery.chooseEvent", defaultValue: "Choose an Event") }
    static var add: String { String(localized: "ideaDiscovery.add", defaultValue: "Add Idea") }
    static var added: String { String(localized: "ideaDiscovery.added", defaultValue: "Idea Added") }
    static var empty: String { String(localized: "ideaDiscovery.noWritableEvents", defaultValue: "No Events Available") }
    static var emptyHint: String { String(localized: "ideaDiscovery.noWritableEventsHint", defaultValue: "Create an event or join one as a planner to add ideas.") }
    static var unavailable: String { String(localized: "ideaDiscovery.destinationUnavailable", defaultValue: "This event can no longer receive ideas. Choose another event.") }
    static var imageFailed: String { String(localized: "ideaDiscovery.imageFailed", defaultValue: "The image couldn’t be copied. Check your connection and try again.") }
    static var saveFailed: String { String(localized: "ideaDiscovery.saveFailed", defaultValue: "The idea couldn’t be saved. Try again.") }
    static var invalidSource: String { String(localized: "ideaDiscovery.invalidSource", defaultValue: "This idea isn’t supported by this version of Gatherory.") }
    static var search: String { String(localized: "ideaDiscovery.searchWorkspaces", defaultValue: "Search your events") }
    static var noSearchResults: String { String(localized: "ideaDiscovery.noMatchingWorkspaces", defaultValue: "No Matching Events") }
    static var mainEvent: String { String(localized: "ideaDiscovery.mainEvent", defaultValue: "Main Event") }
}

/// An explicit add confirms the local archive and offline outbox before success.
/// A sheet owns one copy identity; retries never produce a second proposal.
@MainActor
enum IdeaEventImport {
    static func add(
        entry: IdeaDiscoveryEntry, destination: EventReference, workspace: PlanningWorkspace,
        library: WorkspaceLibrary, persistence: WorkspacePersistenceController,
        accountID: String, accountGeneration: UUID, ideaID: UUID,
        loadImage: (IdeaDiscoveryEntry) async throws -> Data? = { try await Self.copyImage($0) }
    ) async throws -> BlueprintIdeaImportResult {
        func requireCurrentDestination() throws {
            try Task.checkCancellation()
            guard persistence.activeUserID == accountID,
                  persistence.activeUserGeneration == accountGeneration,
                  library.workspaces.contains(where: { $0 === workspace }),
                  workspace.currentViewerMember(for: destination)?.userID == accountID,
                  BlueprintIdeaImport.canAdd(to: destination, in: workspace) else {
                throw CloudSyncFailure.invalidSession
            }
        }
        try requireCurrentDestination()
        let imageData = try await loadImage(entry)
        try requireCurrentDestination()
        let source = BlueprintIdeaImportSource(
            idea: entry.idea, blueprintKey: entry.sourceBlueprintId,
            blueprintRevision: entry.sourceVersion, blueprintTitle: entry.sourceTitle,
            creatorName: entry.creator?.displayName,
            publicCoverURL: entry.coverImageURL.flatMap(URL.init(string:))
        )
        return BlueprintIdeaImport.add(source, to: destination, in: workspace, ideaID: ideaID,
                                       imageData: imageData, persist: {
            try requireCurrentDestination()
            try persistence.saveChanges(in: library)
        })
    }

    static func copyImage(_ entry: IdeaDiscoveryEntry) async throws -> Data? {
        if let value = entry.coverImageURL {
            return try await BlueprintIdeaPublicImage.data(from: value)
        }
        guard let assetID = entry.coverAssetId else { return nil }
        guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            throw BlueprintCoverTransportFailure.invalidResponse
        }
        let bytes = try await BlueprintCoverTransport(baseURL: baseURL).download(
            mediaAssetID: assetID,
            source: BlueprintCoverSource(catalogKey: entry.sourceBlueprintId, revision: entry.sourceVersion)
        )
        let prepared = await Task.detached(priority: .userInitiated) {
            CoverImagePreparation.normalizeJPEG(bytes)
        }.value
        try Task.checkCancellation()
        guard let prepared else { throw BlueprintCoverTransportFailure.invalidResponse }
        return prepared
    }
}

struct IdeaAddToEventSheet: View {
    let entry: IdeaDiscoveryEntry
    var onAdded: ((IdeaDiscoveryAdditionReceipt) -> Void)? = nil
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(\.currentUserAccount) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var path: [UUID] = []
    @State private var selectedID: UUID?
    @State private var copyID = UUID()
    @State private var boundGeneration: UUID?
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var addTask: Task<Void, Never>?

    private var workspaces: [IdeaImportWorkspaceProjection.Workspace] {
        IdeaImportWorkspaceProjection.workspaces(
            in: library.workspaces,
            accountID: account?.id,
            search: searchText,
            sourceCategory: entry.idea.category
        )
    }

    private var selectedWorkspace: IdeaImportWorkspaceProjection.Workspace? {
        guard let selectedWorkspaceID = path.last else { return nil }
        return workspace(for: selectedWorkspaceID)
    }

    private var selectedDestination: IdeaImportWorkspaceProjection.Destination? {
        guard let selectedID else { return nil }
        return selectedWorkspace?.destinations.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if workspaces.isEmpty {
                    emptyWorkspaceView
                } else {
                    workspaceCollection
                }
            }
            .navigationTitle(IdeaImportCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: IdeaImportCopy.search)
            .navigationDestination(for: UUID.self) { workspaceID in
                if let workspace = workspace(for: workspaceID) {
                    destinationPicker(workspace)
                } else {
                    ContentUnavailableView(IdeaImportCopy.unavailable, systemImage: "calendar.badge.exclamationmark")
                        .navigationTitle(IdeaImportCopy.choose)
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                }
            }
            .overlay { if isBusy { ProgressView().allowsHitTesting(false) } }
        }
        .onAppear { if boundGeneration == nil { boundGeneration = persistence.activeUserGeneration } }
        .onChange(of: persistence.activeUserGeneration) { _, _ in dismiss() }
        .onChange(of: path) { _, _ in
            selectedID = nil
            errorMessage = nil
        }
        .onDisappear { addTask?.cancel() }
    }

    private var workspaceCollection: some View {
        ScrollView {
            AdaptiveMasonry(
                columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                spacing: 12,
                layoutDirection: layoutDirection,
                minimumColumnWidth: 145
            ) {
                ForEach(workspaces) { workspace in
                    NavigationLink(value: workspace.id) {
                        workspaceCard(workspace)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("idea.add.workspace.\(workspace.id.uuidString)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
    }

    private func workspaceCard(_ workspace: IdeaImportWorkspaceProjection.Workspace) -> some View {
        IdeaCollectionPresentation(title: workspace.title, category: .event, aspectRatio: 0.86) {
            MediaArtwork(
                imageData: workspace.imageData,
                symbol: IdeaCategory.event.symbol,
                colors: IdeaCategory.event.artworkColors,
                accent: IdeaCategory.event.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 0
            )
        } supporting: {
            EmptyView()
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationPicker(_ workspace: IdeaImportWorkspaceProjection.Workspace) -> some View {
        Group {
            if workspace.destinations.isEmpty {
                ContentUnavailableView(IdeaImportCopy.empty, systemImage: "calendar.badge.plus",
                                       description: Text(IdeaImportCopy.emptyHint))
            } else {
                ScrollView {
                    AdaptiveMasonry(
                        columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                        spacing: 12,
                        layoutDirection: layoutDirection,
                        minimumColumnWidth: 145
                    ) {
                        ForEach(workspace.destinations) { destination in
                            Button {
                                selectedID = destination.id
                                errorMessage = nil
                            } label: {
                                destinationCard(destination)
                                    .overlay(alignment: .topTrailing) {
                                        if selectedID == destination.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title2)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, AppTheme.ColorToken.accent)
                                                .padding(12)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(isBusy)
                            .accessibilityIdentifier("idea.add.destination.\(destination.id.uuidString)")
                            .accessibilityAddTraits(selectedID == destination.id ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                }
                .background(AppTheme.ColorToken.background.ignoresSafeArea())
            }
        }
        .navigationTitle(workspace.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(IdeaImportCopy.add) { addTask = Task { await add() } }
                    .disabled(isBusy || selectedDestination == nil)
                    .accessibilityIdentifier("idea.add.confirm")
            }
        }
        .overlay { if isBusy { ProgressView().allowsHitTesting(false) } }
    }

    private func destinationCard(_ destination: IdeaImportWorkspaceProjection.Destination) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaArtwork(
                imageData: destination.imageData,
                symbol: IdeaCategory.event.symbol,
                colors: IdeaCategory.event.artworkColors,
                accent: IdeaCategory.event.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 0
            )
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                if destination.reference == .main {
                    Text(IdeaImportCopy.mainEvent.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                        .opacity(0.86)
                }
                Text(destination.title)
                    .font(.headline)
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
        }
        .aspectRatio(destination.reference == .main ? 0.88 : 0.96, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    private var emptyWorkspaceView: some View {
        Group {
            if searchText.isEmpty {
                ContentUnavailableView(IdeaImportCopy.empty, systemImage: "calendar.badge.plus",
                                       description: Text(IdeaImportCopy.emptyHint))
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func workspace(for id: UUID) -> IdeaImportWorkspaceProjection.Workspace? {
        IdeaImportWorkspaceProjection.workspace(
            in: library.workspaces,
            mainEventID: id,
            accountID: account?.id,
            search: "",
            sourceCategory: entry.idea.category
        )
    }

    @MainActor
    private func add() async {
        guard !isBusy, let account, let boundGeneration,
              let target = selectedDestination else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let result = try await IdeaEventImport.add(
                entry: entry, destination: target.reference, workspace: target.workspace,
                library: library, persistence: persistence, accountID: account.id,
                accountGeneration: boundGeneration, ideaID: copyID
            )
            switch result {
            case .added(let idea), .alreadyAdded(let idea):
                guard let eventID = idea.eventID else {
                    errorMessage = IdeaImportCopy.invalidSource
                    return
                }
                // IdeaEventImport returns only after its persistence closure has
                // completed and revalidated the active account and destination.
                let receipt = IdeaDiscoveryAdditionReceipt(
                    accountID: account.id,
                    sourceID: entry.id,
                    workspaceID: target.workspace.mainEventID,
                    eventID: eventID,
                    ideaID: idea.id
                )
                if let onAdded {
                    onAdded(receipt)
                } else {
                    dismiss()
                }
            case .unavailable:
                errorMessage = IdeaImportCopy.unavailable
            case .invalidSource:
                errorMessage = IdeaImportCopy.invalidSource
            case .persistenceFailed:
                errorMessage = IdeaImportCopy.saveFailed
            }
        } catch is CancellationError {
            return
        } catch CloudSyncFailure.invalidSession {
            errorMessage = IdeaImportCopy.unavailable
        } catch {
            errorMessage = IdeaImportCopy.imageFailed
        }
    }
}
