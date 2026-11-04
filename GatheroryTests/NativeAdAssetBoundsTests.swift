import GoogleMobileAds
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct NativeAdAssetBoundsTests {
    @Test("Fractional host heights never leave registered assets outside the native view")
    func fractionalUndersizing() {
        let view = sampleView()
        let height = view.fittingSize(forWidth: 180).height
        view.frame = CGRect(x: 0, y: 0, width: 180, height: height - 0.25)
        view.layoutIfNeeded()
        assertAssetsContained(in: view)
    }

    @Test("Shrinking and zero-size layout keep all assets contained until the host fits again")
    func resizeAndRecovery() {
        let view = sampleView()
        for width: CGFloat in [180, 202.333, 380] {
            let height = view.fittingSize(forWidth: width).height
            for hostHeight in [height, height - 20, 0, height] {
                view.frame = CGRect(x: 0, y: 0, width: width, height: hostHeight)
                view.setNeedsLayout()
                view.layoutIfNeeded()
                assertAssetsContained(in: view)
            }
            #expect(view.mediaView?.frame.height == 160)
            #expect(view.callToActionView?.frame.height ?? 0 >= 44)
        }
    }

    @Test("Multiline copy and optional assets fit the same native height used for measurement")
    func completeCreativeLayout() {
        let view = sampleView()
        (view.headlineView as? UILabel)?.text = "A longer headline that wraps across several lines in a narrow Explore column"
        (view.bodyView as? UILabel)?.text = String(repeating: "Bring everyone together. ", count: 5)
        var configuration = (view.callToActionView as? UIButton)?.configuration
        configuration?.title = "Discover all the details and learn more"
        (view.callToActionView as? UIButton)?.configuration = configuration
        for width: CGFloat in [156, 180, 380] {
            let height = view.fittingSize(forWidth: width).height
            view.frame = CGRect(x: 0, y: 0, width: width, height: height)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            assertAssetsContained(in: view)
            #expect(view.headlineView?.frame.height ?? 0 > 0)
        }
    }

    @Test("Right-to-left layout and a fractional bounds origin preserve containment")
    func rightToLeftBounds() {
        let view = sampleView()
        view.semanticContentAttribute = .forceRightToLeft
        let height = view.fittingSize(forWidth: 202.333).height
        view.bounds = CGRect(x: 0.333, y: 0.333, width: 202.333, height: height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        assertAssetsContained(in: view)
        #expect(view.headlineView?.frame.height ?? 0 > 0)
    }

    @Test("A collapsed host width clears stale frames and recovers when a column returns")
    func collapsedWidth() {
        let view = sampleView()
        for width: CGFloat in [180, 0, 1, 2, 180] {
            view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            assertAssetsContained(in: view)
            if width <= 2 { #expect(view.mediaView?.frame.isEmpty == true) }
        }
        #expect(view.mediaView?.frame.height == 160)
    }

    private func sampleView() -> RegisteredNativeAdView {
        let view = RegisteredNativeAdView()
        view.populate(with: nil, isPreviewSample: true)
        return view
    }

    private func assertAssetsContained(in view: RegisteredNativeAdView,
                                      sourceLocation: SourceLocation = #_sourceLocation) {
        let assets: [UIView?] = [view.headlineView, view.bodyView, view.advertiserView,
                               view.iconView, view.mediaView, view.callToActionView, view.adChoicesView]
        for asset in assets.compactMap({ $0 }) where !asset.isHidden && !asset.frame.isEmpty {
            let frame = asset.convert(asset.bounds, to: view)
            #expect(view.bounds.contains(frame),
                    "Asset \(type(of: asset)) at \(frame) exceeds native bounds \(view.bounds)",
                    sourceLocation: sourceLocation)
        }
    }
}
