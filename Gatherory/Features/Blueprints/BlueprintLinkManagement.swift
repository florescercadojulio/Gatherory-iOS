import Foundation
import Observation

struct BlueprintManagedTemplate: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let publishedRevision: Int?
    let retired: Bool
    var listedRevision: Int?

    init(id: UUID, title: String, publishedRevision: Int?, retired: Bool, listedRevision: Int? = nil) {
        self.id = id
        self.title = title
        self.publishedRevision = publishedRevision
        self.retired = retired
        self.listedRevision = listedRevision
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
    func shareURL(token: String) -> URL?
}

enum BlueprintLinkManagementAction: Encodable {
    case templates(eventID: UUID)
    case list(eventID: UUID, templateID: UUID)
    case create(eventID: UUID, templateID: UUID, revision: Int)
    case revoke(eventID: UUID, templateID: UUID, linkID: UUID)
    case listing(eventID: UUID, templateID: UUID, revision: Int?)

    private enum CodingKeys: String, CodingKey {
        case action, eventId, templateId, revision, linkId
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
        case .listing(let eventID, let templateID, let revision):
            try container.encode("listing", forKey: .action)
            try container.encode(eventID.uuidString, forKey: .eventId)
            try container.encode(templateID.uuidString, forKey: .templateId)
            try container.encode(revision, forKey: .revision)
        }
    }
}

struct BlueprintManagedTemplatesResponse: Decodable {
    let templates: [BlueprintManagedTemplate]
}

struct BlueprintManagedLinksResponse: Decodable {
    let links: [BlueprintManagedShareLink]
}

enum BlueprintLinkManagementMessage {
    static let requestFailed = String(localized: "blueprint.sharing.requestFailed", defaultValue: "Couldn't update template links. Check your connection and try again.")
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
    private(set) var errorMessage: String?

    let eventID: UUID
    let accountID: String

    @ObservationIgnored private let transport: any BlueprintLinkManagementTransport
    @ObservationIgnored private let currentAccountID: @MainActor () -> String?
    @ObservationIgnored private var contextRevision = UUID()
    @ObservationIgnored private var loadRevision: UUID?
    @ObservationIgnored private var mutationRevision: UUID?
    @ObservationIgnored private var createdLinkID: UUID?
    private var createRefreshRequiredTemplateID: UUID?
    @ObservationIgnored private var isInvalidated = false

    var createRequiresRefresh: Bool {
        guard let selectedTemplateID else { return false }
        return selectedTemplateID == createRefreshRequiredTemplateID
    }

    var canCreate: Bool {
        guard !isInvalidated, hasLoadedLinks, !createRequiresRefresh, !isLoading, !isMutating,
              errorMessage == nil, isAccountCurrent,
              let selectedTemplateID,
              let template = templates.first(where: { $0.id == selectedTemplateID }) else { return false }
        return template.publishedRevision != nil && !template.retired
    }

