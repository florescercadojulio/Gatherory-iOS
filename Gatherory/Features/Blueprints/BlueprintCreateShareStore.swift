import Foundation
import Observation

struct BlueprintCaptureSourceResponse: Decodable, Equatable, Sendable {
    let source: BlueprintCaptureSource
    let sourceHash: String

    var event: BlueprintCaptureSource.Event { source.event }
    var children: [BlueprintCaptureSource.Child] { source.children }
    var ideas: [BlueprintCaptureSource.Idea] { source.ideas }
    var instructions: [BlueprintCaptureSource.Instruction] { source.instructions }
}

struct BlueprintCaptureSource: Decodable, Equatable, Sendable {
    struct Event: Decodable, Equatable, Sendable {
        let id: UUID
        let title: String
        let startsAt: String?
        let timeZone: String
        let experienceType: String
    }
    struct Child: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let purpose: String
        let category: String
        let startsAt: String?
    }
    struct Idea: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let eventId: UUID
        let title: String
        let category: String
        let notes: String?
    }
    struct Instruction: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let eventId: UUID
        let title: String
        let body: String
        let audience: String
    }
    let event: Event
    let children: [Child]
    let ideas: [Idea]
    let instructions: [Instruction]
}

struct BlueprintCaptureSelection: Encodable, Equatable, Sendable {
    let childIds: [UUID]
    let ideaIds: [UUID]
    let instructionIds: [UUID]
    let includeIdeaNotes: Bool

    private enum CodingKeys: String, CodingKey { case childIds, ideaIds, instructionIds, includeIdeaNotes }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(childIds.map { $0.uuidString.lowercased() }, forKey: .childIds)
        try container.encode(ideaIds.map { $0.uuidString.lowercased() }, forKey: .ideaIds)
        try container.encode(instructionIds.map { $0.uuidString.lowercased() }, forKey: .instructionIds)
        try container.encode(includeIdeaNotes, forKey: .includeIdeaNotes)
    }
}

struct BlueprintCapturedContent: Decodable, Equatable, Sendable {
    struct Target: Decodable, Equatable, Sendable {
        let kind: String
        let key: String?
    }
    struct ScheduleProposal: Decodable, Equatable, Sendable {
        let anchor: String
        let dayOffset: Int
        let localTime: String
    }
    struct Child: Decodable, Equatable, Identifiable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        let purpose: String
        let category: String
        let scheduleProposal: ScheduleProposal?
    }
    struct Idea: Decodable, Equatable, Identifiable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        let category: String
        let notes: String?
        let target: Target
    }
    struct Instruction: Decodable, Equatable, Identifiable, Sendable {
        var id: String { key }
        let key: String
        let title: String
        let body: String
        let audience: String
        let target: Target
    }
    let name: String
    let description: String
    let experienceType: String
    let children: [Child]
    let ideas: [Idea]
    let instructions: [Instruction]
}

struct BlueprintCaptureReview: Decodable, Equatable, Sendable {
    let content: BlueprintCapturedContent
    let sourceHash: String
    let reviewHash: String
    let discoverable: Bool?
}

struct BlueprintNativeCreationResult: Decodable, Equatable, Sendable {
    let templateId: UUID
    let revision: Int
}

struct BlueprintNativeReviewInput: Encodable, Equatable, Sendable {
    let eventId: UUID
    let selection: BlueprintCaptureSelection
    let expectedSourceHash: String
    let name: String
    var discoverable = true

    private enum CodingKeys: String, CodingKey { case action, eventId, selection, expectedSourceHash, name, discoverable }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("review", forKey: .action)
        try container.encode(eventId.uuidString.lowercased(), forKey: .eventId)
        try container.encode(selection, forKey: .selection)
        try container.encode(expectedSourceHash, forKey: .expectedSourceHash)
        try container.encode(name, forKey: .name)
        try container.encode(discoverable, forKey: .discoverable)
    }
}

struct BlueprintNativeCreateInput: Encodable, Equatable, Sendable {
    let eventId: UUID
    let selection: BlueprintCaptureSelection
    let expectedSourceHash: String
    let name: String
    let requestId: UUID
    let expectedReviewHash: String
    var discoverable = true

    private enum CodingKeys: String, CodingKey {
        case action, eventId, selection, expectedSourceHash, name, requestId, expectedReviewHash, discoverable
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("create", forKey: .action)
        try container.encode(eventId.uuidString.lowercased(), forKey: .eventId)
        try container.encode(selection, forKey: .selection)
        try container.encode(expectedSourceHash, forKey: .expectedSourceHash)
        try container.encode(name, forKey: .name)
        try container.encode(requestId.uuidString.lowercased(), forKey: .requestId)
        try container.encode(expectedReviewHash, forKey: .expectedReviewHash)
        try container.encode(discoverable, forKey: .discoverable)
    }
}

