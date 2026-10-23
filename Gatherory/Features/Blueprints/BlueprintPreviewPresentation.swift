import SwiftUI

extension EnvironmentValues {
    /// Root-owned presentation state lets preview/setup dismiss before the
    /// installed workspace opens, including setup resumed from the library.
    @Entry var blueprintPreviewPresented: Binding<Bool> = .constant(false)
}

/// Determines which actions belong on a blueprint preview based on how the
/// person arrived and the explicit source records supplied by that route.
nonisolated struct BlueprintPreviewPresentation: Equatable {
    enum Context: Equatable {
        case discovery
        case collection
        case personal
        case sharedLink
    }

    let context: Context
    private let hasActionStore: Bool
    private let hasInstalledSource: Bool
    private let hasPersonalSource: Bool

    /// Resolves legacy preview routes conservatively. An explicit source takes
    /// precedence over a requested public context. An explicit Yours route
    /// remains personal when its saved working copy retains shared provenance.
    static func resolve(
        requested context: Context,
        currentAccountID: String?,
        actionStoreOwnerID: String?,
        hasInstalledSource: Bool = false,
        hasPersonalSource: Bool = false,
        hasSharedToken: Bool = false
    ) -> Self {
        let resolvedContext: Context
        if context == .personal || hasPersonalSource || hasInstalledSource {
            resolvedContext = .personal
        } else if hasSharedToken {
            resolvedContext = .sharedLink
        } else {
            resolvedContext = context
        }

        return Self(
            context: resolvedContext,
            hasActionStore: currentAccountID.map { !$0.isEmpty && $0 == actionStoreOwnerID } ?? false,
            hasInstalledSource: hasInstalledSource,
            hasPersonalSource: hasPersonalSource
        )
    }

    /// Personal editing is granted only by an explicitly personal route or
    /// personal source record, never by viewer state or a bookmark/like.
    var allowsEditing: Bool { context == .personal }
    var allowsDraftSaving: Bool { context == .personal }

    /// Likes and saves are available on public catalog and collection routes
    /// only when the caller supplied the current account's action store.
    var showsPreferenceActions: Bool {
        hasActionStore && (context == .discovery || context == .collection)
    }

    /// Discovery keeps the primary preview action in the overflow menu.
    var showsUseInMore: Bool { context == .discovery }

    /// Saved/liked collection entries and shared links keep a direct Use action.
    var showsProminentUse: Bool {
        context == .sharedLink || (context == .collection && !blocksInstalledDuplicate)
    }

    /// Existing personal or installed copies pass through the established
    /// duplicate-installation guard before another copy can be created.
    var blocksInstalledDuplicate: Bool { hasInstalledSource || hasPersonalSource }
}
