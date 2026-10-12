import SwiftUI

/// Settings whose scope is the current planning workspace rather than the signed-in person.
struct WorkspaceSettingsView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @State private var isEditingMainEvent = false

    private var eventDateText: String {
        if workspace.mainEventIsAllDay {
            return workspace.mainEventStartsAt.formatted(date: .abbreviated, time: .omitted)
        }

        return workspace.mainEventStartsAt.formatted(
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
                        assetName: workspace.mainEventImageData == nil ? "DefaultVenueHero" : nil,
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

                }
                .padding(.vertical, 8)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Main Event") {
                WorkspaceSettingDetailRow(
                    title: "Status",
                    symbol: "checklist",
                    value: workspace.currentMainEventStatus.title,
                    valueSymbol: workspace.currentMainEventStatus.symbol,
                    valueColor: statusColor
                )

                WorkspaceSettingDetailRow(
                    title: "Date",
                    symbol: "calendar",
                    value: eventDateText
                )

                WorkspaceSettingDetailRow(
                    title: "Location",
                    symbol: "mappin.and.ellipse",
                    value: locationText
                )

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
                Text("People & Access")
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

/// Keeps the workspace summary scannable at standard sizes and lets the
/// value take a full line when Dynamic Type makes a trailing layout too tight.
private struct WorkspaceSettingDetailRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let symbol: String
    let value: String
    var valueSymbol: String? = nil
    var valueColor: Color = AppTheme.ColorToken.textSecondary

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: symbol)
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)

                    valueLabel
                        .padding(.leading, AppTheme.Layout.minimumTouchTarget)
                }
            } else {
                LabeledContent {
                    valueLabel
                        .multilineTextAlignment(.trailing)
                } label: {
                    Label(title, systemImage: symbol)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueLabel: some View {
        if let valueSymbol {
            Label(value, systemImage: valueSymbol)
                .foregroundStyle(valueColor)
        } else {
            Text(value)
                .foregroundStyle(valueColor)
        }
    }
}

private struct WorkspaceParticipantStack: View {
    let members: [WorkspaceMember]

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
    @Environment(PlanningWorkspace.self) private var workspace
    @State private var isManagingPeople = false

    var body: some View {
        List {
            ForEach(WorkspaceRole.allCases) { role in
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
            .environment(PlanningWorkspace.sample)
    }
}
