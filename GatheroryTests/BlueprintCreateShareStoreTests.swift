import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct BlueprintCreateShareStoreTests {
    @Test("Save Blueprint creates a private copy without listing it or making a share link")
    func savePrivately() async {
        let transport = CaptureTestTransport()
        let store = BlueprintCreateShareStore(eventID: transport.root, accountID: "a", transport: transport,
            publishesToSearch: false, createsShareLink: false, currentAccountID: { "a" })
        await store.load()
        await store.review()

        #expect(store.reviewed != nil)
        #expect(transport.reviews.first?.discoverable == false)
        #expect(transport.creates.isEmpty)
        #expect(transport.linkCreates == 0)
        #expect(transport.listingRevisions.isEmpty)

        await store.createAndShare()

        #expect(store.created != nil)
        #expect(transport.creates.count == 1)
        #expect(transport.reviews.first?.discoverable == false)
        #expect(transport.creates.first?.discoverable == false)
        #expect(transport.linkCreates == 0)
        #expect(transport.listingRevisions.isEmpty)
        #expect(store.createdURL == nil)
    }
    @Test("Opening capture selects all supported content and notes without publishing")
    func defaultSelectionAndNoWrites() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        #expect(store.selectedChildIDs == Set(transport.source.source.children.map(\.id)))
        #expect(store.selectedIdeaIDs == Set(transport.source.source.ideas.map(\.id)))
        #expect(store.selectedInstructionIDs == Set(transport.source.source.instructions.map(\.id)))
        #expect(store.selectedTodoIDs.isEmpty)
        #expect(store.eligibleTodos.count == 2)
        #expect(store.includeIdeaNotes)
        #expect(store.canReview)
        #expect(store.reviewed == nil)
        #expect(transport.creates.isEmpty && transport.linkCreates == 0)
        await store.createAndShare()
        #expect(transport.creates.isEmpty)
    }

    @Test("To-do selection is explicit, exact-event scoped, and pruned with a deselected child")
    func todoSelectionIsExplicitAndScoped() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()

        #expect(store.selectedTodoIDs.isEmpty)
        let allTodoIDs = Set(transport.source.source.todos.map(\.id))
        store.setIncludeTodos(true)
        #expect(store.selectedTodoIDs == allTodoIDs)
        #expect(store.reviewed == nil)

        let rootTodo = try #require(transport.source.source.todos.first { $0.eventId == transport.root })
        let childTodo = try #require(transport.source.source.todos.first { $0.eventId == transport.child })
        store.setChild(transport.child, included: false)
        #expect(store.selectedTodoIDs == [rootTodo.id])
        store.setTodo(childTodo.id, included: true)
        #expect(store.selectedTodoIDs == [rootTodo.id])
        store.setIncludeTodos(false)
        #expect(store.selectedTodoIDs.isEmpty)

        store.setChild(transport.child, included: true)
        store.setTodo(childTodo.id, included: true)
        await store.review()
        #expect(transport.reviews.last?.selection.todoIds == [childTodo.id])

        let emptySelection = BlueprintCaptureSelection(childIds: [], ideaIds: [], instructionIds: [], includeIdeaNotes: true)
        let emptyWire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(emptySelection)) as? [String: Any])
        #expect(emptyWire["todoIds"] == nil)
        let selectedWire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(transport.reviews.last!.selection)) as? [String: Any])
        #expect((selectedWire["todoIds"] as? [String]) == [childTodo.id.uuidString.lowercased()])
    }

    @Test("A reviewed share stays unlisted and creates its link only after explicit create")
    func reviewedPreparationIsReadOnlyUntilExplicitCreate() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)

        await store.load()
        store.setChild(transport.child, included: false)
        store.setIdea(transport.source.source.ideas[0].id, included: true)
        store.setInstruction(transport.source.source.instructions[0].id, included: false)
        await store.review()

        let review = try #require(transport.reviews.last)
        #expect(review.selection.childIds.isEmpty)
        #expect(review.selection.ideaIds == [transport.source.source.ideas[0].id])
        #expect(review.selection.instructionIds.isEmpty)
        #expect(review.selection.includeIdeaNotes)
        #expect(!review.discoverable)
        #expect(store.reviewed?.discoverable == false)
        #expect(store.created == nil && store.createdURL == nil)
        #expect(transport.creates.isEmpty && transport.linkCreates == 0)

        await store.createAndShare()

        let creation = try #require(transport.creates.first)
        #expect(creation.selection == review.selection)
        #expect(creation.expectedSourceHash == review.expectedSourceHash)
        #expect(creation.expectedReviewHash == store.reviewed?.reviewHash)
        #expect(!creation.discoverable)
        #expect(store.created != nil && store.createdURL != nil)
        #expect(store.listedRevision == nil)
        #expect(transport.creates.count == 1 && transport.linkCreates == 1)
    }

    @Test("Replacement requires an explicit action and preserves the current link until acknowledgement")
    func explicitReplacementPreservesCurrentLink() async throws {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let store = makeStore(transport, publishesToSearch: true, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()

        let oldURL = try #require(store.createdURL)
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner", eventID: transport.root, templateID: transport.templateID, shareURL: oldURL
        ))
        #expect(store.canReplaceShareLink)
        #expect(try credentials.load(scope)?.token == String(repeating: "c", count: 64))

        transport.nextLinkResponse = transport.replacementLinkResponse(revision: 1)
        await store.createAndShare()
        #expect(store.createdURL == oldURL)
        #expect(transport.linkCreates == 1)
        #expect(transport.nextLinkResponse != nil)

        transport.holdLink = true
        transport.linkStarted = false
        let replacement = Task { await store.replaceShareLink() }
        let didStart = await waitUntil { transport.linkStarted }
        try #require(didStart)

        #expect(store.createdURL == oldURL)
        #expect(store.listedRevision == 1)
        #expect(try credentials.load(scope)?.token == String(repeating: "c", count: 64))
        #expect(!store.canReplaceShareLink)

        let replacementResponse = try #require(transport.nextLinkResponse)
        transport.nextLinkResponse = nil
        transport.resumeLink(.success(replacementResponse))
        await replacement.value

        #expect(store.createdURL != oldURL)
        #expect(store.listedRevision == 1)
        #expect(store.createdLinks.count == 2)
        #expect(try credentials.load(scope)?.token == String(repeating: "d", count: 64))
        #expect(transport.creates.count == 1)
        #expect(transport.linkCreates == 2)

        let replacementURL = try #require(store.createdURL)
        await store.createAndShare()
        #expect(store.createdURL == replacementURL)
        #expect(transport.linkCreates == 2)
    }

    @Test("An uncertain replacement keeps the old URL until a successful refresh")
    func uncertainReplacementKeepsOldURLUntilRefresh() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        await store.createAndShare()
        let oldURL = try #require(store.createdURL)

        transport.failLink = true
        await store.replaceShareLink()
        #expect(store.createdURL == oldURL)
        #expect(store.requiresLinkRefresh)
        #expect(!store.canReplaceShareLink)
        #expect(transport.creates.count == 1)
        #expect(transport.linkCreates == 2)

        transport.failLink = false
        await store.replaceShareLink()
        #expect(transport.linkCreates == 2)
        #expect(store.createdURL == oldURL)

        await store.refreshCreatedLinks()
        #expect(!store.requiresLinkRefresh)
        #expect(store.createdURL == oldURL)
        #expect(store.canReplaceShareLink)

        transport.nextLinkResponse = transport.replacementLinkResponse(revision: 1)
        await store.replaceShareLink()
        #expect(store.createdURL != oldURL)
        #expect(transport.creates.count == 1)
        #expect(transport.linkCreates == 3)
    }

    @Test("A late replacement response after account switching is discarded")
    func switchedAccountDuringReplacement() async throws {
        let transport = CaptureTestTransport()
        let identity = CaptureTestIdentity()
        let store = makeStore(transport) { identity.id }
        await store.load()
        await store.review()
        await store.createAndShare()
        let oldURL = try #require(store.createdURL)

        transport.nextLinkResponse = transport.replacementLinkResponse(revision: 1)
        transport.holdLink = true
        transport.linkStarted = false
        let replacement = Task { await store.replaceShareLink() }
        let didStart = await waitUntil { transport.linkStarted }
        try #require(didStart)
        identity.id = "other"
        let replacementResponse = try #require(transport.nextLinkResponse)
        transport.nextLinkResponse = nil
        transport.resumeLink(.success(replacementResponse))
        await replacement.value

        #expect(store.created == nil && store.createdURL == nil)
        #expect(store.createdLinks.isEmpty)
        #expect(oldURL.absoluteString.contains("/templates/shared/"))
        #expect(transport.creates.count == 1 && transport.linkCreates == 2)
    }

    @Test("Search visibility can be toggled without recreating the blueprint or share link")
    func searchVisibilityDoesNotRecreateShareLink() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        await store.createAndShare()
        let url = try #require(store.createdURL)
        let templateCount = transport.creates.count
        let linkCount = transport.linkCreates

        await store.setDiscoverable(true, creatorName: "Garden Hosts")

        #expect(store.listedRevision == 1)
        #expect(transport.listingRevisions == [1])
        #expect(store.createdURL == url)

        await store.setDiscoverable(false)

        #expect(store.listedRevision == nil)
        #expect(transport.listingRevisions == [1, nil])
        #expect(store.createdURL == url)
        #expect(transport.creates.count == templateCount)
        #expect(transport.linkCreates == linkCount)

        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        await store.revokeCreatedLink(transport.linkID)
        #expect(store.createdURL == nil)
        await store.createAndShare()
        #expect(store.listedRevision == 1)
        #expect(transport.creates.count == templateCount)
        #expect(transport.linkCreates == linkCount + 1)
    }

    @Test("A blueprint reviewed for Search starts with its published revision listed")
    func initiallyListedBlueprintTracksItsRevision() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport, publishesToSearch: true)
        await store.load()
        await store.review()
        #expect(store.reviewed?.discoverable == true)
        await store.createAndShare()

        #expect(transport.reviews.last?.discoverable == true)
        #expect(transport.creates.first?.discoverable == true)
        #expect(store.listedRevision == 1)
        #expect(transport.listingRevisions.isEmpty)
        #expect(transport.creates.count == 1 && transport.linkCreates == 1)
    }

    @Test("Listing failures and mismatched acknowledgements preserve the share state")
    func listingFailuresPreserveShareState() async throws {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        await store.createAndShare()
        let url = try #require(store.createdURL)

        await store.setDiscoverable(true, creatorName: "  ")
        #expect(transport.listingRevisions.isEmpty)
        #expect(store.listedRevision == nil)
        #expect(store.publicCreatorName == nil)
        #expect(store.errorMessage == BlueprintCopy.creatorNameInvalid)

        transport.listingFailure = URLError(.notConnectedToInternet)
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.listedRevision == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)
        #expect(store.createdURL == url)

        transport.listingFailure = nil
        transport.listingMismatch = true
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.listedRevision == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)
        #expect(store.createdURL == url)

        transport.listingMismatch = false
        transport.listingCreatorMismatch = true
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.listedRevision == nil)
        #expect(store.publicCreatorName == nil)
        #expect(store.errorMessage == BlueprintLinkManagementMessage.listingFailed)

        transport.listingCreatorMismatch = false
        await store.setDiscoverable(true, creatorName: "Garden Hosts")
        #expect(store.listedRevision == 1)
        #expect(store.publicCreatorName == "Garden Hosts")
        #expect(store.errorMessage == nil)
        #expect(store.createdURL == url)
        #expect(transport.creates.count == 1 && transport.linkCreates == 1)
    }

    @Test("A stale listing acknowledgement after account switching is discarded")
    func switchedAccountDuringListing() async throws {
        let transport = CaptureTestTransport()
        let identity = CaptureTestIdentity()
        let store = makeStore(transport) { identity.id }
        await store.load()
        await store.review()
        await store.createAndShare()
        #expect(store.createdURL != nil)

        transport.holdListing = true
        let request = Task { await store.setDiscoverable(true, creatorName: "Garden Hosts") }
        let didStart = await waitUntil { transport.listingStarted }
        try #require(didStart)
        identity.id = "other"
        transport.resumeListing(.success(1))
        await request.value

        #expect(store.listedRevision == nil)
        #expect(store.created == nil && store.createdURL == nil)
        #expect(transport.creates.count == 1 && transport.linkCreates == 1)
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

    @Test("An A to B to A account change invalidates an in-flight source response")
    func accountReturnsAfterInvalidation() async throws {
        let identity = CaptureTestIdentity()
        let transport = CaptureTestTransport()
        transport.holdSource = true
        let store = makeStore(transport) { identity.id }

        let request = Task { await store.load() }
        let didStart = await waitUntil { transport.sourceStarted }
        try #require(didStart)
        identity.id = "other"
        store.invalidate()
        identity.id = "owner"
        transport.resumeSource(.success(transport.source))
        await request.value

        #expect(store.source == nil)
        #expect(store.createdURL == nil)
        #expect(transport.sourceReads == 1)
        await store.load()
        #expect(transport.sourceReads == 1)
    }

    @Test("Invalidating a successful share clears transient state but retains the scoped credential")
    func invalidateClearsShareURL() async {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let store = makeStore(transport, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()
        #expect(store.createdURL != nil)
        let scope = BlueprintShareLinkCredentialScope.make(
            accountID: "owner", eventID: transport.root, templateID: transport.templateID,
            shareURL: store.createdURL!
        )!
        let savedCredential = try? credentials.load(scope)
        #expect(savedCredential != nil)

        store.invalidate()

        #expect(store.createdURL == nil)
        #expect(store.created == nil)
        #expect(store.createdLinks.isEmpty)
        #expect(!store.requiresLinkRefresh)
        #expect((try? credentials.load(scope)) == savedCredential)
        await store.load()
        #expect(transport.sourceReads == 1)
    }

    @Test("A failed credential save can be retried locally without creating another link")
    func credentialSaveRetryIsLocalOnly() async throws {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.saveError = CaptureCredentialTestFailure.save
        let store = makeStore(transport, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()

        let url = try #require(store.createdURL)
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner", eventID: transport.root, templateID: transport.templateID, shareURL: url
        ))
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)
        #expect(try credentials.load(scope) == nil)
        let createCount = transport.creates.count
        let linkCreateCount = transport.linkCreates

        credentials.saveError = nil
        store.retrySavingLink()

        #expect(!store.credentialSaveFailed)
        #expect(store.errorMessage == nil)
        #expect(try credentials.load(scope)?.token == String(repeating: "c", count: 64))
        #expect(transport.creates.count == createCount)
        #expect(transport.linkCreates == linkCreateCount)
        #expect(transport.linkLists == 0)
    }

    @Test("Refreshing an active link preserves its pending credential-save warning")
    func refreshPreservesPendingCredentialWarning() async {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.saveError = CaptureCredentialTestFailure.save
        let store = makeStore(transport, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)

        await store.refreshCreatedLinks()

        #expect(store.createdURL != nil)
        #expect(store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkSaveFailed)
    }

    @Test("A stale account cannot retry saving a live share credential")
    func staleAccountCannotSaveCredential() async {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        credentials.saveError = CaptureCredentialTestFailure.save
        let identity = CaptureTestIdentity()
        let store = makeStore(transport, credentialStore: credentials) { identity.id }
        await store.load()
        await store.review()
        await store.createAndShare()
        #expect(store.createdURL != nil && store.credentialSaveFailed)

        identity.id = "other"
        store.retrySavingLink()

        #expect(transport.linkCreates == 1)
        #expect(credentials.credentials.isEmpty)
    }

    @Test("A refreshed missing or revoked link clears its cached credential")
    func refreshRemovesMissingCredential() async throws {
        for isRevoked in [false, true] {
            let transport = CaptureTestTransport()
            let credentials = MemoryBlueprintShareLinkCredentialStore()
            let store = makeStore(transport, credentialStore: credentials)
            await store.load()
            await store.review()
            await store.createAndShare()
            let url = try #require(store.createdURL)
            let scope = try #require(BlueprintShareLinkCredentialScope.make(
                accountID: "owner", eventID: transport.root, templateID: transport.templateID, shareURL: url
            ))
            #expect(try credentials.load(scope) != nil)

            transport.linkResponse = isRevoked ? [
                .init(id: transport.linkID, revision: 1, createdAt: .now, revokedAt: Date())
            ] : []
            await store.refreshCreatedLinks()

            #expect(store.createdURL == nil)
            #expect(try credentials.load(scope) == nil)
        }
    }

    @Test("A failed credential removal hides the revoked URL and can be retried by refresh")
    func failedCredentialRemovalNeverKeepsURL() async throws {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let store = makeStore(transport, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()
        let url = try #require(store.createdURL)
        let id = try #require(store.createdLinks.first?.id)
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner", eventID: transport.root, templateID: transport.templateID, shareURL: url
        ))
        credentials.removeError = CaptureCredentialTestFailure.remove

        await store.revokeCreatedLink(id)

        #expect(store.createdURL == nil)
        #expect(!store.credentialSaveFailed)
        #expect(store.errorMessage == BlueprintCopy.shareLinkStorageFailed)
        #expect(try credentials.load(scope)?.linkID == id)

        credentials.removeError = nil
        transport.linkResponse = [.init(id: id, revision: 1, createdAt: .now, revokedAt: Date())]
        await store.refreshCreatedLinks()
        #expect(try credentials.load(scope) == nil)
        #expect(store.createdURL == nil)
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

    @Test("Authentication and authorization denials clear transient share state")
    func deniedRefreshClearsTransientState() async throws {
        let denials: [CloudSyncFailure] = [
            .invalidSession,
            .forbidden("EVENT_PERMISSION_REQUIRED"),
            .server("BLUEPRINT_NOT_FOUND"),
            .server("HTTP_404")
        ]

        for denial in denials {
            let transport = CaptureTestTransport()
            let credentials = MemoryBlueprintShareLinkCredentialStore()
            let store = makeStore(transport, credentialStore: credentials)
            await store.load()
            await store.review()
            await store.createAndShare()
            let url = try #require(store.createdURL)
            let scope = try #require(BlueprintShareLinkCredentialScope.make(
                accountID: "owner", eventID: transport.root, templateID: transport.templateID, shareURL: url
            ))
            #expect(try credentials.load(scope) != nil)

            transport.listFailure = denial
            await store.refreshCreatedLinks()

            #expect(store.source == nil)
            #expect(store.reviewed == nil)
            #expect(store.created == nil)
            #expect(store.createdURL == nil)
            #expect(store.createdLinks.isEmpty)
            #expect(!store.requiresLinkRefresh)
            if case .invalidSession = denial {
                #expect(try credentials.load(scope) != nil)
            } else {
                #expect(try credentials.load(scope) == nil)
            }
            await store.load()
            #expect(transport.sourceReads == 1)
        }
    }

    @Test("A network refresh failure preserves the current share URL")
    func networkRefreshFailureKeepsTransientState() async {
        let transport = CaptureTestTransport()
        let store = makeStore(transport)
        await store.load()
        await store.review()
        await store.createAndShare()
        let url = store.createdURL

        transport.failList = true
        await store.refreshCreatedLinks()

        #expect(store.createdURL == url)
        #expect(store.created != nil)
        #expect(!store.requiresLinkRefresh)
        #expect(store.errorMessage == BlueprintCopy.templateCreationLinkUncertain)
    }

    @Test("Revocation only changes the displayed link after acknowledgement")
    func confirmedRevocation() async throws {
        let transport = CaptureTestTransport()
        let credentials = MemoryBlueprintShareLinkCredentialStore()
        let store = makeStore(transport, credentialStore: credentials)
        await store.load()
        await store.review()
        await store.createAndShare()
        let id = try #require(store.createdLinks.first?.id)
        let shareURL = try #require(store.createdURL)
        let scope = try #require(BlueprintShareLinkCredentialScope.make(
            accountID: "owner", eventID: transport.root, templateID: transport.templateID,
            shareURL: shareURL
        ))
        #expect(try credentials.load(scope)?.linkID == id)
        transport.failRevoke = true
        await store.revokeCreatedLink(id)
        #expect(store.createdURL != nil && store.createdLinks[0].revokedAt == nil)
        #expect(try credentials.load(scope)?.linkID == id)
        transport.failRevoke = false
        await store.revokeCreatedLink(id)
        #expect(store.createdURL == nil && store.createdLinks[0].revokedAt != nil)
        #expect(try credentials.load(scope) == nil)
    }

    private func makeStore(_ transport: CaptureTestTransport,
        publishesToSearch: Bool = false,
        createsShareLink: Bool = true,
        credentialStore: (any BlueprintShareLinkCredentialStore)? = nil,
        account: @escaping @MainActor () -> String? = { "owner" }) -> BlueprintCreateShareStore {
        BlueprintCreateShareStore(eventID: transport.source.source.event.id, accountID: "owner",
            transport: transport, publishesToSearch: publishesToSearch, createsShareLink: createsShareLink,
            credentialStore: credentialStore, currentAccountID: account)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
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
    var linkLists = 0
    var listingRevisions: [Int?] = []
    var listingStarted = false
    var sourceStarted = false
    var holdSource = false
    var holdListing = false
    var holdLink = false
    var linkStarted = false
    var listingMismatch = false
    var listingCreatorMismatch = false
    var reviews: [BlueprintNativeReviewInput] = []
    var creates: [BlueprintNativeCreateInput] = []
    var failCreation = false
    var sourceChanged = false
    var failLink = false
    var failList = false
    var failRevoke = false
    var reviewForbidden = false
    var listFailure: CloudSyncFailure?
    var listingFailure: Error?
    var linkResponse: [BlueprintManagedShareLink]?
    var nextLinkResponse: BlueprintCreatedShareLink?
    var afterSource: (() -> Void)?
    var afterCreate: (() -> Void)?
    private var sourceContinuation: CheckedContinuation<BlueprintCaptureSourceResponse, Error>?
    private var listingContinuation: CheckedContinuation<Int?, Error>?
    private var linkContinuation: CheckedContinuation<BlueprintCreatedShareLink, Error>?
    lazy var source = BlueprintCaptureSourceResponse(source: BlueprintCaptureSource(
        event: .init(id: root, title: "Our Wedding", startsAt: nil, timeZone: "America/Detroit", experienceType: "wedding"),
        children: [.init(id: child, title: "Dinner", purpose: "part_of_event", category: "food", startsAt: nil)],
        ideas: [.init(id: UUID(), eventId: root, title: "Flowers", category: "decoration", notes: "Private florist details"),
                .init(id: UUID(), eventId: child, title: "Cake", category: "food", notes: nil)],
        instructions: [.init(id: UUID(), eventId: child, title: "Arrival", body: "Use side entrance", audience: "event_participants")],
        todos: [.init(id: rootTodo, eventId: root, title: "Confirm venue", websiteURL: nil),
                .init(id: childTodo, eventId: child, title: "Pack supplies", websiteURL: "https://example.com")]),
        sourceHash: String(repeating: "a", count: 64))
    let rootTodo = UUID()
    let childTodo = UUID()

    func captureSource(eventID: UUID) async throws -> BlueprintCaptureSourceResponse {
        sourceReads += 1
        sourceStarted = true
        if holdSource {
            return try await withCheckedThrowingContinuation { sourceContinuation = $0 }
        }
        afterSource?()
        return source
    }
    func resumeSource(_ result: Result<BlueprintCaptureSourceResponse, Error>) {
        sourceContinuation?.resume(with: result)
        sourceContinuation = nil
    }
    func resumeListing(_ result: Result<Int?, Error>) {
        listingContinuation?.resume(with: result)
        listingContinuation = nil
    }
    func resumeLink(_ result: Result<BlueprintCreatedShareLink, Error>) {
        linkContinuation?.resume(with: result)
        linkContinuation = nil
    }
    func replacementLinkResponse(revision: Int) -> BlueprintCreatedShareLink {
        .init(
            link: .init(id: UUID(), revision: revision, createdAt: .now, revokedAt: nil),
            token: String(repeating: "d", count: 64)
        )
    }
    func reviewCapture(_ input: BlueprintNativeReviewInput) async throws -> BlueprintCaptureReview {
        reviews.append(input)
        if reviewForbidden { throw CloudSyncFailure.forbidden(nil) }
        return BlueprintCaptureReview(content: .init(name: input.name, description: "", experienceType: "wedding",
            children: [], ideas: [], instructions: []), sourceHash: input.expectedSourceHash, reviewHash: String(repeating: "b", count: 64), discoverable: input.discoverable)
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
        linkLists += 1
        if let listFailure { throw listFailure }
        if failList { throw URLError(.notConnectedToInternet) }
        return linkResponse ?? [.init(id: linkID, revision: 1, createdAt: .now, revokedAt: nil)]
    }
    func createLink(eventID: UUID, templateID: UUID, revision: Int) async throws -> BlueprintCreatedShareLink {
        linkCreates += 1
        linkStarted = true
        if holdLink {
            return try await withCheckedThrowingContinuation { linkContinuation = $0 }
        }
        if failLink { throw URLError(.networkConnectionLost) }
        if let nextLinkResponse {
            self.nextLinkResponse = nil
            return nextLinkResponse
        }
        return .init(link: .init(id: linkID, revision: revision, createdAt: .now, revokedAt: nil), token: String(repeating: "c", count: 64))
    }
    func revokeLink(eventID: UUID, templateID: UUID, linkID: UUID) async throws {
        if failRevoke { throw URLError(.notConnectedToInternet) }
    }
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?) async throws -> Int? {
        listingRevisions.append(revision)
        listingStarted = true
        if holdListing {
            return try await withCheckedThrowingContinuation { listingContinuation = $0 }
        }
        if let listingFailure { throw listingFailure }
        return listingMismatch ? revision.map { $0 + 1 } : revision
    }
    func setTemplateListing(eventID: UUID, templateID: UUID, revision: Int?, creatorName: String?) async throws -> BlueprintTemplateListingResult {
        let listedRevision = try await setTemplateListing(eventID: eventID, templateID: templateID, revision: revision)
        return BlueprintTemplateListingResult(
            listedRevision: listedRevision,
            creatorName: listingCreatorMismatch ? "Unexpected Name" : creatorName
        )
    }
    func shareURL(token: String) -> URL? { URL(string: "https://example.test/templates/shared/\(token)") }
}

private enum CaptureCredentialTestFailure: Error {
    case save
    case remove
}
