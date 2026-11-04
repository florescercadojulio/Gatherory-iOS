import SwiftUI
import UIKit

/// Measures native navigation and filter controls in tab bars or adaptive
/// toolbars, publishing their real window frames for the tour coach.
struct MovieNightTourTabTargetProbe: UIViewRepresentable {
    let target: MovieNightTourTarget
    let tracker: MovieNightTourWindowGeometry

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MovieNightTourTabProbeView {
        let view = MovieNightTourTabProbeView()
        context.coordinator.configure(target: target, tracker: tracker)
        view.onLayout = { [weak coordinator = context.coordinator] probe in
            coordinator?.measure(from: probe)
        }
        return view
    }

    func updateUIView(_ view: MovieNightTourTabProbeView, context: Context) {
        context.coordinator.configure(target: target, tracker: tracker)
        view.onLayout = { [weak coordinator = context.coordinator] probe in
            coordinator?.measure(from: probe)
        }
        view.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MovieNightTourTabProbeView, context: Context) -> CGSize? {
        return CGSize(width: 1, height: 1)
    }

    static func dismantleUIView(_ view: MovieNightTourTabProbeView, coordinator: Coordinator) {
        coordinator.dismantle()
        view.onLayout = nil
    }

    @MainActor
    final class Coordinator {
        private weak var tracker: MovieNightTourWindowGeometry?
        private var target: MovieNightTourTarget?
        private var instanceToken = UUID()
        private var pendingUpdateID: UUID?
        private var pendingMeasurement: Task<Void, Never>?

        func configure(target newTarget: MovieNightTourTarget, tracker newTracker: MovieNightTourWindowGeometry) {
            if self.tracker !== newTracker || target != newTarget {
                cancelPendingMeasurement()
                removeCurrentMeasurement()
                instanceToken = UUID()
            }
            tracker = newTracker
            target = newTarget
        }

        func measure(from probe: MovieNightTourTabProbeView) {
            // UIKit accessibility queries can trigger layout and accessibility
            // snapshot work. Coalesce layout callbacks and do all inspection
            // after the current layout pass has returned.
            cancelPendingMeasurement()
            guard let target, let tracker, probe.window != nil else { return }
            let capturedToken = instanceToken
            let capturedID = UUID()
            pendingUpdateID = capturedID
            pendingMeasurement = Task { @MainActor [weak self, weak probe, tracker] in
                guard let self, let probe else { return }
                defer { self.finishMeasurement(id: capturedID) }

                let maximumAttempts = 12
                let initialDelay: UInt64 = 20_000_000
                let retryDelay: UInt64 = 150_000_000
                var scannedWindow: UIWindow?

                for attempt in 0..<maximumAttempts {
                    try? await Task.sleep(nanoseconds: attempt == 0 ? initialDelay : retryDelay)
                    guard !Task.isCancelled,
                          self.instanceToken == capturedToken,
                          self.target == target,
                          self.pendingUpdateID == capturedID,
                          let window = probe.window else { return }

                    if let scannedWindow, scannedWindow !== window { return }
                    scannedWindow = window

                    let frame = Self.measuredFrame(for: target, in: window)
                    guard !Task.isCancelled,
                          self.instanceToken == capturedToken,
                          self.target == target,
                          self.pendingUpdateID == capturedID,
                          probe.window === window else { return }

                    if let frame {
                        tracker.update(
                            target: target,
                            frame: frame,
                            windowObjectIdentifier: ObjectIdentifier(window),
                            instanceToken: capturedToken
                        )
                        return
                    }

                    if attempt == maximumAttempts - 1 {
                        tracker.update(
                            target: target,
                            frame: nil,
                            windowObjectIdentifier: nil,
                            instanceToken: capturedToken
                        )
                    }
                }
            }
        }

        func dismantle() {
            cancelPendingMeasurement()
            removeCurrentMeasurement()
            instanceToken = UUID()
            target = nil
            tracker = nil
        }

        private func cancelPendingMeasurement() {
            pendingMeasurement?.cancel()
            pendingMeasurement = nil
            pendingUpdateID = nil
        }

