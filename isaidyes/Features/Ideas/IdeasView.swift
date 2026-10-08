import SwiftUI

struct IdeasView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var filter: IdeaFilter = .all

    private var filteredIdeas: [WeddingIdea] {
        switch filter {
        case .all:
            workspace.ideas.filter { $0.status != .passed }
        case .inbox:
            workspace.ideas.filter { $0.status == .new }
        case .saved:
            workspace.ideas.filter { $0.status == .maybe || $0.status == .shortlisted || $0.status == .chosen }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Idea filter", selection: $filter) {
                    ForEach(IdeaFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if filteredIdeas.isEmpty {
                    ContentUnavailableView(
                        "No ideas here",
                        systemImage: "sparkles",
                        description: Text("Ideas from your support circle will appear here.")
                    )
                } else {
                    ForEach(filteredIdeas) { idea in
                        IdeaRow(idea: idea)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
            }
        }
    }
}

private enum IdeaFilter: String, CaseIterable, Identifiable {
    case all
    case inbox
    case saved

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .inbox: "Inbox"
        case .saved: "Saved"
        }
    }
}

private struct IdeaRow: View {
    let idea: WeddingIdea

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .fill(idea.category.tint.gradient)
                Image(systemName: idea.category.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(idea.title)
                    .font(.headline)
                    .lineLimit(2)

                Text("\(idea.category.title) · \(idea.submittedBy)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(idea.status.title, systemImage: idea.status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(idea.status.tint)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        IdeasView()
            .environment(WeddingWorkspace.sample)
    }
}
