import SwiftUI

/// Server-authorized content only. Push payloads select an optional row; they
/// never provide announcement text or grant access to the event.
struct EventAnnouncementsView: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(PlanningWorkspace.self) private var workspace: PlanningWorkspace?
    @Environment(ImageSafetyStore.self) private var imageSafety: ImageSafetyStore?
    @Environment(WorkspaceLibrary.self) private var library: WorkspaceLibrary?
    @Environment(WorkspacePersistenceController.self) private var persistence: WorkspacePersistenceController?
    @State private var controller = EventAnnouncementController()
    @State private var sentCount = 0
    @FocusState private var isMessageFocused: Bool
    let eventID: UUID
    var announcementID: UUID? = nil
    var initialAudience: EventAnnouncementAudience? = nil

    private var planningReference: EventReference? {
        guard let workspace, let scope else { return nil }
        return EventAnnouncementPlanningAccess.reference(in: workspace, eventID: eventID, principal: scope.principal, loadFailure: controller.loadFailure)
    }
    private var isDevicePlanning: Bool {
        guard let workspace, planningReference != nil, let principal = scope?.principal, case .guest = principal else { return false }
        return workspace.isLocalGuestViewer
    }
    private var canSaveDeviceUpdate: Bool {
        guard isDevicePlanning, hasCurrentScope, let workspace, let reference = planningReference,
              let library, persistence != nil else { return false }
        return workspace.canSendNote(to: reference) && library.workspaces.contains { $0 === workspace }
    }
    private var planningNotes: [EventNote] {
        guard let workspace, let reference = planningReference else { return [] }
        return ManageNoteHistory.notes(in: workspace, reference: reference) { userID in
            imageSafety?.isBlocked(userID) ?? false
        }
    }
    private var visibleAnnouncements: [EventAnnouncement] {
        guard controller.audience != .all else { return controller.announcements }
        return controller.announcements.filter { $0.audience == controller.audience }
    }
    private var visiblePlanningNotes: [EventNote] {
        controller.audience == .all || controller.audience == .planning ? planningNotes : []
    }
    private var showsEmptyState: Bool {
        guard hasCurrentScope, visibleAnnouncements.isEmpty, visiblePlanningNotes.isEmpty else { return false }
        return isDevicePlanning || controller.hasLoaded
    }

    private var scope: EventAnnouncementScope? {
        guard !authentication.isSigningOut, let principal = authentication.notificationPrincipal else { return nil }
        return EventAnnouncementScope(principal: principal, generation: authentication.principalGeneration, eventID: eventID)
    }
    private var hasCurrentScope: Bool { scope != nil && controller.scope == scope }

    private func member(withUserID userID: String?) -> WorkspaceMember? {
        guard let userID, let workspace else { return nil }
        return workspace.members.first { $0.userID == userID }
    }

    private func sender(for announcement: EventAnnouncement) -> WorkspaceMember? {
        member(withUserID: announcement.authorId)
            ?? (announcement.authorName == "Host"
                ? workspace?.members.first { $0.participantRole == .host }
                : nil)
    }

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if !hasCurrentScope {
                            Text(AnnouncementCopy.unavailable)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                    if !isDevicePlanning && controller.isLoading && !controller.hasLoaded {
                        ProgressView().frame(maxWidth: .infinity).accessibilityLabel(AnnouncementCopy.title)
                    }
                    if !isDevicePlanning, let failure = controller.loadFailure {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(failure == .accessDenied ? AnnouncementCopy.accessDenied : AnnouncementCopy.loadFailed)
                                .foregroundStyle(.secondary)
                            Button(AppCopy.Common.retry) { Task { await controller.refresh() } }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    if !visibleAnnouncements.isEmpty {
                        Text(AnnouncementCopy.latest)
                            .font(.headline)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)
                        ForEach(visibleAnnouncements) { announcement in
                            let authorMember = sender(for: announcement)
                            VStack(alignment: .leading, spacing: 10) {
                                AnnouncementFeedByline(
                                    name: authorMember?.name ?? (announcement.authorName == "Host" ? AnnouncementCopy.host : AnnouncementCopy.planningTeam),
                                    member: authorMember,
                                    audience: AnnouncementCopy.title(for: announcement.audience),
                                    createdAt: announcement.createdAt
                                )
                                Text(announcement.message).font(.body).textSelection(.enabled)
                            }
                            .padding(18)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
                            }
                            .accessibilityElement(children: .combine)
                            .id(announcement.id)
                        }
                    }
                    if !visiblePlanningNotes.isEmpty {
                        if visibleAnnouncements.isEmpty {
                            Text(AnnouncementCopy.latest)
                                .font(.headline)
                                .padding(.horizontal, 4)
                                .padding(.top, 8)
                        }
                        ForEach(visiblePlanningNotes) { note in
                            let sender = member(withUserID: note.authorUserID)
                            VStack(alignment: .leading, spacing: 10) {
                                AnnouncementFeedByline(
                                    name: sender?.name ?? AnnouncementCopy.planningTeam,
                                    member: sender,
                                    audience: AnnouncementCopy.planning,
                                    createdAt: note.sentAt
                                )
                                Text(note.body).font(.body).textSelection(.enabled)
                            }
                            .padding(18)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
                            }
                            .accessibilityElement(children: .combine)
                            .id(note.id)
                        }
                    }
                }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 652)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.ColorToken.background)
            .overlay {
                if showsEmptyState {
                    EventAnnouncementEmptyState(
                        detail: isDevicePlanning ? AnnouncementCopy.localHelp : AnnouncementCopy.emptyDetail
                    )
                }
            }
            .refreshable { if !isDevicePlanning { await controller.refresh() } }
            .onChange(of: controller.hasLoaded) { _, loaded in
                if loaded, let announcementID, controller.announcements.contains(where: { $0.id == announcementID }) {
                    proxy.scrollTo(announcementID, anchor: .top)
                } else if loaded, isMessageFocused {
                    scrollToLatest(using: proxy)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasCurrentScope, controller.canSend || canSaveDeviceUpdate {
                    EventAnnouncementComposer(controller: controller, isDevicePlanning: isDevicePlanning,
                                              canSaveDeviceUpdate: canSaveDeviceUpdate,
                                              saveDeviceUpdate: saveDeviceUpdate,
                                              isMessageFocused: $isMessageFocused) {
                        sentCount += 1
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: isMessageFocused) { _, focused in
                guard focused else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard isMessageFocused else { return }
                    scrollToLatest(using: proxy)
                }
            }
            }
        }
        .navigationTitle(AnnouncementCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .appSoftScrollEdges()
        .toolbar(.hidden, for: .tabBar)
        .sensoryFeedback(.success, trigger: sentCount)
        .task(id: scope) { await activate() }
        .onChange(of: scope) { _, _ in isMessageFocused = false }
    }

    private func activate() async {
        guard let scope else {
            controller.activate(scope: nil, transport: nil, isCurrent: { false })
            return
        }
        let authentication = authentication
        let current = {
            authentication.notificationPrincipal == scope.principal
                && authentication.principalGeneration == scope.generation
                && !authentication.isSigningOut
        }
        if isDevicePlanning {
            controller.activate(scope: scope, transport: nil, initialAudience: .planning, isCurrent: current)
            return
        }
        guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else { return }
        let transport = HTTPEventAnnouncementTransport(baseURL: baseURL) {
            guard current() else { throw EventAnnouncementFailure.staleSession }
            switch scope.principal {
            case .account:
                guard let token = try KeychainSessionTokenStore().read(), !token.isEmpty else {
                    throw EventAnnouncementFailure.accessDenied
                }
                return .account(bearer: token)
            case .guest(let id):
                let proof = try KeychainLocalGuestCredentialStore().loadOrCreateToken(profileID: id)
                return .guest(id: id, proof: proof)
            }
        }
        controller.activate(scope: scope, transport: transport, initialAudience: initialAudience ?? .all, isCurrent: current)
        await controller.refresh()
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let target = visibleAnnouncements.first?.id ?? visiblePlanningNotes.first?.id else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func saveDeviceUpdate() -> Bool {
        guard canSaveDeviceUpdate, let workspace, let reference = planningReference,
              let library, let persistence,
              let note = workspace.sendNote(controller.draft, to: reference) else { return false }
        do {
            try persistence.saveChanges(in: library)
            controller.draft = ""
            return true
        } catch {
            workspace.notes.removeAll { $0.id == note.id }
            return false
        }
    }
}

