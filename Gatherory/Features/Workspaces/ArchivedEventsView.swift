import SwiftUI

struct ArchivedEventsView: View {
    @Environment(PlanningWorkspace.self) private var workspace

    var body: some View {
        List {
            if workspace.archivedChildEvents.isEmpty {
                ContentUnavailableView {
                    Label("No Archived Events", systemImage: "archivebox")
                } description: {
                    Text("Events you archive will be kept here with their ideas, costs, and memories.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(workspace.archivedChildEvents) { item in
                        HStack(spacing: AppTheme.Spacing.standard) {
                            NavigationLink {
                                EventInvitationScreen(reference: .subevent(item.id))
                                    .appImageDetailAppearance()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    if item.hasScheduledDate {
                                        Text(item.scheduledAt, format: .dateTime.month().day().year())
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                _ = workspace.restoreArchivedEvent(item.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(!workspace.canRestoreArchivedEvents)
                            .accessibilityLabel("Restore \(item.title)")
                        }
                    }
                } footer: {
                    Text("Restoring keeps the original event status. Events without a saved status return as drafts.")
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Archived Events")
        .navigationBarTitleDisplayMode(.inline)
    }
}
