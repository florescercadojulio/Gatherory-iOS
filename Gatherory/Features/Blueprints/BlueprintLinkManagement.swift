import Foundation
import Observation

struct BlueprintManagedTemplate: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let publishedRevision: Int?
    let retired: Bool
    var listedRevision: Int?
    var creatorName: String? = nil
    var activeShareLinkCount: Int? = nil

    init(id: UUID, title: String, publishedRevision: Int?, retired: Bool, listedRevision: Int? = nil,
         creatorName: String? = nil, activeShareLinkCount: Int? = nil) {
        self.id = id
        self.title = title
        self.publishedRevision = publishedRevision
        self.retired = retired
        self.listedRevision = listedRevision
        self.creatorName = creatorName
        self.activeShareLinkCount = activeShareLinkCount
    }
}

struct BlueprintManagedShareLink: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: Int
    let createdAt: Date
    var revokedAt: Date?
}

struct BlueprintCreatedShareLink: Decodable, Equatable, Sendable {
    let link: BlueprintManagedShareLink
    let token: String
}

@MainActor
protocol BlueprintLinkManagementTransport {
    func templates(eventID: UUID) async throws -> [BlueprintManagedTemplate]
    func links(eventID: UUID, templateID: UUID) async throws -> [BlueprintManagedShareLink]
    func createLink(eventID: UUID, templateID: UUID, revision: Int) async throws -> BlueprintCreatedShareLink
    func revokeLink(eventID: UUID, templateID: UUID, linkID: UUID) async throws
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int?
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?, creatorName: String?) async throws -> BlueprintTemplateListingResult
    func shareURL(token: String) -> URL?
}

extension BlueprintLinkManagementTransport {
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?, creatorName: String?) async throws -> BlueprintTemplateListingResult {
        let listedRevision = try await setTemplateListing(eventID: eventID, templateID: templateID, revision: revision)
        return BlueprintTemplateListingResult(listedRevision: listedRevision)
    }
}

enum BlueprintLinkManagementAction: Encodable {
    case templates(eventID: UUID)
    case list(eventID: UUID, templateID: UUID)
    case create(eventID: UUID, templateID: UUID, revision: Int)
    case revoke(eventID: UUID, templateID: UUID, linkID: UUID)
    case listing(eventID: UUID, templateID: UUID, revision: Int?, creatorName: String? = nil)

