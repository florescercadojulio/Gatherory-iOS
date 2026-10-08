import SwiftUI
import UIKit

struct IdeasView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
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
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                Picker("Idea filter", selection: $filter) {
                    ForEach(IdeaFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Filters ideas by status")

                ideaCollection
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
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

    @ViewBuilder
    private var ideaCollection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .firstTextBaseline) {
                Text(filter.collectionTitle)
                    .font(.title2.bold())

                Spacer(minLength: AppTheme.Spacing.compact)

                Text(filteredIdeas.count, format: .number)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        filteredIdeas.count == 1 ? "1 idea" : "\(filteredIdeas.count) ideas"
                    )
            }

            if filteredIdeas.isEmpty {
                ContentUnavailableView(
                    "No ideas here",
                    systemImage: "sparkles",
                    description: Text("Ideas from your support circle will appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.section)
            } else {
                MasonryLayout(
                    columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                    spacing: 12,
                    layoutDirection: layoutDirection
                ) {
                    ForEach(filteredIdeas) { idea in
                        ideaButton(idea)
                    }
                }
            }
        }
    }

    private func ideaButton(_ idea: WeddingIdea) -> some View {
        Button {
            selectedIdeaID = idea.id
        } label: {
            IdeaCollectionCard(
                idea: idea,
                transitionNamespace: ideaTransition
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens idea details. Touch and hold for actions.")
        .accessibilityAction(named: "Shortlist") {
            update(idea, to: .shortlisted)
        }
        .accessibilityAction(named: "Save for Now") {
            update(idea, to: .maybe)
        }
        .accessibilityAction(named: idea.status == .archived ? "Restore" : "Archive") {
            update(idea, to: idea.status == .archived ? .new : .archived)
        }
        .contextMenu {
            ideaActions(for: idea)
        }
    }

    @ViewBuilder
    private func ideaActions(for idea: WeddingIdea) -> some View {
        if idea.status != .shortlisted {
            Button("Shortlist", systemImage: "heart.fill") {
                update(idea, to: .shortlisted)
            }
        }

        if idea.status != .maybe && idea.status != .archived {
            Button("Save for Now", systemImage: "bookmark.fill") {
                update(idea, to: .maybe)
            }
        }

        Divider()

        if idea.status == .archived {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                update(idea, to: .new)
            }
        } else {
            Button("Archive", systemImage: "archivebox.fill") {
                update(idea, to: .archived)
            }
        }
    }

    private func update(_ idea: WeddingIdea, to status: IdeaStatus) {
        withAnimation {
            workspace.updateIdea(idea, status: status)
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

    var collectionTitle: String {
        switch self {
        case .all: "All Ideas"
        case .inbox: "Inbox"
        case .saved: "Saved"
        case .archived: "Archive"
        }
    }
}

private struct IdeaCollectionCard: View {
    let idea: WeddingIdea
    let transitionNamespace: Namespace.ID

    private var artworkAspectRatio: CGFloat {
        if let imageData = idea.imageData,
           let image = UIImage(data: imageData),
           image.size.height > 0 {
            return min(max(image.size.width / image.size.height, 0.72), 1.35)
        }

        if idea.musicTrack?.artworkURL != nil {
            return 1
        }

        return idea.category.collectionAspectRatio
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaArtwork(
                imageData: idea.imageData,
                remoteURL: idea.musicTrack?.artworkURL,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 22,
                blurStart: 0.30
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(0.14), location: 0.54),
                    .init(color: .black.opacity(0.74), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Label(idea.category.title, systemImage: idea.category.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(idea.title)
                    .font(.headline)
                    .lineLimit(3)

                HStack(spacing: 4) {
                    Text("From \(idea.submittedBy)")
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: idea.status.symbol)
                        .accessibilityHidden(true)
                }
                .font(.caption)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)
        }
        .aspectRatio(artworkAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .matchedTransitionSource(id: idea.id, in: transitionNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityValue(idea.status.title)
    }
}

private extension IdeaCategory {
    var collectionAspectRatio: CGFloat {
        switch self {
        case .venue: 0.82
        case .attire: 0.74
        case .flowers: 1.12
        case .food: 0.94
        case .photography: 1.20
        case .music: 1.0
        case .decor: 0.78
        case .invitations: 1.14
        case .honeymoon: 0.76
        case .other: 1.06
        }
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
        .appClearNavigationBar()
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
