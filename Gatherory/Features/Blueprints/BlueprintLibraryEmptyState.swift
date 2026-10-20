import SwiftUI

/// A quiet, native empty state; switching collections is presentation-only.
struct BlueprintLibraryEmptyState: View {
    let collection: BlueprintLibraryCollection
    let onSwitchCollection: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            Button(action: onSwitchCollection) {
                Text(actionTitle)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 4)
                    .frame(minHeight: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
    }

    var title: String {
        switch collection {
        case .installedTemplates:
            String(localized: "blueprint.library.empty.installedTitle", defaultValue: "No Blueprints Yet")
        case .inProgress:
            String(localized: "blueprint.library.empty.draftsTitle", defaultValue: "No Drafts Yet")
        }
    }

    var message: String {
        switch collection {
        case .installedTemplates:
            String(localized: "blueprint.library.empty.installedMessage", defaultValue: "Save a blueprint or use one from Explore. You’ll find it here.")
        case .inProgress:
            String(localized: "blueprint.library.empty.draftsMessage", defaultValue: "Save a draft while editing a blueprint to continue here later.")
        }
    }

    var actionTitle: String {
        switch collection {
        case .installedTemplates:
            String(localized: "blueprint.library.empty.viewDrafts", defaultValue: "View Drafts")
        case .inProgress:
            String(localized: "blueprint.library.empty.viewInstalled", defaultValue: "View Blueprints")
        }
    }

    var symbol: String {
        collection == .installedTemplates ? "square.stack.3d.up" : "square.and.pencil"
    }
}

#Preview("Installed · Light") {
    BlueprintLibraryEmptyState(collection: .installedTemplates) {}
        .preferredColorScheme(.light)
}

#Preview("Drafts · Dark · Large Text") {
    BlueprintLibraryEmptyState(collection: .inProgress) {}
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
