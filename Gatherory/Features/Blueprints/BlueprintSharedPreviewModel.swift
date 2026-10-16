import Foundation
import Observation

/// Incoming-link resolution is read-only. A cached setup is a viewing fallback
/// for network loss, never an alternate grant after a server rejection.
@MainActor @Observable
final class BlueprintSharedPreviewModel {
    private(set) var entry: BlueprintCatalogEntry?
    private(set) var isLoading = true
    private(set) var usesSavedPreview = false
    private(set) var hasPendingInstallation = false
    private(set) var errorMessage: String?
    private var generation = UUID()

    func load(
        ownerID: String?,
        token: String,
        pendingInstallation: () throws -> Bool,
        savedDraft: () throws -> BlueprintSetupDraft?,
        fetch: () async throws -> BlueprintCatalogEntry
    ) async {
        let attempt = UUID()
        generation = attempt
        entry = nil
        isLoading = true
        usesSavedPreview = false
        hasPendingInstallation = false
        errorMessage = nil
        defer { if generation == attempt { isLoading = false } }

        guard let ownerID, !ownerID.isEmpty, BlueprintSharedTemplateLink.isValidToken(token) else {
            errorMessage = BlueprintCopy.sharedLinkUnavailable
            return
        }
        do {
            hasPendingInstallation = try pendingInstallation()
            let resolved = try await fetch()
            guard generation == attempt, !Task.isCancelled else { return }
            guard BlueprintPreviewContent(entry: resolved) != nil else {
                throw CloudSyncFailure.invalidResponse
            }
            entry = resolved
        } catch {
            guard generation == attempt, !Task.isCancelled else { return }
            if Self.isNetworkLoss(error),
               let saved = try? savedDraft(),
               saved.ownerUserID == ownerID, saved.shareToken == token,
               BlueprintPreviewContent(entry: saved.entry) != nil {
                entry = saved.entry
                usesSavedPreview = true
                return
            }
            if case CloudSyncFailure.invalidSession = error {
                errorMessage = BlueprintCopy.signInRequired
            } else if case CloudSyncFailure.forbidden = error {
                errorMessage = BlueprintCopy.sharedLinkUnavailable
            } else if case CloudSyncFailure.server(let code) = error,
                      ["BLUEPRINT_NOT_FOUND", "BLUEPRINT_LINK_UNAVAILABLE", "HTTP_404"].contains(code) {
                errorMessage = BlueprintCopy.sharedLinkUnavailable
            } else {
                errorMessage = BlueprintCopy.loadFailed
            }
        }
    }

    private static func isNetworkLoss(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                .internationalRoamingOff, .dataNotAllowed].contains(error.code)
    }
}

enum BlueprintSetupExitPolicy {
    static func dismissesSharedLink(hasSharedToken: Bool, returnsToPreview: Bool, didComplete: Bool) -> Bool {
        hasSharedToken && (didComplete || !returnsToPreview)
    }
}