    private enum CodingKeys: String, CodingKey {
        case action, eventId, templateId, revision, linkId, creatorName
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .templates(let eventID):
            try container.encode("templates", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
        case .list(let eventID, let templateID):
            try container.encode("list", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
            try container.encode(templateID.uuidString, forKey: .templateId)
        case .create(let eventID, let templateID, let revision):
            try container.encode("create", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
            try container.encode(templateID.uuidString, forKey: .templateId)
            try container.encode(revision, forKey: .revision)
        case .revoke(let eventID, let templateID, let linkID):
            try container.encode("revoke", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
            try container.encode(templateID.uuidString, forKey: .templateId)
            try container.encode(linkID.uuidString, forKey: .linkId)
        case .listing(let eventID, let templateID, let revision, let creatorName):
            try container.encode("listing", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
            try container.encode(templateID.uuidString, forKey: .templateId)
            try container.encode(revision, forKey: .revision)
            try container.encodeIfPresent(creatorName, forKey: .creatorName)
        }
    }
}

struct BlueprintManagedTemplatesResponse: Decodable {
    let templates: [BlueprintManagedTemplate]
}

struct BlueprintTemplateListingResult: Decodable, Equatable, Sendable {
    let listedRevision: Int?
    let creatorName: String?

    enum CodingKeys: String, CodingKey { case listedRevision, creatorName }

    init(listedRevision: Int?, creatorName: String? = nil) {
        self.listedRevision = listedRevision
        self.creatorName = creatorName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit null confirms unlisting; an absent field is an invalid acknowledgement.
        listedRevision = try container.decode(Int?.self, forKey: .listedRevision)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
    }
}

struct BlueprintManagedLinksResponse: Decodable {
    let links: [BlueprintManagedShareLink]
}

enum BlueprintLinkManagementMessage {
    static let requestFailed = String(localized: "blueprint.sharing.requestFailed", defaultValue: "Couldn't update blueprint links. Check your connection and try again.")
    static let invalidToken = String(localized: "blueprint.sharing.invalidToken", defaultValue: "The server returned an invalid sharing link. Refresh links before trying again.")
    static let unsafeAddress = String(localized: "blueprint.sharing.unsafeAddress", defaultValue: "The sharing link was created, but this server address cannot make a safe link. Refresh links before creating another.")
    static let listingFailed = String(localized: "blueprint.sharing.listingFailed", defaultValue: "Couldn’t update Search visibility. Check your connection and try again.")
}

@MainActor @Observable
final class BlueprintLinkManagementStore {
    private(set) var templates: [BlueprintManagedTemplate] = []
    private(set) var links: [BlueprintManagedShareLink] = []
    private(set) var selectedTemplateID: UUID?
    private(set) var createdURL: URL?
    private(set) var createdToken: String?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var hasLoadedLinks = false
    private(set) var credentialSaveFailed = false
    private(set) var errorMessage: String?

    let eventID: UUID
    let accountID: String

    @ObservationIgnored private let transport: any BlueprintLinkManagementTransport
    @ObservationIgnored private let credentialStore: (any BlueprintShareLinkCredentialStore)?
    @ObservationIgnored private let currentAccountID: @MainActor () -> String?
    @ObservationIgnored private var contextRevision = UUID()
    @ObservationIgnored private var loadRevision: UUID?
    @ObservationIgnored private var mutationRevision: UUID?
    @ObservationIgnored private var createdLinkID: UUID?
    @ObservationIgnored private var pendingCredentialSave: CredentialSaveCandidate?
    private var createRefreshRequiredTemplateID: UUID?
    @ObservationIgnored private var isInvalidated = false

    var createRequiresRefresh: Bool {
        guard let selectedTemplateID else { return false }
        return selectedTemplateID == createRefreshRequiredTemplateID
    }

    var canCreate: Bool {
        // A local credential-read failure still permits an explicit replacement
        // after authenticated metadata/list reads; it never authorizes restore.
        guard !isInvalidated, hasLoadedLinks, !createRequiresRefresh, !isLoading, !isMutating,
              (errorMessage == nil || errorMessage == BlueprintCopy.shareLinkRestoreFailed), isAccountCurrent,
              let selectedTemplateID,
              let template = templates.first(where: { $0.id == selectedTemplateID }) else { return false }
        return template.publishedRevision != nil && !template.retired
    }

    init(
        eventID: UUID,
        accountID: String,
        transport: any BlueprintLinkManagementTransport,
        credentialStore: (any BlueprintShareLinkCredentialStore)? = nil,
        currentAccountID: @escaping @MainActor () -> String?
    ) {
        self.eventID = eventID
        self.accountID = accountID
        self.transport = transport
        self.credentialStore = credentialStore
        self.currentAccountID = currentAccountID
    }

    func loadTemplates() async {
        guard !isInvalidated, canStartLoad() else { return }
        let revision = beginLoad()
        defer { finishLoad(revision) }
        do {
            let result = try await transport.templates(eventID: eventID)
            guard isCurrent(revision: revision) else { return }
            let previousSelection = selectedTemplateID.flatMap { selectedID in
                templates.first { $0.id == selectedID }
            }
            templates = result
            errorMessage = credentialSaveFailed ? BlueprintCopy.shareLinkSaveFailed : nil
            if let selectedTemplateID, !result.contains(where: { $0.id == selectedTemplateID }) {
                let cacheRemoved = removeSavedCredential(forTemplateID: selectedTemplateID)
                self.selectedTemplateID = nil
                links = []
                hasLoadedLinks = false
                clearCreatedLink()
                errorMessage = cacheRemoved ? nil : BlueprintCopy.shareLinkRestoreFailed
            } else if let selectedTemplateID,
                      let previousSelection,
                      let refreshedSelection = result.first(where: { $0.id == selectedTemplateID }),
                      (previousSelection.publishedRevision != refreshedSelection.publishedRevision ||
                       previousSelection.retired != refreshedSelection.retired) {
                if !(credentialSaveFailed && !refreshedSelection.retired) {
                    clearCreatedLink()
                }
                hasLoadedLinks = false
                if refreshedSelection.retired {
                    errorMessage = removeSavedCredential(forTemplateID: selectedTemplateID)
                        ? nil : BlueprintCopy.shareLinkRestoreFailed
                }
            }
        } catch {
            guard isCurrent(revision: revision) else { return }
            handleFailure(error, message: BlueprintLinkManagementMessage.requestFailed)
        }
    }

    func select(templateID: UUID?) async {
        guard !isInvalidated, !isMutating, !isLoading else { return }
        guard isAccountCurrent else { invalidate(); return }
        guard templateID == nil || templates.contains(where: { $0.id == templateID }) else { return }
        selectedTemplateID = templateID
        links = []
        clearCreatedLink()
        hasLoadedLinks = false
        errorMessage = nil
        if let templateID, templates.first(where: { $0.id == templateID })?.retired == true,
           !removeSavedCredential(forTemplateID: templateID) {
            errorMessage = BlueprintCopy.shareLinkRestoreFailed
        }
        guard templateID != nil else { return }
        await loadLinks()
    }

    func loadLinks() async {
        guard let templateID = selectedTemplateID, canStartLoad() else { return }
        let selectedID = templateID
        let revision = beginLoad()
        defer { finishLoad(revision) }
        do {
            let result = try await transport.links(eventID: eventID, templateID: selectedID)
            guard isCurrent(revision: revision), selectedTemplateID == selectedID else { return }
            links = result
            var cacheRemovalFailed = false
            if let createdLinkID {
                if let createdLink = result.first(where: { $0.id == createdLinkID }),
                   createdLink.revokedAt == nil,
                   createdLink.revision == (pendingCredentialSave?.credential.revision ?? createdLink.revision) {
                    // Keep the one-time URL only while the server still lists it as active.
                } else {
                    cacheRemovalFailed = !removeSavedCredential(forTemplateID: selectedID, linkID: createdLinkID)
                    clearCreatedLink()
                }
            }
            hasLoadedLinks = true
            if createRefreshRequiredTemplateID == selectedID {
                createRefreshRequiredTemplateID = nil
            }
            if createdURL == nil && !cacheRemovalFailed {
                if !credentialSaveFailed { errorMessage = nil }
                restoreSavedCredential(from: result, templateID: selectedID)
            } else if cacheRemovalFailed {
                errorMessage = BlueprintCopy.shareLinkRestoreFailed
            } else if !credentialSaveFailed {
                errorMessage = nil
            }
        } catch {
            guard isCurrent(revision: revision), selectedTemplateID == selectedID else { return }
            handleFailure(error, message: BlueprintLinkManagementMessage.requestFailed)
        }
    }

    func create() async {
        guard canCreate,
              let templateID = selectedTemplateID,
              let template = templates.first(where: { $0.id == templateID }),
              !template.retired,
              let revisionNumber = template.publishedRevision else { return }
        let revision = beginMutation()
        defer { finishMutation(revision) }
        do {
            let created = try await transport.createLink(
                eventID: eventID,
                templateID: templateID,
                revision: revisionNumber
            )
            guard isCurrent(revision: revision), selectedTemplateID == templateID else { return }
            guard Self.isValidToken(created.token), created.link.revokedAt == nil,
                  created.link.revision == revisionNumber else {
                requireCreateRefresh(for: templateID)
                errorMessage = BlueprintLinkManagementMessage.invalidToken
                return
            }
            guard let url = transport.shareURL(token: created.token) else {
                requireCreateRefresh(for: templateID)
                errorMessage = BlueprintLinkManagementMessage.unsafeAddress
                return
            }
            let scope = Self.credentialScope(
                accountID: accountID, eventID: eventID, templateID: templateID, shareURL: url
            )
            let credential = BlueprintShareLinkCredential(
                linkID: created.link.id, revision: created.link.revision, token: created.token
            )
            pendingCredentialSave = CredentialSaveCandidate(credential: credential, scope: scope, url: url)
            var saveFailed = credentialStore != nil && scope == nil
            if let credentialStore {
                if let scope {
                    do {
                        try credentialStore.save(credential, for: scope)
                    } catch {
                        saveFailed = true
                    }
                }
            }
            credentialSaveFailed = saveFailed
            createdLinkID = created.link.id
            createdToken = created.token
            createdURL = url
            if let templateIndex = templates.firstIndex(where: { $0.id == templateID }),
               templates[templateIndex].publishedRevision == created.link.revision {
                let linkWasAlreadyActive = links.contains {
                    $0.id == created.link.id && $0.revokedAt == nil && $0.revision == created.link.revision
                }
                if !linkWasAlreadyActive,
                   let activeCount = templates[templateIndex].activeShareLinkCount {
                    // Keep legacy/invalidated counts unknown until templates refresh.
                    templates[templateIndex].activeShareLinkCount = activeCount + 1
                }
            }
            if let existingIndex = links.firstIndex(where: { $0.id == created.link.id }) {
                links[existingIndex] = created.link
            } else {
                links.insert(created.link, at: 0)
            }
            errorMessage = saveFailed ? BlueprintCopy.shareLinkSaveFailed : nil
        } catch {
            guard isCurrent(revision: revision) else { return }
            // The server may have created the link before the response failed.
            // Require a successful explicit list refresh before permitting retry.
            requireCreateRefresh(for: templateID)
            handleFailure(error, message: BlueprintLinkManagementMessage.requestFailed)
        }
    }

    func revoke(linkID: UUID) async {
        guard !isInvalidated, !isMutating, !isLoading, isAccountCurrent,
              let templateID = selectedTemplateID,
              let index = links.firstIndex(where: { $0.id == linkID }),
              links[index].revokedAt == nil else { return }
        let revokedLink = links[index]
        let currentPublishedRevision = templates.first(where: { $0.id == templateID })?.publishedRevision
        let revision = beginMutation()
        defer { finishMutation(revision) }
        do {
            try await transport.revokeLink(eventID: eventID, templateID: templateID, linkID: linkID)
            guard isCurrent(revision: revision), selectedTemplateID == templateID,
                  let currentIndex = links.firstIndex(where: { $0.id == linkID }) else { return }
            // Reflect revocation only after the server confirms it.
            let cacheRemoved = removeSavedCredential(forTemplateID: templateID, linkID: linkID)
            links[currentIndex].revokedAt = Date()
            if let templateIndex = templates.firstIndex(where: { $0.id == templateID }) {
                if revokedLink.revision == currentPublishedRevision,
                   let activeCount = templates[templateIndex].activeShareLinkCount {
                    templates[templateIndex].activeShareLinkCount = max(0, activeCount - 1)
                } else {
                    // A links response can include rows from retired revisions. Without
                    // a fresh template snapshot, do not infer the current active count.
                    templates[templateIndex].activeShareLinkCount = nil
                }
            }
            if createdLinkID == linkID { clearCreatedLink() }
            errorMessage = cacheRemoved
                ? (credentialSaveFailed ? BlueprintCopy.shareLinkSaveFailed : nil)
                : BlueprintCopy.shareLinkRestoreFailed
        } catch {
            guard isCurrent(revision: revision) else { return }
            handleFailure(error, message: BlueprintLinkManagementMessage.requestFailed)
        }
    }

    func setDiscoverable(_ enabled: Bool, creatorName: String? = nil) async {
        guard !isInvalidated, !isMutating, !isLoading, isAccountCurrent,
              let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }),
              !templates[index].retired,
              let publishedRevision = templates[index].publishedRevision else { return }
        let requestedRevision = enabled ? publishedRevision : nil
        guard templates[index].listedRevision != requestedRevision else { return }
        let existingCreatorName = templates[index].creatorName
        let requestedCreatorName: String?
        if enabled {
            if let normalized = existingCreatorName.flatMap(BlueprintCreatorNameValidation.normalized) {
                requestedCreatorName = normalized
            } else if let normalized = creatorName.flatMap(BlueprintCreatorNameValidation.normalized) {
                requestedCreatorName = normalized
            } else {
                errorMessage = BlueprintCopy.creatorNameInvalid
                return
            }
        } else {
            requestedCreatorName = nil
        }

        let requestContext = beginMutation()
        defer { finishMutation(requestContext) }
        do {
            let acknowledgement = try await transport.setTemplateListing(
                eventID: eventID, templateID: templateID, revision: requestedRevision,
                creatorName: requestedCreatorName
            )
            guard isCurrent(revision: requestContext), selectedTemplateID == templateID,
                  let currentIndex = templates.firstIndex(where: { $0.id == templateID }) else { return }
            guard acknowledgement.listedRevision == requestedRevision,
                  !enabled || acknowledgement.creatorName.flatMap(BlueprintCreatorNameValidation.normalized) == requestedCreatorName else {
                errorMessage = BlueprintLinkManagementMessage.listingFailed
                return
            }
            templates[currentIndex].listedRevision = acknowledgement.listedRevision
            if enabled { templates[currentIndex].creatorName = requestedCreatorName }
            errorMessage = credentialSaveFailed ? BlueprintCopy.shareLinkSaveFailed : nil
        } catch {
            guard isCurrent(revision: requestContext) else { return }
            handleFailure(error, message: BlueprintLinkManagementMessage.listingFailed)
        }
    }

    func invalidate() {
        isInvalidated = true
        contextRevision = UUID()
        loadRevision = nil
        mutationRevision = nil
        templates = []
        links = []
        selectedTemplateID = nil
        clearCreatedLink()
        hasLoadedLinks = false
        createRefreshRequiredTemplateID = nil
        isLoading = false
        isMutating = false
        errorMessage = nil
    }

    func retrySavingLink() {
        guard !isInvalidated, !isLoading, !isMutating, isAccountCurrent, let credentialStore,
              let candidate = pendingCredentialSave, createdURL == candidate.url,
              createdLinkID == candidate.credential.linkID,
              let selectedTemplateID else { return }
        guard let scope = candidate.scope ?? Self.credentialScope(
            accountID: accountID, eventID: eventID,
            templateID: selectedTemplateID, shareURL: candidate.url
        ) else {
            credentialSaveFailed = true
            errorMessage = BlueprintCopy.shareLinkSaveFailed
            return
        }
        do {
            try credentialStore.save(candidate.credential, for: scope)
            credentialSaveFailed = false
            errorMessage = nil
        } catch {
            credentialSaveFailed = true
            errorMessage = BlueprintCopy.shareLinkSaveFailed
        }
    }

    private func handleFailure(_ error: Error, message: String) {
        // A definitive denial must remove the transient bearer URL and any QR
        // derived from it. Connectivity failures retain the existing retry state.
        if let failure = error as? CloudSyncFailure {
            switch failure {
            case .invalidSession:
                invalidate()
                errorMessage = BlueprintCopy.templateLinkSignIn
                return
            case .forbidden, .server("BLUEPRINT_NOT_FOUND"), .server("HTTP_404"):
                let cacheRemoved = selectedTemplateID.map { removeSavedCredential(forTemplateID: $0) } ?? true
                invalidate()
                errorMessage = cacheRemoved ? BlueprintCopy.lostTemplatePermission : BlueprintCopy.shareLinkRestoreFailed
                return
            default:
                break
            }
        }
        errorMessage = message
    }

    private var isAccountCurrent: Bool {
        currentAccountID() == accountID
    }

    private func canStartLoad() -> Bool {
        guard !isInvalidated else { return false }
        guard isAccountCurrent else { invalidate(); return false }
        return !isLoading && !isMutating
    }

    private func beginLoad() -> UUID {
        let revision = UUID()
        contextRevision = revision
        loadRevision = revision
        isLoading = true
        return revision
    }

    private func finishLoad(_ revision: UUID) {
        guard loadRevision == revision else { return }
        loadRevision = nil
        isLoading = false
    }

    private func beginMutation() -> UUID {
        let revision = UUID()
        contextRevision = revision
        mutationRevision = revision
        isMutating = true
        return revision
    }

    private func finishMutation(_ revision: UUID) {
        guard mutationRevision == revision else { return }
        mutationRevision = nil
        isMutating = false
    }

    private func isCurrent(revision: UUID) -> Bool {
        guard !isInvalidated, contextRevision == revision, !Task.isCancelled else { return false }
        guard isAccountCurrent else {
            invalidate()
            return false
        }
        return true
    }

    private func clearCreatedLink() {
        createdLinkID = nil
        createdToken = nil
        createdURL = nil
        pendingCredentialSave = nil
        credentialSaveFailed = false
    }

    private func restoreSavedCredential(from links: [BlueprintManagedShareLink], templateID: UUID) {
        guard let credentialStore else { return }
        // Legacy localhost/non-HTTPS sharing can still produce a live URL,
        // but has no eligible secure credential to restore on this device.
        guard let scope = credentialScope(templateID: templateID) else { return }
        guard templates.first(where: { $0.id == templateID })?.retired == false else {
            if !removeSavedCredential(forTemplateID: templateID) {
                errorMessage = BlueprintCopy.shareLinkRestoreFailed
            }
            return
        }
        do {
            guard let credential = try credentialStore.load(scope) else { return }
            guard credential.isValid,
                  let url = transport.shareURL(token: credential.token),
                  Self.credentialScope(accountID: accountID, eventID: eventID, templateID: templateID, shareURL: url) == scope else {
                errorMessage = BlueprintCopy.shareLinkRestoreFailed
                return
            }
            guard let link = links.first(where: { $0.id == credential.linkID }),
                  link.revokedAt == nil, link.revision == credential.revision else {
                let removed = removeSavedCredential(forTemplateID: templateID)
                if !removed { errorMessage = BlueprintCopy.shareLinkRestoreFailed }
                return
            }
            createdLinkID = credential.linkID
            createdToken = credential.token
            createdURL = url
            pendingCredentialSave = CredentialSaveCandidate(credential: credential, scope: scope, url: url)
            credentialSaveFailed = false
            errorMessage = nil
        } catch {
            errorMessage = BlueprintCopy.shareLinkRestoreFailed
        }
    }

    @discardableResult
    private func removeSavedCredential(forTemplateID templateID: UUID, linkID: UUID? = nil) -> Bool {
        guard let credentialStore else { return true }
        guard let scope = credentialScope(templateID: templateID) else { return false }
        do {
            if let linkID {
                guard let saved = try credentialStore.load(scope), saved.linkID == linkID else { return true }
            }
            try credentialStore.remove(scope)
            return true
        } catch {
            return false
        }
    }

    private func credentialScope(templateID: UUID) -> BlueprintShareLinkCredentialScope? {
        guard let url = transport.shareURL(token: String(repeating: "0", count: 64)) else { return nil }
        return Self.credentialScope(accountID: accountID, eventID: eventID, templateID: templateID, shareURL: url)
    }

    private static func credentialScope(
        accountID: String, eventID: UUID, templateID: UUID, shareURL: URL
    ) -> BlueprintShareLinkCredentialScope? {
        BlueprintShareLinkCredentialScope.make(
            accountID: accountID, eventID: eventID, templateID: templateID, shareURL: shareURL
        )
    }

    private struct CredentialSaveCandidate {
        let credential: BlueprintShareLinkCredential
        let scope: BlueprintShareLinkCredentialScope?
        let url: URL
    }

    private func requireCreateRefresh(for templateID: UUID) {
        createRefreshRequiredTemplateID = templateID
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

