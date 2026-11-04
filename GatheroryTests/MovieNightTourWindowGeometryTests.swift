import Foundation
import CoreGraphics
import Testing
import UIKit
@testable import Gatherory

@MainActor
struct MovieNightTourWindowGeometryTests {
    @Test("Measurements from native toolbar and host controls project into host-local coordinates")
    func sameWindowMeasurementsProjectToHostCoordinates() async {
        let geometry = MovieNightTourWindowGeometry()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let host = MovieNightTourTarget.decision(UUID())
        let toolbarFilter = MovieNightTourTarget.ideasFilter
        let hostFrame = CGRect(x: 24, y: 180, width: 350, height: 500)
        let filterFrame = CGRect(x: 295, y: 198, width: 52, height: 40)
        let hostCoordinator = MovieNightTourWindowTarget.Coordinator()
        let filterCoordinator = MovieNightTourWindowTarget.Coordinator()

        hostCoordinator.configure(target: host, geometry: geometry)
        filterCoordinator.configure(target: toolbarFilter, geometry: geometry)
        hostCoordinator.scheduleMeasurement(frame: hostFrame, window: window)
        filterCoordinator.scheduleMeasurement(frame: filterFrame, window: window)
        await drainMainActorTasks()

        #expect(geometry.frame(for: toolbarFilter, relativeTo: host) == CGRect(x: 271, y: 18, width: 52, height: 40))
        #expect(geometry.windowFrame(for: toolbarFilter) == filterFrame)
    }

    @Test("Measurements from different windows cannot be combined")
    func differentWindowsDoNotProject() async {
        let geometry = MovieNightTourWindowGeometry()
        let hostWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let toolbarWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let host = MovieNightTourTarget.decision(UUID())
        let toolbarFilter = MovieNightTourTarget.ideasFilter
        let hostCoordinator = MovieNightTourWindowTarget.Coordinator()
        let filterCoordinator = MovieNightTourWindowTarget.Coordinator()

        hostCoordinator.configure(target: host, geometry: geometry)
        filterCoordinator.configure(target: toolbarFilter, geometry: geometry)
        hostCoordinator.scheduleMeasurement(frame: CGRect(x: 20, y: 100, width: 350, height: 500), window: hostWindow)
        filterCoordinator.scheduleMeasurement(frame: CGRect(x: 300, y: 110, width: 50, height: 40), window: toolbarWindow)
        await drainMainActorTasks()

        #expect(geometry.frame(for: toolbarFilter, relativeTo: host) == nil)
    }

    @Test("Queued callbacks cannot restore a dismantled or reconfigured target")
    func queuedCallbacksRespectDismantleAndReconfiguration() async {
        let geometry = MovieNightTourWindowGeometry()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let firstTarget = MovieNightTourTarget.ideasFilter
        let secondTarget = MovieNightTourTarget.decision(UUID())
        let coordinator = MovieNightTourWindowTarget.Coordinator()

        coordinator.configure(target: firstTarget, geometry: geometry)
        coordinator.scheduleMeasurement(frame: CGRect(x: 20, y: 30, width: 40, height: 40), window: window)
        coordinator.dismantle()
        await drainMainActorTasks()
        #expect(geometry.frame(for: firstTarget, relativeTo: firstTarget) == nil)

        coordinator.configure(target: firstTarget, geometry: geometry)
        coordinator.scheduleMeasurement(frame: CGRect(x: 40, y: 50, width: 40, height: 40), window: window)
        coordinator.configure(target: secondTarget, geometry: geometry)
        await drainMainActorTasks()
        #expect(geometry.frame(for: firstTarget, relativeTo: firstTarget) == nil)

        coordinator.scheduleMeasurement(frame: CGRect(x: 60, y: 70, width: 90, height: 90), window: window)
        await drainMainActorTasks()
        #expect(geometry.frame(for: secondTarget, relativeTo: secondTarget) == CGRect(x: 0, y: 0, width: 90, height: 90))
    }

    @Test("Dismantling an older coordinator preserves the newer same-target measurement")
    func oldCoordinatorTeardownDoesNotEraseNewMeasurement() async {
        let geometry = MovieNightTourWindowGeometry()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let target = MovieNightTourTarget.ideasFilter
        let oldCoordinator = MovieNightTourWindowTarget.Coordinator()
        let newCoordinator = MovieNightTourWindowTarget.Coordinator()

        oldCoordinator.configure(target: target, geometry: geometry)
        oldCoordinator.scheduleMeasurement(frame: CGRect(x: 10, y: 20, width: 30, height: 40), window: window)
        await drainMainActorTasks()

        newCoordinator.configure(target: target, geometry: geometry)
        newCoordinator.scheduleMeasurement(frame: CGRect(x: 100, y: 200, width: 50, height: 60), window: window)
        await drainMainActorTasks()
        oldCoordinator.dismantle()

        #expect(geometry.frame(for: target, relativeTo: target) == CGRect(x: 0, y: 0, width: 50, height: 60))
    }

    private func drainMainActorTasks() async {
        for _ in 0..<5 { await Task.yield() }
    }
}
