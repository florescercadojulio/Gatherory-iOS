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
            String(localized: "blueprint.library.empty.installedTitle", defaultValue: "No Installed Templates")
        case .inProgress:
            String(localized: "blueprint.library.empty.draftsTitle", defaultValue: "No Drafts Yet")
        }
    }

    var message: String {
        switch collection {
        case .installedTemplates:
            String(localized: "blueprint.library.empty.installedMessage", defaultValue: "Install a template to start your own event plan. Your template history will be here.")
        case .inProgress:
            String(localized: "blueprint.library.empty.draftsMessage", defaultValue: "Find a template in Explore and make it yours. Save a draft to pick up here later.")
        }
    }

    var actionTitle: String {
        switch collection {
        case .installedTemplates:
            String(localized: "blueprint.library.empty.viewDrafts", defaultValue: "View In Progress")
        case .inProgress:
            String(localized: "blueprint.library.empty.viewInstalled", defaultValue: "View Installed Templates")
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
