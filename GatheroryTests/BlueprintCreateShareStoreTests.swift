import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct BlueprintCreateShareStoreTests {
    @Test("Opening capture selects all supported content and notes without publishing")
    func defaultSelectionAndNoWrites() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        #expect(store.selectedChildIDs == Set(transport.source.source.children.map(\.id)))
        #expect(store.selectedIdeaIDs == Set(transport.source.source.ideas.map(\.id)))
        #expect(store.selectedInstructionIDs == Set(transport.source.source.instructions.map(\.id)))
        #expect(store.includeIdeaNotes)
        #expect(store.canReview)
        #expect(store.reviewed == nil)
        #expect(transport.creates.isEmpty && transport.linkCreates == 0)
        await store.createAndShare()
        #expect(transport.creates.isEmpty)
    }

    @Test("Deselecting a child removes dependent ideas and guidance")
    func dependentSelections() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        let child = transport.source.source.children[0].id
        let idea = transport.source.source.ideas[1].id
        let guide = transport.source.source.instructions[0].id
        let rootIdea = transport.source.source.ideas[0].id
        store.setChild(child, included: false)
        store.setIdea(idea, included: true)
        #expect(store.selectedIdeaIDs == [rootIdea])
        store.setChild(child, included: true)
        store.setIdea(idea, included: true)
        store.setInstruction(guide, included: true)
        #expect(store.selectedIdeaIDs == [rootIdea, idea])
        store.setChild(child, included: false)
        #expect(store.selectedIdeaIDs == [rootIdea] && store.selectedInstructionIDs.isEmpty)
        await store.review()
        #expect(transport.reviews.last?.selection.childIds == [])
    }

    @Test("Authors can exclude notes and every content edit invalidates review")
    func reviewAndOptionalNotes() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        store.setIdea(transport.source.source.ideas[0].id, included: true)
        await store.review()
        #expect(transport.reviews.last?.selection.includeIdeaNotes == true)
        #expect(store.canCreate)
        store.setIncludeIdeaNotes(false)
        #expect(store.reviewed == nil && !store.canCreate)
        await store.review()
        #expect(transport.reviews.last?.selection.includeIdeaNotes == false)
        store.setName("Another Name")
        #expect(store.reviewed == nil)
        await store.createAndShare()
        #expect(transport.creates.isEmpty)
    }

    @Test("Name validation counts Unicode scalars and rejects blank values")
    func unicodeNameLimits() async {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        store.setName(String(repeating: "🎉", count: 120))
        #expect(store.canReview)
        store.setName(String(repeating: "e\u{301}", count: 61))
        #expect(!store.canReview)
        store.setName("  \n")
        #expect(!store.canReview)
    }

    @Test("A changed source requires a fresh review and releases only the rejected request")
    func changedSourceRecovery() async {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        store.setName("  Reviewed Name  ")
        await store.review()
        #expect(store.name == "Reviewed Name")
        transport.sourceChanged = true
        await store.createAndShare()
        #expect(store.sourceReloadRequired && store.reviewed == nil && !store.isSelectionLocked)
        #expect(!store.canReview && transport.linkCreates == 0)
        transport.sourceChanged = false
        await store.load()
        #expect(!store.sourceReloadRequired)
        await store.review()
        await store.createAndShare()
        #expect(store.createdURL != nil)
    }

    @Test("An uncertain creation retries the identical request and locks reviewed content")
    func exactCreationRecovery() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        transport.failCreation = true
        await store.createAndShare()
        let original = try #require(transport.creates.first)
        #expect(store.isSelectionLocked && store.created == nil)
        store.setName("Do not change a pending request")
        store.edit()
        #expect(store.name == original.name && store.reviewed != nil)
        transport.failCreation = false
        await store.createAndShare()
        #expect(transport.creates.count == 2)
        #expect(transport.creates[1] == original)
        #expect(store.created != nil && store.createdURL != nil)
        #expect(transport.linkCreates == 1)
        await store.createAndShare()
        #expect(transport.linkCreates == 1)
    }

    @Test("An uncertain link requires a successful explicit refresh without recapturing")
    func uncertainLinkRecovery() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        transport.failLink = true
        await store.createAndShare()
        #expect(store.created != nil && store.requiresLinkRefresh && store.createdURL == nil)
        await store.createAndShare()
        #expect(transport.linkCreates == 1)
        transport.failList = true
        await store.refreshCreatedLinks()
        #expect(store.requiresLinkRefresh)
        transport.failList = false
        transport.failLink = false
        await store.refreshCreatedLinks()
        #expect(!store.requiresLinkRefresh && store.createdLinks.count == 1)
        await store.createAndShare()
        #expect(transport.creates.count == 1 && transport.linkCreates == 2)
        #expect(store.createdURL != nil)
    }

    @Test("A late create response after account switching cannot create a link")
    func switchedAccountAfterCreate() async {
        let transport = CaptureTestTransport()
        let identity = CaptureTestIdentity()
        let store = makeStore(transport) { identity.id }
        await store.load()
        await store.review()
        transport.afterCreate = { identity.id = "other" }
        await store.createAndShare()
        #expect(store.source == nil && store.created == nil && store.reviewed == nil)
        #expect(store.createdURL == nil && transport.linkCreates == 0)
        await store.load()
        #expect(transport.sourceReads == 1)
    }

    @Test("Dismissing during source loading discards the response permanently")
    func dismissalDuringLoad() async {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        transport.afterSource = { store.invalidate() }
        await store.load()
        #expect(store.source == nil && !store.isLoading)
        await store.load()
        #expect(transport.sourceReads == 1)
    }

    @Test("Permission loss clears reviewed data and prevents publication")
    func permissionLoss() async {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        transport.reviewForbidden = true
        await store.review()
        #expect(store.source == nil && store.reviewed == nil)
        #expect(store.errorMessage != nil)
        await store.createAndShare()
        #expect(transport.creates.isEmpty)
    }

    @Test("Revocation only changes the displayed link after acknowledgement")
    func confirmedRevocation() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        await store.createAndShare()
        let id = try #require(store.createdLinks.first?.id)
        transport.failRevoke = true
        await store.revokeCreatedLink(id)
        #expect(store.createdURL != nil && store.createdLinks[0].revokedAt == nil)
        transport.failRevoke = false
        await store.revokeCreatedLink(id)
        #expect(store.createdURL == nil && store.createdLinks[0].revokedAt != nil)
    }

    private func makeStore(_ transport: CaptureTestTransport,
        account: @escaping @MainActor () -> String? = { "owner" }) -> BlueprintCreateShareStore {
        BlueprintCreateShareStore(eventID: transport.source.source.event.id, accountID: "owner",
            transport: transport, currentAccountID: account)
    }
}