@MainActor
protocol BlueprintCreateShareTransport: BlueprintLinkManagementTransport {
    func captureSource(eventID: UUID) async throws -> BlueprintCaptureSourceResponse
    func reviewCapture(_ input: BlueprintNativeReviewInput) async throws -> BlueprintCaptureReview
    func createTemplate(_ input: BlueprintNativeCreateInput) async throws -> BlueprintNativeCreationResult
}

/// Sharing is an explicit online operation. No ordinary event records, outbox
/// entries, installation intents, or account-scoped setup drafts are changed.
@MainActor @Observable
final class BlueprintCreateShareStore {
    let publishesToSearch: Bool
    let createsShareLink: Bool
    let eventID: UUID
    let accountID: String
    private(set) var source: BlueprintCaptureSourceResponse?
    private(set) var name = ""
    private(set) var selectedChildIDs: Set<UUID> = []
    private(set) var selectedIdeaIDs: Set<UUID> = []
    private(set) var selectedInstructionIDs: Set<UUID> = []
    private(set) var includeIdeaNotes = false
    private(set) var reviewed: BlueprintCaptureReview?
    private(set) var created: BlueprintNativeCreationResult?
    private(set) var createdURL: URL?
    private(set) var createdLinks: [BlueprintManagedShareLink] = []
    private(set) var listedRevision: Int?
    private(set) var publicCreatorName: String?
    private(set) var requiresLinkRefresh = false
    private(set) var sourceReloadRequired = false
    private(set) var isLoading = false
    private(set) var isReviewing = false
    private(set) var isCreating = false
    private(set) var credentialSaveFailed = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let transport: any BlueprintCreateShareTransport
    @ObservationIgnored private let credentialStore: (any BlueprintShareLinkCredentialStore)?
    @ObservationIgnored private let currentAccountID: @MainActor () -> String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var pendingCreate: BlueprintNativeCreateInput?
    @ObservationIgnored private var createdLinkID: UUID?
    @ObservationIgnored private var createdCredentialScope: BlueprintShareLinkCredentialScope?
    @ObservationIgnored private var credentialPendingSave: BlueprintShareLinkCredential?

    init(eventID: UUID, accountID: String, transport: any BlueprintCreateShareTransport,
         publishesToSearch: Bool = false,
         createsShareLink: Bool = true,
         credentialStore: (any BlueprintShareLinkCredentialStore)? = nil,
         currentAccountID: @escaping @MainActor () -> String?) {
        self.eventID = eventID
        self.accountID = accountID
        self.transport = transport
        self.publishesToSearch = publishesToSearch
        self.createsShareLink = createsShareLink
        self.credentialStore = credentialStore
        self.currentAccountID = currentAccountID
    }

    var isBusy: Bool { isLoading || isReviewing || isCreating }
    var isSelectionLocked: Bool { pendingCreate != nil || created != nil }
    var canEdit: Bool { isCurrent && !isBusy && !isSelectionLocked }
    var canReview: Bool {
        canEdit && !sourceReloadRequired && source != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count <= 120
    }
    var canCreate: Bool {
        isCurrent && !isBusy && reviewed != nil && !requiresLinkRefresh && createdURL == nil
    }
    var canReplaceShareLink: Bool {
        createsShareLink && isCurrent && !isBusy && !requiresLinkRefresh &&
            created != nil && reviewed != nil && createdURL != nil
    }
    var eligibleIdeas: [BlueprintCaptureSource.Idea] {
        source?.source.ideas.filter { isEligible($0.eventId) } ?? []
    }
    var eligibleInstructions: [BlueprintCaptureSource.Instruction] {
        source?.source.instructions.filter { isEligible($0.eventId) } ?? []
    }

    func setName(_ value: String) {
        guard canEdit else { return }
        name = value
        edit()
    }
    func setIncludeIdeaNotes(_ included: Bool) {
        guard canEdit else { return }
        includeIdeaNotes = included
        edit()
    }
    func setChild(_ id: UUID, included: Bool) {
        guard canEdit, source?.source.children.contains(where: { $0.id == id }) == true else { return }
        if included { selectedChildIDs.insert(id) } else {
            selectedChildIDs.remove(id)
            selectedIdeaIDs = selectedIdeaIDs.intersection(eligibleIdeas.map(\.id))
            selectedInstructionIDs = selectedInstructionIDs.intersection(eligibleInstructions.map(\.id))
        }
        edit()
    }
    func setIdea(_ id: UUID, included: Bool) {
        guard canEdit, eligibleIdeas.contains(where: { $0.id == id }) else { return }
        if included { selectedIdeaIDs.insert(id) } else { selectedIdeaIDs.remove(id) }
        edit()
    }
    func setInstruction(_ id: UUID, included: Bool) {
        guard canEdit, eligibleInstructions.contains(where: { $0.id == id }) else { return }
        if included { selectedInstructionIDs.insert(id) } else { selectedInstructionIDs.remove(id) }
        edit()
    }
    func edit() {
        guard canEdit else { return }
        reviewed = nil
        errorMessage = nil
    }