    init(
        eventID: UUID,
        accountID: String,
        transport: any BlueprintLinkManagementTransport,
        currentAccountID: @escaping @MainActor () -> String?
    ) {
        self.eventID = eventID
        self.accountID = accountID
        self.transport = transport
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
            if let selectedTemplateID, !result.contains(where: { $0.id == selectedTemplateID }) {
                self.selectedTemplateID = nil
                links = []
                hasLoadedLinks = false
                clearCreatedLink()
            } else if let selectedTemplateID,
                      let previousSelection,
                      let refreshedSelection = result.first(where: { $0.id == selectedTemplateID }),
                      (previousSelection.publishedRevision != refreshedSelection.publishedRevision ||
                       previousSelection.retired != refreshedSelection.retired) {
                clearCreatedLink()
                hasLoadedLinks = false
            }
            errorMessage = nil
        } catch {
            guard isCurrent(revision: revision) else { return }
            errorMessage = BlueprintLinkManagementMessage.requestFailed
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
            if let createdLinkID {
                if let createdLink = result.first(where: { $0.id == createdLinkID }), createdLink.revokedAt == nil {
                    // Keep the one-time URL only while the server still lists it as active.
                } else {
                    clearCreatedLink()
                }
            }
            hasLoadedLinks = true
            if createRefreshRequiredTemplateID == selectedID {
                createRefreshRequiredTemplateID = nil
            }
            errorMessage = nil
        } catch {
            guard isCurrent(revision: revision), selectedTemplateID == selectedID else { return }
            errorMessage = BlueprintLinkManagementMessage.requestFailed
        }
    }

    func create() async {
        guard canCreate,
              let templateID = selectedTemplateID,
              let template = templates.first(where: { $0.id == templateID }),
              !template.retired,
              let revisionNumber = template.publishedRevision else { return }
        clearCreatedLink()
        let revision = beginMutation()
        defer { finishMutation(revision) }
        do {
            let created = try await transport.createLink(
                eventID: eventID,
                templateID: templateID,
                revision: revisionNumber
            )
            guard isCurrent(revision: revision), selectedTemplateID == templateID else { return }
            guard Self.isValidToken(created.token) else {
                requireCreateRefresh(for: templateID)
                errorMessage = BlueprintLinkManagementMessage.invalidToken
                return
            }
            createdLinkID = created.link.id
            createdToken = created.token
            createdURL = transport.shareURL(token: created.token)
            if let existingIndex = links.firstIndex(where: { $0.id == created.link.id }) {
                links[existingIndex] = created.link
            } else {
                links.insert(created.link, at: 0)
            }
            errorMessage = createdURL == nil ? BlueprintLinkManagementMessage.unsafeAddress : nil
            if createdURL == nil { requireCreateRefresh(for: templateID) }
        } catch {
            guard isCurrent(revision: revision) else { return }
            // The server may have created the link before the response failed.
            // Require a successful explicit list refresh before permitting retry.
            requireCreateRefresh(for: templateID)
            errorMessage = BlueprintLinkManagementMessage.requestFailed
        }
    }

    func revoke(linkID: UUID) async {
        guard !isInvalidated, !isMutating, !isLoading, isAccountCurrent,
              let templateID = selectedTemplateID,
              let index = links.firstIndex(where: { $0.id == linkID }),
              links[index].revokedAt == nil else { return }
        let revision = beginMutation()
        defer { finishMutation(revision) }
        do {
            try await transport.revokeLink(eventID: eventID, templateID: templateID, linkID: linkID)
            guard isCurrent(revision: revision), selectedTemplateID == templateID,
                  let currentIndex = links.firstIndex(where: { $0.id == linkID }) else { return }
            // Reflect revocation only after the server confirms it.
            links[currentIndex].revokedAt = Date()
            if createdLinkID == linkID { clearCreatedLink() }
            errorMessage = nil
        } catch {
            guard isCurrent(revision: revision) else { return }
            errorMessage = BlueprintLinkManagementMessage.requestFailed
        }
    }

    func setDiscoverable(_ enabled: Bool) async {
        guard !isInvalidated, !isMutating, !isLoading, isAccountCurrent,
              let templateID = selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == templateID }),
              !templates[index].retired,
              let publishedRevision = templates[index].publishedRevision else { return }
        let requestedRevision = enabled ? publishedRevision : nil
        guard templates[index].listedRevision != requestedRevision else { return }

        let requestContext = beginMutation()
        defer { finishMutation(requestContext) }
        do {
            let acknowledgedRevision = try await transport.setTemplateListing(
                eventID: eventID, templateID: templateID, revision: requestedRevision
            )
            guard isCurrent(revision: requestContext), selectedTemplateID == templateID,
                  let currentIndex = templates.firstIndex(where: { $0.id == templateID }) else { return }
            guard acknowledgedRevision == requestedRevision else {
                errorMessage = BlueprintLinkManagementMessage.listingFailed
                return
            }
            templates[currentIndex].listedRevision = acknowledgedRevision
            errorMessage = nil
        } catch {
            guard isCurrent(revision: requestContext) else { return }
            errorMessage = BlueprintLinkManagementMessage.listingFailed
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
    }

    private func requireCreateRefresh(for templateID: UUID) {
        createRefreshRequiredTemplateID = templateID
    }

    private static func isValidToken(_ token: String) -> Bool {
        token.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

