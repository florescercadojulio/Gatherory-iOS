import SwiftUI

struct TimelineView: View {
    @Environment(WeddingWorkspace.self) private var workspace

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

            Section("Upcoming") {
                ForEach(upcoming) { item in
                    TimelineRow(item: item) {
                        withAnimation {
                            workspace.toggleTimelineItem(item)
                        }
                    }
                }
            }

            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { item in
                        TimelineRow(item: item) {
                            withAnimation {
                                workspace.toggleTimelineItem(item)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add task", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
            }
        }
    }

    private var weddingDateSection: some View {
        Section {
            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: "calendar.badge.heart")
                    .font(.title)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 48, height: 48)
                    .background(AppTheme.ColorToken.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Wedding day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(workspace.weddingDate, format: .dateTime.month(.wide).day().year())
                        .font(.headline)
                }
            }
            .padding(.vertical, 6)
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
                    .font(.title2)
                    .foregroundStyle(item.status == .complete ? .green : AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
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
    }
}

#Preview {
    NavigationStack {
        TimelineView()
            .environment(WeddingWorkspace.sample)
    }
}