        private func finishMeasurement(id: UUID) {
            guard pendingUpdateID == id else { return }
            pendingMeasurement = nil
            pendingUpdateID = nil
        }

        private func removeCurrentMeasurement() {
            guard let target else { return }
            tracker?.remove(target: target, instanceToken: instanceToken)
        }

        private static func measuredFrame(for target: MovieNightTourTarget, in window: UIWindow) -> CGRect? {
            if let labels = MovieNightTourTabTargetPolicy.labels(for: target) {
                if let tabBar = matchingVisibleTabBar(in: window, labels: labels) {
                    // Prefer ordinary public UIView accessibility properties. This
                    // avoids invoking UIKit's accessibility container machinery on
                    // common tab-bar implementations.
                    if let frame = publicSubviewFrame(in: tabBar, labels: labels, window: window),
                       let visible = visibleFiniteFrame(frame, in: window) {
                        return visible
                    }
                    if let frame = visibleFiniteFrame(accessibilityElementFrame(in: tabBar, labels: labels, window: window), in: window) {
                        return frame
                    }
                }
            }
            return visibleFiniteFrame(navigationControlFrame(in: window, target: target), in: window)
        }

        private static func matchingVisibleTabBar(in window: UIWindow, labels: Set<String>) -> UITabBar? {
            let bars = findTabBars(in: window)
            // Adaptive tab bars can hide their backing container while exposing
            // live native tab elements in a separate hosting hierarchy. Prefer
            // visibly hosted bars, then validate the actual element's frame.
            let candidates = bars.filter { hasVisibleAncestors($0, in: window) }
                + bars.filter { !hasVisibleAncestors($0, in: window) }
            return candidates.first { tabBar in
                if let subviewFrame = publicSubviewFrame(in: tabBar, labels: labels, window: window),
                   visibleFiniteFrame(subviewFrame, in: window) != nil {
                    return true
                }
                return visibleFiniteFrame(
                    accessibilityElementFrame(in: tabBar, labels: labels, window: window),
                    in: window
                ) != nil
            }
        }

        private static func findTabBars(in root: UIView) -> [UITabBar] {
            var bars: [UITabBar] = []
            if let tabBar = root as? UITabBar { bars.append(tabBar) }
            for child in root.subviews {
                bars.append(contentsOf: findTabBars(in: child))
            }
            return bars
        }

        private static func hasVisibleAncestors(_ view: UIView, in window: UIWindow) -> Bool {
            var current: UIView? = view
            var effectiveAlpha: CGFloat = 1
            while let candidate = current {
                guard !candidate.isHidden else { return false }
                effectiveAlpha *= candidate.alpha
                if candidate === window { break }
                current = candidate.superview
            }
            return effectiveAlpha > 0.01
        }

        private static func accessibilityElementFrame(in tabBar: UITabBar, labels: Set<String>, window: UIWindow) -> CGRect? {
            let items = tabBar.items ?? []
            let itemIndex = items.firstIndex(where: { item in
                MovieNightTourTabTargetPolicy.matches(item.accessibilityLabel ?? item.title, labels: labels)
            })

            // Use an accessibility element exposed by UIKit's public container
            // API. Some UIKit versions expose fewer elements than tab items, so
            // also inspect public accessibility views under the tab bar.
            let container = tabBar
            let count = MovieNightTourTabTargetPolicy.validatedElementCount(
                reported: container.accessibilityElementCount()
            )
            let elements = (0..<count).compactMap { container.accessibilityElement(at: $0) }
            if let frame = elements.lazy.compactMap({ elementFrame($0, labels: labels, in: window) }).first {
                return frame
            }

            if let itemIndex, count == items.count,
               let indexed = container.accessibilityElement(at: itemIndex),
               let frame = elementFrame(indexed, labels: labels, in: window, allowUnlabeled: true) {
                return frame
            }
            return nil
        }

        private static func publicSubviewFrame(in root: UIView, labels: Set<String>, window: UIWindow) -> CGRect? {
            if root !== window,
               root.isAccessibilityElement,
               MovieNightTourTabTargetPolicy.matches(root.accessibilityLabel, labels: labels) {
                return root.convert(root.bounds, to: window)
            }
            for child in root.subviews {
                if let frame = publicSubviewFrame(in: child, labels: labels, window: window) { return frame }
            }
            return nil
        }

