import SwiftUI

/// A planning update, not an SMS, email, or push notification.
struct NoteComposerView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(\.dismiss) private var dismiss
    @State private var event: EventReference
    @State private var eventID: UUID
    @State private var eventTitle: String
    @State private var note = ""
    @State private var saveFailed = false
    @State private var confirmingDiscard = false
    @FocusState private var isFocused: Bool

    init(event: EventReference, eventID: UUID, title: String) {
        _event = State(initialValue: event)
        _eventID = State(initialValue: eventID)
        _eventTitle = State(initialValue: title)
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        workspace.canSendNote(to: event) && !trimmedNote.isEmpty
            && trimmedNote.utf16.count <= 750
            && library.workspaces.contains { $0 === workspace }
    }
    private var recentNotes: [EventNote] {
        workspace.notes.filter {
            ($0.eventID ?? workspace.mainEventID) == eventID && !imageSafety.isBlocked($0.authorUserID)
        }.sorted { $0.sentAt > $1.sentAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Label("Planning update", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(eventTitle).font(AppTheme.Typography.sectionTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Shared here with hosts and collaborators. No email or notification is sent.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        ZStack(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("What should the planning team know?")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5).padding(.top, 8)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                            TextEditor(text: $note)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 180)
                                .focused($isFocused)
                                .accessibilityLabel("Note")
                                .disabled(!workspace.canSendNote(to: event))
                        }
                        .padding(AppTheme.Spacing.standard)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                        Text("\(trimmedNote.utf16.count)/750")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(trimmedNote.utf16.count > 750 ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if !workspace.canSendNote(to: event) {
                            Text("This event is read-only. You can still read previous notes.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    if !recentNotes.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                            Text("Recent Notes").font(.headline)
                            ForEach(recentNotes) { entry in
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                                    Text(workspace.members.first { $0.userID == entry.authorUserID && entry.authorUserID != nil }?.name
                                         ?? String(localized: "Planning team"))
                                        .font(.subheadline.weight(.semibold))
                                    Text(entry.body).textSelection(.enabled)
                                    Text(entry.sentAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.spacious)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await cloudSync.synchronize(trigger: .manual) }
            .navigationTitle("Send a Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if trimmedNote.isEmpty { dismiss() } else { confirmingDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: send).disabled(!canSend)
                }
            }
            .interactiveDismissDisabled(!trimmedNote.isEmpty)
            .confirmationDialog("Discard this note?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Writing", role: .cancel) { }
            }
            .alert("Couldn’t Save Note", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your message is still here. Try sending it again.")
            }
        }
    }

    private func send() {
        guard canSend, let saved = workspace.sendNote(trimmedNote, to: event) else { return }
        do {
            try persistence.saveChanges(in: library)
            // The durable outbox delivers when connected. Do not imply remote delivery.
            dismiss()
        } catch {
            workspace.notes.removeAll { $0.id == saved.id }
            saveFailed = true
        }
    }
}
