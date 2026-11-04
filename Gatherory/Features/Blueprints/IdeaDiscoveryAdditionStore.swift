import Foundation
import Observation

/// Device-local confirmation that a published Explore idea was added to an
/// account's event. This intentionally stores identities only, never content.
struct IdeaDiscoveryAdditionReceipt: Codable, Equatable, Hashable {
    let accountID: String
    let sourceID: String
    let workspaceID: UUID
    let eventID: UUID
    let ideaID: UUID
}

@MainActor @Observable
final class IdeaDiscoveryAdditionStore {
    private(set) var ownerID: String
    private(set) var receipts: [IdeaDiscoveryAdditionReceipt]
    private(set) var callbackGeneration = UUID()
    @ObservationIgnored private let defaults: UserDefaults

    init(ownerID: String, defaults: UserDefaults = .standard) {
        self.ownerID = ownerID
        self.defaults = defaults
        self.receipts = Self.read(accountID: ownerID, defaults: defaults)
    }

    func switchAccount(to accountID: String) {
        guard ownerID != accountID else { return }
        callbackGeneration = UUID()
        ownerID = accountID
        receipts = Self.read(accountID: accountID, defaults: defaults)
    }

    func invalidateCallbacks() {
        callbackGeneration = UUID()
    }

    func record(_ receipt: IdeaDiscoveryAdditionReceipt) {
        guard receipt.accountID == ownerID, !ownerID.isEmpty else { return }
        if !receipts.contains(receipt) { receipts.append(receipt) }
        persist()
    }

    /// Receipts remain through temporary workspace loading gaps, but show only
    /// while the referenced idea still exists in its original event.
    func isAdded(_ entry: IdeaDiscoveryEntry, in library: WorkspaceLibrary) -> Bool {
        receipts.contains { receipt in
            guard receipt.accountID == ownerID, receipt.sourceID == entry.id,
                  let workspace = library.workspaces.first(where: { $0.mainEventID == receipt.workspaceID }) else {
                return false
            }
            let eventReference: EventReference = receipt.eventID == workspace.mainEventID
                ? .main : .subevent(receipt.eventID)
            guard !workspace.isInvitationProjection,
                  let viewer = workspace.currentViewerMember(for: eventReference),
                  viewer.userID == ownerID,
                  viewer.invitationStatus == .active,
                  viewer.participantRole != .guest else { return false }
            return !workspace.isMainEventDeleted && workspace.ideas.contains {
                $0.id == receipt.ideaID && $0.eventID == receipt.eventID
            }
        }
    }

    func clearAccountReceipts() {
        receipts = []
        Self.clear(accountID: ownerID, defaults: defaults)
    }

    static func clear(accountID: String, defaults: UserDefaults = .standard) {
        guard !accountID.isEmpty else { return }
        defaults.removeObject(forKey: key(accountID: accountID))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(receipts) else { return }
        defaults.set(data, forKey: Self.key(accountID: ownerID))
    }

    private static func read(accountID: String, defaults: UserDefaults) -> [IdeaDiscoveryAdditionReceipt] {
        guard !accountID.isEmpty,
              let data = defaults.data(forKey: key(accountID: accountID)),
              let decoded = try? JSONDecoder().decode([IdeaDiscoveryAdditionReceipt].self, from: data) else { return [] }
        return decoded.filter { $0.accountID == accountID }
    }

    private static func key(accountID: String) -> String {
        "ideaDiscovery.additions.v1.\(accountID)"
    }
}
