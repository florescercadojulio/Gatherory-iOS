import SwiftUI

struct NativeInvitationView: View {
    @Environment(InvitationRouter.self) private var invitations
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(GuestInvitationStore.self) private var guests
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var preview: InvitationPreview?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isAccepting = false
    @State private var joinProgress = InvitationJoinProgress()
    @State private var awaitingApproval = false
    @State private var previewRequestID = UUID()
    @State private var retryJoin = false
    @State private var showsGuestName = false
    let token: UUID

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                        Spacer(minLength: geometry.size.height * 0.44)
                        Text("Event Invitation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(preview?.title ?? String(localized: "Event Invitation"))
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        if let value = preview?.startsAt, let date = invitationDate(value) {
                            Text(date, format: .dateTime.month(.wide).day().year()).font(.headline)
                        }
                        if let location = preview?.locationName { Text(location).foregroundStyle(.secondary) }
                        if let role = preview?.role, preview?.status != "accepted" {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                Text("You're invited as a \(WorkspaceRole(rawValue: role)?.title ?? role).")
                                    .font(.headline)
                                if let resolvedRole = WorkspaceRole(rawValue: role), resolvedRole != .collaborator {
                                    Text(LocalizedStringKey(resolvedRole.detail))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        if awaitingApproval || preview?.status == "awaiting_approval" {
                            Label("Awaiting Approval", systemImage: "clock")
                                .font(.headline)
                            Text("Your request has been sent. Once approved, you can open this invitation to join the planning circle.")
                                .foregroundStyle(.secondary)
                        } else if preview?.status == "declined" {
                            Text("Your request was declined. Contact the host if you think this was a mistake.")
                                .foregroundStyle(.secondary)
                        } else if preview?.requiresApproval == true {
                            Text("The host will review your request before access begins.")
                                .foregroundStyle(.secondary)
                        }
                        if let permission = preview?.planningPermission, preview?.role == "collaborator" {
                            Text(LocalizedStringKey((permission == "view_only" ? PlanningPermission.viewOnly : PlanningPermission(rawValue: permission) ?? .contribute).detail))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.spacious)
                    .padding(.bottom, AppTheme.Spacing.spacious)
                    .frame(minHeight: geometry.size.height, alignment: .bottom)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .refreshable { await loadPreview() }
                .appSoftScrollEdges()
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if preview != nil { invitationActions }
            }
            .overlay(alignment: .top) {
                if let errorMessage {
                    InvitationFailureBanner(message: errorMessage, isRetrying: isLoading || isAccepting) {
                        Task { await retry() }
                    } dismiss: {
                        self.errorMessage = nil
                    }
                    .padding(AppTheme.Spacing.standard)
                } else if isLoading && preview == nil {
                    ProgressView().padding(AppTheme.Spacing.spacious)
                }
            }
            .background { invitationArtwork.ignoresSafeArea() }
            .foregroundStyle(AppTheme.ColorToken.onMedia)
            .navigationBarTitleDisplayMode(.inline)
            .appClearNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { invitations.dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .appImageDetailAppearance()
        .sheet(isPresented: $showsGuestName) {
            NavigationStack { LocalGuestNameView() }
                .presentationDetents([.medium])
        }
        .task(id: "\(token)|\(viewerIdentity ?? "anonymous")") {
            preview = nil
            joinProgress = InvitationJoinProgress()
            awaitingApproval = false
            errorMessage = nil
            await loadPreview()
        }
    }

    private var invitationActions: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if authentication.isAuthenticated {
                Button("Use Another Account") {
                    invitations.requiresAuthentication = true
                    Task { await authentication.signOut() }
                }
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            } else if canJoinAsDeviceGuest {
                Text(GuestCopy.joinHelp)
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(collaboratorInvitationRequiresSignIn
                     ? GuestCopy.collaboratorSignInHelp
                     : authentication.isGuestMode ? GuestCopy.guestUnavailable : String(localized: "Sign in or create an account to join. Your invitation will stay here."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                if canJoinAsDeviceGuest {
                    if authentication.isGuestMode { Task { await acceptAsDeviceGuest() } }
                    else { showsGuestName = true }
                } else if !authentication.isAuthenticated {
                    if authentication.isGuestMode { authentication.requestGuestSignIn() }
                    else { invitations.requiresAuthentication = true }
                } else if awaitingApproval || preview?.status == "awaiting_approval" || preview?.status == "declined" {
                    Task { await loadPreview() }
                } else { Task { await accept() } }
            } label: {
                Text(primaryActionTitle)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                .overlay(alignment: .leading) {
                    if isAccepting || isLoading { ProgressView() }
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isLoading || isAccepting)
            if canJoinAsDeviceGuest && !authentication.isAuthenticated {
                Button(String(localized: "Sign In to Join")) {
                    if authentication.isGuestMode { authentication.requestGuestSignIn() }
                    else { invitations.requiresAuthentication = true }
                }
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .disabled(isLoading || isAccepting)
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, AppTheme.Spacing.spacious)
        .padding(.vertical, AppTheme.Spacing.standard)
        .frame(maxWidth: .infinity)
    }

    private var viewerIdentity: String? {
        authentication.currentUser?.id ?? authentication.localGuestProfile?.storageID
    }

    private var canJoinAsDeviceGuest: Bool {
        !authentication.isAuthenticated && preview?.permitsDeviceGuestAttendance == true
    }

    private var collaboratorInvitationRequiresSignIn: Bool {
        !authentication.isAuthenticated && preview?.role == "collaborator"
    }

    private var primaryActionTitle: String {
        if canJoinAsDeviceGuest {
            if joinProgress.acceptedResponse(for: viewerIdentity) != nil { return String(localized: "Open Event") }
            return GuestCopy.attendAsGuest
        }
        guard authentication.isAuthenticated else {
            switch preview?.signInPurpose {
            case .helpPlan: return GuestCopy.signInToHelpPlan
            case .viewPlans: return GuestCopy.signInToViewPlans
            default: return String(localized: "Sign In to Join")
            }
        }
        if joinProgress.acceptedResponse(for: authentication.currentUser?.id) != nil || preview?.status == "accepted" { return String(localized: "Open Event") }
        if awaitingApproval || preview?.status == "awaiting_approval" || preview?.status == "declined" { return String(localized: "Check Status") }
        return preview?.requiresApproval == true ? String(localized: "Request to Join") : String(localized: "Join Event")
    }

    private var invitationArtwork: some View {
        MediaArtwork(
            imageData: nil, remoteURL: preview?.coverURL,
            symbol: IdeaCategory.event.symbol,
            colors: IdeaCategory.event.artworkColors,
            accent: IdeaCategory.event.artworkAccent,
            progressiveBlurRadius: 32, blurStart: 0.24
        )
        // Keep the photo edge-to-edge; Glur softens its detail, not its opacity.
        // A uniform scrim keeps labels legible without fading into a blank panel.
        .overlay(AppTheme.ColorToken.mediaScrim.opacity(reduceTransparency ? 0.8 : 0.52))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func loadPreview() async {
        guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            errorMessage = EventInvitationFailure.unavailable.localizedDescription
            return
        }
        let accountID = viewerIdentity
        let requestID = UUID()
        previewRequestID = requestID
        isLoading = true
        retryJoin = false
        errorMessage = nil
        defer { if previewRequestID == requestID { isLoading = false } }
        do {
            let value: InvitationPreview = try await InvitationAPIClient(baseURL: baseURL).request("api/invitations/preview",
                query: [URLQueryItem(name: "token", value: token.uuidString)], authenticated: authentication.isAuthenticated)
            guard invitations.pendingToken == token, viewerIdentity == accountID,
                  previewRequestID == requestID, !Task.isCancelled else { return }
            preview = value
            awaitingApproval = value.status == "awaiting_approval"
            if value.shouldOpenExistingEvent(isAuthenticated: authentication.isAuthenticated) {
                // The link is a deep link for existing members, not another
                // invitation. Resolve the current role through the idempotent
                // endpoint, then open the account's planning or guest view.
                await accept()
            }
        } catch {
            guard viewerIdentity == accountID, previewRequestID == requestID,
                  !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func retry() async {
        guard !isLoading, !isAccepting else { return }
        if authentication.isGuestMode && canJoinAsDeviceGuest && retryJoin {
            await acceptAsDeviceGuest()
        } else if authentication.isAuthenticated && (retryJoin || joinProgress.acceptedResponse(for: authentication.currentUser?.id) != nil) {
            await accept()
        } else {
            await loadPreview()
        }
    }

    private func invitationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func acceptAsDeviceGuest() async {
        guard !isAccepting, canJoinAsDeviceGuest, authentication.isGuestMode,
              let profile = authentication.localGuestProfile,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        isAccepting = true
        retryJoin = true
        errorMessage = nil
        defer { isAccepting = false }
        do {
            let acceptance: InvitationAcceptance
            if let accepted = joinProgress.acceptedResponse(for: profile.storageID) {
                acceptance = accepted
            } else {
                acceptance = try await DeviceGuestInvitationClient(baseURL: baseURL, profile: profile).join(token: token)
            }
            guard viewerIdentity == profile.storageID, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            joinProgress.record(acceptance, accountID: profile.storageID)
            await guests.activate(localGuest: profile)
            await guests.refresh(force: true)
            guard viewerIdentity == profile.storageID, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            guard guests.presentations[acceptance.eventId] != nil else {
                throw EventInvitationFailure.server(guests.errorMessage ?? String(localized: "You joined the event. Try again to load your invitation."))
            }
            library.closeWorkspace()
            guests.selectedEventID = acceptance.eventId
            invitations.dismiss(joined: true)
        } catch {
            guard viewerIdentity == profile.storageID, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func accept() async {
        guard !isAccepting, let account = authentication.currentUser,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        isAccepting = true
        retryJoin = true
        errorMessage = nil
        defer { isAccepting = false }
        var stage = "accept"
        do {
            let acceptance: InvitationAcceptance
            if let accepted = joinProgress.acceptedResponse(for: account.id) {
                acceptance = accepted
            } else {
                acceptance = try await InvitationAPIClient(baseURL: baseURL).request("api/invitations/accept",
                    method: "POST", body: ["token": token.uuidString])
            }
            guard authentication.currentUser?.id == account.id, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            joinProgress.record(acceptance, accountID: account.id)
            SyncDiagnostics.record("invitation_join_result", fields: [
                "account_key": SyncDiagnostics.accountKey(account.id),
                "event_id": acceptance.eventId.uuidString,
                "status": acceptance.awaitsApproval ? "awaiting_approval" : "accepted",
                "destination": String(describing: acceptance.destination)
            ])
            if acceptance.destination == .awaitingApproval {
                awaitingApproval = true
                await loadPreview()
                return
            }
            if case .planning(let scope) = acceptance.destination {
                stage = "planning_bootstrap"
                await cloudSync.retryInitialBootstrap()
                guard authentication.currentUser?.id == account.id, invitations.pendingToken == token,
                      !Task.isCancelled else { return }
                if let workspace = library.workspaces.first(where: { $0.mainEventID == scope }) {
                    guests.selectedEventID = nil
                    library.open(workspace)
                    invitations.dismiss(joined: true)
                    return
                }
                if let error = cloudSync.lastError { throw error }
                throw EventInvitationFailure.server(String(localized: "You joined the event. Try again to load your invitation."))
            }
            stage = "guest_feed"
            await guests.activate(account: account)
            await guests.refresh(force: true)
            guard authentication.currentUser?.id == account.id, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            guard guests.presentations[acceptance.eventId] != nil else {
                if let message = guests.errorMessage { throw EventInvitationFailure.server(message) }
                throw EventInvitationFailure.server(String(localized: "You joined the event. Try again to load your invitation."))
            }
            library.closeWorkspace()
            guests.selectedEventID = acceptance.eventId
            invitations.dismiss(joined: true)
        } catch {
            guard authentication.currentUser?.id == account.id, invitations.pendingToken == token,
                  !Task.isCancelled else { return }
            SyncDiagnostics.record("invitation_open_failed", fields: [
                "account_key": SyncDiagnostics.accountKey(account.id), "stage": stage,
                "join_completed": String(joinProgress.acceptedResponse(for: account.id) != nil)
            ], error: error)
            errorMessage = error.localizedDescription
        }
    }
}

private struct InvitationFailureBanner: View {
    let message: String
    let isRetrying: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Try Again", action: retry)
                    .disabled(isRetrying)
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                Spacer()
                Button("Close", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: AppTheme.Layout.minimumTouchTarget, minHeight: AppTheme.Layout.minimumTouchTarget)
            }
        }
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .accessibilityIdentifier("invitation-error-banner")
    }
}

struct GuestEventInvitationView: View {
    @Environment(GuestInvitationStore.self) private var guests
    @Environment(NotificationNavigationState.self) private var notificationNavigation: NotificationNavigationState?
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID
    @State private var isConfirmingLeave = false

    var body: some View {
        NavigationStack {
            Group {
                if let workspace = guests.presentations[eventID] {
                    EventInvitationScreen(reference: .main, onAttendanceResponse: { response in
                        Task { await guests.respond(eventID: eventID, response: response) }
                    }, isUpdatingAttendance: guests.isResponding)
                    .environment(workspace)
                    .refreshable { await guests.refresh(force: true) }
                    .appClearNavigationBar()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            if guests.canLeave(eventID: eventID) {
                                Menu {
                                    Button(AppCopy.Lifecycle.leave, systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { isConfirmingLeave = true }
                                } label: { Image(systemName: "ellipsis") }
                                    .disabled(guests.isResponding)
                                    .accessibilityLabel(AppCopy.EventRemoval.actions)
                            }
                            AccountToolbarButton()
                        }
                    }
                } else {
                    ContentUnavailableView("Event unavailable", systemImage: "calendar.badge.exclamationmark")
                        .toolbar { Button("Close") { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = guests.errorMessage {
                    VStack(spacing: 8) {
                        Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        Button("Try Again") { Task { await guests.refresh(force: true) } }
                    }
                    .padding().frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                }
            }
        }
        .appImageDetailAppearance()
        .sheet(item: Binding(
            get: { notificationNavigation?.attendanceAnnouncement.flatMap { $0.eventID == eventID ? $0 : nil } },
            set: { value in
                if value == nil, notificationNavigation?.attendanceAnnouncement?.eventID == eventID {
                    notificationNavigation?.attendanceAnnouncement = nil
                }
            }
        )) { destination in
            NavigationStack {
                EventAnnouncementsView(eventID: destination.eventID, announcementID: destination.announcementID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppCopy.Common.done) { notificationNavigation?.attendanceAnnouncement = nil }
                        }
                    }
            }
        }
        .confirmationDialog(AppCopy.Lifecycle.leave, isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button(AppCopy.Lifecycle.leave, role: .destructive) {
                Task { if await guests.leave(eventID: eventID) { dismiss() } }
            }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { Text(AppCopy.Lifecycle.leaveMessage) }
    }
}
