import SwiftUI

struct IdeasView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var filter: IdeaFilter = .all
    @State private var isAddingIdea = false
    @State private var selectedIdeaID: UUID?
    @Namespace private var ideaTransition

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
                        Button {
                            selectedIdeaID = idea.id
                        } label: {
                            IdeaRow(
                                idea: idea,
                                transitionNamespace: ideaTransition
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens idea details")
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") {
                    isAddingIdea = true
                }
                    .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingIdea) {
            NavigationStack {
                AddIdeaView()
            }
        }
        .navigationDestination(item: $selectedIdeaID) { ideaID in
            IdeaDetailView(
                ideaID: ideaID,
                transitionNamespace: ideaTransition
            )
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
    var transitionNamespace: Namespace.ID?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            artwork

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

    @ViewBuilder
    private var artwork: some View {
        if let transitionNamespace {
            IdeaArtworkThumbnail(idea: idea)
                .matchedTransitionSource(id: idea.id, in: transitionNamespace)
        } else {
            IdeaArtworkThumbnail(idea: idea)
        }
    }
}

private struct IdeaArtworkThumbnail: View {
    let idea: WeddingIdea

    var body: some View {
        MediaArtwork(
            imageData: idea.imageData,
            symbol: idea.category.symbol,
            colors: idea.category.artworkColors,
            accent: idea.category.artworkAccent,
            ambientBlurRadius: 4,
            progressiveBlurRadius: 0,
            blurStart: 1
        )
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct IdeaDetailView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    let ideaID: UUID
    let transitionNamespace: Namespace.ID

    private var idea: WeddingIdea? {
        workspace.ideas.first { $0.id == ideaID }
    }

    var body: some View {
        Group {
            if let idea {
                IdeaDetailScreen(idea: idea)
            } else {
                ContentUnavailableView("Idea unavailable", systemImage: "sparkles")
            }
        }
        .navigationTitle("Idea details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTransition(.zoom(sourceID: ideaID, in: transitionNamespace))
    }
}

private struct IdeaDetailScreen: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let idea: WeddingIdea

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundArtwork
                readingScrim

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                        Spacer(minLength: max(proxy.size.height * 0.42, 260))
                        ideaIdentity
                        metadata
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(.black)
    }

    private var backgroundArtwork: some View {
        MediaArtwork(
            imageData: idea.imageData,
            symbol: idea.category.symbol,
            colors: idea.category.artworkColors,
            accent: idea.category.artworkAccent,
            ambientBlurRadius: 10,
            progressiveBlurRadius: reduceTransparency ? 0 : 22,
            blurStart: 0.44
        )
        .ignoresSafeArea()
    }

    private var readingScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .black.opacity(0.05), location: 0.48),
                .init(color: .black.opacity(reduceTransparency ? 0.56 : 0.22), location: 0.65),
                .init(color: .black.opacity(reduceTransparency ? 0.78 : 0.46), location: 0.82),
                .init(color: .black.opacity(reduceTransparency ? 0.88 : 0.60), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var ideaIdentity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label(idea.category.title, systemImage: idea.category.symbol)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: AppTheme.Spacing.compact)

                Label(idea.status.title, systemImage: idea.status.symbol)
                    .font(.caption.weight(.semibold))
            }

            Text(idea.title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)

            Text(idea.note)
                .font(.body)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.Spacing.compact) {
                metadataViews
            }
        } else {
            HStack(spacing: AppTheme.Spacing.compact) {
                metadataViews
            }
        }
    }

    @ViewBuilder
    private var metadataViews: some View {
        IdeaMetric(title: "Shared by", value: idea.submittedBy, symbol: "person.fill", reduceTransparency: reduceTransparency)

        if let estimatedCost = idea.estimatedCost {
            IdeaMetric(
                title: "Estimate",
                value: estimatedCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")),
                symbol: "tag.fill",
                reduceTransparency: reduceTransparency
            )
        }
    }
}

private struct IdeaMetric: View {
    let title: String
    let value: String
    let symbol: String
    let reduceTransparency: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Text(value)
                    .font(.headline)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(.black.opacity(reduceTransparency ? 0.72 : 0.24), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddIdeaView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var category = IdeaCategory.other
    @State private var estimatedCost = ""
    @State private var imageData: Data?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedEstimate: Int? {
        guard !estimatedCost.isEmpty else { return nil }
        return Int(estimatedCost)
    }

    private var hasValidEstimate: Bool {
        estimatedCost.isEmpty || parsedEstimate != nil
    }

    var body: some View {
        Form {
            Section("Photo") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: category.symbol
                )
            }

            Section("Idea") {
                TextField("Title", text: $title)

                TextField("What makes it special? (optional)", text: $note, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Category", selection: $category) {
                    ForEach(IdeaCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol)
                            .tag(category)
                    }
                }
            }

            Section("Optional") {
                TextField("Estimated cost", text: $estimatedCost)
                    .keyboardType(.numberPad)
            }
        }
        .navigationTitle("Add idea")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    workspace.addIdea(
                        WeddingIdea(
                            title: trimmedTitle,
                            note: trimmedNote,
                            category: category,
                            submittedBy: workspace.members.first?.name ?? "You",
                            estimatedCost: parsedEstimate,
                            imageData: imageData
                        )
                    )
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty || !hasValidEstimate)
            }
        }
    }
}

#Preview {
    NavigationStack {
        IdeasView()
            .environment(WeddingWorkspace.sample)
    }
}
