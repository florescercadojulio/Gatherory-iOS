import ImagePlayground
import PhotosUI
import SwiftUI
import UIKit

struct PhotoAttachmentPicker: View {
    @Binding var imageData: Data?
    @State private var isChoosingImage = false

    let emptySymbol: String
    var suggestedConcept: String = "Wedding celebration artwork"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            preview

            HStack(spacing: AppTheme.Spacing.compact) {
                Button(
                    imageData == nil ? "Add Image" : "Change Image",
                    systemImage: "photo.badge.plus"
                ) {
                    isChoosingImage = true
                }
                .buttonStyle(.bordered)

                if imageData != nil {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        imageData = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $isChoosingImage) {
            AddImageView(
                imageData: $imageData,
                suggestedConcept: suggestedConcept
            )
            .presentationDetents([.large])
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
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .accessibilityLabel("Selected image")
        } else {
            ContentUnavailableView(
                "Add an Image",
                systemImage: emptySymbol,
                description: Text("Choose or create artwork that helps everyone recognize it.")
            )
            .frame(maxWidth: .infinity)
            .frame(height: 180)
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
    @State private var isShowingCamera = false
    @State private var isShowingImagePlayground = false
    @State private var playgroundConcept = ""
    @State private var errorMessage: String?

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
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    sourceControls
                    imagePlaygroundSection
                }
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Spacing.standard)
                .padding(.bottom, AppTheme.Layout.screenBottom)
            }
            .scrollIndicators(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle(imageData == nil ? "Add Image" : "Change Image")
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

            Task {
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
        .alert("Image Unavailable", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private var sourceControls: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.spacious) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                ImageSourceControl(
                    title: "Photos",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
            .buttonStyle(.plain)

            Button {
                isShowingCamera = true
            } label: {
                ImageSourceControl(
                    title: "Camera",
                    systemImage: "camera.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(!cameraAvailable)
            .opacity(cameraAvailable ? 1 : 0.45)
            .accessibilityHint(cameraAvailable ? "Takes a new photo" : "Camera unavailable on this device")

            Spacer(minLength: 0)
        }
    }

    private var imagePlaygroundSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Image Playground")
                    .font(.title2.bold())

                Text(
                    imagePlaygroundAvailable
                        ? "Choose a direction to create original artwork."
                        : "Image Playground isn’t available on this device."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: AppTheme.Spacing.standard) {
                    PlaygroundConceptButton(
                        title: "Original",
                        systemImage: "plus",
                        colors: [.gray, .secondary]
                    ) {
                        openImagePlayground(with: suggestedConcept)
                    }

                    PlaygroundConceptButton(
                        title: "Elegant",
                        systemImage: "sparkles",
                        colors: [.indigo, .blue]
                    ) {
                        openImagePlayground(
                            with: "\(suggestedConcept), elegant editorial composition, refined details"
                        )
                    }

                    PlaygroundConceptButton(
                        title: "Garden",
                        systemImage: "leaf.fill",
                        colors: [.green, .teal]
                    ) {
                        openImagePlayground(
                            with: "\(suggestedConcept), romantic garden setting, botanical details"
                        )
                    }

                    PlaygroundConceptButton(
                        title: "Celebration",
                        systemImage: "party.popper.fill",
                        colors: [.orange, .pink]
                    ) {
                        openImagePlayground(
                            with: "\(suggestedConcept), joyful wedding celebration, colorful details"
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .disabled(!imagePlaygroundAvailable)
            .opacity(imagePlaygroundAvailable ? 1 : 0.45)

            Text("Apple presents the generation experience and lets you approve the final image.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func openImagePlayground(with concept: String) {
        playgroundConcept = concept
        isShowingImagePlayground = true
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

private struct ImageSourceControl: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: systemImage)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(AppTheme.ColorToken.accent.gradient, in: Circle())

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 82)
        .contentShape(Rectangle())
    }
}

private struct PlaygroundConceptButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(AppTheme.Spacing.standard)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
            }
            .frame(width: 150, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create \(title.lowercased()) artwork")
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
