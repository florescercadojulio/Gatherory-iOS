import SwiftUI

struct WorkspaceBrowserDuplicateEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isUnavailable = false

    let workspace: PlanningWorkspace
    let onDuplicate: (String) -> Bool

    init(workspace: PlanningWorkspace, onDuplicate: @escaping (String) -> Bool) {
        self.workspace = workspace
        self.onDuplicate = onDuplicate
        _title = State(initialValue: AppCopy.DuplicateEvent.initialTitle(workspace.title))
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.DuplicateEvent.name, text: $title)
                        .accessibilityIdentifier("workspace.duplicateEvent.name")
                } header: {
                    Text(AppCopy.DuplicateEvent.newEvent)
                }

                Section {
                    Text(AppCopy.DuplicateEvent.copiedContent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(AppCopy.DuplicateEvent.excludedContent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(AppCopy.DuplicateEvent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.DuplicateEvent.title, systemImage: "plus.square.on.square") {
                        guard !trimmedTitle.isEmpty,
                              onDuplicate(trimmedTitle) else {
                            isUnavailable = true
                            return
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("workspace.duplicateEvent.confirm")
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .alert(
                AppCopy.DuplicateEvent.unavailableTitle,
                isPresented: $isUnavailable
            ) {
                Button(AppCopy.Common.done, role: .cancel) {}
            } message: {
                Text(AppCopy.DuplicateEvent.unavailableMessage)
            }
        }
    }
}
