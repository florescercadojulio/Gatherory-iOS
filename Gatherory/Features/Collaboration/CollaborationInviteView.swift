import Glur
import PostHog
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
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var didCopyLink = false
    @State private var participantEditorTarget: ParticipantEditorTarget?
    @State private var invitedRole: WorkspaceRole = .guest
    @State private var isShowingEmailInvite = false
    @State private var isConfirmingDisable = false
    @State private var generatedInvitation: GeneratedEventInvitation?
    @State private var isGenerating = false
    @State private var invitationError: String?
    @State private var isShowingSharingSettings = false

    private var inviteURL: URL? {
        generatedInvitation?.eventId == workspace.selectedEventID ? generatedInvitation?.url : nil
    }

    private var canManageInvitations: Bool {
        workspace.canManageInvitations(for: workspace.selectedEventReference)
    }

    private var joinRequests: [EventJoinRequest] {
        guard canManageInvitations else { return [] }
        return workspace.joinRequestStore.requests(eventID: workspace.selectedEventID, accountID: authentication.currentUser?.id)
    }

    private var reviewingRequestID: UUID? { workspace.joinRequestStore.reviewingRequestID }

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

    private var artworkSymbol: String { workspace.isMainEventContext ? IdeaCategory.event.symbol : selectedEventCategory.symbol }
    private var artworkColors: [Color] { workspace.isMainEventContext ? IdeaCategory.event.artworkColors : selectedEventCategory.artworkColors }
    private var artworkAccent: Color { workspace.isMainEventContext ? IdeaCategory.event.artworkAccent : selectedEventCategory.artworkAccent }

    private var invitationPreviewImage: Image {
        if let selectedEventImageData, let image = UIImage(data: selectedEventImageData) {
            return Image(uiImage: image)
        }
        let renderer = ImageRenderer(content: MediaArtwork(imageData: nil, symbol: artworkSymbol,
            colors: artworkColors, accent: artworkAccent, progressiveBlurRadius: 0)
            .frame(width: 320, height: 400))
        return renderer.uiImage.map { Image(uiImage: $0) } ?? Image(systemName: artworkSymbol)
    }

    var body: some View {
        ZStack {
            CollaborationBackdrop(
                imageData: selectedEventImageData,
                symbol: artworkSymbol,
                colors: artworkColors,
                accent: artworkAccent
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    eventPreview
                        .frame(maxWidth: .infinity)

                    if !joinRequests.isEmpty { pendingRequests }

                    if canManageInvitations { linkSharingCard }

                    workspacePeople
                }
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Spacing.standard)
                .padding(.bottom, AppTheme.Layout.screenBottom)
                .containerRelativeFrame(.horizontal)
            }
            .appSoftScrollEdges()
            .scrollIndicators(.hidden)
            .refreshable { await loadJoinRequests() }
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
        }
        .navigationTitle("Invite")
        .task(id: workspace.selectedEventID) {
            await loadJoinRequests()
        }
        .sheet(isPresented: $isShowingSharingSettings, onDismiss: {
            clearInvitation()
            Task { await loadJoinRequests() }
        }) {
            NavigationStack { CollaboratorSharingSettingsView() }
                .environment(workspace)
                .environment(cloudSync)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: workspace.selectedEventID) { _, _ in clearInvitation() }
        .onChange(of: invitedRole) { _, _ in clearInvitation() }
        .confirmationDialog("Disable this invitation link?", isPresented: $isConfirmingDisable, titleVisibility: .visible) {
            Button("Disable Link", role: .destructive) {
                Task { await revokeInvitation() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Disabling a link stops new joins. People who already joined keep their access.")
        }
        .sheet(isPresented: $isShowingEmailInvite) {
            NavigationStack {
                EmailInvitationView(eventID: workspace.selectedEventID, eventTitle: workspace.selectedEventTitle)
            }
            .environment(cloudSync)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppTheme.Spacing.standard))
            : AnyLayout(HStackLayout(alignment: .top, spacing: AppTheme.Spacing.standard))

        return layout {
            MediaArtwork(
                imageData: selectedEventImageData,
                symbol: artworkSymbol,
                colors: artworkColors,
                accent: artworkAccent,
                progressiveBlurRadius: 0
            )
            .frame(width: 72, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(workspace.selectedEventTitle)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                Text(selectedEventDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.84))

                if let selectedEventLocation {
                    Text(selectedEventLocation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var linkSharingCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Anyone with the Link")
                    .font(.headline)
            } else {
                Label("Anyone with the Link", systemImage: "link")
                    .font(.headline)
            }

            if dynamicTypeSize.isAccessibilitySize {
                linkAccessPicker.pickerStyle(.menu)
            } else {
                linkAccessPicker.pickerStyle(.segmented)
            }

            Text(invitedRole == .guest
                 ? String(localized: "Guests can view the invitation and RSVP. Planning stays private.")
                 : workspace.requiresCollaboratorApproval
                    ? String(localized: "The host will review your request before you can see or change plans.")
                    : String(localized: "People with this link join with the access selected in Sharing Settings."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if invitedRole == .collaborator {
                Button { isShowingSharingSettings = true } label: {
                    Label("Sharing Settings", systemImage: "slider.horizontal.3")
                        .frame(minHeight: 44)
                }
                Text(LocalizedStringKey(workspace.defaultCollaboratorPermission.title))
                    .font(.footnote).foregroundStyle(.secondary)
                if !workspace.isCollaboratorLinkEnabled {
                    Text("Collaborator links are disabled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let inviteURL {
                InvitationDeliveryActions(
                    eventTitle: workspace.selectedEventTitle,
                    invitationURL: inviteURL,
                    previewImage: invitationPreviewImage
                )
                .id(inviteURL)
                .disabled(isGenerating || (invitedRole == .collaborator && !workspace.isCollaboratorLinkEnabled))

                HStack {
                    Button {
                        UIPasteboard.general.url = inviteURL
                        didCopyLink = true
                    } label: {
                        Label(didCopyLink ? "Copied" : "Copy Link",
                              systemImage: didCopyLink ? "checkmark" : "link")
                    }
                    .frame(minHeight: 44)
                    .disabled(isGenerating)

                    Spacer()

                    Menu {
                        Button("Disable Link", systemImage: "link.badge.minus", role: .destructive) {
                            isConfirmingDisable = true
                        }
                    } label: {
                        Label("Link Options", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .disabled(isGenerating)
                }
            } else {
                Button {
                    Task { await generateInvitation() }
                } label: {
                    HStack {
                        if isGenerating { ProgressView() }
                        Text(isGenerating ? String(localized: "Preparing Invitation…") : String(localized: "Create Invitation Link"))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || (invitedRole == .collaborator && !workspace.isCollaboratorLinkEnabled))
            }

            if let invitationError {
                Label {
                    Text(invitationError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
                .foregroundStyle(AppTheme.ColorToken.warning)
            }

            Divider()

            Button {
                isShowingEmailInvite = true
            } label: {
                HStack {
                    Label("Invite by Email", systemImage: "envelope")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .padding(AppTheme.Spacing.standard)
        .collaborationCard(reduceTransparency: reduceTransparency)
    }

    private var linkAccessPicker: some View {
        Picker("Link Access", selection: $invitedRole) {
            Text("Guest").tag(WorkspaceRole.guest)
            Text("Collaborator").tag(WorkspaceRole.collaborator)
        }
        .disabled(isGenerating)
    }

    private var pendingRequests: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Join Requests").font(.title2.bold())
            ForEach(joinRequests) { request in
                EventJoinRequestRow(request: request, isReviewing: reviewingRequestID == request.id,
                                    isDisabled: reviewingRequestID != nil) { action in
                    Task { await review(request, action: action) }
                }
                .padding(AppTheme.Spacing.standard)
                .collaborationCard(reduceTransparency: reduceTransparency)
            }
        }
    }

    private func loadJoinRequests() async {
        guard canManageInvitations, let accountID = authentication.currentUser?.id else { return }
        let eventID = workspace.selectedEventID
        await workspace.joinRequestStore.refresh(eventID: eventID, accountID: accountID, force: true)
        guard workspace.selectedEventID == eventID, authentication.currentUser?.id == accountID else { return }
        invitationError = workspace.joinRequestStore.error(eventID: eventID, accountID: accountID)
    }

    private func review(_ request: EventJoinRequest, action: JoinRequestReviewAction) async {
        guard canManageInvitations, let accountID = authentication.currentUser?.id else { return }
        let eventID = workspace.selectedEventID
        if await workspace.joinRequestStore.review(request, eventID: eventID, accountID: accountID, action: action) {
            await cloudSync.refreshCollaboration()
        }
        guard workspace.selectedEventID == eventID, authentication.currentUser?.id == accountID else { return }
        invitationError = workspace.joinRequestStore.error(eventID: eventID, accountID: accountID)
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

    private func clearInvitation() {
        generatedInvitation = nil
        didCopyLink = false
        invitationError = nil
    }

    @MainActor
    private func generateInvitation() async {
        clearInvitation()
        guard !isGenerating, !cloudSync.isSynchronizing,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            invitationError = EventInvitationFailure.unavailable.localizedDescription
            return
        }
        let eventID = workspace.selectedEventID
        isGenerating = true
        defer { isGenerating = false }
        do {
            // A new/local event must exist canonically before an invite can reference it.
            await cloudSync.refreshCollaboration()
            if cloudSync.lastError != nil { throw EventInvitationFailure.unavailable }
            let invitation = try await EventInvitationClient(baseURL: baseURL).create(
                eventID: eventID, name: nil,
                email: nil, role: invitedRole,
                permission: invitedRole == .guest ? .viewOnly : workspace.defaultCollaboratorPermission
            )
            guard workspace.selectedEventID == eventID else { return }
            generatedInvitation = invitation
            PostHogSDK.shared.capture(
                "invitation_link_created",
                properties: ["role": String(describing: invitedRole)]
            )
        } catch {
            invitationError = error.localizedDescription
        }
    }

    private func revokeInvitation() async {
        guard !isGenerating, let invitation = generatedInvitation,
              invitation.email == nil, let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            try await EventInvitationClient(baseURL: baseURL).revoke(eventID: invitation.eventId)
            clearInvitation()
            PostHogSDK.shared.capture("invitation_link_revoked")
        } catch { invitationError = error.localizedDescription }
    }
}

private struct CollaboratorSharingSettingsView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = true
    @State private var requiresApproval = true
    @State private var permission: PlanningPermission = .contribute
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Invite Link", isOn: $enabled)
                Toggle("Approve Collaborators", isOn: $requiresApproval)
            } footer: {
                Text("Approval keeps the planning circle private even if the link is forwarded.")
            }
            Section("Default access") {
                Picker("Access", selection: $permission) {
                    ForEach(PlanningPermission.allCases) { value in
                        Text(LocalizedStringKey(value.title)).tag(value)
                    }
                }
                Text(LocalizedStringKey(permission.detail)).foregroundStyle(.secondary)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.secondary) } }
        }
        .disabled(isSaving)
        .navigationTitle("Sharing Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || cloudSync.isSynchronizing)
            }
        }
        .onAppear {
            enabled = workspace.isCollaboratorLinkEnabled
            requiresApproval = workspace.requiresCollaboratorApproval
            permission = workspace.defaultCollaboratorPermission
        }
    }

    private func save() async {
        guard !cloudSync.isSynchronizing else { return }
        isSaving = true
        defer { isSaving = false }
        workspace.isCollaboratorLinkEnabled = enabled
        workspace.requiresCollaboratorApproval = requiresApproval
        workspace.defaultCollaboratorPermission = permission
        await cloudSync.refreshCollaboration()
        if let error = cloudSync.lastError { errorMessage = error.localizedDescription }
        else { dismiss() }
    }
}

/// Email-bound invitations have their own draft, so preparing one never
/// replaces the public link or its selected access level in the parent view.
private struct EmailInvitationView: View {
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var role: WorkspaceRole = .guest
    @State private var invitation: GeneratedEventInvitation?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var didCopyLink = false

    let eventID: UUID
    let eventTitle: String

    var body: some View {
        Form {
            Section {
                Text(eventTitle)
                    .font(.headline)
                TextField("Name (optional)", text: $name)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Role", selection: $role) {
                    ForEach(WorkspaceRole.allCases) { option in
                        Text(LocalizedStringKey(option.title)).tag(option)
                    }
                }
            } footer: {
                Text("Only the invited email address can accept this link. Share it using the options below; Gatherory does not send an email automatically.")
            }
            .disabled(isPreparing)

            Section {
                if let invitation {
                    InvitationDeliveryActions(eventTitle: eventTitle, invitationURL: invitation.url)
                        .id(invitation.url)
                    Button {
                        UIPasteboard.general.url = invitation.url
                        didCopyLink = true
                    } label: {
                        Label(didCopyLink ? "Copied" : "Copy Link", systemImage: didCopyLink ? "checkmark" : "link")
                    }
                } else {
                    Button {
                        Task { await prepareInvitation() }
                    } label: {
                        HStack {
                            if isPreparing { ProgressView() }
                            Text(isPreparing ? String(localized: "Preparing Invitation…") : String(localized: "Create Invitation Link"))
                        }
                    }
                    .disabled(isPreparing || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(AppTheme.ColorToken.warning)
                }
            }
        }
        .navigationTitle("Invite by Email")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
            }
        }
        .onChange(of: email) { _, _ in clearDraftLink() }
        .onChange(of: name) { _, _ in clearDraftLink() }
        .onChange(of: role) { _, _ in clearDraftLink() }
    }

    private func clearDraftLink() {
        invitation = nil
        didCopyLink = false
        errorMessage = nil
    }

    @MainActor
    private func prepareInvitation() async {
        guard !isPreparing, !cloudSync.isSynchronizing,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            errorMessage = EventInvitationFailure.unavailable.localizedDescription
            return
        }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        do {
            await cloudSync.synchronize(trigger: .manual)
            if cloudSync.lastError != nil { throw EventInvitationFailure.unavailable }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            invitation = try await EventInvitationClient(baseURL: baseURL).create(
                eventID: eventID, name: trimmedName.isEmpty ? nil : trimmedName,
                email: email, role: role,
                permission: role == .guest ? .viewOnly : .manage
            )
            PostHogSDK.shared.capture(
                "email_invitation_link_created",
                properties: ["role": String(describing: role)]
            )
        } catch { errorMessage = error.localizedDescription }
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
    let symbol: String
    let colors: [Color]
    let accent: Color

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                MediaArtwork(
                    imageData: imageData,
                    symbol: symbol,
                    colors: colors,
                    accent: accent,
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
    let persistence = try! WorkspacePersistenceController(isStoredInMemoryOnly: true)
    let library = WorkspaceLibrary.sample

    CollaborationInviteView()
        .environment(PlanningWorkspace.sample)
        .environment(WorkspaceCloudSyncController(persistence: persistence, library: library, baseURL: nil))
}
