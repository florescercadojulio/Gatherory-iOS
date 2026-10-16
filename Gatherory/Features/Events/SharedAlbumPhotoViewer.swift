import SwiftUI
import UIKit

/// Keeps navigation stable when other participants add or remove photos while the viewer is open.
struct AlbumViewerState {
    private(set) var moments: [EventMoment]
    var selectedMomentID: UUID?
    private(set) var deleteCandidateID: UUID?

    init(moments: [EventMoment], initialMomentID: UUID?) {
        self.moments = moments
        selectedMomentID = moments.contains(where: { $0.id == initialMomentID })
            ? initialMomentID : moments.first?.id
    }

    var selectedMoment: EventMoment? {
        moments.first { $0.id == selectedMomentID }
    }

    var selectedIndex: Int? {
        moments.firstIndex { $0.id == selectedMomentID }
    }

    mutating func reconcile(_ refreshedMoments: [EventMoment]) {
        let previousIndex = selectedIndex ?? 0
        moments = refreshedMoments
        if !moments.contains(where: { $0.id == selectedMomentID }) {
            selectedMomentID = moments.isEmpty ? nil : moments[min(previousIndex, moments.count - 1)].id
        }
        if !moments.contains(where: { $0.id == deleteCandidateID }) {
            deleteCandidateID = nil
        }
    }

    mutating func remove(id: UUID) {
        reconcile(moments.filter { $0.id != id })
    }

    mutating func move(by offset: Int) {
        guard let index = selectedIndex else { return }
        let nextIndex = index + offset
        guard moments.indices.contains(nextIndex) else { return }
        selectedMomentID = moments[nextIndex].id
    }

    mutating func requestDeletion(id: UUID) {
        deleteCandidateID = moments.first { $0.id == id }?.id
    }

    /// Clear pending intent even when permission was revoked or the underlying delete fails.
    mutating func takeDeletionCandidate() -> EventMoment? {
        defer { deleteCandidateID = nil }
        return moments.first { $0.id == deleteCandidateID }
    }

    mutating func cancelDeletion() {
        deleteCandidateID = nil
    }
}

