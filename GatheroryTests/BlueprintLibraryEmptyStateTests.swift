import Testing
@testable import Gatherory

@MainActor
struct BlueprintLibraryEmptyStateTests {
    @Test("Each empty collection describes its content and offers the opposite destination")
    func contentAndSwitch() {
        var switches = 0
        let installed = BlueprintLibraryEmptyState(collection: .installedTemplates) { switches += 1 }
        let drafts = BlueprintLibraryEmptyState(collection: .inProgress) { switches += 1 }
        #expect(installed.title != drafts.title)
        #expect(installed.message != drafts.message)
        #expect(installed.actionTitle != drafts.actionTitle)
        #expect(installed.symbol != drafts.symbol)
        installed.onSwitchCollection()
        drafts.onSwitchCollection()
        #expect(switches == 2)
    }
}
