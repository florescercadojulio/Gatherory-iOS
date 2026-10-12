import SwiftUI

/// Settings whose scope is the current planning workspace rather than the signed-in person.
struct WorkspaceSettingsView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isEditingMainEvent = false

    private var eventDateText: String {
        if workspace.mainEventIsAllDay {
            return workspace.weddingDate.formatted(date: .abbreviated, time: .omitted)
        }

        return workspace.weddingDate.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )
    }

    private var locationText: String {
        let fallbackLocation = [workspace.venueName, workspace.location]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return workspace.mainEventLocation?.title ?? fallbackLocation ?? "Not set"
    }

    private var eventCountText: String {
        let count = workspace.timeline.count
        return count == 1 ? "1 sub-event" : "\(count) sub-events"
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: AppTheme.Spacing.standard) {
                    MediaArtwork(
                        imageData: workspace.mainEventImageData,
                        assetName: workspace.mainEventImageData == nil ? "WeddingVenueHero" : nil,
                        symbol: "calendar",
                        colors: [
                            AppTheme.ColorToken.accentSecondary,
                            AppTheme.ColorToken.accent,
                            AppTheme.ColorToken.accentTertiary
                        ],
                        accent: AppTheme.ColorToken.onAccent,
                        progressiveBlurRadius: 0
                    )
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(workspace.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)
                            .lineLimit(2)

                        Text("Main event · \(eventCountText)")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AppTheme.Spacing.compact)

                    Button {
                        isEditingMainEvent = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                            .frame(
                                width: AppTheme.Layout.minimumTouchTarget,
                                height: AppTheme.Layout.minimumTouchTarget
                            )
                            .background(AppTheme.ColorToken.elevatedSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .accessibilityLabel("Edit workspace details")
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Main Event") {
                LabeledContent {
                    Label(
                        workspace.currentMainEventStatus.title,
                        systemImage: workspace.currentMainEventStatus.symbol
                    )
                    .foregroundStyle(statusColor)
                } label: {
                    Label("Status", systemImage: "checklist")
                }

                LabeledContent {
                    Text(eventDateText)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Date", systemImage: "calendar")
                }

                LabeledContent {
                    Text(locationText)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label("Location", systemImage: "mappin.and.ellipse")
                }

                Button("Edit Main Event", systemImage: "pencil") {
                    isEditingMainEvent = true
                }
                .foregroundStyle(AppTheme.ColorToken.accent)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                NavigationLink {
                    WorkspacePeopleView()
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Label("People", systemImage: "person.3.fill")

                        Spacer(minLength: AppTheme.Spacing.compact)

                        WorkspaceParticipantStack(
                            members: Array(workspace.members.prefix(3))
                        )

                        Text(workspace.members.count.formatted())
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Planning")
            } footer: {
                Text("Manage the people, roles, and invitation access for this workspace.")
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .contentMargins(.top, AppTheme.Spacing.compact, for: .scrollContent)
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

    private var statusColor: Color {
        switch workspace.currentMainEventStatus {
        case .draft:
            AppTheme.ColorToken.textSecondary
        case .ongoing:
            AppTheme.ColorToken.accent
        case .finished:
            AppTheme.ColorToken.success
        }
    }
}

private struct WorkspaceParticipantStack: View {
    let members: [WeddingMember]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(members) { member in
                ParticipantAvatarView(member: member, size: 28, style: .toolbar)
                    .overlay {
                        Circle()
                            .stroke(AppTheme.ColorToken.surface, lineWidth: 2)
                    }
            }
        }
        .accessibilityHidden(true)
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
                                ParticipantAvatarView(member: member, size: 40)

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
                    .listRowBackground(AppTheme.ColorToken.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Manage") {
                    isManagingPeople = true
                }
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
