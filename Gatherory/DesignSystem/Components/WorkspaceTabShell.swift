import SwiftUI

enum WorkspaceTab: Hashable {
    case home, ideas, decide

    var keepsTabBarExpanded: Bool { self == .home || self == .decide }
}

/// Shared navigation chrome; callers own data, navigation stacks and actions.
struct WorkspaceTabShell<Home: View, Ideas: View, Decide: View>: View {
    @Binding var selection: WorkspaceTab
    var showsDecide = true
    var showsIdeasEventFilter = false
    var customIdeasAccessory: AnyView? = nil
    @State private var ideasScope: IdeasScope = .all
    @ViewBuilder var home: () -> Home
    @ViewBuilder var ideas: (Binding<IdeasScope>) -> Ideas
    @ViewBuilder var decide: () -> Decide

    private var showsEventAccessory: Bool {
        showsIdeasEventFilter && selection == .ideas
    }

    private func selectVisibleTab() {
        if !showsDecide, selection == .decide {
            selection = .home
        }
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.1, *) {
            tabContents
                .onAppear(perform: selectVisibleTab)
                .onChange(of: showsDecide) { _, _ in selectVisibleTab() }
                .onChange(of: selection) { _, _ in selectVisibleTab() }
                .tabViewBottomAccessory(isEnabled: showsEventAccessory) {
                    if let customIdeasAccessory {
                        customIdeasAccessory
                    } else {
                        IdeasEventScopeAccessory(scope: $ideasScope)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(selection.keepsTabBarExpanded ? .never : .onScrollDown)
        } else {
            tabContents
                .onAppear(perform: selectVisibleTab)
                .onChange(of: showsDecide) { _, _ in selectVisibleTab() }
                .onChange(of: selection) { _, _ in selectVisibleTab() }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(selection.keepsTabBarExpanded ? .never : .onScrollDown)
        }
    }

    private var tabContents: some View {
        TabView(selection: $selection) {
            Tab(AppCopy.Tab.home, systemImage: "house.fill", value: .home) { home() }
            Tab(AppCopy.Tab.ideas, systemImage: "sparkles.rectangle.stack.fill", value: .ideas) { ideas($ideasScope) }
            if showsDecide {
                Tab(AppCopy.Tab.decide, systemImage: "rectangle.on.rectangle.angled", value: .decide) { decide() }
            }
        }
    }
}