@MainActor private final class CaptureTestIdentity { var id = "owner" }

@MainActor private final class CaptureTestTransport: BlueprintCreateShareTransport {
    let root = UUID()
    let child = UUID()
    let templateID = UUID()
    let linkID = UUID()
    var sourceReads = 0
    var linkCreates = 0
    var reviews: [BlueprintNativeReviewInput] = []
    var creates: [BlueprintNativeCreateInput] = []
    var failCreation = false
    var sourceChanged = false
    var failLink = false
    var failList = false
    var failRevoke = false
    var reviewForbidden = false
    var afterSource: (() -> Void)?
    var afterCreate: (() -> Void)?
    lazy var source = BlueprintCaptureSourceResponse(source: BlueprintCaptureSource(
        event: .init(id: root, title: "Our Wedding", startsAt: nil, timeZone: "America/Detroit", experienceType: "wedding"),
        children: [.init(id: child, title: "Dinner", purpose: "part_of_event", category: "food", startsAt: nil)],
        ideas: [.init(id: UUID(), eventId: root, title: "Flowers", category: "decoration", notes: "Private florist details"),
                .init(id: UUID(), eventId: child, title: "Cake", category: "food", notes: nil)],
        instructions: [.init(id: UUID(), eventId: child, title: "Arrival", body: "Use side entrance", audience: "event_participants")]),
        sourceHash: String(repeating: "a", count: 64))

    func captureSource(eventID: UUID) async throws -> BlueprintCaptureSourceResponse {
        sourceReads += 1
        afterSource?()
        return source
    }
    func reviewCapture(_ input: BlueprintNativeReviewInput) async throws -> BlueprintCaptureReview {
        reviews.append(input)
        if reviewForbidden { throw CloudSyncFailure.forbidden(nil) }
        return BlueprintCaptureReview(content: .init(name: input.name, description: "", experienceType: "wedding",
            children: [], ideas: [], instructions: []), sourceHash: input.expectedSourceHash, reviewHash: String(repeating: "b", count: 64), discoverable: true)
    }
    func createTemplate(_ input: BlueprintNativeCreateInput) async throws -> BlueprintNativeCreationResult {
        creates.append(input)
        if sourceChanged { throw CloudSyncFailure.server("BLUEPRINT_CAPTURE_SOURCE_CHANGED") }
        if failCreation { throw URLError(.networkConnectionLost) }
        afterCreate?()
        return .init(templateId: templateID, revision: 1)
    }
    func templates(eventID: UUID) async throws -> [BlueprintManagedTemplate] { [] }
    func links(eventID: UUID, templateID: UUID) async throws -> [BlueprintManagedShareLink] {
        if failList { throw URLError(.notConnectedToInternet) }
        return [.init(id: linkID, revision: 1, createdAt: .now, revokedAt: nil)]
    }
    func createLink(eventID: UUID, templateID: UUID, revision: Int) async throws -> BlueprintCreatedShareLink {
        linkCreates += 1
        if failLink { throw URLError(.networkConnectionLost) }
        return .init(link: .init(id: linkID, revision: revision, createdAt: .now, revokedAt: nil), token: String(repeating: "c", count: 64))
    }
    func revokeLink(eventID: UUID, templateID: UUID, linkID: UUID) async throws {
        if failRevoke { throw URLError(.notConnectedToInternet) }
    }
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int? { revision }
    func shareURL(token: String) -> URL? { URL(string: "https://example.test/templates/shared/\(token)") }
}