        private static func elementFrame(
            _ element: Any,
            labels: Set<String>,
            in window: UIWindow,
            allowUnlabeled: Bool = false
        ) -> CGRect? {
            if let view = element as? UIView {
                guard allowUnlabeled || MovieNightTourTabTargetPolicy.matches(view.accessibilityLabel, labels: labels) else {
                    return nil
                }
                return view.convert(view.bounds, to: window)
            }
            guard let accessible = element as? UIAccessibilityElement,
                  allowUnlabeled || MovieNightTourTabTargetPolicy.matches(accessible.accessibilityLabel, labels: labels) else {
                return nil
            }
            let screenFrame = accessible.accessibilityFrame
            guard !screenFrame.isNull, !screenFrame.isEmpty else { return nil }
            return window.convert(screenFrame, from: nil)
        }

        private static func navigationControlFrame(in window: UIWindow, target: MovieNightTourTarget) -> CGRect? {
            guard let descriptor = MovieNightTourTabTargetPolicy.navigationControl(for: target) else { return nil }
            return scanNavigationControls(target: target, descriptor: descriptor, in: window)
        }

        private static func scanNavigationControls(
            target: MovieNightTourTarget,
            descriptor: MovieNightTourNavigationControl,
            in window: UIWindow
        ) -> CGRect? {
            struct WorkItem {
                let object: NSObject
                let hostingView: UIView
                let depth: Int
            }
            let maximumDepth = 40
            var remainingWork = 2_048
            var pending = [WorkItem(object: window, hostingView: window, depth: 0)]
            var nextIndex = 0
            var visited = Set<ObjectIdentifier>()

            while nextIndex < pending.count, remainingWork > 0 {
                let item = pending[nextIndex]
                nextIndex += 1
                guard item.depth <= maximumDepth,
                      visited.insert(ObjectIdentifier(item.object)).inserted else { continue }
                remainingWork -= 1

                let label = item.object.accessibilityLabel
                let exactLabelMatch = label == descriptor.label
                if exactLabelMatch {
                    let identifier = MovieNightTourTabTargetPolicy.accessibilityIdentifier(for: item.object)
                    let traits = item.object.accessibilityTraits
                    let isTargetMatch = MovieNightTourTabTargetPolicy.matchesNavigationControl(
                        label: label, identifier: identifier, traits: traits, target: target
                    )
                    let rawFrame = accessibilityFrame(of: item.object, in: window)
                    let visibleFrame = visibleFiniteFrame(rawFrame, in: window)
                    let visibleHost = hasVisibleAncestors(item.hostingView, in: window)
                    let hitValidation: Bool
                    if let visibleFrame, !(item.object is UIView), !visibleHost {
                        hitValidation = hasVisibleHitTarget(at: visibleFrame, in: window)
                    } else {
                        hitValidation = false
                    }
                    let visibleValidation = visibleFrame != nil && (visibleHost || hitValidation)
                    if isTargetMatch, let visibleFrame, visibleValidation {
                        return visibleFrame
                    }
                }

                let elementCount = MovieNightTourTabTargetPolicy.validatedElementCount(
                    reported: item.object.accessibilityElementCount()
                )
                if elementCount > 0 {
                    for index in 0..<elementCount {
                        guard remainingWork > 0,
                              let element = item.object.accessibilityElement(at: index) as? NSObject else { break }
                        remainingWork -= 1

                        if item.depth < maximumDepth {
                            let host = (element as? UIView) ?? item.hostingView
                            pending.append(WorkItem(object: element, hostingView: host, depth: item.depth + 1))
                        }
                    }
                }

                guard item.depth < maximumDepth, let view = item.object as? UIView else { continue }
                for subview in view.subviews {
                    guard remainingWork > 0 else { break }
                    pending.append(WorkItem(object: subview, hostingView: subview, depth: item.depth + 1))
                    remainingWork -= 1
                }
            }
            return nil
        }

        private static func hasVisibleHitTarget(at frame: CGRect, in window: UIWindow) -> Bool {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard window.bounds.contains(center),
                  let hitView = window.hitTest(center, with: nil),
                  hitView !== window,
                  hitView.window === window else { return false }
            return hasVisibleAncestors(hitView, in: window)
        }

