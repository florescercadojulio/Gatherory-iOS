import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private struct BlueprintQRCodePNG: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
    }
}

struct BlueprintShareQRCodeView: View {
    let url: URL
    let templateTitle: String?
    var creatorName: String? = nil
    var activeShareLinkCount: Int? = nil
    var listedRevision: Int? = nil
    var isRetired = false
    private let code: BlueprintShareQRCode?

    init(url: URL, baseURL: URL?, templateTitle: String? = nil,
         creatorName: String? = nil, activeShareLinkCount: Int? = nil,
         listedRevision: Int? = nil, isRetired: Bool = false) {
        self.url = url
        self.templateTitle = templateTitle
        self.creatorName = creatorName
        self.activeShareLinkCount = activeShareLinkCount
        self.listedRevision = listedRevision
        self.isRetired = isRetired
        self.code = try? BlueprintShareQRCode(url: url, baseURL: baseURL)
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            if let creatorName, !creatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(BlueprintCopy.creatorByline(creatorName))
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if activeShareLinkCount != nil || listedRevision != nil {
                BlueprintSharingStatusBadges(
                    activeShareLinkCount: activeShareLinkCount,
                    listedRevision: listedRevision,
                    isRetired: isRetired
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(BlueprintCopy.shareTemplateExplanation)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let code {
                Image(uiImage: code.image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 360)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(BlueprintCopy.shareQRCodeAccessibilityLabel)
                    .accessibilityHint(BlueprintCopy.shareQRCodeAccessibilityHint)
                    .accessibilityAddTraits(.isImage)
                    .privacySensitive()
            } else {
                ContentUnavailableView(
                    BlueprintCopy.shareQRCodeRenderFailed,
                    systemImage: "qrcode"
                )
            }

            ShareLink(
                item: BlueprintQRCodePNG(data: code?.pngData ?? Data()),
                preview: SharePreview(
                    templateTitle ?? BlueprintCopy.shareQRCodeTitle,
                    image: code.map { Image(uiImage: $0.image) } ?? Image(systemName: "qrcode")
                )
            ) {
                Label(BlueprintCopy.shareQRCodeTitle, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(BlueprintCopy.shareQRCodeTitle)
            .disabled(code?.pngData == nil)
            .privacySensitive()

            ShareLink(
                item: url,
                subject: Text(templateTitle ?? BlueprintCopy.shareTemplate)
            ) {
                Label(BlueprintCopy.shareLink, systemImage: "link")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .privacySensitive()
        }
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .privacySensitive()
    }
}
