import SwiftUI

struct WorkspaceSaveStatusView: View {
    @Environment(WorkspaceCloudSyncController.self) private var sync
    @Environment(WorkspacePersistenceController.self) private var persistence
    let scopeID: UUID
    var isEditingDraft = true

    private var needsAttention: Bool {
        persistence.lastError != nil || sync.cannotReadSaveState
            || sync.failedSyncScopeID == scopeID || sync.photoAttentionScopeIDs.contains(scopeID)
            || (sync.lastError != nil && sync.pendingChangeScopeIDs.contains(scopeID))
    }
    private var isUpToDate: Bool {
        !needsAttention
            && !sync.pendingPhotoScopeIDs.contains(scopeID)
            && !sync.pendingChangeScopeIDs.contains(scopeID)
            && sync.confirmedSyncScopeIDs.contains(scopeID)
    }
    private var title: String {
        if persistence.lastError != nil { return AppCopy.Save.localFailure }
        if needsAttention { return AppCopy.Save.needsAttention }
        if sync.pendingPhotoScopeIDs.contains(scopeID) {
            return sync.isSynchronizing && sync.activeSyncScopeID == scopeID ? AppCopy.Save.uploading : AppCopy.Save.photosWaiting
        }
        if sync.pendingChangeScopeIDs.contains(scopeID) {
            return sync.isSynchronizing && sync.activeSyncScopeID == scopeID ? AppCopy.Save.syncing : AppCopy.Save.waiting
        }
        return sync.confirmedSyncScopeIDs.contains(scopeID) ? AppCopy.Save.upToDate : AppCopy.Save.local
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isUpToDate {
                    Label(AppCopy.Save.upToDate, systemImage: "checkmark.icloud")
                        .labelStyle(.iconOnly)
                        .font(.footnote)
                        .accessibilityLabel(AppCopy.Save.upToDate)
                } else {
                    Label(title, systemImage: needsAttention ? "exclamationmark.triangle" : "icloud")
                        .font(.footnote)
                }
                Spacer(minLength: 8)
                if needsAttention && persistence.lastError == nil {
                    Button(AppCopy.Common.retry) { Task { await sync.synchronize(trigger: .manual) } }
                        .disabled(sync.isSynchronizing)
                        .font(.footnote.weight(.semibold))
                }
            }
            if needsAttention { Text(AppCopy.Save.recovery).font(.caption).fixedSize(horizontal: false, vertical: true) }
            else if isEditingDraft { Text(AppCopy.Save.editExplanation).font(.caption).fixedSize(horizontal: false, vertical: true) }
        }
        .foregroundStyle(needsAttention ? AppTheme.ColorToken.warning : AppTheme.ColorToken.textSecondary)
        .accessibilityElement(children: .contain)
    }
}
