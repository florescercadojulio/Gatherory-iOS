import Testing
@testable import Gatherory

struct WorkspaceTabPolicyTests {
    @Test("Decision controls and Home keep workspace navigation expanded")
    func pinnedTabs() {
        #expect(WorkspaceTab.home.keepsTabBarExpanded)
        #expect(WorkspaceTab.decide.keepsTabBarExpanded)
        #expect(!WorkspaceTab.ideas.keepsTabBarExpanded)
        #expect(!WorkspaceTab.manage.keepsTabBarExpanded)
    }
}
