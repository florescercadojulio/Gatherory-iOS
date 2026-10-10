import ImagePlayground
import PhotosUI
import SwiftUI
import UIKit

struct PhotoAttachmentPicker: View {
    @Binding var imageData: Data?
    @State private var isChoosingImage = false

    let emptySymbol: String
    var showsPreview = true
    var fallbackAssetName: String? = nil
    var fallbackColors: [Color]? = nil
    var fallbackAccent: Color = .accentColor
    var suggestedConcept: String = "Wedding celebration artwork"

    private var hasVisibleArtwork: Bool {
        imageData != nil || fallbackAssetName != nil || fallbackColors != nil
    }

    var body: some View {
        Group {
            if showsPreview {
                Button {
                    isChoosingImage = true
                } label: {
                    preview
                        .overlay(alignment: .bottomTrailing) {
                            Label(
                                hasVisibleArtwork ? "Edit Image" : "Add Image",
                                systemImage: hasVisibleArtwork
                                    ? "slider.horizontal.3"
                                    : "photo.badge.plus"
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
                    isChoosingImage = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        Label(
                            hasVisibleArtwork ? "Edit Image" : "Add Image",
                            systemImage: hasVisibleArtwork
                                ? "slider.horizontal.3"
                                : "photo.badge.plus"
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
        .accessibilityLabel(hasVisibleArtwork ? "Edit image" : "Add image")
        .accessibilityHint("Opens image choices")
        .sheet(isPresented: $isChoosingImage) {
            AddImageView(
                imageData: $imageData,
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

    @ViewBuilder
    private var preview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .accessibilityLabel("Selected image")
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
            .accessibilityLabel("Current event artwork")
        } else {
            ContentUnavailableView(
                "Add an Image",
                systemImage: emptySymbol,
                description: Text("Choose or create artwork that helps everyone recognize it.")
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
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isShowingCamera = false
    @State private var isShowingImagePlayground = false
    @State private var playgroundConcept = ""
    @State private var errorMessage: String?

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
                    Section("Current Image") {
                        currentPreview
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ImageSourceRow(
                            title: "Choose from Photos",
                            detail: "Select an image from your photo library.",
                            systemImage: "photo.on.rectangle.angled"
                        )
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        if isLoadingPhoto {
                            ProgressView()
                        }
                    }

                    Button {
                        isShowingCamera = true
                    } label: {
                        ImageSourceRow(
                            title: "Take Photo",
                            detail: cameraAvailable
                                ? "Use the camera to create a new image."
                                : "Camera isn’t available on this device.",
                            systemImage: "camera.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!cameraAvailable)

                    Button {
                        playgroundConcept = suggestedConcept
                        isShowingImagePlayground = true
                    } label: {
                        ImageSourceRow(
                            title: "Create with Image Playground",
                            detail: imagePlaygroundAvailable
                                ? "Generate original artwork using Apple’s experience."
                                : "Image Playground isn’t available on this device.",
                            systemImage: "apple.intelligence"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!imagePlaygroundAvailable)
                } header: {
                    Text("Choose a Source")
                } footer: {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Text("You’ll review a photo or generated image before it becomes part of the event.")
                    }
                }

                if imageData != nil {
                    Section {
                        if fallbackAssetName != nil || fallbackColors != nil {
                            Button("Use Default Artwork", systemImage: "arrow.counterclockwise") {
                                imageData = nil
                                dismiss()
                            }
                        } else {
                            Button("Remove Image", systemImage: "trash", role: .destructive) {
                                imageData = nil
                                dismiss()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle("Choose Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            errorMessage = nil
            isLoadingPhoto = true

            Task {
                defer { isLoadingPhoto = false }
                guard let data = try? await newValue.loadTransferable(type: Data.self) else {
                    errorMessage = "The selected image couldn’t be loaded. Choose another image and try again."
                    return
                }

                imageData = data
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraCaptureView { capturedData in
                isShowingCamera = false
                guard let capturedData else { return }
                imageData = capturedData
                dismiss()
            }
            .ignoresSafeArea()
        }
        .imagePlaygroundSheet(
            isPresented: $isShowingImagePlayground,
            concept: playgroundConcept,
            sourceImage: sourceImage,
            onCompletion: saveGeneratedImage
        )
    }

    @ViewBuilder
    private var currentPreview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()
                .accessibilityLabel("Current image")
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
            .frame(height: 210)
            .clipped()
            .accessibilityLabel("Default artwork")
        }
    }

    private func saveGeneratedImage(at url: URL) {
        do {
            imageData = try Data(contentsOf: url)
            dismiss()
        } catch {
            errorMessage = "The generated image couldn’t be saved. Try creating it again."
        }
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
                Text(title)
                    .foregroundStyle(.primary)

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