    func load() async {
        guard isCurrent, !isBusy, !isSelectionLocked else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let response = try await transport.captureSource(eventID: eventID)
            guard accepts(current) else { return }
            guard response.source.event.id == eventID, Self.isHash(response.sourceHash) else {
                throw CloudSyncFailure.invalidResponse
            }
            source = response
            name = response.source.event.title
            selectedChildIDs = Set(response.source.children.map(\.id))
            selectedIdeaIDs = Set(response.source.ideas.map(\.id))
            selectedInstructionIDs = Set(response.source.instructions.map(\.id))
            includeIdeaNotes = true
            reviewed = nil
            sourceReloadRequired = false
            errorMessage = nil
        } catch { fail(error, generation: current, message: BlueprintCopy.templateCreationLoadFailed) }
    }

    func review() async {
        guard canReview, let source else { return }
        let input = BlueprintNativeReviewInput(eventId: eventID, selection: selection,
            expectedSourceHash: source.sourceHash, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            discoverable: publishesToSearch)
        let current = generation
        isReviewing = true
        reviewed = nil
        defer { if current == generation { isReviewing = false } }
        do {
            let response = try await transport.reviewCapture(input)
            guard accepts(current) else { return }
            guard response.sourceHash == input.expectedSourceHash, Self.isHash(response.reviewHash),
                  (response.discoverable == true) == publishesToSearch,
                  response.content.name == input.name else { throw CloudSyncFailure.invalidResponse }
            name = input.name
            reviewed = response
            errorMessage = nil
        } catch { fail(error, generation: current, message: BlueprintCopy.templateCreationReviewFailed) }
    }

    func createAndShare() async {
        guard canCreate else { return }
        await performCreateAndShare(replacingCurrentLink: false)
    }

    func replaceShareLink() async {
        guard canReplaceShareLink else { return }
        await performCreateAndShare(replacingCurrentLink: true)
    }

    private func performCreateAndShare(replacingCurrentLink: Bool) async {
        guard isCurrent, !isBusy, !requiresLinkRefresh, let reviewed,
              replacingCurrentLink ? canReplaceShareLink : canCreate else { return }
        let current = generation
        isCreating = true
        defer { if current == generation { isCreating = false } }
        if created == nil {
            let input = pendingCreate ?? BlueprintNativeCreateInput(eventId: eventID,
                selection: selection, expectedSourceHash: reviewed.sourceHash, name: reviewed.content.name,
                requestId: UUID(), expectedReviewHash: reviewed.reviewHash, discoverable: publishesToSearch)
            pendingCreate = input
            do {
                let response = try await transport.createTemplate(input)
                guard accepts(current) else { return }
                guard response.revision > 0 else { throw CloudSyncFailure.invalidResponse }
                created = response
                listedRevision = publishesToSearch ? response.revision : nil
            } catch {
                fail(error, generation: current, message: BlueprintCopy.templateCreationUncertain)
                return
            }
        }
        guard accepts(current), let created else { return }
        if let personal = transport as? any BlueprintPersonalLibraryTransport {
            do {
                let records = try await personal.listPersonalBlueprints()
                guard accepts(current), records.contains(where: { $0.id == created.templateId }) else {
                    throw CloudSyncFailure.invalidResponse
                }
                try BlueprintPersonalLibraryStore().save(records, ownerID: accountID)
            } catch {
                fail(error, generation: current, message: BlueprintCopy.previewSaveFailed)
                return
            }
        }
        guard createsShareLink else { errorMessage = nil; return }
        do {
            let link = try await transport.createLink(eventID: eventID, templateID: created.templateId, revision: created.revision)
            guard accepts(current) else { return }
            guard BlueprintSharedTemplateLink.isValidToken(link.token), link.link.revokedAt == nil,
                  link.link.revision == created.revision, let url = transport.shareURL(token: link.token) else {
                throw CloudSyncFailure.invalidResponse
            }
            // Keep any current URL and cached credential until the server returns
            // a valid replacement. An uncertain response can then continue to
            // show the old link while requiring an explicit links refresh.
            createdLinkID = link.link.id
            createdURL = url
            requiresLinkRefresh = false
            let credential = BlueprintShareLinkCredential(
                linkID: link.link.id,
                revision: link.link.revision,
                token: link.token
            )
            createdCredentialScope = BlueprintShareLinkCredentialScope.make(
                accountID: accountID,
                eventID: eventID,
                templateID: created.templateId,
                shareURL: url
            )
            createdLinks.removeAll { $0.id == link.link.id }
            createdLinks.insert(link.link, at: 0)
            errorMessage = nil
            credentialSaveFailed = false
            credentialPendingSave = credentialStore == nil ? nil : credential
            if let credentialStore, let scope = createdCredentialScope {
                do {
                    try credentialStore.save(credential, for: scope)
                    credentialPendingSave = nil
                } catch {
                    credentialSaveFailed = true
                    errorMessage = BlueprintCopy.shareLinkSaveFailed
                }
            } else if credentialStore != nil {
                credentialSaveFailed = true
                errorMessage = BlueprintCopy.shareLinkSaveFailed
            }
        } catch {
            guard accepts(current) else { return }
            requiresLinkRefresh = true
            fail(error, generation: current, message: BlueprintCopy.templateCreationLinkUncertain)
        }
    }

    func setDiscoverable(_ enabled: Bool, creatorName: String? = nil) async {
        guard createsShareLink, isCurrent, !isBusy, !requiresLinkRefresh, let created else { return }
        let requestedRevision = enabled ? created.revision : nil
        guard listedRevision != requestedRevision else { return }
        let requestedCreatorName: String?
        if enabled {
            if let normalized = publicCreatorName.flatMap(BlueprintCreatorNameValidation.normalized) {
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

        let current = generation
        isCreating = true
        defer { if current == generation { isCreating = false } }
        do {
            let acknowledgement = try await transport.setTemplateListing(
                eventID: eventID, templateID: created.templateId, revision: requestedRevision,
                creatorName: requestedCreatorName
            )
            guard accepts(current), self.created?.templateId == created.templateId,
                  self.created?.revision == created.revision else { return }
            guard acknowledgement.listedRevision == requestedRevision,
                  !enabled || acknowledgement.creatorName.flatMap(BlueprintCreatorNameValidation.normalized) == requestedCreatorName else {
                errorMessage = BlueprintLinkManagementMessage.listingFailed
                return
            }
            listedRevision = acknowledgement.listedRevision
            if enabled { publicCreatorName = requestedCreatorName }
            errorMessage = credentialSaveFailed ? BlueprintCopy.shareLinkSaveFailed : nil
        } catch {
            fail(error, generation: current, message: BlueprintLinkManagementMessage.listingFailed)
        }
    }

    func refreshCreatedLinks() async {
        guard isCurrent, !isBusy, let created else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let links = try await transport.links(eventID: eventID, templateID: created.templateId)
            guard accepts(current) else { return }
            createdLinks = links
            if let createdLinkID, !links.contains(where: { $0.id == createdLinkID && $0.revokedAt == nil }) {
                createdURL = nil
                credentialPendingSave = nil
                requiresLinkRefresh = false
                let removalSucceeded = removeSavedCredential(linkID: createdLinkID)
                if !removalSucceeded {
                    errorMessage = BlueprintCopy.shareLinkStorageFailed
                    return
                }
                self.createdLinkID = nil
            }
            requiresLinkRefresh = false
            errorMessage = credentialSaveFailed && createdURL != nil
                ? BlueprintCopy.shareLinkSaveFailed
                : nil
        } catch { fail(error, generation: current, message: BlueprintCopy.templateCreationLinkUncertain) }
    }

    /// Retries only the local credential write for the already acknowledged link.
    /// It never calls the sharing API or creates another server link.
    func retrySavingLink() {
        guard isCurrent, !isBusy,
              let credentialStore,
              let credential = credentialPendingSave,
              let scope = createdCredentialScope,
              let createdURL,
              let createdLinkID,
              let created,
              credential.isValid,
              credential.linkID == createdLinkID,
              credential.revision == created.revision,
              transport.shareURL(token: credential.token) == createdURL else { return }

        isCreating = true
        defer { isCreating = false }
        do {
            try credentialStore.save(credential, for: scope)
            guard isCurrent,
                  self.createdURL == createdURL,
                  self.createdLinkID == credential.linkID,
                  self.created?.templateId == created.templateId else { return }
            credentialPendingSave = nil
            credentialSaveFailed = false
            if errorMessage == BlueprintCopy.shareLinkSaveFailed { errorMessage = nil }
        } catch {
            guard isCurrent else { return }
            credentialSaveFailed = true
            errorMessage = BlueprintCopy.shareLinkSaveFailed
        }
    }

    func revokeCreatedLink(_ linkID: UUID) async {
        guard isCurrent, !isBusy, let created,
              createdLinks.contains(where: { $0.id == linkID && $0.revokedAt == nil }) else { return }
        let current = generation
        isCreating = true
        defer { if current == generation { isCreating = false } }
        do {
            try await transport.revokeLink(eventID: eventID, templateID: created.templateId, linkID: linkID)
            guard accepts(current), let index = createdLinks.firstIndex(where: { $0.id == linkID }) else { return }
            createdLinks[index].revokedAt = Date()
            if createdLinkID == linkID {
                createdURL = nil
                credentialPendingSave = nil
                let removalSucceeded = removeSavedCredential(linkID: linkID)
                if !removalSucceeded {
                    errorMessage = BlueprintCopy.shareLinkStorageFailed
                    return
                }
                createdLinkID = nil
            }
            errorMessage = nil
        } catch { fail(error, generation: current, message: BlueprintCopy.templateCreationLinkUncertain) }
    }

    func invalidate() {
        invalidated = true
        generation = UUID()
        source = nil
        name = ""
        selectedChildIDs = []
        selectedIdeaIDs = []
        selectedInstructionIDs = []
        includeIdeaNotes = false
        reviewed = nil
        pendingCreate = nil
        created = nil
        listedRevision = nil
        publicCreatorName = nil
        createdURL = nil
        createdLinkID = nil
        createdLinks = []
        requiresLinkRefresh = false
        sourceReloadRequired = false
        isLoading = false
        isReviewing = false
        isCreating = false
        credentialSaveFailed = false
        createdCredentialScope = nil
        credentialPendingSave = nil
        errorMessage = nil
    }

    private var isCurrent: Bool { !invalidated && currentAccountID() == accountID }
    private func accepts(_ value: UUID) -> Bool {
        guard value == generation, isCurrent else {
            if currentAccountID() != accountID { invalidate() }
            return false
        }
        return true
    }
    private func isEligible(_ eventId: UUID) -> Bool {
        eventId == eventID || selectedChildIDs.contains(eventId)
    }
    private var selection: BlueprintCaptureSelection {
        func sorted(_ ids: Set<UUID>) -> [UUID] { ids.sorted { $0.uuidString < $1.uuidString } }
        return BlueprintCaptureSelection(childIds: sorted(selectedChildIDs), ideaIds: sorted(selectedIdeaIDs),
            instructionIds: sorted(selectedInstructionIDs), includeIdeaNotes: includeIdeaNotes)
    }
    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func fail(_ error: Error, generation value: UUID, message: String) {
        guard accepts(value) else { return }
        if let failure = error as? CloudSyncFailure {
            switch failure {
            case .invalidSession:
                invalidate()
                errorMessage = BlueprintCopy.templateLinkSignIn
                return
            case .forbidden, .server("BLUEPRINT_NOT_FOUND"), .server("HTTP_404"):
                let credentialRemovalFailed = createdLinkID.map { !removeSavedCredential(linkID: $0) } ?? false
                invalidate()
                if credentialRemovalFailed {
                    errorMessage = BlueprintCopy.shareLinkStorageFailed
                } else {
                    errorMessage = BlueprintCopy.templateCreationPermissionLost
                }
                return
            default:
                break
            }
        }
        if case CloudSyncFailure.server("BLUEPRINT_CAPTURE_SOURCE_CHANGED") = error {
            // A definitive conflict rolls back creation. A fresh source review
            // is required; this differs from an uncertain network response.
            pendingCreate = nil
            reviewed = nil
            sourceReloadRequired = true
            errorMessage = BlueprintCopy.templateCreationSourceChanged
        } else {
            errorMessage = message
        }
    }

    /// Removes only the cached credential for the expected server link. A failed
    /// Keychain removal never restores or retains the revoked live URL.
    private func removeSavedCredential(linkID: UUID) -> Bool {
        guard let credentialStore, let scope = createdCredentialScope else { return true }
        do {
            guard let saved = try credentialStore.load(scope), saved.linkID == linkID else {
                credentialSaveFailed = false
                return true
            }
            try credentialStore.remove(scope)
            credentialSaveFailed = false
            return true
        } catch {
            credentialSaveFailed = false
            errorMessage = BlueprintCopy.shareLinkStorageFailed
            return false
        }
    }
}
