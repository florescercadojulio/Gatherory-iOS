import Foundation

@MainActor
struct BlueprintSetupRecovery {
    let drafts: [BlueprintSetupDraft]
    let hasPendingInstallation: Bool
    let loadFailed: Bool

    /// These stores fail independently. A corrupt draft must not hide a
    /// committed installation waiting to finish its canonical import.
    static func load(
        ownerID: String,
        readDrafts: (String) throws -> [BlueprintSetupDraft],
        readPending: (String) throws -> Bool
    ) -> Self {
        guard !ownerID.isEmpty else {
            return Self(drafts: [], hasPendingInstallation: false, loadFailed: false)
        }
        var drafts: [BlueprintSetupDraft] = []
        var hasPendingInstallation = false
        var loadFailed = false
        do { drafts = try readDrafts(ownerID) } catch { loadFailed = true }
        do { hasPendingInstallation = try readPending(ownerID) } catch { loadFailed = true }
        return Self(drafts: drafts, hasPendingInstallation: hasPendingInstallation, loadFailed: loadFailed)
    }
}
