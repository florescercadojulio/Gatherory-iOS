#if DEBUG
import UIKit

/// Explicit, device-local artwork for album UI tests. Ordinary development
/// samples stay empty, and these photos never enter a persistent account store.
enum SharedAlbumUITestFixtures {
    static func applying(to workspaces: [PlanningWorkspace]) -> [PlanningWorkspace] {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-SeedSharedAlbumUITestPhotos"),
              AppRuntimeConfiguration.usesEphemeralDataStore,
              AppRuntimeConfiguration.seedsDevelopmentData,
              AppRuntimeConfiguration.skipsAuthentication else { return workspaces }
        return workspaces.map { workspace in
            guard workspace.title.hasPrefix("Maya & Theo") else { return workspace }
            var archive = WorkspaceArchiveV1(workspace: workspace)
            let owner = DevelopmentAccountFixtures.planner
            let sizes = [
                CGSize(width: 360, height: 500), CGSize(width: 500, height: 360),
                CGSize(width: 420, height: 420), CGSize(width: 480, height: 340)
            ]
            let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo, .systemPink]
            archive.eventMoments = sizes.enumerated().map { index, size in
                EventMoment(
                    eventID: workspace.mainEventID,
                    imageData: artwork(size: size, color: colors[index]),
                    addedBy: index == 1 ? "Alexandria Jacqueline Montgomery and family" : owner.displayName,
                    addedByUserID: index == 1 ? nil : owner.id,
                    addedAt: Date(timeIntervalSince1970: 1_791_043_200 + Double(index * 60))
                )
            }
            return archive.makeWorkspace()
        }
    }

    private static func artwork(size: CGSize, color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.9) { renderer in
            let bounds = CGRect(origin: .zero, size: size)
            color.setFill()
            renderer.fill(bounds)
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(ovalIn: CGRect(x: -size.width * 0.3, y: -size.height * 0.2, width: size.width, height: size.width)).fill()
            UIColor.white.withAlphaComponent(0.8).setFill()
            UIBezierPath(roundedRect: CGRect(x: size.width * 0.14, y: size.height * 0.45, width: size.width * 0.72, height: size.height * 0.35), cornerRadius: 30).fill()
            for index in 0..<3 {
                color.withAlphaComponent(0.8).setFill()
                UIBezierPath(ovalIn: CGRect(x: size.width * (0.25 + CGFloat(index) * 0.18), y: size.height * 0.56, width: 28, height: 28)).fill()
            }
            UIColor.white.withAlphaComponent(0.35).setFill()
            UIBezierPath(ovalIn: CGRect(x: size.width * 0.66, y: size.height * 0.1, width: size.width * 0.5, height: size.width * 0.5)).fill()
        }
    }
}
#endif
