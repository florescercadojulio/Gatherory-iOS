import Foundation
import Testing
@testable import Gatherory

struct BlueprintLibraryCollectionSelectionTests {
    @Test("An empty collection offers the other collection in both directions")
    func emptyCollectionSwitch() {
        #expect(BlueprintLibraryCollection.installedTemplates.other == .inProgress)
        #expect(BlueprintLibraryCollection.inProgress.other == .installedTemplates)
        for collection in BlueprintLibraryCollection.allCases {
            #expect(collection.other.other == collection)
        }
    }
    @Test("No preference chooses the collection that has content")
    func noPreference() {
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: nil,
            hasInstalledTemplates: false,
            hasInProgressContent: true
        ) == .inProgress)
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: nil,
            hasInstalledTemplates: true,
            hasInProgressContent: false
        ) == .installedTemplates)
    }

    @Test("Recent collection is kept when it has content")
    func recentCollectionWithContent() {
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: .inProgress,
            hasInstalledTemplates: true,
            hasInProgressContent: true
        ) == .inProgress)
    }

    @Test("Empty recent collection falls back to the other collection with content")
    func recentEmptyFallback() {
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: .installedTemplates,
            hasInstalledTemplates: false,
            hasInProgressContent: true
        ) == .inProgress)
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: .inProgress,
            hasInstalledTemplates: true,
            hasInProgressContent: false
        ) == .installedTemplates)
    }

    @Test("When both collections are empty, retain the preference or default to installed")
    func bothEmpty() {
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: .inProgress,
            hasInstalledTemplates: false,
            hasInProgressContent: false
        ) == .inProgress)
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: nil,
            hasInstalledTemplates: false,
            hasInProgressContent: false
        ) == .installedTemplates)
    }

    @Test("Pending installation recovery counts as in-progress content")
    func pendingRecoveryCountsAsContent() {
        #expect(BlueprintLibraryCollectionSelection.resolve(
            preferred: .installedTemplates,
            hasInstalledTemplates: false,
            hasInProgressContent: true
        ) == .inProgress)
    }

    @Test("Preferences remain isolated by authenticated owner")
    func ownerIsolation() {
        let suite = "BlueprintLibraryCollectionPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BlueprintLibraryCollectionPreferenceStore(defaults: defaults)

        store.save(.inProgress, ownerID: "account-a")
        store.save(.installedTemplates, ownerID: "account-b")

        #expect(store.collection(ownerID: "account-a") == .inProgress)
        #expect(store.collection(ownerID: "account-b") == .installedTemplates)
        #expect(store.collection(ownerID: "account-c") == nil)
    }
}
