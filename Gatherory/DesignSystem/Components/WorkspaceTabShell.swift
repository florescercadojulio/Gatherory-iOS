import SwiftUI

enum WorkspaceTab: Hashable {
    case home, ideas, decide, manage
}

/// Shared navigation chrome; callers own data, navigation stacks and actions.
struct WorkspaceTabShell<Home: View, Ideas: View, Decide: View, Manage: View>: View {
    @Binding var selection: WorkspaceTab
    var showsManage: Bool
    @ViewBuilder var home: () -> Home
    @ViewBuilder var ideas: () -> Ideas
    @ViewBuilder var decide: () -> Decide
    @ViewBuilder var manage: () -> Manage

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppCopy.Tab.home, systemImage: "house.fill", value: .home) { home() }
            Tab(AppCopy.Tab.ideas, systemImage: "sparkles.rectangle.stack.fill", value: .ideas) { ideas() }
            Tab(AppCopy.Tab.decide, systemImage: "rectangle.on.rectangle.angled", value: .decide) { decide() }
            if showsManage {
                Tab(AppCopy.Tab.manage, systemImage: "slider.horizontal.3", value: .manage) { manage() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(selection == .home || selection == .decide ? .never : .onScrollDown)
    }
}
