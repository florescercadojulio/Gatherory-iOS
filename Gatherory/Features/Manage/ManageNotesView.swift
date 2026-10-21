import SwiftUI

/// Shared, validated projection for the preview and full note history.
@MainActor
enum ManageNoteHistory {
    static func notes(
        in workspace: PlanningWorkspace,
        reference: EventReference,
        isBlocked: (String?) -> Bool
    ) -> [EventNote] {
        guard !workspace.isInvitationProjection,
              workspace.canReadTodos(for: reference),
              let summary = ManageEventSummary(workspace: workspace, reference: reference) else { return [] }

        return workspace.notes.enumerated()
            .filter { _, note in
                (note.eventID ?? workspace.mainEventID) == summary.eventID
                    && !isBlocked(note.authorUserID)
            }
            .sorted { lhs, rhs in
                if lhs.element.sentAt == rhs.element.sentAt { return lhs.offset < rhs.offset }
                return lhs.element.sentAt > rhs.element.sentAt
            }
            .map(\.element)
    }
}

@MainActor
struct ManageNotesPreview: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    let reference: EventReference

    private var latestNote: EventNote? {
        guard let authentication, !authentication.isSigningOut,
              let summary = ManageEventSummary(workspace: workspace, reference: reference),
              EventAnnouncementPlanningAccess.reference(in: workspace, eventID: summary.eventID,
                  principal: authentication.notificationPrincipal) == reference else { return nil }
        return ManageNoteHistory.notes(in: workspace, reference: reference, isBlocked: imageSafety.isBlocked).first
    }

    var body: some View {
        if let summary = ManageEventSummary(workspace: workspace, reference: reference) {
            NavigationLink {
                EventAnnouncementsView(eventID: summary.eventID)
            } label: {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    HStack {
                        Label(AnnouncementCopy.title, systemImage: "megaphone").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    if let latestNote {
                        Text(AnnouncementCopy.planning).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(latestNote.body).font(.body).lineLimit(2)
                    } else {
                        Text(AnnouncementCopy.openUpdates).font(.body).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, AppTheme.Spacing.spacious)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityHint(AnnouncementCopy.openUpdates)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Compatibility destination for saved navigation; all active entries share
/// the same Updates screen and persistent composer.
@MainActor
struct ManageNotesView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    let reference: EventReference
    var body: some View {
        if let summary = ManageEventSummary(workspace: workspace, reference: reference) {
            EventAnnouncementsView(eventID: summary.eventID)
        } else {
            ContentUnavailableView(AnnouncementCopy.title, systemImage: "lock", description: Text(AnnouncementCopy.accessDenied))
        }
    }
}