private struct EventAnnouncementEmptyState: View {
    let detail: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 64, height: 64)
                .background(
                    AppTheme.ColorToken.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

            VStack(spacing: 8) {
                Text(AnnouncementCopy.emptyTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .accessibilityElement(children: .combine)
    }
}

private struct AnnouncementFeedByline: View {
    let name: String
    let member: WorkspaceMember?
    let audience: String
    let createdAt: Date

    var body: some View {
        HStack(spacing: 12) {
            if let member {
                ParticipantAvatarView(member: member, size: 42)
            } else {
                Text(initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.ColorToken.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                HStack(spacing: 6) {
                    Text(audience)
                    Text("·").accessibilityHidden(true)
                    Text(createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let value = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return value.isEmpty ? "?" : String(value).uppercased()
    }
}

private struct EventAnnouncementComposer: View {
    @Bindable var controller: EventAnnouncementController
    let isDevicePlanning: Bool
    let canSaveDeviceUpdate: Bool
    let saveDeviceUpdate: () -> Bool
    @FocusState.Binding var isMessageFocused: Bool
    let onSent: () -> Void
    @State private var localSaveFailed = false
    private var allowedAudiences: [EventAnnouncementAudience] {
        isDevicePlanning ? [.planning] : controller.allowedAudiences
    }
    private var canSubmit: Bool {
        isDevicePlanning ? canSaveDeviceUpdate && EventAnnouncementMessage.isValid(controller.draft)
            && EventAnnouncementMessage.normalized(controller.draft).utf16.count <= 750 : controller.canSubmit
    }

    var body: some View {
        VStack(spacing: 8) {
            if EventAnnouncementMessage.normalized(controller.draft).unicodeScalars.count > EventAnnouncementMessage.maximumScalars
                || (isDevicePlanning && EventAnnouncementMessage.normalized(controller.draft).utf16.count > 750) {
                composerNotice(AnnouncementCopy.tooLong, symbol: "exclamationmark.circle", tint: AppTheme.ColorToken.warning)
            }
            if localSaveFailed {
                composerNotice(AnnouncementCopy.localSaveFailed, symbol: "exclamationmark.triangle", tint: AppTheme.ColorToken.destructive)
            }
            if let failure = controller.sendFailure {
                composerNotice(failure == .accessDenied ? AnnouncementCopy.accessDenied : failure == .requestConflict ? AnnouncementCopy.requestConflict : AnnouncementCopy.sendFailed,
                               symbol: "exclamationmark.triangle", tint: AppTheme.ColorToken.destructive)
            }
            if controller.isSending {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 4).accessibilityLabel(AnnouncementCopy.sendUpdate)
            }

            HStack(spacing: 2) {
                ForEach(allowedAudiences) { audience in
                    let isSelected = controller.audience == audience
                    Button {
                        controller.audience = audience
                    } label: {
                        Text(AnnouncementCopy.title(for: audience))
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? AppTheme.ColorToken.onAccent : AppTheme.ColorToken.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background {
                                if isSelected {
                                    Capsule().fill(AppTheme.ColorToken.accent)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .disabled(controller.isSending || allowedAudiences.count < 2)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AnnouncementCopy.to)

            HStack(alignment: .bottom, spacing: 10) {
                TextField(AnnouncementCopy.message, text: $controller.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .focused($isMessageFocused)
                    .accessibilityLabel(AnnouncementCopy.message)
                    .disabled(controller.isSending)
                    .frame(minHeight: 44, alignment: .center)

                Button {
                    if isDevicePlanning {
                        if saveDeviceUpdate() { onSent() } else { localSaveFailed = true }
                    } else {
                        Task { if await controller.send() { onSent() } }
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.onAccent)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.ColorToken.accent, in: Circle())
                }
                .accessibilityLabel(isDevicePlanning ? AppCopy.Common.save : AnnouncementCopy.send)
                .disabled(!canSubmit || controller.isSending)
                .opacity(canSubmit && !controller.isSending ? 1 : 0.45)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private func composerNotice(_ message: String, symbol: String, tint: Color) -> some View {
        Label(message, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#if DEBUG
/// Uses the real composer with an in-memory transport: no account, Keychain,
/// database or notification registration is touched by the canvas.
private struct EventAnnouncementComposerPreview: View {
    @State private var controller = EventAnnouncementController()
    @FocusState private var isMessageFocused: Bool
    let startsAtAnnouncements: Bool
    private let eventID = UUID(uuidString: "D5EE5592-9246-4664-8C7F-03F76074D842")!

    var body: some View {
        NavigationStack {
            if startsAtAnnouncements {
                List {
                    Section {
                        ForEach(controller.announcements) { announcement in
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(AnnouncementCopy.host).font(.subheadline.weight(.semibold))
                                    Text(AnnouncementCopy.title(for: announcement.audience))
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Text(announcement.createdAt, format: .dateTime.hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(announcement.message).font(.body)
                            }
                            .padding(18)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text(AnnouncementCopy.latest)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(AppTheme.ColorToken.background)
                .navigationTitle(AnnouncementCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .appClearNavigationBar()
                .appSoftScrollEdges()
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            } else {
                composer
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .task {
            controller.activate(
                scope: EventAnnouncementScope(principal: .account(id: "preview-host"), generation: 0, eventID: eventID),
                transport: PreviewAnnouncementTransport(),
                initialAudience: .all,
                isCurrent: { true }
            )
            await controller.refresh()
            if !startsAtAnnouncements {
                controller.draft = "Let's meet at the venue at 3:00 to set up the flowers and welcome table."
            }
        }
    }

    private var composer: some View {
        EventAnnouncementComposer(
            controller: controller,
            isDevicePlanning: false,
            canSaveDeviceUpdate: false,
            saveDeviceUpdate: { false },
            isMessageFocused: $isMessageFocused,
            onSent: { }
        )
    }
}

@MainActor
private struct PreviewAnnouncementTransport: EventAnnouncementTransport {
    func load(eventID: UUID) async throws -> EventAnnouncementFeed {
        EventAnnouncementFeed(
            announcements: [
                EventAnnouncement(
                    id: UUID(uuidString: "64CBAF1E-5B60-4C2F-8559-4D2905D54B64")!,
                    eventId: eventID,
                    message: "Doors open at 5:30 PM. Please use the garden entrance when you arrive.",
                    authorName: "Host",
                    createdAt: .now.addingTimeInterval(-3600),
                    audience: .all
                ),
                EventAnnouncement(
                    id: UUID(uuidString: "84EB4376-389B-4E24-85E9-84DD34308404")!,
                    eventId: eventID,
                    message: "Planning team: the florist will arrive at 3:00 PM through the side entrance.",
                    authorName: "Host",
                    createdAt: .now.addingTimeInterval(-1800),
                    audience: .planning
                )
            ],
            canSend: true,
            allowedAudiences: EventAnnouncementAudience.allCases
        )
    }

    func send(eventID: UUID, requestID: UUID, message: String,
              audience: EventAnnouncementAudience) async throws -> EventAnnouncement {
        EventAnnouncement(id: requestID, eventId: eventID, message: message,
                          authorName: "Host", createdAt: .now, audience: audience)
    }
}

#Preview("Announcements · Persistent Composer") {
    EventAnnouncementComposerPreview(startsAtAnnouncements: true)
}

#Preview("Send Update · Draft") {
    EventAnnouncementComposerPreview(startsAtAnnouncements: false)
}

#Preview("Send Update · Dark") {
    EventAnnouncementComposerPreview(startsAtAnnouncements: false)
        .preferredColorScheme(.dark)
}
#endif
