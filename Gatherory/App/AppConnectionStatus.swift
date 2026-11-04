import Foundation
import Network
import Observation

@Observable
@MainActor
final class AppConnectionStatus {
    enum Status: Equatable, Sendable {
        case checking
        case online
        case offline
    }

    private(set) var status: Status
    @ObservationIgnored private var monitor: NWPathMonitor?

    init(fixtureStatus: Status? = nil) {
        status = fixtureStatus ?? .checking
        guard fixtureStatus == nil else { return }

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let status: Status = path.status == .satisfied ? .online : .offline
            guard let connectionStatus = self else { return }
            Task { @MainActor in connectionStatus.status = status }
        }
        monitor.start(queue: DispatchQueue(label: "com.gatherory.connection-status"))
    }

    deinit {
        monitor?.cancel()
    }

    static func bootstrap() -> AppConnectionStatus {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard AppRuntimeConfiguration.usesEphemeralDataStore,
              AppRuntimeConfiguration.skipsAuthentication else {
            return AppConnectionStatus()
        }
        if arguments.contains("-ConnectionOfflineUITest") {
            return AppConnectionStatus(fixtureStatus: .offline)
        }
        if arguments.contains("-ConnectionOnlineUITest") {
            return AppConnectionStatus(fixtureStatus: .online)
        }
#endif
        return AppConnectionStatus()
    }
}
