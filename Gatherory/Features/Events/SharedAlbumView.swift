import SwiftUI
import UIKit

struct SharedAlbumView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appContentColorScheme) private var appContentColorScheme
    @State private var selectedPhoto: EventMoment?
    @State private var isSelecting = false
    @State private var selection = AlbumSelection()
    @State private var saver = AlbumPhotoSaver()
    @State private var saveResult: AlbumSaveResult?
    @State private var hasOpenedInitialPhoto = false

    let moments: [EventMoment]
    let canDelete: (EventMoment) -> Bool
    let delete: (EventMoment) -> Bool
    let hide: (EventMoment) -> Void
    var initialMomentID: UUID? = nil
    var avatar: (EventMoment) -> WorkspaceMember? = { _ in nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !moments.isEmpty {
                            Text(isSelecting ? AlbumCopy.selectionHint : AlbumCopy.browseHint)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("album.hint")
                            SharedAlbumCollage(
                                moments: moments,
                                availableWidth: max(geometry.size.width - 32, 0),
                                isSelecting: isSelecting,
                                selectedIDs: selection.selectedIDs,
                                avatar: avatar,
                                open: tapPhoto
                            )
                            .disabled(saver.isSaving)
                        }
                    }
                    .padding(16)
                }
                .overlay {
                    if moments.isEmpty {
                        ContentUnavailableView(AlbumCopy.title, systemImage: "photo.stack", description: Text(AlbumCopy.empty))
                    }
                }
            }
            .background(AppTheme.ColorToken.background)
            .navigationTitle(AlbumCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .appSoftScrollEdges()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AlbumCopy.close, systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(AlbumCopy.close)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(saver.isSaving)
                        .accessibilityIdentifier("album.close")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(AlbumCopy.title).font(.headline)
                        Text(isSelecting ? AlbumCopy.selectedCount(selection.count) : AlbumCopy.photoCount(moments.count))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? AppCopy.Common.done : AlbumCopy.select) {
                        isSelecting.toggle()
                        selection.clear()
                        saveResult = nil
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(moments.isEmpty || saver.isSaving)
                    .accessibilityIdentifier("album.select")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting || saveResult != nil { selectionFooter }
            }
            .navigationDestination(item: $selectedPhoto) { photo in
                SharedAlbumPhotoViewer(moments: moments, initialMomentID: photo.id, canDelete: canDelete, delete: delete, hide: hide, avatar: avatar)
            }
            .onAppear {
                guard !hasOpenedInitialPhoto else { return }
                hasOpenedInitialPhoto = true
                if let initialMomentID { selectedPhoto = moments.first { $0.id == initialMomentID } }
            }
            .onChange(of: moments.map(\.id)) { _, ids in
                selection.reconcile(availableIDs: ids)
                if ids.isEmpty { isSelecting = false }
            }
        }
        .interactiveDismissDisabled(saver.isSaving)
        .environment(\.colorScheme, appContentColorScheme)
        .preferredColorScheme(appContentColorScheme)
    }

    private var selectionFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let saveResult { AlbumSaveFeedback(result: saveResult) }
            if isSelecting {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { selectionActions }
                    VStack(alignment: .leading, spacing: 12) { selectionActions }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    @ViewBuilder
    private var selectionActions: some View {
        Button(selection.count == moments.count ? AlbumCopy.deselectAll : AlbumCopy.selectAll) {
            if selection.count == moments.count { selection.clear() }
            else { selection.selectAll(moments.map(\.id)) }
            saveResult = nil
        }
        .frame(minHeight: 44)
        .disabled(saver.isSaving)
        .accessibilityIdentifier("album.selectAll")
        Button {
            let photos = selection.selectedMoments(from: moments)
            Task {
                saveResult = nil
                let result = await saver.save(photos)
                saveResult = result
                if case .saved = result { selection.clear() }
            }
        } label: {
            HStack {
                if saver.isSaving { ProgressView() }
                Label(saver.isSaving ? AlbumCopy.saving : AlbumCopy.saveSelection(selection.count), systemImage: "square.and.arrow.down")
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selection.isEmpty || saver.isSaving)
        .accessibilityIdentifier("album.saveSelection")
    }

    private func tapPhoto(_ moment: EventMoment) {
        if isSelecting {
            selection.toggle(moment.id)
            saveResult = nil
        } else { selectedPhoto = moment }
    }
}

struct AlbumSaveFeedback: View {
    @Environment(\.openURL) private var openURL
    let result: AlbumSaveResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: symbol)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if case .permissionDenied = result {
                Button(AlbumCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("album.saveFeedback")
    }

    private var message: String {
        switch result {
        case .saved(let count): AlbumCopy.savedPhotos(count)
        case .permissionDenied: AlbumCopy.savePermissionDenied
        case .invalidImage: AlbumCopy.saveInvalidImage
        case .failed: AlbumCopy.saveFailed
        }
    }

    private var symbol: String {
        if case .saved = result { "checkmark.circle" } else { "exclamationmark.circle" }
    }
}
