import SwiftUI
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourSpotlightTests {
    @Test("Spotlight leaves the native tab and guide clear, with surrounding app dimmed")
    func preservesTargetAndGuide() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let tab = CGRect(x: 280, y: 790, width: 90, height: 54)
        let dialog = CGRect(x: 31, y: 590, width: 340, height: 140)
        let path = MovieNightTourSpotlight(targetFrame: tab, dialogFrame: dialog).path(in: screen)
        #expect(!path.contains(CGPoint(x: tab.midX, y: tab.midY), eoFill: true))
        #expect(!path.contains(CGPoint(x: dialog.midX, y: dialog.midY), eoFill: true))
        #expect(path.contains(CGPoint(x: 40, y: 200), eoFill: true))
        #expect(path.contains(CGPoint(x: 80, y: 817), eoFill: true))
    }

    @Test("Invalid or offscreen guide bounds cannot cut a false spotlight into the app")
    func ignoresUnavailableGuideFrame() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 874)
        let tab = CGRect(x: 280, y: 790, width: 90, height: 54)
        for dialog in [CGRect?.none, CGRect(x: 500, y: 200, width: 100, height: 80),
                       CGRect(x: CGFloat.nan, y: 200, width: 100, height: 80)] {
            let path = MovieNightTourSpotlight(targetFrame: tab, dialogFrame: dialog).path(in: screen)
            #expect(path.contains(CGPoint(x: 40, y: 200), eoFill: true))
            #expect(!path.contains(CGPoint(x: tab.midX, y: tab.midY), eoFill: true))
        }
    }

    @Test("Overlapping guide and tab cutouts stay clear")
    func overlappingCutoutsDoNotRedimTab() {
        let screen = CGRect(x: 0, y: 0, width: 402, height: 650)
        let tab = CGRect(x: 280, y: 565, width: 90, height: 54)
        let dialog = CGRect(x: 31, y: 430, width: 340, height: 150)
        let path = MovieNightTourSpotlight(targetFrame: tab, dialogFrame: dialog).path(in: screen)
        #expect(!path.contains(CGPoint(x: 320, y: 580), eoFill: true))
    }
}