        private static func accessibilityFrame(of object: NSObject, in window: UIWindow) -> CGRect? {
            if let view = object as? UIView {
                return view.convert(view.bounds, to: window)
            }
            return window.convert(object.accessibilityFrame, from: nil)
        }

        private static func visibleFiniteFrame(_ frame: CGRect?, in window: UIWindow) -> CGRect? {
            guard let frame, !frame.isNull, !frame.isInfinite,
                  frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0 else { return nil }
            let visible = frame.intersection(window.bounds)
            guard !visible.isNull, !visible.isEmpty,
                  visible.origin.x.isFinite, visible.origin.y.isFinite,
                  visible.width.isFinite, visible.height.isFinite else { return nil }
            return visible
        }
    }
}

@MainActor
final class MovieNightTourTabProbeView: UIView {
    var onLayout: ((MovieNightTourTabProbeView) -> Void)?

    override var intrinsicContentSize: CGSize { .zero }

    override var isUserInteractionEnabled: Bool {
        get { false }
        set { super.isUserInteractionEnabled = false }
    }

    override var isAccessibilityElement: Bool {
        get { false }
        set { super.isAccessibilityElement = false }
    }

    override var accessibilityElementsHidden: Bool {
        get { true }
        set { super.accessibilityElementsHidden = true }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onLayout?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}

enum MovieNightTourTabTargetPolicy {
    static func accessibilityIdentifier(for object: NSObject) -> String? {
        if let identified = object as? UIAccessibilityIdentification,
           let identifier = identified.accessibilityIdentifier {
            return identifier
        }
        let getter = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard object.responds(to: getter) else { return nil }
        return object.perform(getter)?.takeUnretainedValue() as? String
    }

    static func validatedElementCount(reported: Int) -> Int {
        guard (1...128).contains(reported) else { return 0 }
        return reported
    }

    static func labels(for target: MovieNightTourTarget) -> Set<String>? {
        switch target {
        case .exploreTab:
            [ExploreCopy.title]
        case .ideasTab:
            [AppCopy.Tab.ideas]
        case .decideTab:
            [AppCopy.Tab.decide]
        case .homeTab:
            [AppCopy.Tab.home]
        default:
            nil
        }
    }

    static func navigationControl(for target: MovieNightTourTarget) -> MovieNightTourNavigationControl? {
        switch target {
        case .exploreTab:
            MovieNightTourNavigationControl(label: ExploreCopy.title, systemImageIdentifier: "magnifyingglass")
        case .homeTab:
            MovieNightTourNavigationControl(label: AppCopy.Tab.home, systemImageIdentifier: "house.fill")
        case .ideasTab:
            MovieNightTourNavigationControl(label: AppCopy.Tab.ideas, systemImageIdentifier: "sparkles.rectangle.stack.fill")
        case .decideTab:
            MovieNightTourNavigationControl(label: AppCopy.Tab.decide, systemImageIdentifier: "rectangle.on.rectangle.angled")
        case .ideasFilter:
            MovieNightTourNavigationControl(label: String(localized: "Filter ideas", defaultValue: "Filter ideas"), systemImageIdentifier: "ideas.filter")
        default:
            nil
        }
    }

    static func matches(_ itemLabel: String?, target: MovieNightTourTarget) -> Bool {
        guard let labels = labels(for: target) else { return false }
        return matches(itemLabel, labels: labels)
    }

    static func matches(_ itemLabel: String?, labels: Set<String>) -> Bool {
        guard let itemLabel else { return false }
        return labels.contains(itemLabel)
    }

    static func matchesNavigationControl(
        label: String?,
        identifier: String?,
        traits: UIAccessibilityTraits,
        target: MovieNightTourTarget
    ) -> Bool {
        guard let descriptor = navigationControl(for: target),
              label == descriptor.label,
              identifier == descriptor.systemImageIdentifier,
              traits.contains(.button) else { return false }
        return true
    }
}

struct MovieNightTourNavigationControl: Equatable {
    let label: String
    let systemImageIdentifier: String
}
