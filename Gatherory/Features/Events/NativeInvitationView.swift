import SwiftUI

struct NativeInvitationView: View {
    @Environment(InvitationRouter.self) private var invitations
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(GuestInvitationStore.self) private var guests
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @State private var preview: InvitationPreview?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isAccepting = false
    let token: UUID

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    invitationArtwork
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
                    if let role = preview?.role {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            Text("You're invited as a \(WorkspaceRole(rawValue: role)?.title ?? role).")
                                .font(.headline)
                            if let resolvedRole = WorkspaceRole(rawValue: role) {
                                Text(LocalizedStringKey(resolvedRole.detail))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if isLoading { ProgressView() }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Try Again") { Task { await loadPreview() } }
                    }
                if preview != nil {
                    VStack(spacing: AppTheme.Spacing.compact) {
                        Button {
                            if !authentication.isAuthenticated {
                                invitations.requiresAuthentication = true
                            } else { Task { await accept() } }
                        } label: {
                            HStack {
                                if isAccepting { ProgressView() }
                                Text(authentication.isAuthenticated ? (preview?.status == "accepted" ? String(localized: "Open Event") : String(localized: "Join Event")) : String(localized: "Sign In to Join"))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .disabled(isLoading || isAccepting)
                        if authentication.isAuthenticated {
                            Button("Use Another Account") {
                                invitations.requiresAuthentication = true
                                Task { await authentication.signOut() }
                            }
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                        } else {
                            Text("Sign in or create an account to join. Your invitation will stay here.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(.top, AppTheme.Spacing.compact)
                    .frame(maxWidth: .infinity)
                }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.spacious)
                .padding(.bottom, AppTheme.Spacing.spacious)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .appSoftScrollEdges()
            .ignoresSafeArea(edges: .top)
            .background(AppTheme.ColorToken.background)
            .navigationBarTitleDisplayMode(.inline)
            .appClearNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { invitations.dismiss() }.labelStyle(.iconOnly)
                }
            }
        }
        .task(id: "\(token)|\(authentication.currentUser?.id ?? "anonymous")") { await loadPreview() }
    }

    private var invitationArtwork: some View {
        MediaArtwork(
            imageData: nil, remoteURL: preview?.coverURL,
            symbol: IdeaCategory.event.symbol,
            colors: IdeaCategory.event.artworkColors,
            accent: IdeaCategory.event.artworkAccent,
            progressiveBlurRadius: 20, blurStart: 0.45
        )
        .frame(height: 240)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.65),
                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .padding(.horizontal, -AppTheme.Spacing.spacious)
        .accessibilityHidden(true)
    }

    private func loadPreview() async {
        guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            errorMessage = EventInvitationFailure.unavailable.localizedDescription
            return
        }
        isLoading = true
        preview = nil
        errorMessage = nil
        defer { isLoading = false }
        do {
            let value: InvitationPreview = try await InvitationAPIClient(baseURL: baseURL).request("api/invitations/preview",
                query: [URLQueryItem(name: "token", value: token.uuidString)], authenticated: false)
            guard invitations.pendingToken == token, !Task.isCancelled else { return }
            preview = value
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func invitationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func accept() async {
        guard !isAccepting, let account = authentication.currentUser,
              let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }
        do {
            let acceptance: InvitationAcceptance = try await InvitationAPIClient(baseURL: baseURL).request("api/invitations/accept",
                method: "POST", body: ["token": token.uuidString])
            guard authentication.currentUser?.id == account.id, invitations.pendingToken == token else { return }
            await guests.activate(account: account)
            await guests.refresh(force: true)
            guard authentication.currentUser?.id == account.id, invitations.pendingToken == token else { return }
            if let scope = acceptance.planningScopeId {
                await cloudSync.retryInitialBootstrap()
                guard authentication.currentUser?.id == account.id, invitations.pendingToken == token else { return }
                if let workspace = library.workspaces.first(where: { $0.mainEventID == scope }) {
                    guests.selectedEventID = nil
                    library.open(workspace)
                    invitations.dismiss(joined: true)
                    return
                }
                throw EventInvitationFailure.server(String(localized: "You joined the event. Try again to load your invitation."))
            }
            guard guests.presentations[acceptance.eventId] != nil else {
                throw EventInvitationFailure.server(String(localized: "You joined the event. Try again to load your invitation."))
            }
            library.closeWorkspace()
            guests.selectedEventID = acceptance.eventId
            invitations.dismiss(joined: true)
        } catch { errorMessage = error.localizedDescription }
    }
}

struct GuestEventInvitationView: View {
    @Environment(GuestInvitationStore.self) private var guests
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
        .confirmationDialog(AppCopy.Lifecycle.leave, isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button(AppCopy.Lifecycle.leave, role: .destructive) {
                Task { if await guests.leave(eventID: eventID) { dismiss() } }
            }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { Text(AppCopy.Lifecycle.leaveMessage) }
    }
}
