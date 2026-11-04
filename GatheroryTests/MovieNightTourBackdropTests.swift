import SwiftUI
import UIKit
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourBackdropTests {
    @Test("Rounded corners keep heading and footer padding fully inside the protected core")
    func roundedCoreProtectsTextInsets() {
        for size in [CGSize(width: 320, height: 124), CGSize(width: 340, height: 240)] {
            let core = MovieNightTourBackdropCore().path(in: CGRect(origin: .zero, size: size))
            for point in [CGPoint(x: 14, y: 14), CGPoint(x: size.width - 14, y: 14),
                          CGPoint(x: 14, y: size.height - 14),
                          CGPoint(x: size.width - 14, y: size.height - 14),
                          CGPoint(x: size.width / 2, y: size.height / 2)] {
                #expect(core.contains(point))
            }
            #expect(!core.contains(CGPoint(x: 1, y: 1)))
        }
    }

    @Test("Backdrop protection stays fully opaque beneath the whole guide, including header and footer")
    func protectsContentBeforeFeathering() {
        for contentLength in [CGFloat(124), 240, 320, 340] {
            let extent = MovieNightTourBackdropFeather.extent
            let expandedLength = contentLength + 2 * extent
            let stops = MovieNightTourBackdropFeather.stops(length: expandedLength)
            for contentPosition in [CGFloat(0), 14, contentLength / 2, contentLength - 14, contentLength] {
                let position = (extent + contentPosition) / expandedLength
                #expect(alpha(at: position, stops: stops) >= 0.999)
            }
            #expect(alpha(at: 0, stops: stops) == 0)
            #expect(alpha(at: 1, stops: stops) == 0)
            #expect(alpha(at: extent / 2 / expandedLength, stops: stops) < 1)
        }
    }

    @Test("Unavailable or tiny backdrop geometry never produces invalid gradient locations")
    func handlesTransientGeometry() {
        for length in [CGFloat.zero, -1, .nan, .infinity, 1, 44] {
            let stops = MovieNightTourBackdropFeather.stops(length: length)
            #expect(stops.allSatisfy { $0.location.isFinite && (0...1).contains($0.location) })
            #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location })
        }
    }

    private func alpha(at position: CGFloat, stops: [Gradient.Stop]) -> CGFloat {
        for (start, end) in zip(stops, stops.dropFirst()) where position >= start.location && position <= end.location {
            let fraction = (position - start.location) / max(end.location - start.location, .leastNonzeroMagnitude)
            let first = UIColor(start.color).cgColor.alpha
            let last = UIColor(end.color).cgColor.alpha
            return first + (last - first) * fraction
        }
        return 0
    }
}
