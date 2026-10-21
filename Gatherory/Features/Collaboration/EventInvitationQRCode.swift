import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A print-friendly QR containing only a validated Gatherory `/join/<UUID>` URL.
nonisolated struct EventInvitationQRCode {
    enum RenderError: Error, Equatable {
        case invalidInvitationURL
        case generationFailed
    }

    static let modulePixelSize = 16
    static let quietZoneModules = 4

    let cgImage: CGImage
    let pixelSize: CGSize
    let moduleCount: Int

    var image: UIImage { UIImage(cgImage: cgImage, scale: 1, orientation: .up) }
    var pngData: Data? { image.pngData() }

    init(invitation: GeneratedEventInvitation, role: WorkspaceRole, baseURL: URL) throws {
        guard role == .guest || role == .collaborator,
              invitation.email == nil,
              invitation.role == role.rawValue,
              invitation.isValid(for: invitation.eventId, baseURL: baseURL) else {
            throw RenderError.invalidInvitationURL
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(invitation.url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let generated = filter.outputImage,
              generated.extent.width.isFinite,
              generated.extent.width == generated.extent.height,
              generated.extent.width.rounded(.down) == generated.extent.width,
              let moduleCount = Int(exactly: generated.extent.width), moduleCount > 0,
              let rawQR = Self.context.createCGImage(generated, from: generated.extent) else {
            throw RenderError.generationFailed
        }

        let margin = Self.quietZoneModules * Self.modulePixelSize
        let dimension = (moduleCount + 2 * Self.quietZoneModules) * Self.modulePixelSize
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: dimension, height: dimension,
                  bitsPerComponent: 8, bytesPerRow: dimension * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw RenderError.generationFailed
        }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(rawQR, in: CGRect(x: margin, y: margin,
            width: moduleCount * Self.modulePixelSize, height: moduleCount * Self.modulePixelSize))
        guard let rendered = context.makeImage() else { throw RenderError.generationFailed }
        self.cgImage = rendered
        self.pixelSize = CGSize(width: dimension, height: dimension)
        self.moduleCount = moduleCount
    }

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
}

private struct InvitationQRCodePNG: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }
}

/// Reusable role-aware QR sheet. Only server-issued public role links are accepted.
struct EventInvitationQRCodeSheet: View {
    let invitation: GeneratedEventInvitation
    let role: WorkspaceRole
    let eventTitle: String
    let baseURL: URL
    private let code: EventInvitationQRCode?

    init(invitation: GeneratedEventInvitation, role: WorkspaceRole, eventTitle: String, baseURL: URL) {
        self.invitation = invitation
        self.role = role
        self.eventTitle = eventTitle
        self.baseURL = baseURL
        self.code = try? EventInvitationQRCode(invitation: invitation, role: role, baseURL: baseURL)
    }

    private var roleTitle: String { role == .guest ? String(localized: "Guest Invitation") : String(localized: "Collaborator Invitation") }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            VStack(spacing: 6) {
                Text(roleTitle).font(.title2.bold())
                Text(eventTitle).font(.headline).foregroundStyle(.secondary)
                Text("This link stays active until you revoke it.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let code, let pngData = code.pngData {
                Image(uiImage: code.image)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 360)
                    .padding(16).background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Invitation QR code")
                    .accessibilityAddTraits(.isImage)
                    .privacySensitive()
                ShareLink(item: InvitationQRCodePNG(data: pngData),
                          preview: SharePreview(roleTitle, image: Image(uiImage: code.image))) {
                    Label("Share QR Code", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .privacySensitive()
            } else {
                ContentUnavailableView("QR Code Unavailable", systemImage: "qrcode")
            }
        }
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: 520).frame(maxWidth: .infinity)
        .privacySensitive()
    }
}
