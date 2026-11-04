import SwiftUI

/// A control in the Movie Night walkthrough that can be measured in the host
/// overlay's coordinate space.
enum MovieNightTourTarget: Hashable {
    case viewport
    case exploreTab
    case homeTab
    case ideasTab
    case decideTab
    case movieNightBlueprint
    case discoveryDialog
    case idea(UUID)
    case decision(UUID)
    case ideasFilter
}

private struct MovieNightTourTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [MovieNightTourTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [MovieNightTourTarget: Anchor<CGRect>],
        nextValue: () -> [MovieNightTourTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private struct MovieNightTourSuppressionPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func movieNightDiscoveryOverlay(
        phase: MovieNightTourDiscoveryPhase?, windowGeometry: MovieNightTourWindowGeometry
    ) -> some View {
        modifier(MovieNightTourDiscoveryOverlayModifier(
            phase: phase, windowGeometry: windowGeometry))
    }
    /// Publishes this view's real bounds for the walkthrough without changing
    /// its layout or hit-testing behavior.
    func movieNightTourTarget(_ target: MovieNightTourTarget) -> some View {
        anchorPreference(key: MovieNightTourTargetPreferenceKey.self, value: .bounds) {
            [target: $0]
        }

    }

    /// Suppresses the walkthrough while a descendant presents a modal surface.
    func movieNightTourSuppressed(_ isSuppressed: Bool = true) -> some View {
        preference(key: MovieNightTourSuppressionPreferenceKey.self, value: isSuppressed)
    }

    /// Hosts the tour above the existing content, resolving target anchors in
    /// the same geometry space. The overlay itself does not reserve layout.
    func movieNightTourOverlay(selectedTab: Binding<WorkspaceTab>, windowGeometry: MovieNightTourWindowGeometry? = nil) -> some View {
        modifier(MovieNightTourOverlayModifier(selectedTab: selectedTab, providedWindowGeometry: windowGeometry))
    }
}

private struct MovieNightTourDiscoveryOverlayModifier: ViewModifier {
    let phase: MovieNightTourDiscoveryPhase?
    let windowGeometry: MovieNightTourWindowGeometry

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(MovieNightTourTargetPreferenceKey.self) { anchors in
            GeometryReader { geometry in
                if let phase {
                    let tabFrame = windowGeometry.frame(for: .exploreTab, relativeTo: .viewport)
                    let cardFrame = windowGeometry.frame(for: .movieNightBlueprint, relativeTo: .viewport)
                        ?? anchors[.movieNightBlueprint].map { geometry[$0] }
                    let dialogFrame = windowGeometry.frame(for: .discoveryDialog, relativeTo: .viewport)
                    let targetFrame = phase == .chooseExplore ? tabFrame : cardFrame
                    MovieNightTourDiscoveryFocus(phase: phase, targetFrame: targetFrame,
                        dialogFrame: dialogFrame, viewport: CGRect(origin: .zero, size: geometry.size))
                }
            }
            .background {
                if phase != nil { MovieNightTourWindowTarget(target: .viewport, tracker: windowGeometry) }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private struct MovieNightTourDiscoveryFocus: View {
    let phase: MovieNightTourDiscoveryPhase
    let targetFrame: CGRect?
    let dialogFrame: CGRect?
    let viewport: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let targetFrame, !targetFrame.isEmpty,
               viewport.intersection(targetFrame).height >= targetFrame.height * 0.5 {
                if phase == .chooseExplore {
                    Color.black.opacity(0.32)
                        .mask {
                            MovieNightTourSpotlight(targetFrame: targetFrame, dialogFrame: dialogFrame)
                                .fill(style: FillStyle(eoFill: true))
                                .blur(radius: 8)
                        }
                        .accessibilityHidden(true)
                }
                RoundedRectangle(cornerRadius: phase == .chooseExplore ? 22 : AppTheme.Radius.card)
                    .strokeBorder(phase == .chooseExplore ? Color.accentColor : .clear, lineWidth: 3)
                    .frame(width: targetFrame.width, height: targetFrame.height)
                    .position(x: targetFrame.midX, y: targetFrame.midY)
                    .accessibilityHidden(true)
                if let dialogFrame {
                    let placement = MovieNightTourOverlayLayout.place(target: targetFrame,
                        viewport: dialogFrame, bubbleSize: dialogFrame.size, targetViewport: viewport)
                    if let start = placement.pointerStart, let end = placement.pointerEnd {
                        MovieNightTourPointer(start: start, end: end)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MovieNightTourOverlayModifier: ViewModifier {
    @Binding var selectedTab: WorkspaceTab
    @State private var isSuppressed = false
    @State private var ideasFilter = IdeaFilter.all.rawValue
    @State private var localWindowGeometry = MovieNightTourWindowGeometry()
    var providedWindowGeometry: MovieNightTourWindowGeometry?
    private var windowGeometry: MovieNightTourWindowGeometry { providedWindowGeometry ?? localWindowGeometry }

    func body(content: Content) -> some View {
        content
            .environment(\.movieNightTourWindowGeometry, windowGeometry)
            .transformAnchorPreference(key: MovieNightTourTargetPreferenceKey.self, value: .bounds) { values, bounds in
                values[.viewport] = bounds
            }
            .onPreferenceChange(MovieNightTourSuppressionPreferenceKey.self) { isSuppressed = $0 }
            .onPreferenceChange(MovieNightTourIdeasFilterPreferenceKey.self) { value in
                if let value { ideasFilter = value }
            }
            .overlayPreferenceValue(MovieNightTourTargetPreferenceKey.self) { anchors in
                GeometryReader { geometry in
                    if !isSuppressed {
                        MovieNightTourCoach(
                            selectedTab: $selectedTab,
                            targetFrames: resolvedFrames(anchors, in: geometry),
                            viewport: MovieNightTourOverlayLayout.safeViewport(in: geometry),
                            targetViewport: targetViewport(in: geometry),
                            ideasFilter: ideasFilter
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .background { MovieNightTourWindowTarget(target: .viewport, tracker: windowGeometry) }
                .environment(\.movieNightTourWindowGeometry, windowGeometry)
            }
    }

    private func resolvedFrames(_ anchors: [MovieNightTourTarget: Anchor<CGRect>], in geometry: GeometryProxy) -> [MovieNightTourTarget: CGRect] {
        var frames = anchors.mapValues { geometry[$0] }
        for target in [MovieNightTourTarget.ideasFilter, .homeTab, .ideasTab, .decideTab] {
            if let frame = windowGeometry.frame(for: target, relativeTo: .viewport) {
                frames[target] = frame
            }
        }
        return frames
    }

    private func targetViewport(in geometry: GeometryProxy) -> CGRect {
        var viewport = CGRect(origin: .zero, size: geometry.size)
        // The guide stays inside the content safe area; its pointer can reach
        // native navigation and filter controls outside that area using their
        // measured bounds, including side toolbars on adaptive phone layouts.
        for target in [MovieNightTourTarget.homeTab, .ideasTab, .decideTab, .ideasFilter] {
            if let frame = windowGeometry.frame(for: target, relativeTo: .viewport) {
                viewport = viewport.union(frame)
            }
        }
        return viewport
    }
}

/// Geometry for a measured coach bubble and its optional pointer. Target and
/// viewport coordinates must be in the same space; bubbleSize comes from the
/// rendered coach content rather than a screen-size assumption.
struct MovieNightTourOverlayLayout {
    struct Placement: Equatable {
        let bubbleFrame: CGRect
        let pointerStart: CGPoint?
        let pointerEnd: CGPoint?
        let targetIsVisible: Bool
    }

    private enum Side: CaseIterable {
        case above, below, leading, trailing
    }

    private static let gap: CGFloat = 12
    private static let targetClearance: CGFloat = 8
    private static let pointerInset: CGFloat = 16

    static func safeViewport(in proxy: GeometryProxy) -> CGRect {
        let insets = proxy.safeAreaInsets
        let values = [proxy.size.width, proxy.size.height, insets.leading, insets.trailing, insets.top, insets.bottom]
        guard values.allSatisfy(\.isFinite), proxy.size.width > 0, proxy.size.height > 0 else { return .zero }
        let viewport = CGRect(
            x: insets.leading,
            y: insets.top,
            width: max(0, proxy.size.width - insets.leading - insets.trailing),
            height: max(0, proxy.size.height - insets.top - insets.bottom)
        )
        return isFinite(viewport) ? viewport : .zero
    }

    static func place(
        target: CGRect?,
        viewport: CGRect,
        bubbleSize: CGSize,
        targetViewport: CGRect? = nil
    ) -> Placement {
        guard isFinite(viewport), viewport.width > 0, viewport.height > 0,
              bubbleSize.width.isFinite, bubbleSize.height.isFinite,
              bubbleSize.width > 0, bubbleSize.height > 0 else {
            return Placement(bubbleFrame: .zero, pointerStart: nil, pointerEnd: nil, targetIsVisible: false)
        }
        let size = CGSize(
            width: min(max(0, bubbleSize.width), viewport.width),
            height: min(max(0, bubbleSize.height), viewport.height)
        )
        let visibleBounds = targetViewport ?? viewport
        guard isFinite(visibleBounds), visibleBounds.width > 0, visibleBounds.height > 0,
              let target, isFinite(target),
              target.width > 0, target.height > 0,
              isMostlyVisible(target, in: visibleBounds) else {
            return Placement(
                bubbleFrame: fallbackFrame(in: viewport, size: size),
                pointerStart: nil,
                pointerEnd: nil,
                targetIsVisible: false
            )
        }

        let visibleTarget = target.intersection(visibleBounds)
        let candidates = Side.allCases.map { side in
            (side, candidateFrame(for: visibleTarget, side: side, size: size))
        }
        let fullyFitting = candidates.filter { viewport.contains($0.1) }
        let pool = fullyFitting.isEmpty ? candidates : fullyFitting
        let selected = pool.min { lhs, rhs in
            score(lhs.1, side: lhs.0, target: visibleTarget, viewport: viewport)
                < score(rhs.1, side: rhs.0, target: visibleTarget, viewport: viewport)
        } ?? (.below, fallbackFrame(in: viewport, size: size))
        let frame = clamp(selected.1, to: viewport)
        let endpoints: (start: CGPoint, end: CGPoint)?
        if frame.insetBy(dx: -targetClearance, dy: -targetClearance).intersection(visibleTarget).isEmpty {
            endpoints = pointerEndpoints(from: frame, to: visibleTarget, side: selected.0)
        } else {
            endpoints = exposedTargetPointer(from: frame, to: visibleTarget)
        }
        return Placement(
            bubbleFrame: frame,
            pointerStart: endpoints?.start,
            pointerEnd: endpoints?.end,
            targetIsVisible: true
        )
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }

    private static func isMostlyVisible(_ target: CGRect, in viewport: CGRect) -> Bool {
        guard viewport.width > 0, viewport.height > 0 else { return false }
        let intersection = target.intersection(viewport)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let visibleArea = intersection.width * intersection.height
        let totalArea = target.width * target.height
        return totalArea > 0 && visibleArea / totalArea >= 0.5
    }

    private static func candidateFrame(for target: CGRect, side: Side, size: CGSize) -> CGRect {
        switch side {
        case .above:
            CGRect(x: target.midX - size.width / 2, y: target.minY - gap - size.height,
                   width: size.width, height: size.height)
        case .below:
            CGRect(x: target.midX - size.width / 2, y: target.maxY + gap,
                   width: size.width, height: size.height)
        case .leading:
            CGRect(x: target.minX - gap - size.width, y: target.midY - size.height / 2,
                   width: size.width, height: size.height)
        case .trailing:
            CGRect(x: target.maxX + gap, y: target.midY - size.height / 2,
                   width: size.width, height: size.height)
        }
    }

    private static func score(_ frame: CGRect, side: Side, target: CGRect, viewport: CGRect) -> CGFloat {
        let overlap = frame.insetBy(dx: -targetClearance, dy: -targetClearance).intersection(target)
        let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
        let overflow = max(0, viewport.minX - frame.minX) + max(0, frame.maxX - viewport.maxX)
            + max(0, viewport.minY - frame.minY) + max(0, frame.maxY - viewport.maxY)
        let preferredSidePenalty: CGFloat = (side == .above || side == .below) ? 0 : 1
        return overflow * 10_000 + overlapArea * 100 + preferredSidePenalty
    }

    private static func clamp(_ frame: CGRect, to viewport: CGRect) -> CGRect {
        CGRect(
            x: min(max(frame.minX, viewport.minX), max(viewport.minX, viewport.maxX - frame.width)),
            y: min(max(frame.minY, viewport.minY), max(viewport.minY, viewport.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }

    private static func fallbackFrame(in viewport: CGRect, size: CGSize) -> CGRect {
        let x = viewport.midX - size.width / 2
        // Keep the fallback near an edge to avoid covering the central content.
        let y = viewport.minY + min(gap, max(0, viewport.height - size.height))
        return clamp(CGRect(origin: CGPoint(x: x, y: y), size: size), to: viewport)
    }

    private static func pointerEndpoints(
        from bubble: CGRect,
        to target: CGRect,
        side: Side
    ) -> (start: CGPoint, end: CGPoint) {
        switch side {
        case .above:
            (CGPoint(x: min(max(target.midX, bubble.minX + pointerInset), bubble.maxX - pointerInset), y: bubble.maxY),
             CGPoint(x: target.midX, y: target.minY))
        case .below:
            (CGPoint(x: min(max(target.midX, bubble.minX + pointerInset), bubble.maxX - pointerInset), y: bubble.minY),
             CGPoint(x: target.midX, y: target.maxY))
        case .leading:
            (CGPoint(x: bubble.maxX, y: min(max(target.midY, bubble.minY + pointerInset), bubble.maxY - pointerInset)),
             CGPoint(x: target.minX, y: target.midY))
        case .trailing:
            (CGPoint(x: bubble.minX, y: min(max(target.midY, bubble.minY + pointerInset), bubble.maxY - pointerInset)),
             CGPoint(x: target.maxX, y: target.midY))
        }
    }

    /// When a target is larger than the available free space, point at an
    /// exposed portion of the measured target instead of drawing the pointer
    /// through the coach bubble. Endpoints are derived from the real rectangles.
    private static func exposedTargetPointer(from bubble: CGRect, to target: CGRect) -> (start: CGPoint, end: CGPoint)? {
        let clearanceBubble = bubble.insetBy(dx: -targetClearance, dy: -targetClearance)
        let regions: [(CGRect, (CGRect, CGRect) -> (CGPoint, CGPoint))] = [
            (CGRect(x: target.minX, y: target.minY, width: target.width,
                    height: max(0, min(target.maxY, clearanceBubble.minY) - target.minY)),
             { _, b in (CGPoint(x: min(max(target.midX, b.minX), b.maxX), y: b.minY),
                        CGPoint(x: target.midX, y: min(target.maxY, clearanceBubble.minY) - 0.5)) }),
            (CGRect(x: target.minX, y: max(target.minY, clearanceBubble.maxY), width: target.width,
                    height: max(0, target.maxY - max(target.minY, clearanceBubble.maxY))),
             { _, b in (CGPoint(x: min(max(target.midX, b.minX), b.maxX), y: b.maxY),
                        CGPoint(x: target.midX, y: max(target.minY, clearanceBubble.maxY) + 0.5)) }),
            (CGRect(x: target.minX, y: target.minY, width: max(0, min(target.maxX, clearanceBubble.minX) - target.minX),
                    height: target.height),
             { _, b in (CGPoint(x: b.minX, y: min(max(target.midY, b.minY), b.maxY)),
                        CGPoint(x: min(target.maxX, clearanceBubble.minX) - 0.5, y: target.midY)) }),
            (CGRect(x: max(target.minX, clearanceBubble.maxX), y: target.minY,
                    width: max(0, target.maxX - max(target.minX, clearanceBubble.maxX)), height: target.height),
             { _, b in (CGPoint(x: b.maxX, y: min(max(target.midY, b.minY), b.maxY)),
                        CGPoint(x: max(target.minX, clearanceBubble.maxX) + 0.5, y: target.midY)) })
        ]
        guard let region = regions.filter({ $0.0.width > 1 && $0.0.height > 1 })
            .max(by: { $0.0.width * $0.0.height < $1.0.width * $1.0.height }) else { return nil }
        let points = region.1(region.0, bubble)
        guard isFinite(points.0), isFinite(points.1),
              !clearanceBubble.contains(points.1), target.contains(points.1) else { return nil }
        return points
    }

    private static func isFinite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }
}
