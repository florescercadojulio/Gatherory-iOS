import Foundation

/// Education appears once per account, when its tab first becomes active.
/// During a tour the native primer takes priority, then the guide resumes.
enum ContextualPrimerPolicy {
    static func shouldPresent(
        hasSeenPrimer: Bool,
        isTabActive: Bool,
        accountState: AccountOnboardingState
    ) -> Bool {
        !hasSeenPrimer && isTabActive && accountState == .complete
    }
}

extension Notification.Name {
    static let contextualPrimerTourDidFinish = Notification.Name("contextualPrimerTourDidFinish")
}

struct ContextualPrimerStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func hasSeen(_ primer: Primer, accountID: String) -> Bool {
        guard !accountID.isEmpty else { return false }
        if defaults.bool(forKey: key(primer, accountID: accountID)) { return true }
        // Preserve explicit UI-test launch overrides without importing the old
        // app-wide value into every account's dismissal state.
        return primer == .decide
            && ProcessInfo.processInfo.arguments.contains("-hasSeenDecideTimelinePrimer")
            && defaults.bool(forKey: "hasSeenDecideTimelinePrimer")
    }

    func markSeen(_ primer: Primer, accountID: String) {
        guard !accountID.isEmpty else { return }
        defaults.set(true, forKey: key(primer, accountID: accountID))
    }

    /// Clears only this account's contextual primer dismissals for an explicit
    /// tour replay or account deletion.
    func reset(accountID: String) {
        guard !accountID.isEmpty else { return }
        for primer in Primer.allCases {
            defaults.removeObject(forKey: key(primer, accountID: accountID))
        }
    }

    static func announceTourFinished(accountID: String, center: NotificationCenter = .default) {
        guard !accountID.isEmpty else { return }
        center.post(name: .contextualPrimerTourDidFinish, object: nil, userInfo: ["accountID": accountID])
    }

    enum Primer: String, CaseIterable { case decide, search }

    private func key(_ primer: Primer, accountID: String) -> String {
        "contextualPrimer.\(primer.rawValue).\(accountID)"
    }
}
