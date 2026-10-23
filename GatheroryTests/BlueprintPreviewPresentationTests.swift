import Testing
@testable import Gatherory

struct BlueprintPreviewPresentationTests {
    @Test("Discovery previews expose public preferences and keep Use in More")
    func discovery() {
        let presentation = BlueprintPreviewPresentation.resolve(
            requested: .discovery,
            currentAccountID: "account",
            actionStoreOwnerID: "account"
        )

        #expect(presentation.context == .discovery)
        #expect(presentation.showsPreferenceActions)
        #expect(presentation.showsUseInMore)
        #expect(!presentation.showsProminentUse)
        #expect(!presentation.allowsEditing)
        #expect(!presentation.allowsDraftSaving)
        #expect(!presentation.blocksInstalledDuplicate)
    }

    @Test("Collection previews are read-only with preferences and a prominent Use action")
    func collection() {
        let presentation = BlueprintPreviewPresentation.resolve(
            requested: .collection,
            currentAccountID: "account",
            actionStoreOwnerID: "account"
        )

        #expect(presentation.context == .collection)
        #expect(presentation.showsPreferenceActions)
        #expect(presentation.showsProminentUse)
        #expect(!presentation.showsUseInMore)
        #expect(!presentation.allowsEditing)
        #expect(!presentation.allowsDraftSaving)
    }

    @Test("Personal previews enable editing and draft saving only in Yours context")
    func personal() {
        let presentation = BlueprintPreviewPresentation.resolve(
            requested: .personal,
            currentAccountID: "account",
            actionStoreOwnerID: "account"
        )

        #expect(presentation.context == .personal)
        #expect(presentation.allowsEditing)
        #expect(presentation.allowsDraftSaving)
        #expect(!presentation.showsPreferenceActions)
        #expect(!presentation.showsUseInMore)
        #expect(!presentation.showsProminentUse)
    }

    @Test("Shared links stay read-only, suppress public preferences, and retain direct Use")
    func sharedLink() {
        let presentation = BlueprintPreviewPresentation.resolve(
            requested: .sharedLink,
            currentAccountID: "account",
            actionStoreOwnerID: "account",
            hasSharedToken: true
        )

        #expect(presentation.context == .sharedLink)
        #expect(!presentation.allowsEditing)
        #expect(!presentation.allowsDraftSaving)
        #expect(!presentation.showsPreferenceActions)
        #expect(!presentation.showsUseInMore)
        #expect(presentation.showsProminentUse)
    }

    @Test("Preference controls require the current account action store")
    func actionStoreIsRequired() {
        let discovery = BlueprintPreviewPresentation.resolve(requested: .discovery, currentAccountID: "account", actionStoreOwnerID: nil)
        let collection = BlueprintPreviewPresentation.resolve(requested: .collection, currentAccountID: "account", actionStoreOwnerID: nil)
        let staleAccountStore = BlueprintPreviewPresentation.resolve(
            requested: .discovery,
            currentAccountID: "current-account",
            actionStoreOwnerID: "previous-account"
        )

        #expect(!discovery.showsPreferenceActions)
        #expect(!collection.showsPreferenceActions)
        #expect(!staleAccountStore.showsPreferenceActions)
    }

    @Test("Explicit legacy source flags override a contradictory public context")
    func legacySourceFlagsFailClosed() {
        let installed = BlueprintPreviewPresentation.resolve(
            requested: .discovery,
            currentAccountID: "account",
            actionStoreOwnerID: "account",
            hasInstalledSource: true
        )
        let personal = BlueprintPreviewPresentation.resolve(
            requested: .discovery,
            currentAccountID: "account",
            actionStoreOwnerID: "account",
            hasPersonalSource: true
        )
        let shared = BlueprintPreviewPresentation.resolve(
            requested: .discovery,
            currentAccountID: "account",
            actionStoreOwnerID: "account",
            hasSharedToken: true
        )
        let savedWorkingCopy = BlueprintPreviewPresentation.resolve(
            requested: .personal,
            currentAccountID: "account",
            actionStoreOwnerID: "account",
            hasInstalledSource: true,
            hasSharedToken: true
        )

        #expect(installed.context == .personal)
        #expect(installed.allowsEditing)
        #expect(!installed.showsProminentUse)
        #expect(installed.blocksInstalledDuplicate)
        #expect(personal.context == .personal)
        #expect(personal.allowsEditing)
        #expect(!personal.showsPreferenceActions)
        #expect(personal.blocksInstalledDuplicate)
        #expect(shared.context == .sharedLink)
        #expect(!shared.allowsEditing)
        #expect(!shared.showsPreferenceActions)
        #expect(shared.showsProminentUse)
        #expect(!shared.blocksInstalledDuplicate)
        #expect(savedWorkingCopy.context == .personal)
        #expect(savedWorkingCopy.allowsEditing)
        #expect(savedWorkingCopy.blocksInstalledDuplicate)
    }

    @Test("Like or bookmark surface context never grants personal editing")
    func collectionSignalsDoNotGrantOwnership() {
        let liked = BlueprintPreviewPresentation.resolve(requested: .collection, currentAccountID: "account",
            actionStoreOwnerID: "account")
        let bookmarked = BlueprintPreviewPresentation.resolve(requested: .collection, currentAccountID: "account",
            actionStoreOwnerID: "account")

        #expect(!liked.allowsEditing)
        #expect(!bookmarked.allowsEditing)
        #expect(!liked.allowsDraftSaving)
        #expect(!bookmarked.allowsDraftSaving)
    }
}
