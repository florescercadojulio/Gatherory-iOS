import SwiftUI

/// Settings whose scope is the current planning workspace rather than the signed-in person.
struct WorkspaceSettingsView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isEditingMainEvent = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: workspace.title)

                LabeledContent("Status") {
                    Label(
                        workspace.currentMainEventStatus.title,
                        systemImage: workspace.currentMainEventStatus.symbol
                    )
                }

                Button("Edit Workspace Details", systemImage: "pencil") {
                    isEditingMainEvent = true
                }
            } header: {
                Text("Workspace")
            } footer: {
                Text("Workspace details come from the main event.")
            }

            Section("Planning") {
                NavigationLink {
                    WorkspacePeopleView()
                } label: {
                    Label("People", systemImage: "person.3.fill")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Workspace Settings")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .sheet(isPresented: $isEditingMainEvent) {
            NavigationStack {
                EventEditorView(mode: .main)
            }
            .environment(workspace)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct WorkspacePeopleView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isManagingPeople = false

    var body: some View {
        List {
            ForEach(WeddingParticipantRole.allCases) { role in
                let people = workspace.members.filter { $0.participantRole == role }

                if !people.isEmpty {
                    Section(role.pluralTitle) {
                        ForEach(people) { member in
                            HStack(spacing: AppTheme.Spacing.standard) {
                                Text(member.initials)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(AppTheme.ColorToken.accent, in: Circle())
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                    Text(member.participantRole == .guest
                                         ? member.attendance.title
                                         : member.planningPermission.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                if member.invitationStatus == .invited {
                                    Label(
                                        member.invitationStatus.title,
                                        systemImage: member.invitationStatus.symbol
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Manage People", systemImage: "person.badge.plus") {
                    isManagingPeople = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .fullScreenCover(isPresented: $isManagingPeople) {
            CollaborationInviteView()
                .environment(workspace)
        }
    }
}

#Preview {
    NavigationStack {
        WorkspaceSettingsView()
            .environment(WeddingWorkspace.sample)
    }
}
