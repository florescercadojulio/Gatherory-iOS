import SwiftUI

struct TimelineView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isAddingTimelineItem = false

    private var upcoming: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .upcoming }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var completed: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .complete }
            .sorted { $0.dueDate > $1.dueDate }
    }

    var body: some View {
        List {
            weddingDateSection

            Section {
                ForEach(upcoming) { item in
                    TimelineRow(item: item) {
                        withAnimation {
                            workspace.toggleTimelineItem(item)
                        }
                    }
                }
            } header: {
                Text("Coming up")
            }

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { item in
                        TimelineRow(item: item) {
                            withAnimation {
                                workspace.toggleTimelineItem(item)
                            }
                        }
                    }
                } header: {
                    Text("Completed")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, AppTheme.Layout.screenTop, for: .scrollContent)
        .contentMargins(.bottom, AppTheme.Layout.screenBottom, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add task", systemImage: "plus") {
                    isAddingTimelineItem = true
                }
                    .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingTimelineItem) {
            NavigationStack {
                AddTimelineItemView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var weddingDateSection: some View {
        Section("Event") {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wedding day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(workspace.weddingDate, format: .dateTime.month(.wide).day().year())
                        .font(.headline)
                }
            } icon: {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 36)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AddTimelineItemView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var owner = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var defaultOwner: String {
        let couple = workspace.members.prefix(2).map(\.name).joined(separator: " & ")
        return couple.isEmpty ? "You" : couple
    }

    private var ownerOptions: [String] {
        [defaultOwner] + workspace.members.map(\.name).filter { $0 != defaultOwner }
    }

    private var earliestDueDate: Date {
        Calendar.current.startOfDay(for: .now)
    }

    var body: some View {
        Form {
            Section("Task") {
                TextField("Task name", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .title)
            }

            Section("Schedule") {
                DatePicker(
                    "Due date",
                    selection: $dueDate,
                    in: earliestDueDate...,
                    displayedComponents: .date
                )

                Picker("Assigned to", selection: $owner) {
                    ForEach(ownerOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
        }
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    workspace.addTimelineItem(
                        TimelineItem(
                            title: trimmedTitle,
                            dueDate: dueDate,
                            owner: owner
                        )
                    )
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if owner.isEmpty {
                owner = defaultOwner
            }

            dueDate = max(dueDate, earliestDueDate)
            focusedField = .title
        }
    }
}

private struct TimelineRow: View {
    let item: TimelineItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Button(action: toggle) {
                Image(systemName: item.status == .complete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.status == .complete ? .green : AppTheme.ColorToken.accent)
            .accessibilityLabel(item.status == .complete ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .strikethrough(item.status == .complete)
                    .foregroundStyle(item.status == .complete ? .secondary : .primary)
                Text("\(item.dueDate.formatted(date: .abbreviated, time: .omitted)) · \(item.owner)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

#Preview {
    NavigationStack {
        TimelineView()
            .environment(WeddingWorkspace.sample)
    }
}
