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

    @Test("An A to B to A account change invalidates a request from the first A session")
    func accountReturnsAfterInvalidation() async throws {
        let activeAccount = BlueprintLinkTestAccount()
        let transport = BlueprintLinkManagementTestTransport()
        transport.holdTemplates = true
        let store = makeStore(transport: transport) { activeAccount.id }

        let request = Task { await store.loadTemplates() }
        let didStart = await waitUntil { transport.templatesStarted }
        try #require(didStart)
        activeAccount.id = "account-b"
        store.invalidate()
        activeAccount.id = "account-a"
        transport.resumeTemplates(.success([template()]))
        await request.value

        #expect(store.templates.isEmpty)
        #expect(store.createdURL == nil)
        #expect(transport.templateReadCount == 1)
        await store.loadTemplates()
        #expect(transport.templateReadCount == 1)
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
        #expect(store.templates.first?.activeShareLinkCount == nil)

        transport.revokeError = true
        await store.revoke(linkID: linkID)
        #expect(store.links.first(where: { $0.id == linkID })?.revokedAt == nil)
        #expect(store.createdURL != nil)
        #expect(store.templates.first?.activeShareLinkCount == nil)

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
        #expect(store.templates.first?.activeShareLinkCount == nil)
    }

    @Test("Known active-link counts change from zero to one and back after acknowledgements")
    func knownActiveLinkCountChanges() async {
        let transport = BlueprintLinkManagementTestTransport()
        transport.template = BlueprintManagedTemplate(
            id: transport.template.id,
            title: transport.template.title,
            publishedRevision: 3,
            retired: false,
            activeShareLinkCount: 0
        )
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)

        await store.create()
        #expect(store.templates.first?.activeShareLinkCount == 1)

        await store.revoke(linkID: transport.created.link.id)
        #expect(store.templates.first?.activeShareLinkCount == 0)
    }

    @Test("An older-revision revoke leaves the count unknown, and later create does not infer a total")
    func unknownCountSurvivesOlderRevisionRevokeAndCreate() async {
        let transport = BlueprintLinkManagementTestTransport()
        let oldLinkID = UUID()
        transport.links = [BlueprintManagedShareLink(
            id: oldLinkID,
            revision: 2,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            revokedAt: nil
        )]
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)

        await store.revoke(linkID: oldLinkID)
        #expect(store.templates.first?.activeShareLinkCount == nil)

        await store.create()
        #expect(store.createdURL != nil)
        #expect(store.templates.first?.activeShareLinkCount == nil)
    }

    @Test("An uncertain replacement blocks retry while preserving the current URL")
    func uncertainCreateRequiresRefresh() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        let currentURL = store.createdURL
        let currentToken = store.createdToken
        #expect(currentURL != nil)
        transport.createError = true

        await store.create()
        #expect(store.createRequiresRefresh)
        #expect(store.createdURL == currentURL)
        #expect(store.createdToken == currentToken)
        #expect(transport.createCount == 2)
        await store.create()
        #expect(transport.createCount == 2)

        transport.createError = false
        await store.loadLinks()
        #expect(!store.createRequiresRefresh)
        // The refreshed fixture reports no active rows, so it must clear the
        // retained URL rather than treating an uncertain request as authority.
        #expect(store.createdURL == nil)
        #expect(store.createdToken == nil)
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

        transport.links = [transport.created.link]
        let reopened = makeStore(transport: transport)
        #expect(reopened.createdToken == nil)
        #expect(reopened.createdURL == nil)
        #expect(reopened.templates.isEmpty)
        await reopened.loadTemplates()
        await reopened.select(templateID: transport.template.id)
        #expect(reopened.createdToken == nil)
        #expect(reopened.createdURL == nil)
        #expect(transport.createCount == 1)
    }

    @Test("Reopening restores the saved URL for the same active pinned link")
    func reopeningRestoresCachedCredential() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let first = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(first, transport: transport)
        await first.create()
        transport.links = [transport.created.link]

        let reopened = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await reopened.loadTemplates()
        await reopened.select(templateID: transport.template.id)

        #expect(reopened.createdURL == transport.shareURL(token: transport.created.token))
        #expect(reopened.createdToken == transport.created.token)
        #expect(transport.createCount == 1)
    }

    @Test("Saved link credentials are isolated by account, event, and URL origin")
    func credentialScopeIsolation() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let owner = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(owner, transport: transport)
        await owner.create()
        transport.links = [transport.created.link]

        let otherAccount = makeStore(transport: transport, eventID: eventID, accountID: "account-b",
            credentialStore: credentials, currentAccountID: { "account-b" })
        await otherAccount.loadTemplates()
        await otherAccount.select(templateID: transport.template.id)
        #expect(otherAccount.createdURL == nil)

        let otherEvent = makeStore(transport: transport, eventID: UUID(), credentialStore: credentials)
        await otherEvent.loadTemplates()
        await otherEvent.select(templateID: transport.template.id)
        #expect(otherEvent.createdURL == nil)

        transport.shareHost = "other.example.test"
        let otherOrigin = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await otherOrigin.loadTemplates()
        await otherOrigin.select(templateID: transport.template.id)
        #expect(otherOrigin.createdURL == nil)
        #expect(transport.createCount == 1)
    }

    @Test("A stale credential restore after invalidation cannot repopulate the URL")
    func invalidationDuringCredentialRestore() async throws {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let first = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(first, transport: transport)
        await first.create()
        transport.links = [transport.created.link]

        transport.holdLinks = true
        transport.linksStarted = false
        let reopened = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await reopened.loadTemplates()
        let selection = Task { await reopened.select(templateID: transport.template.id) }
        let didStart = await waitUntil { transport.linksStarted }
        try #require(didStart)
        reopened.invalidate()
        transport.resumeLinks(.success([transport.created.link]))
        await selection.value

        #expect(reopened.createdURL == nil)
        #expect(reopened.createdToken == nil)
    }

    @Test("Missing or revoked server rows delete the saved raw credential")
    func missingOrRevokedCredentialIsRemoved() async {
        for revoked in [false, true] {
            let transport = BlueprintLinkManagementTestTransport()
            let credentials = MemoryBlueprintShareLinkCredentialStore()
            let eventID = UUID()
            let first = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
            await prepare(first, transport: transport)
            await first.create()
            let saved = transport.created.link

            transport.links = revoked ? [revokedLink(id: saved.id)] : []
            let reopened = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
            await reopened.loadTemplates()
            await reopened.select(templateID: transport.template.id)

            #expect(reopened.createdURL == nil)
            #expect(reopened.createdToken == nil)
            #expect(credentials.credentials.isEmpty)
        }
    }

    @Test("Revocation, retirement, missing ownership, and denial remove saved credentials")
    func invalidAuthorityRemovesSavedCredential() async {
        enum Scenario: CaseIterable { case revoke, retirement, missingOwnership, forbidden, notFound }
        for scenario in Scenario.allCases {
            let transport = BlueprintLinkManagementTestTransport()
            let credentials = MemoryBlueprintShareLinkCredentialStore()
            let store = makeStore(transport: transport, credentialStore: credentials)
            await prepare(store, transport: transport)
            await store.create()
            transport.links = [transport.created.link]
            #expect(!credentials.credentials.isEmpty)

            switch scenario {
            case .revoke:
                await store.revoke(linkID: transport.created.link.id)
            case .retirement:
                transport.template = BlueprintManagedTemplate(
                    id: transport.template.id, title: transport.template.title,
                    publishedRevision: 3, retired: true
                )
                await store.loadTemplates()
                await store.select(templateID: transport.template.id)
            case .missingOwnership:
                transport.templatesOverride = []
                await store.loadTemplates()
            case .forbidden:
                transport.linksFailure = .forbidden("EVENT_PERMISSION_REQUIRED")
                await store.loadLinks()
            case .notFound:
                transport.linksFailure = .server("HTTP_404")
                await store.loadLinks()
            }

            #expect(credentials.credentials.isEmpty)
            #expect(store.createdURL == nil)
        }
    }

    @Test("A newer publication still restores the older link's exact pin")
    func publicationChangeRestoresOldPin() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let first = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(first, transport: transport)
        await first.create()
        transport.links = [transport.created.link]
        transport.template = BlueprintManagedTemplate(
            id: transport.template.id, title: transport.template.title, publishedRevision: 4, retired: false
        )

        let reopened = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await reopened.loadTemplates()
        await reopened.select(templateID: transport.template.id)

        #expect(reopened.createdURL == transport.shareURL(token: transport.created.token))
        #expect(credentials.credentials.values.first?.revision == 3)
        #expect(transport.createCount == 1)
    }

    @Test("A failed credential save can be retried without creating another link")
    func retryCredentialSaveDoesNotCreateLink() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.saveError = BlueprintShareLinkCredentialStoreError.invalidRecord
        let store = makeStore(transport: transport, credentialStore: credentials)
        await prepare(store, transport: transport)
        await store.create()

        #expect(store.createdURL != nil)
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)
        #expect(!store.createRequiresRefresh)
        #expect(transport.createCount == 1)
        transport.links = [transport.created.link]
        await store.loadLinks()
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)

        await store.loadTemplates()
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)

        credentials.saveError = nil
        store.retrySavingLink()
        #expect(!store.credentialSaveFailed)
        #expect(store.errorMessage == nil)
        #expect(credentials.credentials.values.first?.token == transport.created.token)
        #expect(transport.createCount == 1)
    }

    @Test("Invalid token retains its specific validation error and explicit refresh gate")
    func invalidTokenResponseRequiresRefresh() async {
        let transport = BlueprintLinkManagementTestTransport()
        transport.created = BlueprintCreatedShareLink(
            link: transport.created.link, token: String(repeating: "g", count: 64)
        )
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()

        #expect(store.createdURL == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.invalidToken)
        #expect(store.createRequiresRefresh)
    }

    @Test("Without a credential vault, the live URL keeps its transport-provided scheme")
    func nonpersistentShareURLKeepsExistingSchemeBehavior() async {
        let transport = BlueprintLinkManagementTestTransport()
        transport.shareURLBuilder = { URL(string: "gatherory://template/\($0)") }
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()

        #expect(store.createdURL == URL(string: "gatherory://template/\(transport.created.token)"))
        #expect(!store.credentialSaveFailed)
        #expect(!store.createRequiresRefresh)
    }

    @Test("A legacy localhost link remains shareable when secure retention is unavailable")
    func localhostLinkDoesNotBecomeAnUncertainCreate() async {
        let transport = BlueprintLinkManagementTestTransport()
        transport.shareURLBuilder = { URL(string: "http://localhost/templates/shared/\($0)") }
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let store = makeStore(transport: transport, credentialStore: credentials)
        await prepare(store, transport: transport)
        #expect(store.canCreate)
        await store.create()
        #expect(store.createdURL == URL(string: "http://localhost/templates/shared/\(transport.created.token)"))
        #expect(store.credentialSaveFailed)
        #expect(!store.createRequiresRefresh)
        #expect(credentials.credentials.isEmpty)
        #expect(transport.createCount == 1)
    }

    @Test("A corrupt credential read allows retry or explicit replacement without automatic creation")
    func corruptCredentialReadIsRecoverable() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.loadError = BlueprintShareLinkCredentialStoreError.invalidRecord
        let store = makeStore(transport: transport, credentialStore: credentials)
        await store.loadTemplates()
        await store.select(templateID: transport.template.id)

        #expect(store.errorMessage == BlueprintCopy.shareLinkRestoreFailed)
        #expect(store.canCreate)
        #expect(transport.createCount == 0)
    }

    @Test("An unreadable saved credential can be explicitly replaced after successful authorization")
    func explicitReplacementRepairsUnreadableCredential() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.loadError = BlueprintShareLinkCredentialStoreError.invalidRecord
        let store = makeStore(transport: transport, credentialStore: credentials)
        await prepare(store, transport: transport)
        #expect(store.createdURL == nil)
        #expect(store.canCreate)
        #expect(transport.createCount == 0)
        await store.create()
        #expect(transport.createCount == 1)
        #expect(store.createdURL == transport.shareURL(token: transport.created.token))
        #expect(!store.credentialSaveFailed)
        #expect(store.errorMessage == nil)
    }

    @Test("A successful refresh clears a temporary credential read error and restores the saved URL")
    func credentialReadErrorCanRecoverOnRefresh() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let first = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(first, transport: transport)
        await first.create()
        transport.links = [transport.created.link]

        let reopened = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        credentials.loadError = BlueprintShareLinkCredentialStoreError.invalidRecord
        await reopened.loadTemplates()
        await reopened.select(templateID: transport.template.id)

        #expect(reopened.errorMessage == BlueprintCopy.shareLinkRestoreFailed)
        #expect(reopened.createdURL == nil)
        #expect(reopened.canCreate)
        #expect(transport.createCount == 1)

        credentials.loadError = nil
        await reopened.loadTemplates()
        #expect(reopened.errorMessage == nil)
        await reopened.loadLinks()

        #expect(reopened.createdURL == transport.shareURL(token: transport.created.token))
        #expect(reopened.createdToken == transport.created.token)
        #expect(reopened.errorMessage == nil)
        #expect(transport.createCount == 1)
    }

    @Test("An uncertain replacement stays blocked until an explicit successful refresh")
    func uncertainReplacementRemainsExplicit() async {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let store = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(store, transport: transport)
        await store.create()
        let currentURL = store.createdURL
        let currentToken = store.createdToken
        transport.links = [transport.created.link]
        transport.createError = true

        await store.create()
        #expect(store.createRequiresRefresh)
        #expect(store.createdURL == currentURL)
        #expect(store.createdToken == currentToken)
        let countAfterUncertainAttempt = transport.createCount
        await store.create()
        #expect(transport.createCount == countAfterUncertainAttempt)

        transport.createError = false
        await store.loadLinks()
        #expect(!store.createRequiresRefresh)
        #expect(store.createdURL == currentURL)
        #expect(store.createdToken == currentToken)
        #expect(transport.createCount == countAfterUncertainAttempt)
    }

    @Test("A replacement keeps the current URL and cached credential until acknowledgement")
    func replacementRetainsCurrentURLUntilAcknowledged() async throws {
        let transport = BlueprintLinkManagementTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let eventID = UUID()
        let store = makeStore(transport: transport, eventID: eventID, credentialStore: credentials)
        await prepare(store, transport: transport)
        await store.create()
        let oldResponse = transport.created
        let oldURL = try #require(store.createdURL)
        let oldToken = try #require(store.createdToken)
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "account-a", eventID: eventID, templateID: transport.template.id, shareURL: oldURL
        ))
        let oldCredential = try #require(credentials.credentials[scope])
        transport.links = [oldResponse.link]
        transport.created = BlueprintCreatedShareLink(
            link: BlueprintManagedShareLink(
                id: UUID(), revision: 3, createdAt: Date(timeIntervalSince1970: 1_800_000_001), revokedAt: nil
            ),
            token: String(repeating: "c9", count: 32)
        )
        let replacement = transport.created
        transport.holdCreate = true
        transport.createStarted = false

        let request = Task { await store.create() }
        let didStart = await waitUntil { transport.createStarted }
        try #require(didStart)

        #expect(store.createdURL == oldURL)
        #expect(store.createdToken == oldToken)
        #expect(credentials.credentials[scope] == oldCredential)

        transport.resumeCreate(.success(replacement))
        await request.value

        #expect(store.createdURL == transport.shareURL(token: replacement.token))
        #expect(store.createdToken == replacement.token)
        #expect(credentials.credentials[scope] == BlueprintShareLinkCredential(
            linkID: replacement.link.id, revision: replacement.link.revision, token: replacement.token
        ))
        #expect(store.links.contains(where: { $0.id == oldResponse.link.id && $0.revokedAt == nil }))
        #expect(store.links.contains(where: { $0.id == replacement.link.id && $0.revokedAt == nil }))
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

        await store.setDiscoverable(true, creatorName: "   ")
        #expect(transport.listingStarted == false)
        #expect(store.templates.first?.listedRevision == nil)
        #expect(store.templates.first?.creatorName == nil)
        #expect(store.errorMessage == BlueprintCopy.creatorNameInvalid)

        transport.listingError = true
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.templates.first?.listedRevision == nil)
        #expect(store.templates.first?.creatorName == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)

        transport.listingError = false
        transport.listingCreatorMismatch = true
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.templates.first?.listedRevision == nil)
        #expect(store.templates.first?.creatorName == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)

        transport.listingCreatorMismatch = false
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.templates.first?.listedRevision == 3)
        #expect(store.templates.first?.creatorName == "Garden Hosts")
        #expect(store.errorMessage == nil)

        await store.setDiscoverable(false)
        #expect(store.templates.first?.listedRevision == nil)
        #expect(store.templates.first?.creatorName == "Garden Hosts")
    }

    @Test("A late listing acknowledgement after account switching is discarded")
    func lateListingAfterAccountSwitch() async throws {
        let identity = BlueprintLinkTestAccount()
        let transport = BlueprintLinkManagementTestTransport()
        transport.holdListing = true
        let store = makeStore(transport: transport) { identity.id }
        await prepare(store, transport: transport)

        let request = Task { await store.setDiscoverable(true, creatorName: "Garden Hosts") }
        let didStart = await waitUntil { transport.listingStarted }
        try #require(didStart)
        identity.id = "account-b"
        transport.resumeListing(.success(3))
        await request.value

        #expect(store.templates.isEmpty)
        #expect(!store.isMutating)
    }

    @Test("Authentication and authorization denials clear transient link state")
    func denialsClearTransientState() async {
        let denials: [CloudSyncFailure] = [
            .invalidSession,
            .forbidden("EVENT_PERMISSION_REQUIRED"),
            .server("BLUEPRINT_NOT_FOUND"),
            .server("HTTP_404")
        ]

        for operation in DeniedOperation.allCases {
            for denial in denials {
                let transport = BlueprintLinkManagementTestTransport()
                let store = makeStore(transport: transport)
                await prepare(store, transport: transport)
                await store.create()
                #expect(store.createdURL != nil)

                switch operation {
                case .templates:
                    transport.templatesFailure = denial
                    await store.loadTemplates()
                case .links:
                    transport.linksFailure = denial
                    await store.loadLinks()
                case .revoke:
                    transport.revokeFailure = denial
                    await store.revoke(linkID: transport.created.link.id)
                case .listing:
                    transport.listingFailure = denial
                    await store.setDiscoverable(true, creatorName: "Garden Hosts")
                }

                #expect(store.createdURL == nil)
                #expect(store.createdToken == nil)
                #expect(store.templates.isEmpty)
                #expect(store.links.isEmpty)
                #expect(store.selectedTemplateID == nil)
                #expect(!store.hasLoadedLinks)
                let reads = transport.templateReadCount
                await store.loadTemplates()
                #expect(transport.templateReadCount == reads)
            }
        }
    }

    @Test("Network list failures retain a valid one-time link")
    func networkListFailureKeepsTransientState() async {
        let transport = BlueprintLinkManagementTestTransport()
        let store = makeStore(transport: transport)
        await prepare(store, transport: transport)
        await store.create()
        let url = store.createdURL
        let token = store.createdToken

        transport.linksError = true
        await store.loadLinks()

        #expect(store.createdURL == url)
        #expect(store.createdToken == token)
        #expect(store.selectedTemplateID == transport.template.id)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.requestFailed)
    }

    private func prepare(_ store: BlueprintLinkManagementStore, transport: BlueprintLinkManagementTestTransport) async {
        await store.loadTemplates()
        await store.select(templateID: transport.template.id)
    }

    private func makeStore(
        transport: BlueprintLinkManagementTestTransport,
        eventID: UUID = UUID(),
        accountID: String = "account-a",
        credentialStore: (any BlueprintShareLinkCredentialStore)? = nil,
        currentAccountID: @escaping @MainActor () -> String? = { "account-a" }
    ) -> BlueprintLinkManagementStore {
        BlueprintLinkManagementStore(
            eventID: eventID, accountID: accountID, transport: transport,
            credentialStore: credentialStore,
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

    private enum DeniedOperation: CaseIterable {
        case templates
        case links
        case revoke
        case listing
    }
}

@MainActor
private final class BlueprintLinkManagementTestTransport: BlueprintLinkManagementTransport {
    var template = BlueprintManagedTemplate(id: UUID(), title: "Wedding", publishedRevision: 3, retired: false)
    var templatesOverride: [BlueprintManagedTemplate]?
    var shareHost = "share.example.test"
    var shareURLBuilder: ((String) -> URL?)?
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
    var listingCreatorMismatch = false
    var holdListing = false
    var listingStarted = false
    var createCount = 0
    var templateReadCount = 0
    var templatesFailure: CloudSyncFailure?
    var linksFailure: CloudSyncFailure?
    var revokeFailure: CloudSyncFailure?
    var listingFailure: CloudSyncFailure?
    private var templateContinuation: CheckedContinuation<[BlueprintManagedTemplate], Error>?
    private var linksContinuation: CheckedContinuation<[BlueprintManagedShareLink], Error>?
    private var createContinuation: CheckedContinuation<BlueprintCreatedShareLink, Error>?
    private var listingContinuation: CheckedContinuation<Int?, Error>?

    func templates(eventID: UUID) async throws -> [BlueprintManagedTemplate] {
        templateReadCount += 1
        templatesStarted = true
        if holdTemplates {
            return try await withCheckedThrowingContinuation { templateContinuation = $0 }
        }
        if let templatesFailure { throw templatesFailure }
        return templatesOverride ?? [template]
    }

    func links(eventID: UUID, templateID: UUID) async throws -> [BlueprintManagedShareLink] {
        linksStarted = true
        if holdLinks {
            return try await withCheckedThrowingContinuation { linksContinuation = $0 }
        }
        if let linksFailure { throw linksFailure }
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
        if let revokeFailure { throw revokeFailure }
        if revokeError { throw BlueprintLinkManagementTestError.failed }
    }

    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int? {
        listingStarted = true
        if holdListing {
            return try await withCheckedThrowingContinuation { listingContinuation = $0 }
        }
        if let listingFailure { throw listingFailure }
        if listingError { throw BlueprintLinkManagementTestError.failed }
        return revision
    }

    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?, creatorName: String?) async throws -> BlueprintTemplateListingResult {
        let listedRevision = try await setTemplateListing(eventID: eventID, templateID: templateID, revision: revision)
        return BlueprintTemplateListingResult(
            listedRevision: listedRevision,
            creatorName: listingCreatorMismatch ? "Unexpected Name" : creatorName
        )
    }

    func shareURL(token: String) -> URL? {
        if let shareURLBuilder { return shareURLBuilder(token) }
        return URL(string: "https://\(shareHost)/templates/shared/\(token)")
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
