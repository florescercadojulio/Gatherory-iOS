import SwiftUI

/// Blurs the live content behind the guide, with feathered edges instead of a
/// bordered card. The text and controls are never part of the blur.
struct MovieNightTourBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: MovieNightTourBackdropCore.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
                    .overlay {
                        colorWash.clipShape(RoundedRectangle(
                            cornerRadius: MovieNightTourBackdropCore.cornerRadius, style: .continuous))
                    }
            } else {
                Rectangle()
                    .fill(.thickMaterial)
                    .overlay { Color(uiColor: .systemBackground).opacity(0.94) }
                    .overlay { colorWash }
                    .mask {
                        ZStack {
                            MovieNightTourBackdropCore().fill(.white)
                                .padding(MovieNightTourBackdropFeather.extent)
                                .blur(radius: 20)
                            MovieNightTourBackdropCore().fill(.white)
                                .padding(MovieNightTourBackdropFeather.extent)
                        }
                        .mask {
                            GeometryReader { geometry in
                                LinearGradient(stops: MovieNightTourBackdropFeather.stops(length: geometry.size.width),
                                               startPoint: .leading, endPoint: .trailing)
                                    .mask {
                                        LinearGradient(stops: MovieNightTourBackdropFeather.stops(length: geometry.size.height),
                                                       startPoint: .top, endPoint: .bottom)
                                    }
                            }
                        }
                    }
                    .padding(-MovieNightTourBackdropFeather.extent)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var colorWash: some View {
        LinearGradient(colors: [.cyan.opacity(0.22), .purple.opacity(0.14),
                                .pink.opacity(0.14), .orange.opacity(0.18)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Continuous corners preserve the guide's padded text area while the outer
/// copy feathers into the surrounding artwork.
struct MovieNightTourBackdropCore: Shape {
    static let cornerRadius: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).path(in: rect)
    }
}

/// The linear feather stays opaque across the guide's rounded core. Only the
/// extra blur outside it fades, protecting the padded header and footer.
enum MovieNightTourBackdropFeather {
    static let extent: CGFloat = 44

    static func stops(length: CGFloat) -> [Gradient.Stop] {
        guard length.isFinite, length > 0 else {
            return [.init(color: .clear, location: 0), .init(color: .clear, location: 1)]
        }
        let edge = min(0.5, extent / length)
        return [.init(color: .clear, location: 0), .init(color: .white, location: edge),
                .init(color: .white, location: 1 - edge), .init(color: .clear, location: 1)]
    }
}

/// A cutout mask keeps the real native tab and guide clear while dimming the
/// surrounding app. All coordinates belong to the measured root viewport.
struct MovieNightTourSpotlight: Shape {
    let targetFrame: CGRect
    let dialogFrame: CGRect?

    func path(in rect: CGRect) -> Path {
        var holes = Path()
        for (frame, padding, radius) in [(Optional(targetFrame), CGFloat(5), CGFloat(26)),
                                         (dialogFrame, CGFloat(28), CGFloat(36))] {
            guard let frame,
                  [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
                  frame.width > 0, frame.height > 0, frame.intersects(rect) else { continue }
            let hole = Path(roundedRect: frame.insetBy(dx: -padding, dy: -padding),
                            cornerRadius: radius)
            holes = holes.union(hole)
        }
        // Extend the outer fill beyond the screen so feathering softens only
        // the cutouts, without creating a bright rim at the display edges.
        return Path(rect.insetBy(dx: -24, dy: -24)).subtracting(holes)
    }
}