struct SharedAlbumPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewer: AlbumViewerState
    @State private var isConfirmingDelete = false
    @State private var reportedMoment: EventMoment?
    @State private var saver = AlbumPhotoSaver()
    @State private var saveResult: AlbumSaveResult?
    @State private var deletionFailed = false

    private let latestMoments: [EventMoment]
    let canDelete: (EventMoment) -> Bool
    let delete: (EventMoment) -> Bool
    let hide: (EventMoment) -> Void
    let avatar: (EventMoment) -> WorkspaceMember?

    init(
        moments: [EventMoment],
        initialMomentID: UUID?,
        canDelete: @escaping (EventMoment) -> Bool,
        delete: @escaping (EventMoment) -> Bool,
        hide: @escaping (EventMoment) -> Void,
        avatar: @escaping (EventMoment) -> WorkspaceMember? = { _ in nil }
    ) {
        _viewer = State(initialValue: AlbumViewerState(moments: moments, initialMomentID: initialMomentID))
        latestMoments = moments
        self.canDelete = canDelete
        self.delete = delete
        self.hide = hide
        self.avatar = avatar
    }

    var body: some View {
            Group {
                if viewer.moments.isEmpty {
                    ContentUnavailableView(AlbumCopy.title, systemImage: "photo.stack")
                } else {
                    photoPages
                }
            }
            .background(.black)
            .foregroundStyle(.white)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selectedMoment = viewer.selectedMoment {
                    footer(for: selectedMoment)
                }
            }
            .navigationTitle(AlbumCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AlbumCopy.closePhoto, systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(AlbumCopy.closePhoto)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("album.viewer.close")
                }
                ToolbarItem(placement: .principal) {
                    if let selectedIndex = viewer.selectedIndex {
                        Text(AlbumCopy.photoPosition(selectedIndex + 1, total: viewer.moments.count))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityAdjustableAction { direction in
                                switch direction {
                                case .increment: viewer.move(by: 1)
                                case .decrement: viewer.move(by: -1)
                                @unknown default: break
                                }
                            }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let selectedMoment = viewer.selectedMoment {
                        photoActions(for: selectedMoment)
                    }
                }
            }
            .confirmationDialog(
                AlbumCopy.confirmDeleteTitle,
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button(AlbumCopy.deletePhoto, role: .destructive) { deletePendingPhoto() }
                Button(AppCopy.Common.cancel, role: .cancel) { viewer.cancelDeletion() }
            } message: {
                Text(AlbumCopy.confirmDeleteMessage)
            }
            .sheet(item: $reportedMoment) { moment in ReportImageView(moment: moment) }
            .onChange(of: isConfirmingDelete) { _, isPresented in
                if !isPresented { viewer.cancelDeletion() }
            }
            .onChange(of: latestMoments) { _, refreshedMoments in
                viewer.reconcile(refreshedMoments)
                if viewer.deleteCandidateID == nil { isConfirmingDelete = false }
                if let reportedMoment, !refreshedMoments.contains(where: { $0.id == reportedMoment.id }) {
                    self.reportedMoment = nil
                }
                if viewer.moments.isEmpty { dismiss() }
            }
            .onChange(of: viewer.selectedMomentID) { _, _ in
                saveResult = nil
                deletionFailed = false
            }
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var photoPages: some View {
        TabView(selection: $viewer.selectedMomentID) {
            ForEach(viewer.moments) { moment in
                AlbumPhotoPage(moment: moment, isActive: viewer.selectedMomentID == moment.id)
                    .tag(moment.id as UUID?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(.black)
    }

    private func photoActions(for moment: EventMoment) -> some View {
        Menu {
            Button(AppCopy.Safety.hide, systemImage: "eye.slash") {
                hide(moment)
                removePhoto(id: moment.id)
            }
            if moment.mediaAssetID != nil {
                Button(AppCopy.Safety.report, systemImage: "flag", role: .destructive) {
                    reportedMoment = moment
                }
            }
            if canDelete(moment) {
                Divider()
                Button(AlbumCopy.deletePhoto, systemImage: "trash", role: .destructive) {
                    viewer.requestDeletion(id: moment.id)
                    isConfirmingDelete = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(AlbumCopy.actions)
        .accessibilityIdentifier("album.viewer.actions")
    }

    private func footer(for moment: EventMoment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                SharedAlbumContributor(moment: moment, member: avatar(moment), showsDate: true)
                saveButton(for: moment)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 16) {
                    SharedAlbumContributor(moment: moment, member: avatar(moment), showsDate: true)
                    Spacer(minLength: 0)
                    saveButton(for: moment)
                }
            }
            if let saveResult {
                saveFeedback(saveResult)
            }
            if deletionFailed {
                Label(AlbumCopy.deleteFailed, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black)
    }

    private func saveButton(for moment: EventMoment) -> some View {
        Button {
            Task {
                saveResult = nil
                let result = await saver.save([moment])
                // A completed save belongs to the photo that initiated it, even after a swipe.
                if viewer.selectedMomentID == moment.id { saveResult = result }
            }
        } label: {
            HStack(spacing: 8) {
                if saver.isSaving { ProgressView().controlSize(.small) }
                Label(saver.isSaving ? AlbumCopy.saving : AlbumCopy.savePhoto, systemImage: "square.and.arrow.down")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(saver.isSaving)
        .accessibilityIdentifier("album.viewer.save")
    }

    @ViewBuilder
    private func saveFeedback(_ result: AlbumSaveResult) -> some View {
        switch result {
        case .saved(let count):
            Label(AlbumCopy.savedPhotos(count), systemImage: "checkmark.circle")
                .font(.footnote)
                .accessibilityIdentifier("album.viewer.save.success")
        case .permissionDenied:
            VStack(alignment: .leading, spacing: 4) {
                Text(AlbumCopy.savePermissionDenied).font(.footnote)
                Button(AlbumCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 44)
            }
        case .invalidImage:
            Label(AlbumCopy.saveInvalidImage, systemImage: "exclamationmark.circle").font(.footnote)
        case .failed:
            Label(AlbumCopy.saveFailed, systemImage: "exclamationmark.circle").font(.footnote)
        }
    }

    private func deletePendingPhoto() {
        guard let candidate = viewer.takeDeletionCandidate() else { return }
        guard canDelete(candidate), delete(candidate) else {
            deletionFailed = true
            return
        }
        removePhoto(id: candidate.id)
    }

    private func removePhoto(id: UUID) {
        viewer.remove(id: id)
        if viewer.moments.isEmpty { dismiss() }
    }
}

private struct AlbumPhotoPage: View {
    let moment: EventMoment
    let isActive: Bool
    @State private var zoomRequest = AlbumZoomRequest()
    @State private var image: UIImage?
    @State private var didLoadImage = false

    var body: some View {
        // A concrete, stable root keeps PagingCollectionView from replacing its page
        // when loading finishes. Image ownership follows selection, never view lifecycle.
        ZStack {
            Color.black
            if let image {
                AlbumZoomablePhoto(image: image, isActive: isActive, request: zoomRequest)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(AlbumCopy.photoBy(moment.addedBy))
                    .accessibilityHint(AlbumCopy.zoomPhotoHint)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityAction(named: Text(AlbumCopy.zoomIn)) {
                        zoomRequest = AlbumZoomRequest(sequence: zoomRequest.sequence + 1, zoomIn: true)
                    }
                    .accessibilityAction(named: Text(AlbumCopy.zoomOut)) {
                        zoomRequest = AlbumZoomRequest(sequence: zoomRequest.sequence + 1, zoomIn: false)
                    }
            } else if didLoadImage {
                ContentUnavailableView(
                    AlbumCopy.photoUnavailable,
                    systemImage: "photo.badge.exclamationmark",
                    description: Text(AlbumCopy.photoUnavailableDescription)
                )
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                if !didLoadImage { loadImage() }
            } else {
                // Release the previous original without creating an appear/disappear loop.
                if image != nil { image = nil }
                if didLoadImage { didLoadImage = false }
                if zoomRequest != AlbumZoomRequest() { zoomRequest = AlbumZoomRequest() }
            }
        }
        .onChange(of: moment.imageData) { _, _ in
            if isActive { loadImage() }
        }
    }

    private func loadImage() {
        image = UIImage(data: moment.imageData)
        didLoadImage = true
    }
}

private struct AlbumZoomRequest: Equatable {
    var sequence = 0
    var zoomIn = true
}

private struct AlbumZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let isActive: Bool
    let request: AlbumZoomRequest

    func makeUIView(context: Context) -> AlbumZoomScrollView {
        let scrollView = AlbumZoomScrollView()
        scrollView.setImage(image)
        return scrollView
    }

    func updateUIView(_ scrollView: AlbumZoomScrollView, context: Context) {
        scrollView.setImage(image)
        if !isActive { scrollView.resetZoom() }
        if scrollView.lastRequest != request {
            scrollView.lastRequest = request
            if isActive { scrollView.changeZoom(zoomIn: request.zoomIn) }
        }
    }
}

/// UIKit provides familiar focal-point pinch and double-tap zoom without cropping the source photo.
private final class AlbumZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let photo = UIImageView()
    private var fittedSize: CGSize = .zero
    var lastRequest = AlbumZoomRequest()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photo.contentMode = .scaleAspectFit
        addSubview(photo)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        panGestureRecognizer.isEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    func setImage(_ image: UIImage) {
        guard photo.image !== image else { return }
        photo.image = image
        fittedSize = .zero
        resetZoom()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let image = photo.image,
              image.size.width > 0, image.size.height > 0 else { return }
        if fittedSize != bounds.size {
            fittedSize = bounds.size
            resetZoom()
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            photo.frame = CGRect(origin: .zero, size: size)
            contentSize = size
        }
        centerPhoto()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Let the enclosing pager receive horizontal swipes until someone zooms in.
        let canPan = zoomScale > minimumZoomScale + 0.01
        if panGestureRecognizer.isEnabled != canPan { panGestureRecognizer.isEnabled = canPan }
        centerPhoto()
    }

    func resetZoom() {
        if zoomScale != minimumZoomScale { setZoomScale(minimumZoomScale, animated: false) }
        if panGestureRecognizer.isEnabled { panGestureRecognizer.isEnabled = false }
    }

    func changeZoom(zoomIn: Bool) {
        let target = zoomIn ? min(zoomScale * 2, maximumZoomScale) : max(zoomScale / 2, minimumZoomScale)
        setZoomScale(target, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            let target: CGFloat = 2.5
            let point = gesture.location(in: photo)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
                 animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func centerPhoto() {
        let insets = UIEdgeInsets(
            top: max((bounds.height - contentSize.height) / 2, 0),
            left: max((bounds.width - contentSize.width) / 2, 0),
            bottom: 0,
            right: 0
        )
        if contentInset != insets { contentInset = insets }
    }
}
