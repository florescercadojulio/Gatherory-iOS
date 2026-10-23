import SwiftUI

/// Invitation-safe snapshot of the newest server announcement or authorized
/// planning note for this exact event.
@MainActor
struct EventInvitationUpdatesPreview: View {
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    @Environment(PlanningWorkspace.self) private var workspace: PlanningWorkspace?
    @Environment(ImageSafetyStore.self) private var imageSafety: ImageSafetyStore?
    @Environment(\.scenePhase) private var scenePhase

    @State private var controller = EventAnnouncementController()
    let eventID: UUID

    private var scope: EventAnnouncementScope? {
        guard let authentication, !authentication.isSigningOut,
              let principal = authentication.notificationPrincipal else { return nil }
        return EventAnnouncementScope(
            principal: principal,
            generation: authentication.principalGeneration,
            eventID: eventID
        )
    }

    private var isCurrentScope: Bool {
        guard let scope, let authentication else { return false }
        return controller.scope == scope
            && authentication.notificationPrincipal == scope.principal
            && authentication.principalGeneration == scope.generation
            && !authentication.isSigningOut
    }

    private var planningReference: EventReference? {
        guard let workspace, let scope else { return nil }
        return EventAnnouncementPlanningAccess.reference(
            in: workspace,
            eventID: eventID,
            principal: scope.principal,
            loadFailure: controller.loadFailure
        )
    }

    private var latestPlanningNote: EventNote? {
        guard isCurrentScope, let workspace, let reference = planningReference else { return nil }
        return ManageNoteHistory.notes(in: workspace, reference: reference) { userID in
            imageSafety?.isBlocked(userID) ?? false
        }.first
    }

    private var latestAnnouncement: EventAnnouncement? {
        guard isCurrentScope, controller.loadFailure != .accessDenied else { return nil }
        return controller.announcements.first { announcement in
            !(imageSafety?.isBlocked(announcement.authorId) ?? false)
        }
    }

    private var latestContent: EventInvitationUpdateCardContent? {
        let announcement = latestAnnouncement
        let note = latestPlanningNote
        guard let announcement else {
            guard let note else { return nil }
            return EventInvitationUpdateCardContent(note: note, member: member(withUserID: note.authorUserID))
        }
        guard let note else {
            return EventInvitationUpdateCardContent(announcement: announcement, member: sender(for: announcement))
        }
        return note.sentAt > announcement.createdAt
            ? EventInvitationUpdateCardContent(note: note, member: member(withUserID: note.authorUserID))
            : EventInvitationUpdateCardContent(announcement: announcement, member: sender(for: announcement))
    }

