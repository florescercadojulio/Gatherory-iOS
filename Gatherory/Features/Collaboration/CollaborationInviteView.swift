import Glur
import SwiftUI
import UIKit

struct CollaborationInviteView: View {
    var body: some View {
        NavigationStack {
            CollaborationInviteScreen()
        }
        .appImageDetailAppearance()
    }
}

private struct CollaborationInviteScreen: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var didCopyLink = false
    @State private var participantEditorTarget: ParticipantEditorTarget?

    private var invitationMessage: String {
        "Join \(workspace.selectedEventTitle): \(workspace.collaboratorInviteURL.absoluteString)"
    }

    private var selectedTimelineEvent: TimelineItem? {
        guard case .subevent(let id) = workspace.selectedEventReference else { return nil }
        return workspace.timeline.first(where: { $0.id == id })
    }

    private var selectedEventDate: Date {
        workspace.eventDate(for: workspace.selectedEventReference)
    }

    private var selectedEventLocation: String? {
        if workspace.isMainEventContext {
            return workspace.mainEventLocation?.formatted
        }
        return selectedTimelineEvent?.eventLocation?.formatted
    }

    private var selectedEventCategory: TimelineCategory {
        selectedTimelineEvent?.category ?? .ceremony
    }

    private var selectedEventImageData: Data? {
        workspace.isMainEventContext ? workspace.mainEventImageData : selectedTimelineEvent?.imageData
    }

    private var invitationPreviewImage: Image {
        if let selectedEventImageData, let image = UIImage(data: selectedEventImageData) {
            Image(uiImage: image)
        } else {
            Image("DefaultVenueHero")
        }
    }

    var body: some View {
        @Bindable var workspace = workspace

        ZStack {
            CollaborationBackdrop(
                imageData: selectedEventImageData,
                assetName: workspace.isMainEventContext ? "DefaultVenueHero" : nil,
                category: selectedEventCategory
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    eventPreview
                        .frame(maxWidth: .infinity)

                    linkSharingCard(
                        linkEnabled: $workspace.isCollaboratorLinkEnabled,
                        requiresApproval: $workspace.requiresCollaboratorApproval
                    )

                    workspacePeople
                }
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Spacing.standard)
                .padding(.bottom, AppTheme.Layout.screenBottom)
                .containerRelativeFrame(.horizontal)
            }
            .appSoftScrollEdges()
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .tint(.white)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                invitationShareLink {
                    Label("Share Invitation", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .tint(.white)
                .accessibilityHint("Opens sharing options including AirDrop")

                NavigationLink {
                    CollaboratorPickerView()
                } label: {
                    Label("Add Person", systemImage: "person.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .tint(.white)

                NavigationLink {
                    CollaborationSharingSettingsView()
                } label: {
                    Label("Sharing settings", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .tint(.white)
            }
        }
        .sheet(item: $participantEditorTarget) { target in
            NavigationStack {
                ParticipantEditorView(target: target)
            }
            .environment(workspace)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var eventPreview: some View {
        ZStack(alignment: .bottom) {
            MediaArtwork(
                imageData: selectedEventImageData,
                assetName: workspace.isMainEventContext ? "DefaultVenueHero" : nil,
                symbol: selectedEventCategory.symbol,
                colors: selectedEventCategory.artworkColors,
                accent: selectedEventCategory.artworkAccent,
                progressiveBlurRadius: 0
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(spacing: 5) {
                Text(workspace.selectedEventTitle)
                    .font(.headline)
                    .lineLimit(2)

                Text(selectedEventDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.84))

                if let selectedEventLocation {
                    Text(selectedEventLocation)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(AppTheme.Spacing.standard)
        }
        .foregroundStyle(.white)
        .frame(
            width: dynamicTypeSize.isAccessibilitySize ? 210 : 168,
            height: dynamicTypeSize.isAccessibilitySize ? 270 : 218
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(eventPreviewAccessibilityLabel)
    }

    private var eventPreviewAccessibilityLabel: String {
        let date = selectedEventDate.formatted(date: .long, time: .omitted)
        guard let selectedEventLocation else {
            return "\(workspace.selectedEventTitle), \(date)"
        }
        return "\(workspace.selectedEventTitle), \(date), \(selectedEventLocation)"
    }

    private func linkSharingCard(
        linkEnabled: Binding<Bool>,
        requiresApproval: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .firstTextBaseline) {
                Label("Anyone with the Link", systemImage: "link")
                    .font(.title3.bold())

                Spacer(minLength: AppTheme.Spacing.compact)

                Toggle("Invite link", isOn: linkEnabled)
                    .labelsHidden()
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                    count: 4
                ),
                spacing: AppTheme.Spacing.standard
            ) {
                inviteAction(title: "Messages", systemImage: "message.fill") {
                    sendMessage()
                }

                inviteAction(title: "Mail", systemImage: "envelope.fill") {
                    sendEmail()
                }

                invitationShareLink {
                    inviteActionLabel(
                        title: "AirDrop & More",
                        systemImage: "airplayaudio"
                    )
                }
                .buttonStyle(.plain)

                inviteAction(
                    title: didCopyLink ? "Copied" : "Copy Link",
                    systemImage: didCopyLink ? "checkmark" : "link"
                ) {
                    UIPasteboard.general.url = workspace.collaboratorInviteURL
                    withAnimation(.snappy) {
                        didCopyLink = true
                    }
                }
            }

            Divider()

            Toggle(isOn: requiresApproval) {
                Label("Approve Collaborators", systemImage: "lock.fill")
                    .font(.body.weight(.medium))
            }

            Text(
                workspace.requiresCollaboratorApproval
                    ? "People who use the link will ask to join before they can see or change plans."
                    : "Anyone with the link can join with the default access level."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.spacious)
        .collaborationCard(reduceTransparency: reduceTransparency)
    }

    private var workspacePeople: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text("People")
                    .font(.title2.bold())

                Text(
                    workspace.isMainEventContext
                        ? "Everyone connected to the main event."
                        : "People included in \(workspace.selectedEventTitle)."
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(WorkspaceRole.allCases) { role in
                let people = workspace.selectedEventParticipants.filter { $0.participantRole == role }

                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Label(role.pluralTitle, systemImage: role.symbol)
                            .font(.headline)

                        VStack(spacing: 0) {
                            ForEach(people) { member in
                                let isCurrentUser = member.id == workspace.currentViewerMember?.id

                                Button {
                                    participantEditorTarget = ParticipantEditorTarget(
                                        member: member,
                                        eventReference: workspace.selectedEventReference,
                                        eventTitle: workspace.selectedEventTitle,
                                        isCurrentUser: isCurrentUser
                                    )
                                } label: {
                                    participantRow(member, isCurrentUser: isCurrentUser)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edits this participant's role and event access")

                                if member.id != people.last?.id {
                                    Divider()
                                        .padding(.leading, 58)
                                }
                            }
                        }
                        .collaborationCard(reduceTransparency: reduceTransparency)
                    }
                }
            }

            if workspace.selectedEventParticipants.isEmpty {
                ContentUnavailableView(
                    "No Participants",
                    systemImage: "person.2.slash",
                    description: Text("Add someone to include them in this event.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.standard)
                .collaborationCard(reduceTransparency: reduceTransparency)
            }

        }
    }

    private func participantRow(_ member: WorkspaceMember, isCurrentUser: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            ParticipantAvatarView(member: member, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(isCurrentUser ? "\(member.name) (You)" : member.name)
                    .font(.body.weight(.medium))

                Text(participantDetail(for: member))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            if member.invitationStatus == .invited {
                Label(member.invitationStatus.title, systemImage: member.invitationStatus.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(member.invitationStatus.title)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func participantDetail(for member: WorkspaceMember) -> String {
        switch member.participantRole {
        case .host:
            member.planningPermission.title
        case .collaborator:
            member.planningPermission.title
        case .guest:
            member.attendance.title
        }
    }

    private func inviteAction(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            inviteActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!workspace.isCollaboratorLinkEnabled)
    }

    /// Sharing the invitation URL through the system sheet automatically
    /// includes AirDrop and the system's supported nearby-device behavior.
    private func invitationShareLink<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        ShareLink(
            item: workspace.collaboratorInviteURL,
            subject: Text("Join \(workspace.selectedEventTitle)"),
            message: Text(invitationMessage),
            preview: SharePreview(
                workspace.selectedEventTitle,
                image: invitationPreviewImage
            ),
            label: label
        )
        .disabled(!workspace.isCollaboratorLinkEnabled)
    }

    private func inviteActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 30, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(workspace.isCollaboratorLinkEnabled ? 1 : 0.45)
    }

    private func sendMessage() {
        guard let encodedMessage = invitationMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "sms:&body=\(encodedMessage)") else {
            return
        }
        openURL(url)
    }

    private func sendEmail() {
        let subject = "Join \(workspace.selectedEventTitle)"
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedMessage = invitationMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedMessage)") else {
            return
        }
        openURL(url)
    }
}

private struct ParticipantEditorTarget: Identifiable {
    let member: WorkspaceMember
    let eventReference: EventReference
    let eventTitle: String
    let isCurrentUser: Bool

    var id: UUID { member.id }
}

private struct ParticipantEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var role: WorkspaceRole
    @State private var planningPermission: PlanningPermission
    @State private var isConfirmingRemoval = false

    let target: ParticipantEditorTarget

    init(target: ParticipantEditorTarget) {
        self.target = target
        _role = State(initialValue: target.member.participantRole)
        _planningPermission = State(initialValue: target.member.planningPermission)
    }

    private var canEdit: Bool {
        !target.isCurrentUser
    }

    private var canRemove: Bool {
        canEdit && workspace.canRemoveParticipant(
            target.member.id,
            from: target.eventReference
        )
    }

    private var canSave: Bool {
        canEdit && workspace.canAssignParticipantRole(role, to: target.member.id)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: AppTheme.Spacing.standard) {
                    ParticipantAvatarView(member: target.member, size: 52)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.isCurrentUser ? "\(target.member.name) (You)" : target.member.name)
                            .font(.headline)

                        if let email = target.member.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Role", selection: $role) {
                    ForEach(WorkspaceRole.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                            .disabled(!workspace.canAssignParticipantRole(option, to: target.member.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(!canEdit)

                Text(role.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Role")
            } footer: {
                if target.isCurrentUser {
                    Text("Your own role is managed from workspace settings.")
                } else if !workspace.canAssignParticipantRole(role, to: target.member.id) {
                    Text("Assign another host before changing the workspace's only host.")
                }
            }

            if role == .collaborator {
                Section {
                    Picker("Access", selection: $planningPermission) {
                        ForEach(PlanningPermission.inviteOptions) { permission in
                            Label(permission.title, systemImage: permission.symbol)
                                .tag(permission)
                        }
                    }
                    .disabled(!canEdit)

                    Text(planningPermission.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Planning Access")
                }
            }

            if canEdit {
                Section {
                    Button("Remove from Event", systemImage: "person.badge.minus", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                    .disabled(!canRemove)
                } footer: {
                    Text(
                        canRemove
                            ? "Removes this person from \(target.eventTitle) only. Their access to other events stays the same."
                            : "Every main event needs at least one host."
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Participant")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(canEdit ? "Cancel" : "Done") {
                    dismiss()
                }
            }

            if canEdit {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onChange(of: role) { _, newRole in
            planningPermission = newRole.defaultPlanningPermission
        }
        .confirmationDialog(
            "Remove \(target.member.name) from \(target.eventTitle)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Event", role: .destructive) {
                if workspace.removeParticipant(
                    target.member.id,
                    from: target.eventReference
                ) {
                    dismiss()
                }
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This does not remove them from other events in the workspace.")
        }
    }

    private func save() {
        guard workspace.updateParticipant(
            target.member.id,
            role: role,
            planningPermission: planningPermission
        ) else { return }

        dismiss()
    }
}

private struct CollaborationBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let imageData: Data?
    let assetName: String?
    let category: TimelineCategory

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                MediaArtwork(
                    imageData: imageData,
                    assetName: assetName,
                    symbol: category.symbol,
                    colors: category.artworkColors,
                    accent: category.artworkAccent,
                    progressiveBlurRadius: 0
                )
                    .scaleEffect(1.16)
                    .glur(radius: 42, noise: 0.035)

                Color.black.opacity(colorScheme == .dark ? 0.48 : 0.28)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.32),
                        Color.black.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct CollaborationSharingSettingsView: View {
    @Environment(PlanningWorkspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace

        Form {
            Section {
                Toggle("Invite Link", systemImage: "link", isOn: $workspace.isCollaboratorLinkEnabled)

                Toggle(
                    "Approve Collaborators",
                    systemImage: "person.badge.shield.checkmark.fill",
                    isOn: $workspace.requiresCollaboratorApproval
                )
                .disabled(!workspace.isCollaboratorLinkEnabled)
            } footer: {
                Text("Approval keeps the planning circle private even if the link is forwarded.")
            }

            Section("Default access") {
                Picker("Access", selection: $workspace.defaultCollaboratorPermission) {
                    ForEach(PlanningPermission.inviteOptions) { permission in
                        Label(permission.title, systemImage: permission.symbol)
                            .tag(permission)
                    }
                }

                Text(workspace.defaultCollaboratorPermission.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Sharing Settings")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
    }
}

private struct CollaboratorPickerView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var role: WorkspaceRole = .collaborator

    private let suggestions = SuggestedCollaborator.samples

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(name: String, email: String?) -> Bool {
        normalizedSearchText.isEmpty
            || name.localizedCaseInsensitiveContains(normalizedSearchText)
            || email?.localizedCaseInsensitiveContains(normalizedSearchText) == true
    }

    private var availableMainEventParticipants: [WorkspaceMember] {
        guard !workspace.isMainEventContext else { return [] }
        let includedIDs = Set(workspace.selectedEventParticipants.map(\.id))
        return workspace.participants(for: .main).filter { member in
            !includedIDs.contains(member.id)
                && matchesSearch(name: member.name, email: member.email)
        }
    }

    private var filteredSuggestions: [SuggestedCollaborator] {
        suggestions.filter { suggestion in
            let isNewToEvent = !workspace.selectedEventParticipants.contains { member in
                let sameName = member.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame
                let sameEmail = member.email?.localizedCaseInsensitiveCompare(suggestion.email) == .orderedSame
                return sameName || sameEmail
            }
            return isNewToEvent && matchesSearch(name: suggestion.name, email: suggestion.email)
        }
    }

    var body: some View {
        List {
            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(WorkspaceRole.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }

                Text(role.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Not in Suggestions") {
                NavigationLink {
                    NewParticipantView(initialRole: role)
                } label: {
                    Label("New Person", systemImage: "plus.circle")
                }
            }

            if !availableMainEventParticipants.isEmpty {
                Section("From Main Event") {
                    ForEach(availableMainEventParticipants) { member in
                        Button {
                            workspace.addParticipant(member.id)
                            dismiss()
                        } label: {
                            ExistingParticipantRow(member: member)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Suggested") {
                ForEach(filteredSuggestions) { suggestion in
                    Button {
                        workspace.inviteParticipant(
                            name: suggestion.name,
                            email: suggestion.email,
                            initials: initials(for: suggestion.name),
                            role: role
                        )
                        dismiss()
                    } label: {
                        SuggestedCollaboratorRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Choose a Person")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .searchable(text: $searchText, prompt: "Name or email")
    }
}

private struct ExistingParticipantRow: View {
    let member: WorkspaceMember

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            ParticipantAvatarView(member: member, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .foregroundStyle(.primary)

                Text(member.participantRole.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Adds this person to the selected event")
    }
}

private struct NewParticipantView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role: WorkspaceRole

    init(initialRole: WorkspaceRole) {
        _role = State(initialValue: initialRole)
    }

    var body: some View {
        Form {
            Section("Person") {
                TextField("Name", text: $name)
                    .textContentType(.name)

                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
            }

            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(WorkspaceRole.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }

                Text(role.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("New Person")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Invite") {
                    invite()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func invite() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.inviteParticipant(
            name: trimmedName,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            initials: initials(for: trimmedName),
            role: role
        )
        dismiss()
    }
}

private struct SuggestedCollaboratorRow: View {
    let suggestion: SuggestedCollaborator

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Text(initials(for: suggestion.name))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(suggestion.tint, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name)
                    .foregroundStyle(.primary)

                Text(suggestion.email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Invites this person")
    }
}

private struct SuggestedCollaborator: Identifiable {
    let id = UUID()
    let name: String
    let email: String
    let tint: Color

    static let samples = [
        SuggestedCollaborator(name: "Avery Morgan", email: "avery@example.com", tint: AppTheme.ColorToken.avatar(1)),
        SuggestedCollaborator(name: "Casey Lee", email: "casey@example.com", tint: AppTheme.ColorToken.avatar(5)),
        SuggestedCollaborator(name: "Elena Brooks", email: "elena@example.com", tint: AppTheme.ColorToken.avatar(2)),
        SuggestedCollaborator(name: "Maya Patel", email: "maya@example.com", tint: AppTheme.ColorToken.avatar(3)),
        SuggestedCollaborator(name: "Noah Kim", email: "noah@example.com", tint: AppTheme.ColorToken.avatar(0))
    ]
}

private func initials(for name: String) -> String {
    name
        .split(separator: " ")
        .prefix(2)
        .compactMap(\.first)
        .map(String.init)
        .joined()
        .uppercased()
}

private extension View {
    @ViewBuilder
    func collaborationCard(reduceTransparency: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)

        foregroundStyle(.white)
            .background {
                if reduceTransparency {
                    shape.fill(.black.opacity(0.92))
                } else {
                    shape
                        .fill(.regularMaterial)
                        .overlay(shape.fill(.black.opacity(0.42)))
                }
            }
            .overlay {
                shape.stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .appImageOverlayAppearance()
    }
}

#Preview {
    CollaborationInviteView()
        .environment(PlanningWorkspace.sample)
}
