import Foundation

enum MovieNightTourDiscoveryPhase: String, Sendable {
    case chooseExplore
    case chooseMovieNight
}

/// Account-bound entry education, before any owned lesson workspace exists.
struct MovieNightTourDiscoveryStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func phase(accountID: String) -> MovieNightTourDiscoveryPhase? {
        guard !accountID.isEmpty, let value = defaults.string(forKey: key(accountID)) else { return nil }
        return MovieNightTourDiscoveryPhase(rawValue: value)
    }

    func begin(accountID: String) { set(.chooseExplore, accountID: accountID) }

    func openExplore(accountID: String) {
        guard phase(accountID: accountID) != nil else { return }
        set(.chooseMovieNight, accountID: accountID)
    }

    func previous(accountID: String) {
        guard phase(accountID: accountID) == .chooseMovieNight else { return }
        set(.chooseExplore, accountID: accountID)
    }

    func clear(accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.removeObject(forKey: key(accountID))
        announce(accountID)
    }

    private func set(_ phase: MovieNightTourDiscoveryPhase, accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.set(phase.rawValue, forKey: key(accountID))
        announce(accountID)
    }

    private func key(_ accountID: String) -> String { "movieNightTourDiscovery.\(accountID)" }
    private func announce(_ accountID: String) {
        NotificationCenter.default.post(name: .movieNightTourDiscoveryDidChange,
                                        object: nil, userInfo: ["accountID": accountID])
    }
}

extension Notification.Name {
    static let movieNightTourDiscoveryDidChange = Notification.Name("movieNightTourDiscoveryDidChange")
}

@MainActor
enum MovieNightTourDiscoveryCoordinator {
    enum EntryError: Error { case movieNightSelectionRequired }

    static func selectMovieNight(
        account: UserAccount,
        library: WorkspaceLibrary,
        persistence: WorkspacePersistenceController,
        discoveryStore: MovieNightTourDiscoveryStore? = nil,
        tourStore: MovieNightTourStore? = nil,
        localJSON: Data? = nil
    ) throws -> PlanningWorkspace {
        let discoveryStore = discoveryStore ?? MovieNightTourDiscoveryStore()
        guard discoveryStore.phase(accountID: account.id) == .chooseMovieNight else {
            throw EntryError.movieNightSelectionRequired
        }
        let workspace = try MovieNightTourCoordinator.startOrResume(
            account: account, library: library, persistence: persistence,
            store: tourStore, localJSON: localJSON
        )
        // A failed local save leaves the card/entry phase available for retry.
        discoveryStore.clear(accountID: account.id)
        return workspace
    }
}
