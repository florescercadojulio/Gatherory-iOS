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

            Section {
                ForEach(upcoming) { item in
                    TimelineRow(item: item) {
                        withAnimation {
                            workspace.toggleTimelineItem(item)
                        }
                    }
                    .listRowInsets(AppTheme.Layout.listRowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text("Coming up")
                    .editorialEyebrow()
            }

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { item in
                        TimelineRow(item: item) {
                            withAnimation {
                                workspace.toggleTimelineItem(item)
                            }
                        }
                        .listRowInsets(AppTheme.Layout.listRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Completed")
                        .editorialEyebrow()
                }
            }
        }
        .listStyle(.plain)
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
                Button("Add task", systemImage: "plus") { }
                    .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
    }

    private var weddingDateSection: some View {
        Section {
            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: "calendar.badge.heart")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Wedding day")
                        .editorialEyebrow()
                        .foregroundStyle(.black.opacity(0.52))
                    Text(workspace.weddingDate, format: .dateTime.month(.wide).day().year())
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(
                background: AppTheme.ColorToken.lime,
                foreground: .black,
                padding: AppTheme.Spacing.spacious,
                border: false
            )
            .listRowInsets(AppTheme.Layout.featuredRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(item.status == .complete ? .green : AppTheme.ColorToken.ink)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(background: AppTheme.ColorToken.surface)
    }
}

#Preview {
    NavigationStack {
        TimelineView()
            .environment(WeddingWorkspace.sample)
    }
}
