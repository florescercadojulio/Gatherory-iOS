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
                .accessibilityHint("Filters ideas by status")
                .listRowInsets(
                    EdgeInsets(
                        top: 0,
                        leading: AppTheme.Layout.screenHorizontal,
                        bottom: 0,
                        trailing: AppTheme.Layout.screenHorizontal
                    )
                )
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
                        .listRowInsets(AppTheme.Layout.listRowInsets)
                        .accessibilityHint("Opens idea details")
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
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
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

struct IdeaRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let idea: WeddingIdea
    var transitionNamespace: Namespace.ID?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                Text("\(idea.category.title) · \(idea.submittedBy)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if dynamicTypeSize.isAccessibilitySize {
                    statusLabel
                }
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            if !dynamicTypeSize.isAccessibilitySize {
                statusLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: some View {
        Label(idea.status.title, systemImage: idea.status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(idea.status.tint)
            .lineLimit(1)
            .fixedSize()
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
            remoteURL: idea.musicTrack?.artworkURL,
            symbol: idea.category.symbol,
            colors: idea.category.artworkColors,
            accent: idea.category.artworkAccent,
            ambientBlurRadius: 4,
            progressiveBlurRadius: 0,
            blurStart: 1
        )
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

struct IdeaDetailView: View {
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
        .toolbar {
            if let idea {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Idea actions", systemImage: "ellipsis") {
                        if idea.status != .new {
                            Button("Move to Inbox", systemImage: "tray") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .new)
                                }
                            }
                        }

                        if idea.status != .shortlisted {
                            Button("Shortlist", systemImage: "heart.fill") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .shortlisted)
                                }
                            }
                        }

                        if idea.status != .maybe {
                            Button("Save for Now", systemImage: "bookmark.fill") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .maybe)
                                }
                            }
                        }

                        if idea.status != .chosen {
                            Button("Choose", systemImage: "checkmark.circle.fill") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .chosen)
                                }
                            }
                        }

                        Divider()

                        if idea.status == .archived {
                            Button("Restore", systemImage: "arrow.uturn.backward") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .new)
                                }
                            }
                        } else {
                            Button("Archive", systemImage: "archivebox.fill") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .archived)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTransition(.zoom(sourceID: ideaID, in: transitionNamespace))
    }
}

private struct IdeaDetailScreen: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
            remoteURL: idea.musicTrack?.artworkURL,
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

            if !idea.note.isEmpty {
                Text(idea.note)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            if let track = idea.musicTrack {
                IdeaMetadataRow(
                    title: "Artist",
                    value: track.artistName,
                    symbol: "person.wave.2.fill"
                )

                if let albumTitle = track.albumTitle {
                    Divider()
                        .padding(.leading, 44)

                    IdeaMetadataRow(
                        title: "Album",
                        value: albumTitle,
                        symbol: "square.stack.fill"
                    )
                }

                Divider()
                    .padding(.leading, 44)
            }

            IdeaMetadataRow(
                title: "Shared by",
                value: idea.submittedBy,
                symbol: "person.fill"
            )

            if let estimatedCost = idea.estimatedCost {
                Divider()
                    .padding(.leading, 44)

                IdeaMetadataRow(
                    title: "Estimated cost",
                    value: estimatedCost.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")),
                    symbol: "tag.fill"
                )
            }

            if let track = idea.musicTrack, let externalURL = track.externalURL {
                Divider()
                    .padding(.leading, 44)

                Link(destination: externalURL) {
                    LabeledContent {
                        Label("Open", systemImage: "arrow.up.forward")
                            .font(.body.weight(.semibold))
                    } label: {
                        Label(track.providerID.displayName, systemImage: "music.note")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                    .padding(.horizontal, AppTheme.Spacing.standard)
                    .frame(minHeight: 56)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this song in \(track.providerID.displayName)")
            }
        }
        .padding(.vertical, 4)
        .background(
            reduceTransparency ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct IdeaMetadataRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        LabeledContent {
            Text(value)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .padding(.horizontal, AppTheme.Spacing.standard)
        .frame(minHeight: 56)
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
    @State private var selectedTrack: MusicTrack?

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

            if category == .music {
                Section {
                    NavigationLink {
                        MusicSearchView { track in
                            let shouldUseSongTitle = trimmedTitle.isEmpty || title == selectedTrack?.title
                            selectedTrack = track
                            if shouldUseSongTitle {
                                title = track.title
                            }
                        }
                    } label: {
                        if let selectedTrack {
                            MusicTrackRow(track: selectedTrack)
                        } else {
                            Label("Choose from Apple Music", systemImage: "music.note.list")
                                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                        }
                    }

                    if selectedTrack != nil {
                        Button("Remove Song", systemImage: "minus.circle", role: .destructive) {
                            selectedTrack = nil
                        }
                    }
                } header: {
                    Text("Song")
                } footer: {
                    Text("Optional. The song reference stays connected to its music service while the idea remains shareable with everyone.")
                }
            }

            if selectedTrack == nil {
                Section("Photo") {
                    PhotoAttachmentPicker(
                        imageData: $imageData,
                        emptySymbol: category.symbol,
                        suggestedConcept: "Wedding \(category.title.lowercased()) inspiration for \(trimmedTitle.isEmpty ? "our celebration" : trimmedTitle)"
                    )
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
                            imageData: imageData,
                            musicTrack: category == .music ? selectedTrack : nil
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
            .environment(MusicCatalog())
    }
}