    var body: some View {
        Group {
            if let latestContent {
                NavigationLink {
                    EventAnnouncementsView(eventID: eventID, initialAudience: latestContent.audience)
                } label: {
                    EventInvitationUpdateCard(content: latestContent)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    EventAnnouncementsView(eventID: eventID)
                } label: {
                    Label(AnnouncementCopy.title, systemImage: "megaphone")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: scope) { await activate() }
        .onAppear { Task { await refreshIfCurrent() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshIfCurrent() }
        }
    }

    private func activate() async {
        guard let scope, let authentication else {
            controller.activate(scope: nil, transport: nil, isCurrent: { false })
            return
        }

        let isCurrent = {
            authentication.notificationPrincipal == scope.principal
                && authentication.principalGeneration == scope.generation
                && !authentication.isSigningOut
        }

        if isDevicePlanning(for: scope) {
            controller.activate(scope: scope, transport: nil, initialAudience: .planning, isCurrent: isCurrent)
            return
        }

        guard let baseURL = AppRuntimeConfiguration.authenticationBaseURL else {
            controller.activate(scope: nil, transport: nil, isCurrent: { false })
            return
        }

        let transport = HTTPEventAnnouncementTransport(baseURL: baseURL) {
            guard isCurrent() else { throw EventAnnouncementFailure.staleSession }
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
        controller.activate(scope: scope, transport: transport, initialAudience: .all, isCurrent: isCurrent)
        await controller.refresh()
    }

    private func isDevicePlanning(for scope: EventAnnouncementScope) -> Bool {
        guard let workspace, workspace.isLocalGuestViewer,
              case .guest = scope.principal else { return false }
        return EventAnnouncementPlanningAccess.reference(
            in: workspace,
            eventID: eventID,
            principal: scope.principal
        ) != nil
    }

    private func refreshIfCurrent() async {
        guard scenePhase == .active, isCurrentScope, let scope,
              !isDevicePlanning(for: scope) else { return }
        await controller.refresh()
    }

    private func member(withUserID userID: String?) -> WorkspaceMember? {
        guard let userID, let workspace else { return nil }
        let reference: EventReference = eventID == workspace.mainEventID ? .main : .subevent(eventID)
        return workspace.participants(for: reference).first { $0.userID == userID }
    }

    private func sender(for announcement: EventAnnouncement) -> WorkspaceMember? {
        member(withUserID: announcement.authorId)
    }
}

private struct EventInvitationUpdateCardContent {
    let message: String
    let createdAt: Date
    let audience: EventAnnouncementAudience
    let authorName: String
    let member: WorkspaceMember?

    var initials: String {
        let letters = authorName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    init(announcement: EventAnnouncement, member: WorkspaceMember?) {
        message = announcement.message
        createdAt = announcement.createdAt
        audience = announcement.audience
        self.member = member
        authorName = member?.name
            ?? (announcement.authorName == "Host" ? AnnouncementCopy.host : AnnouncementCopy.planningTeam)
    }

    init(note: EventNote, member: WorkspaceMember?) {
        message = note.body
        createdAt = note.sentAt
        audience = .planning
        self.member = member
        authorName = member?.name ?? AnnouncementCopy.planningTeam
    }
}

private struct EventInvitationUpdateCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content: EventInvitationUpdateCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack {
                Label(AnnouncementCopy.title, systemImage: "megaphone")
                    .font(.headline)
                Spacer(minLength: AppTheme.Spacing.compact)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
                if let member = content.member {
                    ParticipantAvatarView(member: member, size: 38)
                } else {
                    Text(content.initials)
                        .font(.caption.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.authorName)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(AnnouncementCopy.title(for: content.audience))
                        Text("·").accessibilityHidden(true)
                        Text(content.createdAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))

                    Text(content.message)
                        .font(.body)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            if reduceTransparency {
                shape.fill(.black.opacity(0.92))
            } else {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(.black.opacity(0.38)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(reduceTransparency ? 0.14 : 0.22), lineWidth: 0.5)
        }
        .foregroundStyle(.white)
        .appImageOverlayAppearance()
        .accessibilityElement(children: .combine)
        .accessibilityHint(AnnouncementCopy.openUpdates)
    }
}

#if DEBUG
private struct EventInvitationUpdatesPreviewCanvas: View {
    private let eventID = UUID(uuidString: "9BC048E1-36E0-4C7F-8739-58FA46C9162A")!
    private let host = WorkspaceMember(
        id: UUID(uuidString: "E497A5AA-83B1-4C0D-A58B-69A4654C7AF2")!,
        userID: "preview-host",
        name: "Jordan Lee",
        participantRole: .host,
        initials: "JL"
    )
    private var sample: EventAnnouncement {
        EventAnnouncement(
            id: UUID(uuidString: "7EFA96C8-28A6-48A8-9C80-F8264EC711A2")!,
            eventId: eventID,
            message: "We’ve confirmed the garden entrance for 4:30. Please use the north gate when you arrive.",
            authorName: "Host",
            createdAt: .now,
            audience: .all,
            authorId: "preview-host"
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    EventInvitationUpdateCard(content: EventInvitationUpdateCardContent(announcement: sample, member: host))
                }
                .padding(20)
            }
            .background(.black)
            .navigationTitle("Event")
        }
    }
}

#Preview("Invitation Updates · Dark") {
    EventInvitationUpdatesPreviewCanvas().preferredColorScheme(.dark)
}

#Preview("Invitation Updates · Light") {
    EventInvitationUpdatesPreviewCanvas().preferredColorScheme(.light)
}

#Preview("Invitation Updates · Large Text") {
    EventInvitationUpdatesPreviewCanvas()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .xxxLarge)
}
#endif
