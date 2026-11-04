import Observation
import SwiftUI
import UIKit

/// Window-space measurements for tour anchors that live in separate UIKit
/// hosting hierarchies, such as a native navigation toolbar.
@Observable @MainActor
final class MovieNightTourWindowGeometry {
    private struct Measurement {
        let frame: CGRect
        let windowObjectIdentifier: ObjectIdentifier
        let instanceToken: UUID
    }

    private var measurements: [MovieNightTourTarget: Measurement] = [:]

    func windowFrame(for target: MovieNightTourTarget) -> CGRect? {
        measurements[target]?.frame
    }

    func frame(for target: MovieNightTourTarget, relativeTo host: MovieNightTourTarget) -> CGRect? {
        guard let targetMeasurement = measurements[target],
              let hostMeasurement = measurements[host],
              targetMeasurement.windowObjectIdentifier == hostMeasurement.windowObjectIdentifier else {
            return nil
        }

        return targetMeasurement.frame.offsetBy(
            dx: -hostMeasurement.frame.minX,
            dy: -hostMeasurement.frame.minY
        )
    }

    func update(
        target: MovieNightTourTarget,
        frame: CGRect?,
        windowObjectIdentifier: ObjectIdentifier?,
        instanceToken: UUID
    ) {
        guard let frame, let windowObjectIdentifier else {
            remove(target: target, instanceToken: instanceToken)
            return
        }
        if let existing = measurements[target], existing.instanceToken == instanceToken,
           existing.frame == frame, existing.windowObjectIdentifier == windowObjectIdentifier {
            return
        }
        measurements[target] = Measurement(
            frame: frame,
            windowObjectIdentifier: windowObjectIdentifier,
            instanceToken: instanceToken
        )
    }

    func remove(target: MovieNightTourTarget, instanceToken: UUID) {
        guard measurements[target]?.instanceToken == instanceToken else { return }
        measurements.removeValue(forKey: target)
    }
}

extension EnvironmentValues {
    @Entry var movieNightTourWindowGeometry: MovieNightTourWindowGeometry? = nil
}

/// Measures this representable's real UIKit bounds in the containing window.
/// A transparent, noninteractive UIView keeps the measurement out of layout
/// and leaves its underlying SwiftUI control tappable.
struct MovieNightTourWindowTarget: UIViewRepresentable {
    let target: MovieNightTourTarget
    var tracker: MovieNightTourWindowGeometry? = nil
    @Environment(\.movieNightTourWindowGeometry) private var geometry

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MovieNightTourMeasurementView {
        let view = MovieNightTourMeasurementView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: MovieNightTourMeasurementView, context: Context) {
        configure(view, coordinator: context.coordinator)
        view.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MovieNightTourMeasurementView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    static func dismantleUIView(_ view: MovieNightTourMeasurementView, coordinator: Coordinator) {
        coordinator.dismantle()
        view.onMeasurement = nil
    }

    private func configure(_ view: MovieNightTourMeasurementView, coordinator: Coordinator) {
        coordinator.configure(target: target, geometry: tracker ?? geometry)
        view.onMeasurement = { [weak coordinator] frame, window in
            coordinator?.scheduleMeasurement(frame: frame, window: window)
        }
    }

    @MainActor
    final class Coordinator {
        private weak var geometry: MovieNightTourWindowGeometry?
        private var target: MovieNightTourTarget?
        private var instanceToken = UUID()

        func configure(target newTarget: MovieNightTourTarget, geometry newGeometry: MovieNightTourWindowGeometry?) {
            if self.geometry !== newGeometry {
                removeCurrentMeasurement()
                instanceToken = UUID()
            }
            if target != newTarget {
                removeCurrentMeasurement()
                instanceToken = UUID()
                target = newTarget
            }
            geometry = newGeometry
        }

        func scheduleMeasurement(frame: CGRect?, window: UIWindow?) {
            let capturedToken = instanceToken
            let capturedTarget = target
            let capturedGeometry = geometry
            let windowIdentifier = window.map { ObjectIdentifier($0) }
            Task { @MainActor in
                guard let capturedTarget, let capturedGeometry,
                      capturedToken == self.instanceToken, capturedTarget == self.target else { return }
                capturedGeometry.update(
                    target: capturedTarget,
                    frame: frame,
                    windowObjectIdentifier: windowIdentifier,
                    instanceToken: capturedToken
                )
            }
        }

        func removeCurrentMeasurement() {
            guard let target else { return }
            geometry?.remove(target: target, instanceToken: instanceToken)
        }

        func dismantle() {
            removeCurrentMeasurement()
            instanceToken = UUID()
            target = nil
            geometry = nil
        }
    }
}

@MainActor
final class MovieNightTourMeasurementView: UIView {
    var onMeasurement: ((CGRect?, UIWindow?) -> Void)?

    override var intrinsicContentSize: CGSize { .zero }
    override var isUserInteractionEnabled: Bool {
        get { false }
        set { super.isUserInteractionEnabled = false }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reportMeasurement()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportMeasurement()
    }

    private func reportMeasurement() {
        let window = self.window
        let frame = window.map { convert(bounds, to: $0) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onMeasurement?(frame, window)
        }
    }
}
