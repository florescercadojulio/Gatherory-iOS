import CoreImage
import Foundation
import Testing
import UIKit
@testable import Gatherory

struct EventInvitationQRCodeTests {
    private let baseURL = URL(string: "https://app.gatherory.com")!
    private let eventID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let token = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private var invitation: GeneratedEventInvitation {
        GeneratedEventInvitation(eventId: eventID, email: nil, expiresAt: nil,
            url: URL(string: "https://app.gatherory.com/join/\(token)")!, role: "guest")
    }

    @Test("Invitation decoding and URL validation can run outside the main actor")
    func validatesAcrossActorBoundary() async throws {
        let payload = Data(#"{"eventId":"11111111-1111-4111-8111-111111111111","email":null,"role":"guest","expiresAt":null,"url":"https://app.gatherory.com/join/22222222-2222-4222-8222-222222222222"}"#.utf8)
        let decoded = try await Task.detached {
            let value = try JSONDecoder().decode(GeneratedEventInvitation.self, from: payload)
            let eventID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
            let baseURL = URL(string: "https://app.gatherory.com")!
            #expect(value.isValid(for: eventID, baseURL: baseURL))
            #expect(!value.isValid(for: eventID, baseURL: URL(string: "https://other.example")!))
            return value
        }.value
        #expect(decoded.eventId == eventID)
        #expect(decoded.role == "guest")
    }

    @Test("Invitation QR round trips only the server-issued join URL")
    func roundTripURL() throws {
        let code = try EventInvitationQRCode(invitation: invitation, role: .guest, baseURL: baseURL)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode,
            context: CIContext(options: [.useSoftwareRenderer: true]),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let feature = try #require(detector.features(in: CIImage(cgImage: code.cgImage))
            .compactMap { $0 as? CIQRCodeFeature }.first)
        #expect(feature.messageString == invitation.url.absoluteString)
        let png = try #require(code.pngData)
        let pngImage = try #require(UIImage(data: png)?.cgImage)
        #expect(pngImage.width == Int(code.pixelSize.width))
        #expect(code.pixelSize.width == code.pixelSize.height)
        #expect(code.pixelSize.width == CGFloat((code.moduleCount + 2 * EventInvitationQRCode.quietZoneModules)
            * EventInvitationQRCode.modulePixelSize))
    }

    @Test("Invitation QR rejects email links, a mismatched role, and non-join template URLs")
    func rejectsUntrustedURLsAndRoles() throws {
        let emailInvitation = GeneratedEventInvitation(eventId: eventID, email: "guest@example.com",
            expiresAt: "2026-10-26T00:00:00Z", url: invitation.url, role: "guest")
        #expect(throws: EventInvitationQRCode.RenderError.invalidInvitationURL) {
            try EventInvitationQRCode(invitation: emailInvitation, role: .guest, baseURL: baseURL)
        }
        #expect(throws: EventInvitationQRCode.RenderError.invalidInvitationURL) {
            try EventInvitationQRCode(invitation: invitation, role: .collaborator, baseURL: baseURL)
        }
        #expect(throws: EventInvitationQRCode.RenderError.invalidInvitationURL) {
            try EventInvitationQRCode(invitation: invitation, role: .host, baseURL: baseURL)
        }
        let templateURL = URL(string: "https://app.gatherory.com/templates/shared/\(token)")!
        let template = GeneratedEventInvitation(eventId: eventID, email: nil, expiresAt: nil,
            url: templateURL, role: "guest")
        #expect(throws: EventInvitationQRCode.RenderError.invalidInvitationURL) {
            try EventInvitationQRCode(invitation: template, role: .guest, baseURL: baseURL)
        }
        let nonWebURL = GeneratedEventInvitation(eventId: eventID, email: nil, expiresAt: nil,
            url: URL(string: "ftp://app.gatherory.com/join/\(token)")!, role: "guest")
        #expect(throws: EventInvitationQRCode.RenderError.invalidInvitationURL) {
            try EventInvitationQRCode(invitation: nonWebURL, role: .guest, baseURL: URL(string: "ftp://app.gatherory.com")!)
        }
    }
}
