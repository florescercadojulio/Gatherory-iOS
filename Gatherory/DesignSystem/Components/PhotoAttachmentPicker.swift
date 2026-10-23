import ImagePlayground
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PhotoAttachmentPicker: View {
    @Binding var imageData: Data?
    @State private var isChoosingImage = false
    @State private var pickerGeneration = UUID()

    let emptySymbol: String
    var showsPreview = true
    var fallbackAssetName: String? = nil
    var fallbackColors: [Color]? = nil
    var fallbackAccent: Color = .accentColor
    var suggestedConcept: String = "Wedding celebration artwork"
    var showsExistingImage = false

    private var hasVisibleArtwork: Bool {
        imageData != nil || fallbackAssetName != nil || fallbackColors != nil || showsExistingImage
    }

    var body: some View {
        Group {
            if showsPreview {
                Button {
                    openImagePicker()
                } label: {
                    preview
                        .overlay(alignment: .bottomTrailing) {
                            Label(
                                hasVisibleArtwork ? CoverImageCopy.changeImage : CoverImageCopy.addImage,
                                systemImage: hasVisibleArtwork ? "photo" : "photo.badge.plus"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, AppTheme.Spacing.standard)
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                            .background(.regularMaterial, in: Capsule())
                            .appImageOverlayAppearance()
                            .padding(AppTheme.Spacing.compact)
                        }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    openImagePicker()
                } label: {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        Label(
                            hasVisibleArtwork ? CoverImageCopy.changeImage : CoverImageCopy.addImage,
                            systemImage: hasVisibleArtwork ? "photo" : "photo.badge.plus"
                        )
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(hasVisibleArtwork ? CoverImageCopy.changeImage : CoverImageCopy.addImage)
        .accessibilityHint(CoverImageCopy.openChoices)
        .sheet(isPresented: imagePickerPresentation) {
            AddImageView(
                imageData: $imageData,
                sourceRequestID: $pickerGeneration,
                emptySymbol: emptySymbol,
                fallbackAssetName: fallbackAssetName,
                fallbackColors: fallbackColors,
                fallbackAccent: fallbackAccent,
                suggestedConcept: suggestedConcept
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openImagePicker() {
        pickerGeneration = UUID()
        isChoosingImage = true
    }

    private var imagePickerPresentation: Binding<Bool> {
        Binding(
            get: { isChoosingImage },
            set: { isPresented in
                if !isPresented { pickerGeneration = UUID() }
                isChoosingImage = isPresented
            }
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .accessibilityLabel(CoverImageCopy.selectedImage)
        } else if fallbackAssetName != nil || fallbackColors != nil {
            MediaArtwork(
                imageData: nil,
                assetName: fallbackAssetName,
                symbol: emptySymbol,
                colors: fallbackColors ?? [.gray, .secondary],
                accent: fallbackAccent,
                progressiveBlurRadius: 0
            )
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .accessibilityLabel(CoverImageCopy.defaultArtwork)
        } else {
            ContentUnavailableView(
                CoverImageCopy.addImage,
                systemImage: emptySymbol,
                description: Text(CoverImageCopy.emptyPrompt)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .background(
                AppTheme.ColorToken.elevatedSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            )
        }
    }
}

private struct AddImageView: View {
    @Binding var imageData: Data?
    @Binding var sourceRequestID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var isShowingCamera = false
    @State private var isShowingImagePlayground = false
    @State private var isImportingFile = false
    @State private var playgroundConcept = ""
    @State private var errorMessage: String?
    @State private var cameraRequestID = UUID()
    @State private var fileRequestID = UUID()
    @State private var playgroundRequestID = UUID()

    let emptySymbol: String
    let fallbackAssetName: String?
    let fallbackColors: [Color]?
    let fallbackAccent: Color
    let suggestedConcept: String

    private var sourceImage: Image? {
        guard let imageData, let image = UIImage(data: imageData) else { return nil }
        return Image(uiImage: image)
    }

    private var imagePlaygroundAvailable: Bool {
        ImagePlaygroundViewController.isAvailable
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            Form {
                if imageData != nil || fallbackAssetName != nil || fallbackColors != nil {
                    Section(CoverImageCopy.currentImage) {
                        currentPreview
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)

                    }
                }

                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ImageSourceRow(
                            title: CoverImageCopy.chooseFromPhotos,
                            detail: CoverImageCopy.photosDetail,
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingImage)

                    Button {
                        fileRequestID = beginRequest()
                        isImportingFile = true
                    } label: {
                        ImageSourceRow(
                            title: CoverImageCopy.browseFiles,
                            detail: CoverImageCopy.filesDetail,
                            systemImage: "folder"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingImage)

                    Button {
                        cameraRequestID = beginRequest()
                        isShowingCamera = true
                    } label: {
                        ImageSourceRow(
                            title: CoverImageCopy.takePhoto,
                            detail: cameraAvailable ? CoverImageCopy.cameraDetail : CoverImageCopy.cameraUnavailable,
                            systemImage: "camera.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!cameraAvailable || isLoadingImage)

                    Button {
                        playgroundConcept = suggestedConcept
                        playgroundRequestID = beginRequest()
                        isShowingImagePlayground = true
                    } label: {
                        ImageSourceRow(
                            title: CoverImageCopy.playground,
                            detail: imagePlaygroundAvailable ? CoverImageCopy.playgroundDetail : CoverImageCopy.playgroundUnavailable,
                            systemImage: "apple.intelligence"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!imagePlaygroundAvailable || isLoadingImage)
                } header: {
                    Text(CoverImageCopy.chooseSource)
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(AppTheme.ColorToken.destructive)
                    } else if isLoadingImage {
                        HStack(spacing: AppTheme.Spacing.compact) {
                            ProgressView()
                            Text(CoverImageCopy.loading)
                        }
                            .foregroundStyle(.secondary)
                    } else {
                        Text(CoverImageCopy.reviewBeforeUse)
                    }
                }

                Section(CoverImageCopy.curated) {
                    curatedCoverCollection
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                if imageData != nil {
                    Section {
                        if fallbackAssetName != nil || fallbackColors != nil {
                            Button(CoverImageCopy.useDefault, systemImage: "arrow.counterclockwise") {
                                imageData = nil
                                dismiss()
                            }
                        } else {
                            Button(CoverImageCopy.removeImage, systemImage: "trash", role: .destructive) {
                                imageData = nil
                                dismiss()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle(CoverImageCopy.chooseImage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CoverImageCopy.close, systemImage: "xmark") {
                        sourceRequestID = UUID()
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            let requestID = beginRequest()
            errorMessage = nil
            isLoadingImage = true

            Task {
                defer {
                    if sourceRequestID == requestID { isLoadingImage = false }
                }
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self) else {
                        throw ImageLoadError.unavailable
                    }
                    await stageImage(data, requestID: requestID)
                } catch {
                    showError(CoverImageCopy.loadFailed, requestID: requestID)
                }
                if sourceRequestID == requestID { selectedPhoto = nil }
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            let requestID = fileRequestID
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    isLoadingImage = true
                    errorMessage = nil
                    defer {
                        if sourceRequestID == requestID { isLoadingImage = false }
                    }
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try await Self.readImage(at: url)
                        await stageImage(data, requestID: requestID)
                    } catch {
                        showError(CoverImageCopy.loadFailed, requestID: requestID)
                    }
                }
            case .failure(let error):
                let nsError = error as NSError
                if nsError.code != NSUserCancelledError {
                    showError(CoverImageCopy.loadFailed, requestID: requestID)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { capturedData in
                isShowingCamera = false
                guard let capturedData else { return }
                Task { await stageImage(capturedData, requestID: cameraRequestID) }
            }
            .ignoresSafeArea()
        }
        .imagePlaygroundSheet(
            isPresented: $isShowingImagePlayground,
            concept: playgroundConcept,
            sourceImage: sourceImage,
            onCompletion: { url in
                let requestID = playgroundRequestID
                isLoadingImage = true
                Task {
                    do {
                        let data = try await Self.readImage(at: url)
                        await stageImage(data, requestID: requestID)
                    } catch {
                        showError(CoverImageCopy.generatedFailed, requestID: requestID)
                    }
                }
            }
        )
    }

    private var curatedCoverCollection: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
                ForEach(CuratedCover.allCases) { cover in
                    Button {
                        guard let data = cover.imageData else {
                            errorMessage = CoverImageCopy.loadFailed
                            return
                        }
                        beginLoading(data)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(cover.assetName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 112, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(cover.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(width: 112, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cover.title)
                    .disabled(isLoadingImage)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(CoverImageCopy.curated)
    }

    @ViewBuilder
    private var currentPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipped()
                .accessibilityLabel(CoverImageCopy.currentPreview)
        } else {
            MediaArtwork(
                imageData: nil,
                assetName: fallbackAssetName,
                symbol: emptySymbol,
                colors: fallbackColors ?? [.gray, .secondary],
                accent: fallbackAccent,
                progressiveBlurRadius: 0
            )
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .accessibilityLabel(CoverImageCopy.defaultArtwork)
        }
    }

    private func beginRequest() -> UUID {
        let requestID = UUID()
        sourceRequestID = requestID
        errorMessage = nil
        return requestID
    }

    private func beginLoading(_ data: Data) {
        let requestID = beginRequest()
        isLoadingImage = true
        Task { await stageImage(data, requestID: requestID) }
    }

    @MainActor
    private func stageImage(_ data: Data, requestID: UUID) async {
        guard sourceRequestID == requestID else { return }
        isLoadingImage = true
        errorMessage = nil
        guard data.count <= CoverImagePreparation.maximumInputBytes else {
            showError(CoverImageCopy.tooLarge, requestID: requestID)
            return
        }

        let normalizedData = await Task.detached(priority: .userInitiated) {
            CoverImagePreparation.normalizeJPEG(data)
        }.value

        guard sourceRequestID == requestID else { return }
        guard let normalizedData else {
            showError(CoverImageCopy.prepareFailed, requestID: requestID)
            return
        }

        errorMessage = nil
        isLoadingImage = false
        imageData = normalizedData
        dismiss()
    }

    private func showError(_ message: String, requestID: UUID) {
        guard sourceRequestID == requestID else { return }
        errorMessage = message
        isLoadingImage = false
    }

    private enum ImageLoadError: Error {
        case unavailable
    }

    nonisolated private static func readImage(at url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url, options: .mappedIfSafe)
        }.value
    }
}

private struct ImageSourceRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 38, height: 38)
                .background(
                    AppTheme.ColorToken.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCompletion: (Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCompletion: (Data?) -> Void

        init(onCompletion: @escaping (Data?) -> Void) {
            self.onCompletion = onCompletion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onCompletion(image?.jpegData(compressionQuality: 0.92))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCompletion(nil)
        }
    }
}
