import SwiftUI

struct IdeasView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var filter: IdeaFilter = .all

    private var filteredIdeas: [WeddingIdea] {
        switch filter {
        case .all:
            workspace.ideas.filter { $0.status != .passed && $0.status != .archived }
        case .inbox:
            workspace.ideas.filter { $0.status == .new }
        case .saved:
            workspace.ideas.filter { $0.status == .maybe || $0.status == .shortlisted || $0.status == .chosen }
        case .archived:
            workspace.ideas.filter { $0.status == .archived }
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
                .listRowInsets(AppTheme.Layout.featuredRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                            .listRowInsets(AppTheme.Layout.listRowInsets)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("Shortlist", systemImage: "heart.fill") {
                                    withAnimation {
                                        workspace.updateIdea(idea, status: .shortlisted)
                                    }
                                }
                                .tint(AppTheme.ColorToken.accent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if idea.status == .archived {
                                    Button("Restore", systemImage: "arrow.uturn.backward") {
                                        withAnimation {
                                            workspace.updateIdea(idea, status: .new)
                                        }
                                    }
                                    .tint(AppTheme.ColorToken.navy)
                                } else {
                                    Button("Archive", systemImage: "archivebox.fill") {
                                        withAnimation {
                                            workspace.updateIdea(idea, status: .archived)
                                        }
                                    }
                                    .tint(.gray)

                                    Button("Save for now", systemImage: "bookmark.fill") {
                                        withAnimation {
                                            workspace.updateIdea(idea, status: .maybe)
                                        }
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
            } header: {
                Text("Shared inspiration")
                    .editorialEyebrow()
            }
        }
        .listStyle(.plain)
        .contentMargins(.top, AppTheme.Layout.screenTop, for: .scrollContent)
        .contentMargins(.bottom, AppTheme.Layout.screenBottom, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") { }
                    .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
    }
}

private enum IdeaFilter: String, CaseIterable, Identifiable {
    case all
    case inbox
    case saved
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .inbox: "Inbox"
        case .saved: "Saved"
        case .archived: "Archive"
        }
    }
}

private struct IdeaRow: View {
    let idea: WeddingIdea

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control)
                    .fill(.black.opacity(0.08))
                Image(systemName: idea.category.symbol)
                    .font(.title2)
                    .foregroundStyle(.black)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(idea.title)
                    .font(.headline)
                    .lineLimit(2)

                Text("\(idea.category.title) · \(idea.submittedBy)")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.58))

                Label(idea.status.title, systemImage: idea.status.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(
            background: idea.category.tint,
            foreground: .black,
            padding: AppTheme.Spacing.standard,
            border: false
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        IdeasView()
            .environment(WeddingWorkspace.sample)
    }
}
