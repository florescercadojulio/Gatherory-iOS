import SwiftUI

struct MovieNightTourDiscoveryCoach: View {
    let phase: MovieNightTourDiscoveryPhase
    var saveFailed = false
    var windowGeometry: MovieNightTourWindowGeometry? = nil
    let onPrevious: () -> Void
    let onSkip: () -> Void

    var body: some View {
        dialog.background {
            ZStack {
                MovieNightTourWindowTarget(target: .discoveryDialog, tracker: windowGeometry)
                if phase == .chooseExplore, let windowGeometry {
                    MovieNightTourTabTargetProbe(target: .exploreTab, tracker: windowGeometry)
                        .frame(width: 1, height: 1)
                }
            }
        }
        .overlay(alignment: .topLeading) {
#if DEBUG
            // A tiny harness-only readout keeps geometry assertions away from
            // the real native tab's accessibility hit region.
            if ProcessInfo.processInfo.arguments.contains("-ResetMovieNightTourUITestState"),
               let target = windowGeometry?.windowFrame(for: phase == .chooseExplore ? .exploreTab : .movieNightBlueprint) {
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: String(format:
                        String(localized: "movieNightTour.focus", defaultValue: "Guide focus: %@"),
                        phase == .chooseExplore ? ExploreCopy.title : String(localized: "Movie Night"))))
                    .accessibilityValue("[\(target.minX),\(target.minY),\(target.width),\(target.height)]")
                    .accessibilityIdentifier("movieNightTour.discovery.focus")
                    .allowsHitTesting(false)
            }
#endif
        }
    }

    private var dialog: some View {
        VStack(spacing: 8) {
            Text(phase == .chooseExplore
                 ? String(localized: "Tap Explore to find Movie Night.")
                 : String(localized: "Tap Movie Night to start your plan."))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("movieNightTour.discovery.instruction")
            if saveFailed {
                Text("The tour could not be saved. Try again or skip for now.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("movieNightTour.discovery.error")
            }
            MovieNightTourFooter(canGoPrevious: phase == .chooseMovieNight, canGoNext: false,
                                 onPrevious: onPrevious, onSkip: onSkip, onNext: {})
        }
        .padding(14)
        .frame(maxWidth: 340)
        .background { MovieNightTourBackdrop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("movieNightTour.discovery.overlay")
    }
}
