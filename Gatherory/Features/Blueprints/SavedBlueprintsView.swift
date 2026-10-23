import SwiftUI

/// Account management for the recommendations a person has hidden.
/// Saved and liked public Blueprints live in the main library collections.
struct SavedBlueprintsView: View {
    let actionStore: BlueprintActionStore
    @State private var actionFailed = false

    private var hidden: [BlueprintSavedPreference] { actionStore.savedItems.filter(\.notInterested) }

    var body: some View {
        List {
            if actionStore.preferencesLoadFailed {
                HStack {
                    Label(ExploreCopy.connection, systemImage: "wifi.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(AppCopy.Common.retry) { Task { await actionStore.loadPreferences() } }
                }
            }
            ForEach(hidden) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.entry?.name ?? BlueprintCopy.hiddenTitle).font(.headline)
                        if let creator = item.entry?.creatorName {
                            Text(BlueprintCopy.creatorByline(creator)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    Button {
                        Task {
                            if !(await actionStore.set(.notInterested, enabled: false, for: item)) {
                                actionFailed = actionStore.error != nil
                            }
                        }
                    } label: {
                        Image(systemName: "eye")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(BlueprintCopy.undoNotInterested)
                }
            }
            if hidden.isEmpty && actionStore.isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 72).listRowSeparator(.hidden)
            } else if hidden.isEmpty && !actionStore.preferencesLoadFailed {
                ContentUnavailableView(BlueprintCopy.noHidden, systemImage: "eye")
            }
        }
        .navigationTitle(BlueprintCopy.notInterested)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await actionStore.loadPreferences() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(AppCopy.Common.retry)
            }
        }
        .task { await actionStore.loadPreferences() }
        .refreshable { await actionStore.loadPreferences() }
        .alert(BlueprintCopy.actionUpdateFailed, isPresented: $actionFailed) {
            Button(AppCopy.Common.retry) { Task { await actionStore.retryLastAction() } }
            Button(AppCopy.Common.cancel, role: .cancel) { actionStore.clearError() }
        } message: {
            Text(actionStore.error?.localizedDescription ?? BlueprintCopy.actionUpdateFailed)
        }
    }
}
