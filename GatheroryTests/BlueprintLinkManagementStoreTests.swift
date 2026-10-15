import Foundation
import Testing
@testable import Gatherory

@MainActor
private final class BlueprintLinkTestAccount {
    var id = "account-a"
}

@Suite(.serialized)
@MainActor
struct BlueprintLinkManagementStoreTests {
    @Test("An account switch discards an in-flight response and clears private state")
    func accountSwitchDuringLoad() async throws {
        let activeAccount = BlueprintLinkTestAccount()
        let transport = BlueprintLinkManagementTestTransport()
        transport.holdTemplates = true
        let store = makeStore(transport: transport) { activeAccount.id }
        #expect(!store.createRequiresRefresh)

        let request = Task { await store.loadTemplates() }
        let didStart = await waitUntil { transport.templatesStarted }
        try #require(didStart)
        activeAccount.id = "account-b"
        transport.resumeTemplates(.success([template()]))
        await request.value

        #expect(store.templates.isEmpty)
        #expect(store.links.isEmpty)
        #expect(store.createdToken == nil)
        #expect(!store.isLoading)
    }

    @Test("A selected template cannot create until links load successfully")
    func selectionRequiresSuccessfulLinkLoad() async {
        let transport = BlueprintLinkManagementTestTransport()
        transport.linksError = true
        let store = makeStore(transport: transport)
        await store.loadTemplates()
        await store.select(templateID: transport.template.id)

        #expect(store.selectedTemplateID == transport.template.id)
        #expect(!store.createRequiresRefresh)
        #expect(!store.canCreate)
        await store.create()
        #expect(transport.createCount == 0)

        transport.linksError = false
        await store.loadLinks()
        #expect(!store.createRequiresRefresh)
        #expect(store.canCreate)
    }

    @Test("Changing selection while a link list is loading cannot strand the new selection")
    func selectionIsStableDuringLoad() async throws {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await store.loadTemplates()
        transport.holdLinks = true

        let selection = Task { await store.select(templateID: transport.template.id) }
        let didStart = await waitUntil { transport.linksStarted }
        try #require(didStart)
        await store.select(templateID: nil)
        transport.resumeLinks(.success([]))
        await selection.value

        #expect(store.selectedTemplateID == transport.template.id)
        #expect(store.hasLoadedLinks)
    }

    @Test("List and revoke failures do not imply revocation; refresh clears a URL revoked elsewhere")
    func listAndRevokeFailureThenExternalRevocation() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        let linkID = transport.created.link.id
        #expect(store.createdURL != nil)
        #expect(store.createdToken == transport.created.token)

        transport.revokeError = true
        await store.revoke(linkID: linkID)
        #expect(store.links.first(where: { $0.id == linkID })?.revokedAt == nil)
        #expect(store.createdURL != nil)

        transport.linksError = true
        await store.loadLinks()
        #expect(store.links.first(where: { $0.id == linkID })?.revokedAt == nil)
        #expect(store.createdURL != nil)

