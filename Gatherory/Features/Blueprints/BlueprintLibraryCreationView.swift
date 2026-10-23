import SwiftUI

/// Reuses event capture instead of creating an empty or implicitly public plan.
struct BlueprintLibraryCreationView: View {
    let ownerID: String
    var onViewEvents: () -> Void
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(\.currentUserAccount) private var account
    @Environment(\.dismiss) private var dismiss

    private var eligibleEvents: [PlanningWorkspace] {
        guard account?.id == ownerID else { return [] }
        return library.workspaces.filter { canCapture($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if account?.id != ownerID {
                    ContentUnavailableView(BlueprintCopy.signInRequired, systemImage: "person.crop.circle.badge.exclamationmark")
                } else if eligibleEvents.isEmpty {
                    ContentUnavailableView {
                        Label(BlueprintCopy.libraryNoSourceEventsTitle, systemImage: "calendar.badge.plus")
                    } description: {
                        Text(BlueprintCopy.libraryNoSourceEventsMessage)
                    } actions: {
                        Button(BlueprintCopy.libraryViewEvents) {
                            dismiss()
                            onViewEvents()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(eligibleEvents, id: \.mainEventID) { workspace in
                                NavigationLink(value: workspace.mainEventID) {
                                    Text(workspace.title)
                                }
                            }
                        } header: {
                            Text(BlueprintCopy.libraryChooseEventMessage)
                        }
                    }
                }
            }
            .navigationTitle(BlueprintCopy.libraryChooseEventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { eventID in
                if let workspace = library.workspaces.first(where: { $0.mainEventID == eventID }),
                   canCapture(workspace) {
                    BlueprintCreateShareView(
                        eventID: eventID, workspace: workspace,
                        publishesToSearch: false, createsShareLink: false,
                        startsWithReview: true, onClose: { dismiss() }
                    )
                } else {
                    ContentUnavailableView(BlueprintCopy.templateLinksUnavailable, systemImage: "lock")
                }
            }
        }
    }

    private func canCapture(_ workspace: PlanningWorkspace) -> Bool {
        account?.id == ownerID && BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL, workspace: workspace
        ) != nil
    }
}
