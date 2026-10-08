import PhotosUI
import SwiftUI

struct PhotoAttachmentPicker: View {
    @Binding var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    let emptySymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            preview

            HStack(spacing: AppTheme.Spacing.compact) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(imageData == nil ? "Add Photo" : "Change Photo", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.bordered)

                if imageData != nil {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        imageData = nil
                        selectedPhoto = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }

            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    imageData = data
                }
            }
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
                .accessibilityLabel("Selected photo")
        } else {
            ContentUnavailableView(
                "Add a Photo",
                systemImage: emptySymbol,
                description: Text("Choose an image that helps everyone recognize it.")
            )
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(AppTheme.ColorToken.elevatedSurface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        }
    }
}