        transport.linksError = false
        transport.links = [revokedLink(id: linkID)]
        await store.loadLinks()
        #expect(store.links.first(where: { $0.id == linkID })?.revokedAt != nil)
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
    }

    @Test("An uncertain create blocks retry until an explicit successful refresh")
    func uncertainCreateRequiresRefresh() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        #expect(store.createdURL != nil)
        transport.createError = true

        await store.create()
        #expect(store.createRequiresRefresh)
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
        #expect(transport.createCount == 2)
        await store.create()
        #expect(transport.createCount == 2)

        transport.createError = false
        await store.loadLinks()
        #expect(!store.createRequiresRefresh)
        await store.create()
        #expect(transport.createCount == 3)
        #expect(store.createdURL != nil)

        store.invalidate()
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
        #expect(!store.createRequiresRefresh)
    }

    @Test("Overlapping create calls issue one request and old one-time URL is cleared")
    func duplicateCreateAndTransientURL() async throws {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        #expect(store.createdToken == transport.created.token)

        transport.holdCreate = true
        transport.createStarted = false
        let firstCreate = Task { await store.create() }
        let didStart = await waitUntil { transport.createStarted }
        try #require(didStart)
        await store.create()
        #expect(transport.createCount == 2)

        transport.resumeCreate(.success(transport.created))
        await firstCreate.value
        #expect(!store.isMutating)
        #expect(store.createdURL != nil)
        store.invalidate()
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
    }

    @Test("Invalidating during create drops the late token and permanently disables the old store")
    func invalidateDuringCreate() async throws {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        transport.holdCreate = true

        let request = Task { await store.create() }
        let didStart = await waitUntil { transport.createStarted }
        try #require(didStart)
        store.invalidate()
        transport.resumeCreate(.success(transport.created))
        await request.value

        #expect(store.createdToken == nil)
        #expect(store.createdURL == nil)
        #expect(transport.createCount == 1)
        await store.loadTemplates()
        await store.create()
        #expect(transport.createCount == 1)
    }

    @Test("Opening a new store does not restore a one-time token or create another link")
    func reopeningDoesNotReplayCreate() async {
        let transport = BlueprintLinkManagementTestTransport()
        let first = makeStore(transport: transport)
        await prepare(first, transport: transport)
        await first.create()
        #expect(first.createdToken == transport.created.token)

        let reopened = makeStore(transport: transport)
        #expect(reopened.createdToken == nil)
        #expect(reopened.createdURL == nil)
        #expect(reopened.templates.isEmpty)
        await reopened.loadTemplates()
        #expect(reopened.createdToken == nil)
        #expect(transport.createCount == 1)
    }

    @Test("A template publication or retirement change clears its transient share URL")
    func refreshedTemplateChangesPin() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        #expect(store.createdURL != nil)

        transport.template = BlueprintManagedTemplate(
            id: transport.template.id, title: transport.template.title,
            publishedRevision: 4, retired: false
        )
        await store.loadTemplates()
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
    }

    @Test("Retiring the selected template clears its transient share URL")
    func refreshedTemplateRetirementClearsURL() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        #expect(store.createdURL != nil)

        transport.template = BlueprintManagedTemplate(
            id: transport.template.id, title: transport.template.title,
            publishedRevision: 3, retired: true
        )
        await store.loadTemplates()
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
        #expect(!store.canCreate)
    }

    @Test("Search visibility changes only after acknowledgement and failures preserve the current state")
    func listingAcknowledgement() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)

        transport.listingError = true
        await store.setDiscoverable(true)
        #expect(store.templates.first?.listedRevision == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)

        transport.listingError = false
        await store.setDiscoverable(true)
        #expect(store.templates.first?.listedRevision == 3)
        #expect(store.errorMessage == nil)

        await store.setDiscoverable(false)
        #expect(store.templates.first?.listedRevision == nil)
    }

    @Test("A late listing acknowledgement after account switching is discarded")
    func lateListingAfterAccountSwitch() async throws {
        let identity = BlueprintLinkTestAccount()
        let transport = BlueprintLinkManagementTestTransport()
        transport.holdListing = true
        let store = makeStore(transport: transport) { identity.id }
        await prepare(store, transport: transport)

        let request = Task { await store.setDiscoverable(true) }
        let didStart = await waitUntil { transport.listingStarted }
        try #require(didStart)
        identity.id = "account-b"
        transport.resumeListing(.success(3))
        await request.value

        #expect(store.templates.isEmpty)
        #expect(!store.isMutating)
    }

    private func prepare(_ store: BlueprintLinkManagementStore, transport: BlueprintLinkManagementTestTransport) async {
        await store.loadTemplates()
        await store.select(templateID: transport.template.id)
    }

    private func makeStore(
        transport: BlueprintLinkManagementTestTransport,
        currentAccountID: @escaping @MainActor () -> String? = { "account-a" }
    ) -> BlueprintLinkManagementStore {
        BlueprintLinkManagementStore(
            eventID: UUID(), accountID: "account-a", transport: transport,
            currentAccountID: currentAccountID
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func template() -> BlueprintManagedTemplate {
        BlueprintManagedTemplate(id: UUID(), title: "Wedding", publishedRevision: 3, retired: false)
    }

    private func revokedLink(id: UUID) -> BlueprintManagedShareLink {
        BlueprintManagedShareLink(id: id, revision: 3, createdAt: Date(timeIntervalSince1970: 1_700_000_000), revokedAt: Date())
    }
}

@MainActor
private final class BlueprintLinkManagementTestTransport: BlueprintLinkManagementTransport {
    var template = BlueprintManagedTemplate(id: UUID(), title: "Wedding", publishedRevision: 3, retired: false)
    var links: [BlueprintManagedShareLink] = []
    var created = BlueprintCreatedShareLink(
        link: BlueprintManagedShareLink(id: UUID(), revision: 3, createdAt: Date(timeIntervalSince1970: 1_800_000_000), revokedAt: nil),
        token: String(repeating: "b7", count: 32)
    )
    var holdTemplates = false
    var templatesStarted = false
    var holdCreate = false
    var createStarted = false
    var linksError = false
    var holdLinks = false
    var linksStarted = false
    var createError = false
    var revokeError = false
    var listingError = false
    var holdListing = false
    var listingStarted = false
    var createCount = 0
    private var templateContinuation: CheckedContinuation<[BlueprintManagedTemplate], Error>?
    private var linksContinuation: CheckedContinuation<[BlueprintManagedShareLink], Error>?
    private var createContinuation: CheckedContinuation<BlueprintCreatedShareLink, Error>?
    private var listingContinuation: CheckedContinuation<Int?, Error>?

    func templates(eventID: UUID) async throws -> [BlueprintManagedTemplate] {
        templatesStarted = true
        if holdTemplates {
            return try await withCheckedThrowingContinuation { templateContinuation = $0 }
        }
        return [template]
    }

    func links(eventID: UUID, templateID: UUID) async throws -> [BlueprintManagedShareLink] {
        linksStarted = true
        if holdLinks {
            return try await withCheckedThrowingContinuation { linksContinuation = $0 }
        }
        if linksError { throw BlueprintLinkManagementTestError.failed }
        return links
    }

    func createLink(eventID: UUID, templateID: UUID, revision: Int) async throws -> BlueprintCreatedShareLink {
        createCount += 1
        createStarted = true
        if holdCreate {
            return try await withCheckedThrowingContinuation { createContinuation = $0 }
        }
        if createError { throw BlueprintLinkManagementTestError.failed }
        return created
    }

    func revokeLink(eventID: UUID, templateID: UUID, linkID: UUID) async throws {
        if revokeError { throw BlueprintLinkManagementTestError.failed }
    }

    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int? {
        listingStarted = true
        if holdListing {
            return try await withCheckedThrowingContinuation { listingContinuation = $0 }
        }
        if listingError { throw BlueprintLinkManagementTestError.failed }
        return revision
    }

    func shareURL(token: String) -> URL? {
        URL(string: "https://share.example.test/templates/shared/\(token)")
    }

    func resumeTemplates(_ result: Result<[BlueprintManagedTemplate], Error>) {
        templateContinuation?.resume(with: result)
        templateContinuation = nil
    }

    func resumeCreate(_ result: Result<BlueprintCreatedShareLink, Error>) {
        createContinuation?.resume(with: result)
        createContinuation = nil
    }

    func resumeLinks(_ result: Result<[BlueprintManagedShareLink], Error>) {
        linksContinuation?.resume(with: result)
        linksContinuation = nil
    }

    func resumeListing(_ result: Result<Int?, Error>) {
        listingContinuation?.resume(with: result)
        listingContinuation = nil
    }
}

private enum BlueprintLinkManagementTestError: Error {
    case failed
}
