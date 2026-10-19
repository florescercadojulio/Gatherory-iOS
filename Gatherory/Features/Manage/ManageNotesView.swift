import SwiftUI

/// Shared, validated projection for the preview and full note history.
@MainActor
enum ManageNoteHistory {
    static func notes(
        in workspace: PlanningWorkspace,
        reference: EventReference,
        isBlocked: (String?) -> Bool
    ) -> [EventNote] {
        guard let summary = ManageEventSummary(workspace: workspace, reference: reference) else { return [] }

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
    let reference: EventReference

    private var summary: ManageEventSummary? {
        ManageEventSummary(workspace: workspace, reference: reference)
    }

    private var latestNote: EventNote? {
        ManageNoteHistory.notes(in: workspace, reference: reference, isBlocked: imageSafety.isBlocked).first
    }

    var body: some View {
        Group {
            if summary != nil {
                NavigationLink {
                    ManageNotesView(reference: reference)
                } label: {
                    Group {
                        if let latestNote {
                            Text(latestNote.body)
                                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                        } else {
                            Text("No recent notes")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, AppTheme.Spacing.spacious)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(AppTheme.ColorToken.surface,
                                in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Notes")
                    .accessibilityValue(latestNote?.body ?? String(localized: "No recent notes"))
                    .accessibilityHint("View note history")
                }
                .buttonStyle(.plain)
            } else {
                ContentUnavailableView("Notes Unavailable", systemImage: "lock",
                                       description: Text("No planning event is available."))
            }
        }
    }
}

@MainActor
struct ManageNotesView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @State private var isComposing = false
    let reference: EventReference

    private var summary: ManageEventSummary? {
        ManageEventSummary(workspace: workspace, reference: reference)
    }

    private var notes: [EventNote] {
        ManageNoteHistory.notes(in: workspace, reference: reference, isBlocked: imageSafety.isBlocked)
    }

    var body: some View {
        Group {
            if let summary {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                        if notes.isEmpty {
                            ContentUnavailableView("No Notes Yet", systemImage: "text.bubble",
                                                   description: Text("Planning team notes will appear here."))
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            ForEach(notes) { note in
                                noteCard(note)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.top, AppTheme.Layout.screenTop)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                }
                .background(AppTheme.ColorToken.background)
                .refreshable { await cloudSync.synchronize(trigger: .manual) }
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if summary.canSendNote {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Send a Note", systemImage: "square.and.pencil") {
                                isComposing = true
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Send a Note")
                        }
                    }
                }
                .sheet(isPresented: $isComposing) {
                    NoteComposerView(event: summary.reference, eventID: summary.eventID, title: summary.title)
                        .environment(workspace)
                }
            } else {
                ContentUnavailableView("Notes Unavailable", systemImage: "lock",
                                       description: Text("No planning event is available."))
                    .navigationTitle("Notes")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func noteCard(_ note: EventNote) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text(authorName(for: note))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                Text(note.sentAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(note.body)
                .font(.body)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.spacious)
        .background(AppTheme.ColorToken.surface,
                    in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func authorName(for note: EventNote) -> String {
        workspace.members.first { $0.userID == note.authorUserID && note.authorUserID != nil }?.name
            ?? String(localized: "Planning team")
    }
}
