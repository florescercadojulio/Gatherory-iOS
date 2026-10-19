import SwiftUI

struct BlueprintSharedPreviewView: View {
    let token: String
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(BlueprintSharedTemplateRouter.self) private var sharedLinks
    @Environment(\.currentUserAccount) private var account
    @State private var model = BlueprintSharedPreviewModel()
    @State private var showsRecovery = false
    private let drafts = BlueprintSetupDraftStore()

    var body: some View {
        Group {
            if !model.isLoading, let entry = model.entry {
                BlueprintPreviewView(
                    entry: entry, sharedToken: token,
                    usesSavedPreview: model.usesSavedPreview,
                    hasPendingInstallation: model.hasPendingInstallation,
                    onClose: { sharedLinks.dismiss() }
                )
            } else {
                NavigationStack {
                    fallback
                        .background(AppTheme.ColorToken.background)
                        .navigationTitle(BlueprintCopy.previewTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                WorkspaceLibraryToolbarButton(
                                    action: { sharedLinks.dismiss() },
                                    title: BlueprintCopy.libraryTitle,
                                    hint: BlueprintCopy.returnToTemplates
                                )
                            }
                        }
                }
            }
        }
        .task(id: account?.id) { await load() }
        .sheet(isPresented: $showsRecovery) {
            NavigationStack {
                BlueprintSetupView(catalogKey: nil, sharedToken: token, returnsToPreview: true)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var fallback: some View {
        if model.isLoading {
            VStack(spacing: 20) {
                ProgressView(ExploreCopy.loading)
                if model.hasPendingInstallation {
                    Button(BlueprintCopy.retryInstall) { showsRecovery = true }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(BlueprintCopy.previewTitle, systemImage: "square.stack.3d.up.slash")
            } description: {
                Text(model.errorMessage ?? BlueprintCopy.loadFailed)
            } actions: {
                Button(AppCopy.Common.retry) { Task { await load() } }
                if model.hasPendingInstallation {
                    Button(BlueprintCopy.retryInstall) { showsRecovery = true }
                }
            }
        }
    }

    private func load() async {
        let ownerID = account?.id
        let coordinator = cloudSync.makeBlueprintInstallationCoordinator()
        await model.load(
            ownerID: ownerID,
            token: token,
            pendingInstallation: {
                guard let coordinator else { throw CloudSyncFailure.invalidSession }
                return try !coordinator.pendingIntentsForActiveAccount().isEmpty
            },
            savedDraft: {
                guard let ownerID else { return nil }
                return try drafts.load(ownerUserID: ownerID, shareToken: token)
            },
            fetch: {
                guard let coordinator else { throw CloudSyncFailure.invalidSession }
                return try await coordinator.sharedBlueprint(token: token)
            }
        )
    }
}
