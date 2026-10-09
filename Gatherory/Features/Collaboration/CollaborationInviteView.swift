import Glur
import SwiftUI
import UIKit

struct CollaborationInviteView: View {
    var body: some View {
        NavigationStack {
            CollaborationInviteScreen()
        }
        .preferredColorScheme(.dark)
    }
}

private struct CollaborationInviteScreen: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL
    @State private var didCopyLink = false

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

    var body: some View {
        @Bindable var workspace = workspace

        ZStack {
            CollaborationBackdrop(
                imageData: selectedEventImageData,
                assetName: workspace.isMainEventContext ? "WeddingVenueHero" : nil,
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

                    weddingPeople
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
    }

    private var eventPreview: some View {
        ZStack(alignment: .bottom) {
            MediaArtwork(
                imageData: selectedEventImageData,
                assetName: workspace.isMainEventContext ? "WeddingVenueHero" : nil,
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

                ShareLink(
                    item: workspace.collaboratorInviteURL,
                    subject: Text("Join \(workspace.selectedEventTitle)"),
                    message: Text(invitationMessage),
                    preview: SharePreview(workspace.selectedEventTitle, image: Image("WeddingVenueHero"))
                ) {
                    inviteActionLabel(title: "Share Link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(!workspace.isCollaboratorLinkEnabled)

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

    private var weddingPeople: some View {
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

            ForEach(WeddingParticipantRole.allCases) { role in
                let people = workspace.selectedEventParticipants.filter { $0.participantRole == role }

                if !people.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Label(role.pluralTitle, systemImage: role.symbol)
                            .font(.headline)

                        VStack(spacing: 0) {
                            ForEach(people) { member in
                                participantRow(member, isCurrentUser: member.id == workspace.members.first?.id)

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

    private func participantRow(_ member: WeddingMember, isCurrentUser: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Text(member.initials)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.ColorToken.accent, in: Circle())
                .accessibilityHidden(true)

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

    private func participantDetail(for member: WeddingMember) -> String {
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
    @Environment(WeddingWorkspace.self) private var workspace

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
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var role: WeddingParticipantRole = .collaborator

    private let suggestions = SuggestedCollaborator.samples

    private var availableMainEventParticipants: [WeddingMember] {
        guard !workspace.isMainEventContext else { return [] }
        let includedIDs = Set(workspace.selectedEventParticipants.map(\.id))
        return workspace.participants(for: .main).filter { !includedIDs.contains($0.id) }
    }

    private var filteredSuggestions: [SuggestedCollaborator] {
        suggestions.filter { suggestion in
            let isNewToEvent = !workspace.selectedEventParticipants.contains {
                $0.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame
            }
            let matchesSearch = searchText.isEmpty
                || suggestion.name.localizedCaseInsensitiveContains(searchText)
                || suggestion.email.localizedCaseInsensitiveContains(searchText)
            return isNewToEvent && matchesSearch
        }
    }

    var body: some View {
        List {
            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(WeddingParticipantRole.allCases) { option in
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
    let member: WeddingMember

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Text(member.initials)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.ColorToken.accent, in: Circle())
                .accessibilityHidden(true)

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
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role: WeddingParticipantRole

    init(initialRole: WeddingParticipantRole) {
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
                    ForEach(WeddingParticipantRole.allCases) { option in
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
        SuggestedCollaborator(name: "Avery Morgan", email: "avery@example.com", tint: .indigo),
        SuggestedCollaborator(name: "Casey Lee", email: "casey@example.com", tint: .orange),
        SuggestedCollaborator(name: "Elena Brooks", email: "elena@example.com", tint: .teal),
        SuggestedCollaborator(name: "Maya Patel", email: "maya@example.com", tint: .purple),
        SuggestedCollaborator(name: "Noah Kim", email: "noah@example.com", tint: .blue)
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
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    CollaborationInviteView()
        .environment(WeddingWorkspace.sample)
}
