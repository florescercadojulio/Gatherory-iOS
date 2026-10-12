import SwiftUI
import UIKit
import MusicKit

struct IdeasView: View {
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var filter: IdeaFilter = .all
    @State private var isAddingIdea = false
    @State private var addIdeaDetent: PresentationDetent = .medium
    @State private var selectedIdeaID: UUID?
    @Namespace private var ideaTransition

    private var filteredIdeas: [WeddingIdea] {
        workspace.contextualIdeas.filter(filter.includes)
    }

    var body: some View {
        ScrollView {
            ideaCollection
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
            ToolbarItem(placement: .principal) {
                EventContextLabel(section: "Ideas", eventTitle: workspace.selectedEventTitle)
            }

            ToolbarItemGroup(placement: .topBarLeading) {
                if let onExitWorkspace {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }

                Menu {
                    ForEach(IdeaFilter.allCases) { option in
                        Button {
                            withAnimation(.snappy) {
                                filter = option
                            }
                        } label: {
                            Label(
                                option.title,
                                systemImage: option == filter ? "checkmark" : option.symbol
                            )
                        }
                    }
                } label: {
                    Label(filter.title, systemImage: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filter ideas")
                .accessibilityValue(filter.title)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") {
                    addIdeaDetent = .medium
                    isAddingIdea = true
                }
                    .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingIdea) {
            NavigationStack {
                IdeaEditorView { detent in
                    withAnimation(.snappy) {
                        addIdeaDetent = detent
                    }
                }
            }
            .presentationDetents([.medium, .large], selection: $addIdeaDetent)
            .presentationDragIndicator(.visible)
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
        if filteredIdeas.isEmpty {
            ContentUnavailableView(
                filter.emptyTitle,
                systemImage: filter.symbol,
                description: Text(filter.emptyDescription)
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

enum IdeaFilter: String, CaseIterable, Identifiable {
    case all
    case inbox
    case saved
    case approved
    case passed
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .inbox: "Inbox"
        case .saved: "Saved"
        case .approved: "Approved"
        case .passed: "Passed"
        case .archived: "Archive"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .inbox: "tray"
        case .saved: "bookmark"
        case .approved: "checkmark.seal"
        case .passed: "xmark.circle"
        case .archived: "archivebox"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No ideas yet"
        case .inbox: "Inbox is clear"
        case .saved: "No saved ideas"
        case .approved: "No approved ideas"
        case .passed: "No passed ideas"
        case .archived: "No archived ideas"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: "Add an idea to start shaping the event."
        case .inbox: "New ideas from your planning team appear here."
        case .saved: "Ideas saved for later appear here."
        case .approved: "Ideas appear here after they are approved."
        case .passed: "Ideas you passed on appear here."
        case .archived: "Archived ideas appear here."
        }
    }

    func includes(_ idea: WeddingIdea) -> Bool {
        switch self {
        case .all:
            idea.status != .archived
        case .inbox:
            idea.status == .new
        case .saved:
            idea.status == .maybe || idea.status == .shortlisted
        case .approved:
            idea.status == .chosen
        case .passed:
            idea.status == .passed
        case .archived:
            idea.status == .archived
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
            artwork

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
                    Text(cardSupportingText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: idea.category == .music ? "person.3.fill" : idea.status.symbol)
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

    @ViewBuilder
    private var artwork: some View {
        if idea.category == .music {
            MusicPlaylistArtwork(
                imageData: idea.imageData,
                tracks: idea.musicTracks,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 22,
                blurStart: 0.30
            )
        } else {
            MediaArtwork(
                imageData: idea.imageData,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 22,
                blurStart: 0.30
            )
        }
    }

    private var cardSupportingText: String {
        if let link = idea.linkConfiguration {
            return link.url.host ?? link.url.absoluteString
        }
        guard idea.category == .music else { return "From \(idea.submittedBy)" }
        let count = idea.musicTracks.count
        return "\(count) \(count == 1 ? "song" : "songs") · Shared playlist"
    }
}

private extension IdeaCategory {
    var collectionAspectRatio: CGFloat {
        switch self {
        case .event: 0.84
        case .registry: 0.92
        case .link: 1.06
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
    @State private var isEditingIdea = false
    @State private var editorDetent: PresentationDetent = .large
    let ideaID: UUID
    let transitionNamespace: Namespace.ID

    private var idea: WeddingIdea? {
        workspace.ideas.first { $0.id == ideaID }
    }

    var body: some View {
        Group {
            if let idea {
                if idea.category == .event, idea.eventConfiguration != nil {
                    EventInvitationScreen(reference: .idea(idea.id))
                } else {
                    IdeaDetailScreen(idea: idea)
                }
            } else {
                ContentUnavailableView("Idea unavailable", systemImage: "sparkles")
            }
        }
        .navigationTitle("Idea details")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .appImageNavigationBarAppearance()
        .toolbar {
            if let idea {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit idea", systemImage: "pencil") {
                        editorDetent = .large
                        isEditingIdea = true
                    }
                    .labelStyle(.iconOnly)
                }

                if idea.category != .music {
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
                            Button("Approve", systemImage: "checkmark.circle.fill") {
                                withAnimation {
                                    workspace.updateIdea(idea, status: .chosen)
                                }
                            }
                        }

                        if idea.category == .event, idea.status == .chosen {
                            if workspace.timeline.contains(where: { $0.linkedIdeaID == idea.id }) {
                                Button("Added to Timeline", systemImage: "calendar.badge.checkmark") {}
                                    .disabled(true)
                            } else if idea.eventConfiguration?.proposedDate != nil {
                                Button("Add to Timeline", systemImage: "calendar.badge.plus") {
                                    _ = withAnimation {
                                        workspace.scheduleEventIdea(idea)
                                    }
                                }
                            } else {
                                Button("Add Date to Schedule", systemImage: "calendar.badge.clock") {
                                    editorDetent = .large
                                    isEditingIdea = true
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
        }
        .sheet(isPresented: $isEditingIdea) {
            if let idea {
                NavigationStack {
                    IdeaEditorView(existingIdea: idea) { detent in
                        withAnimation(.snappy) {
                            editorDetent = detent
                        }
                    }
                }
                .presentationDetents([.medium, .large], selection: $editorDetent)
                .presentationDragIndicator(.visible)
            }
        }
        .navigationTransition(.zoom(sourceID: ideaID, in: transitionNamespace))
    }
}

private struct IdeaDetailScreen: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(MusicPreviewPlayer.self) private var previewPlayer
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
                        IdeaCategoryDetailContent(idea: idea)
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
        .onDisappear {
            previewPlayer.stop()
        }
    }

    @ViewBuilder
    private var backgroundArtwork: some View {
        Group {
            if idea.category == .music {
                MusicPlaylistArtwork(
                    imageData: idea.imageData,
                    tracks: idea.musicTracks,
                    symbol: idea.category.symbol,
                    colors: idea.category.artworkColors,
                    accent: idea.category.artworkAccent,
                    ambientBlurRadius: 10,
                    progressiveBlurRadius: reduceTransparency ? 0 : 22,
                    blurStart: 0.44
                )
            } else {
                MediaArtwork(
                    imageData: idea.imageData,
                    symbol: idea.category.symbol,
                    colors: idea.category.artworkColors,
                    accent: idea.category.artworkAccent,
                    ambientBlurRadius: 10,
                    progressiveBlurRadius: reduceTransparency ? 0 : 22,
                    blurStart: 0.44
                )
            }
        }
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
        }
        .foregroundStyle(.white)
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            if idea.category != .event {
                IdeaMetadataRow(
                    title: "Shared by",
                    value: idea.submittedBy,
                    symbol: "person.fill"
                )
            }

            if idea.category.supportsInvitationVisibility {
                Divider()
                    .padding(.leading, 44)

                IdeaMetadataRow(
                    title: "Guests",
                    value: guestVisibilityValue,
                    symbol: "person.crop.rectangle"
                )
            }

            if let estimatedCost = idea.estimatedCost {
                if idea.category != .event {
                    Divider()
                        .padding(.leading, 44)
                }

                IdeaMetadataRow(
                    title: estimatedCostLabel,
                    value: estimatedCost.formatted(.currency(code: workspace.currencyCode)),
                    symbol: "tag.fill"
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            reduceTransparency ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .appImageOverlayAppearance()
    }

    private var guestVisibilityValue: String {
        guard idea.isShownOnInvitation else { return "Planning only" }
        return idea.status == .chosen ? "Shown on invitation" : "Shows when approved"
    }

    private var estimatedCostLabel: String {
        switch idea.category {
        case .event: "Estimated event cost"
        case .registry: "Estimated gift price"
        case .link: "Estimated cost"
        case .attire: "Estimated attire cost"
        case .food: "Estimated food budget"
        case .music: "Estimated music cost"
        case .venue: "Estimated venue cost"
        case .flowers: "Estimated floral budget"
        case .photography: "Estimated photography cost"
        case .decor: "Estimated decor budget"
        case .invitations: "Estimated stationery cost"
        case .honeymoon: "Estimated trip budget"
        case .other: "Estimated cost"
        }
    }
}

private struct IdeaCategoryDetailContent: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isPickingMusic = false
    @State private var pickedSongs: [Song] = []

    let idea: WeddingIdea

    var body: some View {
        Group {
            switch idea.category {
            case .link:
                if let configuration = idea.linkConfiguration {
                    linkContent(configuration)
                } else {
                    genericContent
                }

            case .event:
                if let configuration = idea.eventConfiguration {
                    EventIdeaDetailCard(idea: idea, configuration: configuration)
                } else {
                    genericContent
                }

        case .registry:
            if let configuration = idea.registryConfiguration {
                configurationContent(
                    primaryTitle: "Registry Category",
                    primaryValue: configuration.category.title,
                    primarySymbol: configuration.category.symbol,
                    facts: [
                        configuration.price.map {
                            IdeaDetailFact(
                                title: "Price",
                                value: $0.formatted(.currency(code: workspace.currencyCode)),
                                symbol: "tag.fill"
                            )
                        },
                        IdeaDetailFact(
                            title: "Quantity",
                            value: configuration.quantity.formatted(),
                            symbol: "shippingbox.fill"
                        )
                    ].compactMap { $0 }
                )
            } else {
                genericContent
            }

        case .venue:
            if let configuration = idea.venueConfiguration {
                configurationContent(
                    primaryTitle: "Setting",
                    primaryValue: configuration.setting.title,
                    primarySymbol: configuration.setting.symbol,
                    facts: [
                        configuration.area.isEmpty ? nil : IdeaDetailFact(title: "Area", value: configuration.area, symbol: "mappin.and.ellipse"),
                        configuration.capacity.map { IdeaDetailFact(title: "Capacity", value: "About \($0) guests", symbol: "person.3.fill") }
                    ].compactMap { $0 }
                )
            } else {
                genericContent
            }

        case .attire:
            if let configuration = idea.attireConfiguration {
                attireContent(configuration)
            } else {
                genericContent
            }

        case .food:
            if let configuration = idea.foodConfiguration {
                foodContent(configuration)
            } else {
                genericContent
            }

        case .flowers:
            if let configuration = idea.flowerConfiguration {
                configurationContent(
                    primaryTitle: "Floral Focus",
                    primaryValue: configuration.focus.title,
                    primarySymbol: configuration.focus.symbol,
                    facts: configuration.palette.isEmpty ? [] : [
                        IdeaDetailFact(title: "Palette", value: configuration.palette, symbol: "paintpalette.fill")
                    ]
                )
            } else {
                genericContent
            }

        case .photography:
            if let configuration = idea.photographyConfiguration {
                configurationContent(
                    primaryTitle: "Photography Style",
                    primaryValue: configuration.style.title,
                    primarySymbol: configuration.style.symbol,
                    facts: [
                        configuration.coverageHours.map { IdeaDetailFact(title: "Coverage", value: "\($0) hours", symbol: "clock.fill") },
                        configuration.priorities.isEmpty ? nil : IdeaDetailFact(title: "Priorities", value: configuration.priorities, symbol: "camera.viewfinder")
                    ].compactMap { $0 }
                )
            } else {
                genericContent
            }

        case .music:
            musicContent

        case .decor:
            if let configuration = idea.decorConfiguration {
                configurationContent(
                    primaryTitle: "Decor Area",
                    primaryValue: configuration.focus.title,
                    primarySymbol: configuration.focus.symbol,
                    facts: configuration.paletteOrMaterials.isEmpty ? [] : [
                        IdeaDetailFact(title: "Colors & Materials", value: configuration.paletteOrMaterials, symbol: "paintbrush.fill")
                    ]
                )
            } else {
                genericContent
            }

        case .invitations:
            if let configuration = idea.invitationConfiguration {
                configurationContent(
                    primaryTitle: "Format",
                    primaryValue: configuration.format.title,
                    primarySymbol: configuration.format.symbol,
                    facts: [
                        configuration.quantity.map { IdeaDetailFact(title: "Quantity", value: $0.formatted(), symbol: "number") },
                        configuration.productionNotes.isEmpty ? nil : IdeaDetailFact(title: "Production", value: configuration.productionNotes, symbol: "printer.fill")
                    ].compactMap { $0 }
                )
            } else {
                genericContent
            }

        case .honeymoon:
            if let configuration = idea.honeymoonConfiguration {
                configurationContent(
                    primaryTitle: "Trip Style",
                    primaryValue: configuration.style.title,
                    primarySymbol: configuration.style.symbol,
                    facts: [
                        configuration.destination.isEmpty ? nil : IdeaDetailFact(title: "Destination", value: configuration.destination, symbol: "mappin.and.ellipse"),
                        configuration.nights.map { IdeaDetailFact(title: "Length", value: "\($0) nights", symbol: "moon.stars.fill") }
                    ].compactMap { $0 }
                )
            } else {
                genericContent
            }

            case .other:
                genericContent
            }
        }
        .musicPicker(
            isPresented: $isPickingMusic,
            title: Text("Add to Playlist"),
            selection: $pickedSongs
        )
        .onChange(of: pickedSongs) { _, songs in
            appendPickedSongs(songs)
        }
    }

    private func configurationContent(
        primaryTitle: String,
        primaryValue: String,
        primarySymbol: String,
        facts: [IdeaDetailFact]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: primarySymbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(primaryValue)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !idea.note.isEmpty {
                Divider()
                detailText(title: "Why It Works", text: idea.note, symbol: "text.quote")
            }

            ForEach(facts) { fact in
                Divider()
                detailText(title: fact.title, text: fact.value, symbol: fact.symbol)
            }
        }
        .ideaDetailCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .contain)
    }

    private func linkContent(_ configuration: LinkIdeaConfiguration) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: "link")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Website")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(configuration.url.host ?? configuration.url.absoluteString)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            if !idea.note.isEmpty {
                Divider()
                detailText(title: "Description", text: idea.note, symbol: "text.alignleft")
            }

            Link(destination: configuration.url) {
                Label("Open Website", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
            }
            .buttonStyle(.borderedProminent)
        }
        .ideaDetailCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .contain)
    }

    private func attireContent(_ configuration: AttireIdeaConfiguration) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(spacing: AppTheme.Spacing.standard) {
                AttireStyleSilhouette(style: configuration.style, color: .white)
                    .frame(width: 58, height: 72)
                    .padding(AppTheme.Spacing.compact)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dress Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(configuration.style.title)
                        .font(.title2.bold())
                }

                Spacer(minLength: 0)
            }

            if !idea.note.isEmpty {
                detailText(title: "Inspiration", text: idea.note, symbol: "sparkles")
            }

            if !configuration.restrictions.isEmpty {
                detailText(title: "Guidance", text: configuration.restrictions, symbol: "checklist")
            }
        }
        .ideaDetailCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .contain)
    }

    private func foodContent(_ configuration: FoodIdeaConfiguration) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(spacing: AppTheme.Spacing.standard) {
                Label(configuration.type.title, systemImage: configuration.type.symbol)
                    .font(.headline)

                Spacer(minLength: AppTheme.Spacing.compact)

                if let servings = configuration.servings {
                    Label("Serves \(servings)", systemImage: "person.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !idea.note.isEmpty {
                detailText(title: "Concept", text: idea.note, symbol: "fork.knife")
            }

            if !configuration.dietaryNotes.isEmpty {
                detailText(
                    title: "Dietary Considerations",
                    text: configuration.dietaryNotes,
                    symbol: "leaf.fill"
                )
            }
        }
        .ideaDetailCard(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .contain)
    }

    private var musicContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Image(systemName: "person.3.sequence.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Event Playlist")
                        .font(.headline)
                    Text("\(idea.musicTracks.count) \(idea.musicTracks.count == 1 ? "song" : "songs")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.Spacing.compact)

                Button {
                    isPickingMusic = true
                } label: {
                    Label("Add Songs", systemImage: "music.note.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if !idea.note.isEmpty {
                Divider()
                detailText(title: "Playlist Direction", text: idea.note, symbol: "music.note.list")
                    .padding(.bottom, idea.musicTracks.isEmpty ? 0 : AppTheme.Spacing.compact)
            }

            ForEach(Array(idea.musicTracks.enumerated()), id: \.element.id) { index, track in
                if index > 0 || !idea.note.isEmpty {
                    Divider()
                }

                trackRow(track)
            }

            if idea.musicTracks.isEmpty {
                Text("No songs yet. Add the first one for everyone attending this event.")
                    .foregroundStyle(.secondary)
            }
        }
        .ideaDetailCard(reduceTransparency: reduceTransparency)
    }

    private func appendPickedSongs(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        var updatedIdea = idea
        var tracks = idea.musicTracks
        for song in songs {
            let track = MusicTrack(appleMusicSong: song)
            guard !tracks.contains(where: { $0.id == track.id }) else { continue }
            tracks.append(track)
        }
        updatedIdea.configuration = .music(MusicIdeaConfiguration(tracks: tracks))
        workspace.updateIdea(updatedIdea)
        pickedSongs.removeAll()
    }

    private var genericContent: some View {
        Group {
            if !idea.note.isEmpty {
                detailText(title: "About This Idea", text: idea.note, symbol: idea.category.symbol)
                    .ideaDetailCard(reduceTransparency: reduceTransparency)
            }
        }
    }

    private func detailText(title: String, text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trackRow(_ track: MusicTrack) -> some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            MusicTrackArtwork(track: track)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            if track.previewURL != nil {
                MusicPreviewButton(track: track)
            }

            if let externalURL = track.externalURL {
                Link(destination: externalURL) {
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: AppTheme.Layout.minimumTouchTarget, height: AppTheme.Layout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open \(track.title) in \(track.providerID.displayName)")
            }
        }
        .frame(minHeight: 56)
    }
}

private struct EventIdeaDetailCard: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var weather = EventWeatherModel()

    let idea: WeddingIdea
    let configuration: EventIdeaConfiguration

    private var requestID: String {
        let date = configuration.proposedDate?.timeIntervalSinceReferenceDate ?? 0
        let endDate = configuration.proposedEndDate?.timeIntervalSinceReferenceDate ?? 0
        let latitude = configuration.location?.latitude ?? 0
        let longitude = configuration.location?.longitude ?? 0
        return "\(date)-\(endDate)-\(configuration.isAllDay)-\(configuration.timeZoneIdentifier)-\(latitude)-\(longitude)"
    }

    var body: some View {
        VStack(spacing: 0) {
            EventIdeaMetadataRow(
                title: "Purpose",
                value: configuration.purpose.title,
                symbol: configuration.purpose.symbol
            )

            divider
            EventIdeaMetadataRow(
                title: "Participants",
                value: configuration.audience.title,
                symbol: configuration.audience.symbol
            )

            if let proposedDate = configuration.proposedDate {
                divider
                EventIdeaMetadataRow(
                    title: "Proposed Schedule",
                    value: EventSchedule(
                        startsAt: proposedDate,
                        endsAt: configuration.proposedEndDate,
                        isAllDay: configuration.isAllDay,
                        timeZoneIdentifier: configuration.timeZoneIdentifier
                    ).summary,
                    symbol: "calendar"
                )
            }

            if let proposedBudget = configuration.proposedBudget {
                divider
                EventIdeaMetadataRow(
                    title: "Budget Limit",
                    value: proposedBudget.formatted(
                        .currency(code: workspace.currencyCode)
                    ),
                    symbol: "chart.pie.fill"
                )
            }

            if !configuration.attireDescription.isEmpty {
                divider
                EventIdeaMetadataRow(
                    title: "Attire",
                    value: configuration.attireDescription,
                    symbol: "hanger"
                )
            }

            if let location = configuration.location {
                divider
                if let directionsURL = directionsURL(for: location) {
                    Link(destination: directionsURL) {
                        EventIdeaMetadataRow(
                            title: "Location",
                            value: location.formatted,
                            symbol: "mappin.and.ellipse"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens directions in Maps")
                } else {
                    EventIdeaMetadataRow(
                        title: "Location",
                        value: location.formatted,
                        symbol: "mappin.and.ellipse"
                    )
                }
            }

            if configuration.proposedDate != nil, configuration.location != nil {
                divider
                TimelineWeatherRow(
                    phase: weather.phase,
                    attribution: weather.attribution
                ) {
                    loadWeather()
                }
            }

            divider
            EventIdeaMetadataRow(
                title: "Proposed By",
                value: idea.submittedBy,
                symbol: "person.2.fill"
            )

            if !idea.note.isEmpty {
                divider
                EventIdeaMetadataRow(
                    title: "Notes",
                    value: idea.note,
                    symbol: "text.quote"
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            reduceTransparency ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .appImageOverlayAppearance()
        .task(id: requestID) {
            loadWeather()
        }
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 44)
    }

    private func loadWeather() {
        guard let proposedDate = configuration.proposedDate else { return }
        Task {
            await weather.load(on: proposedDate, location: configuration.location)
        }
    }

    private func directionsURL(for location: EventLocation) -> URL? {
        if let latitude = location.latitude, let longitude = location.longitude {
            let name = location.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Event"
            return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(name)")
        }

        let address = location.formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return address.isEmpty ? nil : URL(string: "https://maps.apple.com/?q=\(address)")
    }
}

private struct EventIdeaMetadataRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if title == "Location" {
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct IdeaDetailFact: Identifiable {
    let title: String
    let value: String
    let symbol: String

    var id: String { title }
}

private extension View {
    func ideaDetailCard(reduceTransparency: Bool) -> some View {
        self
            .padding(AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                reduceTransparency ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            )
            .appImageOverlayAppearance()
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

private struct IdeaEditorView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(MusicPreviewPlayer.self) private var previewPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var title = ""
    @State private var note = ""
    @State private var linkAddress = ""
    @State private var category: IdeaCategory = .other
    @State private var isChoosingCategory = true
    @State private var categoryPage = 0
    @State private var estimatedCost = ""
    @State private var imageData: Data?
    @State private var showOnInvitation = false
    @State private var attireStyle: AttireStyle = .any
    @State private var attireRestrictions = ""
    @State private var venueSetting: VenueSetting = .indoor
    @State private var venueCapacity = ""
    @State private var venueArea = ""
    @State private var foodType: FoodIdeaType = .meal
    @State private var foodServings = ""
    @State private var dietaryNotes = ""
    @State private var flowerFocus: FlowerFocus = .bouquet
    @State private var flowerPalette = ""
    @State private var photographyStyle: PhotographyStyle = .documentary
    @State private var photographyHours = ""
    @State private var photographyPriorities = ""
    @State private var decorFocus: DecorFocus = .reception
    @State private var decorPalette = ""
    @State private var invitationFormat: InvitationFormat = .printed
    @State private var invitationQuantity = ""
    @State private var invitationNotes = ""
    @State private var tripStyle: TripStyle = .relaxing
    @State private var tripDestination = ""
    @State private var tripNights = ""
    @State private var musicTracks: [MusicTrack] = []
    @State private var editingMusicPlaylistID: UUID?
    @State private var isPickingMusic = false
    @State private var pickedSongs: [Song] = []
    @State private var eventCategory: TimelineCategory = .other
    @State private var eventPurpose: EventPurpose = .planning
    @State private var eventAudience: EventAudience = .inherited
    @State private var eventBudgetAmount = ""
    @State private var includesProposedDate = false
    @State private var eventProposedDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var eventProposedEndDate: Date?
    @State private var eventIsAllDay = false
    @State private var eventTimeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
    @State private var isEditingEventDateAndTime = false
    @State private var eventLocation: EventLocation?
    @State private var isEditingEventLocation = false
    @State private var isShowingEventContextPrompt = false
    @State private var registryCategory: RegistryCategory = .home
    @State private var registryPrice = ""
    @State private var registryQuantity = 1

    let existingIdea: WeddingIdea?
    let setDetent: (PresentationDetent) -> Void

    init(
        existingIdea: WeddingIdea? = nil,
        setDetent: @escaping (PresentationDetent) -> Void
    ) {
        self.existingIdea = existingIdea
        self.setDetent = setDetent

        guard let existingIdea else { return }

        _title = State(initialValue: existingIdea.title)
        _note = State(initialValue: existingIdea.note)
        _category = State(initialValue: existingIdea.category)
        _isChoosingCategory = State(initialValue: false)
        _categoryPage = State(initialValue: Self.legacyAttendableCategories.contains(existingIdea.category) ? 1 : 0)
        _estimatedCost = State(
            initialValue: existingIdea.estimatedCost.map {
                MoneyInputFormatter.editingText(
                    from: NSDecimalNumber(decimal: $0).stringValue,
                    allowsFraction: true
                )
            } ?? ""
        )
        _imageData = State(initialValue: existingIdea.imageData)
        _showOnInvitation = State(initialValue: existingIdea.isShownOnInvitation)

        switch existingIdea.configuration {
        case .standard:
            break
        case .link(let configuration):
            _linkAddress = State(initialValue: configuration.url.absoluteString)
        case .attire(let configuration):
            _attireStyle = State(initialValue: configuration.style)
            _attireRestrictions = State(initialValue: configuration.restrictions)
        case .venue(let configuration):
            _venueSetting = State(initialValue: configuration.setting)
            _venueCapacity = State(initialValue: configuration.capacity.map { String($0) } ?? "")
            _venueArea = State(initialValue: configuration.area)
        case .food(let configuration):
            _foodType = State(initialValue: configuration.type)
            _foodServings = State(initialValue: configuration.servings.map { String($0) } ?? "")
            _dietaryNotes = State(initialValue: configuration.dietaryNotes)
        case .flowers(let configuration):
            _flowerFocus = State(initialValue: configuration.focus)
            _flowerPalette = State(initialValue: configuration.palette)
        case .photography(let configuration):
            _photographyStyle = State(initialValue: configuration.style)
            _photographyHours = State(initialValue: configuration.coverageHours.map { String($0) } ?? "")
            _photographyPriorities = State(initialValue: configuration.priorities)
        case .decor(let configuration):
            _decorFocus = State(initialValue: configuration.focus)
            _decorPalette = State(initialValue: configuration.paletteOrMaterials)
        case .invitations(let configuration):
            _invitationFormat = State(initialValue: configuration.format)
            _invitationQuantity = State(initialValue: configuration.quantity.map { String($0) } ?? "")
            _invitationNotes = State(initialValue: configuration.productionNotes)
        case .honeymoon(let configuration):
            _tripStyle = State(initialValue: configuration.style)
            _tripDestination = State(initialValue: configuration.destination)
            _tripNights = State(initialValue: configuration.nights.map { String($0) } ?? "")
        case .music(let configuration):
            _musicTracks = State(initialValue: configuration.tracks)
        case .event(let configuration):
            _eventCategory = State(initialValue: configuration.category)
            _eventPurpose = State(
                initialValue: configuration.category == .honeymoon
                    ? .eventExperience
                    : configuration.purpose
            )
            _eventAudience = State(
                initialValue: configuration.category == .honeymoon
                    ? .hostsOnly
                    : configuration.audience
            )
            _eventBudgetAmount = State(
                initialValue: configuration.proposedBudget.map {
                    MoneyInputFormatter.editingText(
                        from: NSDecimalNumber(decimal: $0).stringValue,
                        allowsFraction: false
                    )
                } ?? ""
            )
            _includesProposedDate = State(initialValue: configuration.proposedDate != nil)
            _eventProposedDate = State(initialValue: configuration.proposedDate ?? .now)
            _eventProposedEndDate = State(initialValue: configuration.proposedEndDate)
            _eventIsAllDay = State(initialValue: configuration.isAllDay)
            _eventTimeZoneIdentifier = State(initialValue: configuration.timeZoneIdentifier)
            _eventLocation = State(initialValue: configuration.location)
            _attireStyle = State(initialValue: configuration.attireStyle)
            _attireRestrictions = State(initialValue: configuration.attireGuidance)
        case .registry(let configuration):
            _registryCategory = State(initialValue: configuration.category)
            _registryPrice = State(
                initialValue: configuration.price.map {
                    MoneyInputFormatter.editingText(
                        from: NSDecimalNumber(decimal: $0).stringValue
                    )
                } ?? ""
            )
            _registryQuantity = State(initialValue: configuration.quantity)
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ideaBeingEdited: WeddingIdea? {
        if let existingIdea { return existingIdea }
        guard category == .music, let editingMusicPlaylistID else { return nil }
        return workspace.ideas.first { $0.id == editingMusicPlaylistID }
    }

    private var suggestedTitle: String {
        switch category {
        case .event:
            return eventCategory == .other
                ? (eventPurpose == .planning ? "Planning Event" : "Event")
                : eventCategory.title
        case .registry:
            return registryCategory == .cashFund ? "Cash Fund" : "Registry Gift"
        case .link:
            return "Website"
        case .attire:
            return attireStyle == .any ? "Attire" : "\(attireStyle.title) Attire"
        case .venue:
            return venueSetting == .other ? "Venue" : "\(venueSetting.title) Venue"
        case .food:
            return switch foodType {
            case .tasting: "Food Tasting"
            case .other: "Food & Cake"
            default: foodType.title
            }
        case .music:
            return "\(workspace.selectedEventTitle) Playlist"
        case .flowers:
            return flowerFocus == .other ? "Flowers" : "\(flowerFocus.title) Flowers"
        case .photography:
            return photographyStyle == .other ? "Photography" : "\(photographyStyle.title) Photography"
        case .decor:
            return decorFocus == .other ? "Decor" : "\(decorFocus.title) Decor"
        case .invitations:
            return invitationFormat == .other ? "Invitations" : "\(invitationFormat.title) Invitations"
        case .honeymoon:
            let destination = tripDestination.trimmingCharacters(in: .whitespacesAndNewlines)
            if !destination.isEmpty {
                return destination
            } else if tripStyle == .other {
                return "Honeymoon"
            } else {
                return "\(tripStyle.title) Honeymoon"
            }
        case .other:
            return "Other Idea"
        }
    }

    private var resolvedTitle: String {
        if category == .event { return suggestedTitle }
        if category == .music { return suggestedTitle }
        return trimmedTitle.isEmpty ? suggestedTitle : trimmedTitle
    }

    private var notePrompt: String {
        switch category {
        case .event: "Why should this event happen? (optional)"
        case .registry: "Why would this be useful? (optional)"
        case .link: "Description (optional)"
        case .attire: "Extra guidance (optional)"
        case .venue: "What stands out about this place? (optional)"
        case .food: "What should collaborators know? (optional)"
        case .music: "Playlist direction or moment (optional)"
        case .flowers: "Varieties or inspiration (optional)"
        case .photography: "Creative direction (optional)"
        case .decor: "Mood or inspiration (optional)"
        case .invitations: "Message or visual direction (optional)"
        case .honeymoon: "What makes this trip appealing? (optional)"
        case .other: "What makes it special? (optional)"
        }
    }

    private var estimatePrompt: String {
        switch category {
        case .event: "Estimated event cost"
        case .attire: "Estimated attire cost"
        case .venue: "Estimated venue cost"
        case .food: "Estimated food cost"
        case .music: "Estimated music cost"
        case .flowers: "Estimated floral cost"
        case .photography: "Estimated photography cost"
        case .decor: "Estimated decor cost"
        case .invitations: "Estimated stationery cost"
        case .honeymoon: "Estimated trip cost"
        case .other: "Estimated cost"
        case .registry: "Estimated cost"
        case .link: "Estimated cost"
        }
    }

    private var normalizedLinkURL: URL? {
        LinkIdeaConfiguration.normalizedURL(from: linkAddress)
    }

    private var parsedEstimate: Decimal? {
        guard !estimatedCost.isEmpty else { return nil }
        return MoneyInputFormatter.decimal(from: estimatedCost)
    }

    private var parsedEventBudget: Decimal? {
        guard !eventBudgetAmount.isEmpty else { return nil }
        return MoneyInputFormatter.decimal(from: eventBudgetAmount)
    }

    private var hasValidEventBudget: Bool {
        category != .event
            || eventBudgetAmount.isEmpty
            || (parsedEventBudget.map { $0 > .zero } ?? false)
    }

    private var hasValidEstimate: Bool {
        estimatedCost.isEmpty || parsedEstimate != nil
    }

    private func parsedOptionalInt(_ value: String) -> Int? {
        guard !value.isEmpty else { return nil }
        return Int(value)
    }

    private func isValidOptionalInt(_ value: String) -> Bool {
        value.isEmpty || parsedOptionalInt(value) != nil
    }

    private var hasValidCategoryNumbers: Bool {
        let standardNumbersAreValid = [foodServings, venueCapacity, photographyHours, invitationQuantity, tripNights]
            .allSatisfy(isValidOptionalInt)
        let registryPriceIsValid = registryPrice.isEmpty
            || MoneyInputFormatter.decimal(from: registryPrice) != nil
        return standardNumbersAreValid && registryPriceIsValid
    }

    private var isValid: Bool {
        hasValidEstimate
            && hasValidCategoryNumbers
            && hasValidEventBudget
            && (category != .link || (!trimmedTitle.isEmpty && normalizedLinkURL != nil))
    }

    private var editedIdea: WeddingIdea {
        let baseIdea = ideaBeingEdited
        return WeddingIdea(
            id: baseIdea?.id ?? UUID(),
            eventID: baseIdea?.eventID ?? workspace.selectedEventID,
            title: resolvedTitle,
            note: trimmedNote,
            category: category,
            submittedBy: baseIdea?.submittedBy ?? workspace.members.first?.name ?? "You",
            submittedByUserID: baseIdea?.submittedByUserID,
            estimatedCost: category == .music || category == .link ? nil : parsedEstimate,
            status: category == .music ? .chosen : baseIdea?.status ?? .new,
            submittedAt: baseIdea?.submittedAt ?? .now,
            imageData: imageData,
            configuration: ideaConfiguration,
            invitationVisibility: category.supportsInvitationVisibility
                ? (showOnInvitation ? .shownToGuests : .planningOnly)
                : .planningOnly
        )
    }

    private var hasChanges: Bool {
        guard let ideaBeingEdited else { return true }
        return editedIdea != ideaBeingEdited
    }

    private var ideaConfiguration: IdeaConfiguration {
        switch category {
        case .link:
            return .link(
                LinkIdeaConfiguration(
                    url: normalizedLinkURL ?? URL(string: "https://example.invalid")!
                )
            )
        case .event:
            return .event(
                EventIdeaConfiguration(
                    category: eventCategory,
                    purpose: eventPurpose,
                    audience: eventAudience,
                    requiresBudget: parsedEventBudget != nil,
                    proposedBudget: parsedEventBudget,
                    proposedDate: includesProposedDate ? eventProposedDate : nil,
                    proposedEndDate: includesProposedDate ? eventProposedEndDate : nil,
                    isAllDay: eventIsAllDay,
                    timeZoneIdentifier: eventTimeZoneIdentifier,
                    location: eventLocation,
                    attireStyle: attireStyle,
                    attireGuidance: attireRestrictions.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .registry:
            return .registry(
                RegistryIdeaConfiguration(
                    category: registryCategory,
                    price: registryPrice.isEmpty
                        ? nil
                        : MoneyInputFormatter.decimal(from: registryPrice),
                    quantity: registryQuantity
                )
            )
        case .attire:
            return .attire(
                AttireIdeaConfiguration(
                    style: attireStyle,
                    restrictions: attireRestrictions.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .venue:
            return .venue(
                VenueIdeaConfiguration(
                    setting: venueSetting,
                    capacity: parsedOptionalInt(venueCapacity),
                    area: venueArea.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .food:
            return .food(
                FoodIdeaConfiguration(
                    type: foodType,
                    servings: parsedOptionalInt(foodServings),
                    dietaryNotes: dietaryNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .flowers:
            return .flowers(
                FlowerIdeaConfiguration(
                    focus: flowerFocus,
                    palette: flowerPalette.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .photography:
            return .photography(
                PhotographyIdeaConfiguration(
                    style: photographyStyle,
                    coverageHours: parsedOptionalInt(photographyHours),
                    priorities: photographyPriorities.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .decor:
            return .decor(
                DecorIdeaConfiguration(
                    focus: decorFocus,
                    paletteOrMaterials: decorPalette.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .invitations:
            return .invitations(
                InvitationIdeaConfiguration(
                    format: invitationFormat,
                    quantity: parsedOptionalInt(invitationQuantity),
                    productionNotes: invitationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        case .honeymoon:
            return .honeymoon(
                HoneymoonIdeaConfiguration(
                    style: tripStyle,
                    destination: tripDestination.trimmingCharacters(in: .whitespacesAndNewlines),
                    nights: parsedOptionalInt(tripNights)
                )
            )
        case .music:
            return .music(MusicIdeaConfiguration(tracks: musicTracks))
        case .other:
            return .standard
        }
    }

    var body: some View {
        Group {
            if isChoosingCategory {
                categoryChooser
                    .transition(.opacity)
            } else {
                ideaEditor(for: category)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationTitle(editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardDismissal()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            if isChoosingCategory {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") {
                        beginEditing()
                    }
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ideaBeingEdited == nil ? "Add" : "Save") {
                        saveIdea()
                    }
                    .disabled(!isValid || !hasChanges)
                }
            }
        }
        .alert("Switch to the Main Event?", isPresented: $isShowingEventContextPrompt) {
            Button("Not Now", role: .cancel) {}
            Button("Switch & Continue") {
                switchToMainEventAndContinue()
            }
        } message: {
            Text("Event ideas are only available in the main event context.")
        }
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private var categoryChooser: some View {
        ScrollView {
            categoryGrid(selectedCategory: category)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Spacing.compact)
                .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.ColorToken.background)
    }

    private func ideaEditor(for category: IdeaCategory) -> some View {
        Form {
            selectedCategorySection(for: category)

            switch category {
            case .link:
                categoryConfiguration(for: category)
                    .listRowBackground(AppTheme.ColorToken.surface)

            case .music:
                categoryConfiguration(for: category)
                    .listRowBackground(AppTheme.ColorToken.surface)
                playlistNotesSection

            case .event:
                categoryConfiguration(for: category)
                    .listRowBackground(AppTheme.ColorToken.surface)
                ideaIdentitySection(for: category)
                eventPlanningSection

            case .registry:
                ideaIdentitySection(for: category)
                categoryConfiguration(for: category)
                    .listRowBackground(AppTheme.ColorToken.surface)

            default:
                ideaIdentitySection(for: category)
                categoryConfiguration(for: category)
                    .listRowBackground(AppTheme.ColorToken.surface)

                if category.supportsInvitationVisibility {
                    invitationVisibilitySection(for: category)
                }

                costEstimateSection(for: category)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .onChange(of: eventCategory) { _, updatedCategory in
            if updatedCategory == .honeymoon {
                eventPurpose = .eventExperience
                eventAudience = .hostsOnly
            } else if eventAudience == .hostsOnly {
                eventAudience = .inherited
            }
        }
        .sheet(isPresented: $isEditingEventLocation) {
            EventLocationEditorView(location: eventLocation) { updatedLocation in
                eventLocation = updatedLocation
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingEventDateAndTime) {
            EventDateTimeEditorView(
                startsAt: eventProposedDate,
                endsAt: eventProposedEndDate,
                isAllDay: eventIsAllDay,
                timeZoneIdentifier: eventTimeZoneIdentifier
            ) { updatedStart, updatedEnd, updatedAllDay, updatedTimeZone in
                eventProposedDate = updatedStart
                eventProposedEndDate = updatedEnd
                eventIsAllDay = updatedAllDay
                eventTimeZoneIdentifier = updatedTimeZone
                includesProposedDate = true
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .musicPicker(
            isPresented: $isPickingMusic,
            title: Text("Add to \(workspace.selectedEventTitle)"),
            selection: $pickedSongs
        )
        .onChange(of: pickedSongs) { _, songs in
            appendPickedSongs(songs)
        }
    }

    private func selectedCategorySection(for category: IdeaCategory) -> some View {
        Section {
            Button {
                withAnimation(.snappy) {
                    isChoosingCategory = true
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: category.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(category.artworkAccent)
                        .frame(width: 48, height: 48)
                        .background(
                            category.artworkAccent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        Text("For \(workspace.selectedEventTitle)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: AppTheme.Spacing.compact)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .accessibilityHidden(true)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: AppTheme.Layout.minimumTouchTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Idea type, \(category.title), for \(workspace.selectedEventTitle)"
            )
            .accessibilityHint("Choose a different idea type")
        } header: {
            Text("Idea Type")
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private func ideaIdentitySection(for category: IdeaCategory) -> some View {
        Section {
            if category != .event {
                TextField(titlePrompt(for: category), text: $title)
                    .textInputAutocapitalization(.sentences)
            }

            TextField(notePrompt, text: $note, axis: .vertical)
                .lineLimit(3...6)

            PhotoAttachmentPicker(
                imageData: $imageData,
                emptySymbol: category.symbol,
                fallbackColors: category.artworkColors,
                fallbackAccent: category.artworkAccent,
                suggestedConcept: "Wedding \(category.title.lowercased()) inspiration for \(resolvedTitle)"
            )
        } header: {
            Text(identitySectionTitle(for: category))
        } footer: {
            if category == .event {
                Text("Explain what makes this event worth adding. The cover helps everyone recognize it at a glance.")
            } else {
                Text("Leave the title blank to use “\(suggestedTitle)”.")
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var playlistNotesSection: some View {
        Section {
            TextField(notePrompt, text: $note, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Playlist Direction")
        } footer: {
            Text("Add a mood, moment, or request that helps everyone choose songs for this event.")
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private func invitationVisibilitySection(for category: IdeaCategory) -> some View {
        Section {
            Toggle(isOn: $showOnInvitation) {
                Label("Show to Guests", systemImage: "person.crop.rectangle")
            }
        } header: {
            Text("Guest Visibility")
        } footer: {
            if category == .attire {
                Text(
                    showOnInvitation
                        ? "When approved, this becomes an acceptable dress option for this event."
                        : "This attire idea stays in planning, even after it is approved."
                )
            } else {
                Text(
                    showOnInvitation
                        ? "When approved, this appears in the event details guests can see."
                        : "This idea stays with the planning team, even after it is approved."
                )
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var eventPlanningSection: some View {
        Section {
            EventBudgetAmountField(
                amount: $eventBudgetAmount,
                currencyCode: workspace.currencyCode
            )

            MoneyAmountField(
                amount: $estimatedCost,
                title: "Estimated Cost",
                currencyCode: workspace.currencyCode
            )
        } header: {
            Text("Budget & Cost")
        } footer: {
            if !hasValidEventBudget {
                Text("Enter a budget greater than zero, or leave it blank.")
                    .foregroundStyle(AppTheme.ColorToken.destructive)
            } else {
                Text("Set a spending limit only when this event needs one. The estimate becomes a tracked cost after approval.")
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private func costEstimateSection(for category: IdeaCategory) -> some View {
        Section {
            MoneyAmountField(
                amount: $estimatedCost,
                title: estimatePrompt,
                placeholder: "Optional",
                symbol: category.symbol,
                style: .prominent,
                currencyCode: workspace.currencyCode
            )
        } header: {
            Text("Cost Estimate")
        } footer: {
            Text("Optional. Add this only when the idea affects the event budget.")
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private func identitySectionTitle(for category: IdeaCategory) -> String {
        switch category {
        case .event: "Event Story & Cover"
        case .registry: "Gift or Fund"
        case .venue: "Venue Idea"
        case .attire: "Attire Idea"
        case .flowers: "Floral Idea"
        case .food: "Food or Cake Idea"
        case .photography: "Photography Idea"
        case .decor: "Decor Idea"
        case .invitations: "Invitation Idea"
        case .honeymoon: "Trip Idea"
        case .other: "Idea"
        case .link, .music: category.title
        }
    }

    private func titlePrompt(for category: IdeaCategory) -> String {
        switch category {
        case .registry: "Gift or fund name (optional)"
        case .venue: "Venue name (optional)"
        case .attire: "Look name (optional)"
        case .flowers: "Arrangement name (optional)"
        case .food: "Dish, cake, or vendor (optional)"
        case .photography: "Photographer or concept (optional)"
        case .decor: "Decor idea name (optional)"
        case .invitations: "Invitation concept (optional)"
        case .honeymoon: "Trip name (optional)"
        case .other: "Idea title (optional)"
        case .event, .link, .music: "Title"
        }
    }

    private var editorTitle: String {
        if isChoosingCategory { return "Choose a Category" }
        if category == .music { return "Event Playlist" }
        return ideaBeingEdited == nil ? "New Idea" : "Edit Idea"
    }

    private static let categoryPages: [[IdeaCategory]] = [
        [.link, .event, .registry, .attire, .food, .flowers, .music, .decor, .invitations, .other]
    ]
    private static let legacyAttendableCategories: Set<IdeaCategory> = [.venue, .photography, .honeymoon]

    private var visibleCategoryPages: [[IdeaCategory]] {
        var pages = Self.categoryPages
            .filter { !$0.isEmpty }

        if let existingIdea, Self.legacyAttendableCategories.contains(existingIdea.category) {
            pages.append([existingIdea.category])
        }
        return pages
    }

    private func categoryGrid(selectedCategory: IdeaCategory?) -> some View {
        TabView(selection: $categoryPage) {
            ForEach(visibleCategoryPages.indices, id: \.self) { pageIndex in
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                            count: 3
                        ),
                        spacing: AppTheme.Spacing.compact
                    ) {
                        ForEach(visibleCategoryPages[pageIndex]) { option in
                            categoryTile(option, isSelected: selectedCategory == option)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .tag(pageIndex)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 500 : 390)
        .accessibilityLabel("Idea categories")
    }

    private func categoryTile(_ option: IdeaCategory, isSelected: Bool) -> some View {
        let isContextRestricted = option == .event && !workspace.isMainEventContext

        return Button {
            if isContextRestricted {
                isShowingEventContextPrompt = true
            } else {
                select(option)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: option.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(
                            isContextRestricted
                                ? AppTheme.ColorToken.textSecondary
                                : isSelected ? AppTheme.ColorToken.onAccent : option.artworkAccent
                        )
                        .frame(width: 38, height: 38)
                        .background(
                            isSelected && !isContextRestricted ? option.artworkAccent : Color.clear,
                            in: Circle()
                        )
                        .background(.regularMaterial, in: Circle())

                    if isContextRestricted {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                            .offset(x: 3, y: -3)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.ColorToken.onAccent, AppTheme.ColorToken.accent)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(option.title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        isContextRestricted
                            ? AppTheme.ColorToken.textSecondary
                            : AppTheme.ColorToken.textPrimary
                    )
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 76)
            .padding(4)
            .background(
                isSelected && !isContextRestricted
                    ? option.artworkAccent.opacity(0.14)
                    : AppTheme.ColorToken.elevatedSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(
                        isSelected && !isContextRestricted
                            ? option.artworkAccent
                            : AppTheme.ColorToken.cardBorder,
                        lineWidth: isSelected && !isContextRestricted ? 2 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .saturation(isContextRestricted ? 0 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(
            isContextRestricted
                ? "Available from the main event"
                : isSelected ? "Selected" : "Not selected"
        )
        .accessibilityHint(
            isContextRestricted
                ? "Offers to switch to the main event and continue"
                : "Selects the \(option.title.lowercased()) idea form"
        )
    }

    private func optionStrip<Option: Identifiable & Equatable>(
        _ options: [Option],
        selection: Binding<Option>,
        title: @escaping (Option) -> String,
        symbol: @escaping (Option) -> String
    ) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ForEach(options) { option in
                    let isSelected = selection.wrappedValue == option

                    Button {
                        selection.wrappedValue = option
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: symbol(option))
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)

                            Text(title(option))
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundStyle(isSelected ? AppTheme.ColorToken.onAccent : .primary)
                        .frame(width: 98, height: 76)
                        .background(
                            isSelected ? AppTheme.ColorToken.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                            .stroke(
                                isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.cardBorder,
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
                    .accessibilityLabel(title(option))
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private var eventScheduleSummary: String {
        EventSchedule(
            startsAt: eventProposedDate,
            endsAt: eventProposedEndDate,
            isAllDay: eventIsAllDay,
            timeZoneIdentifier: eventTimeZoneIdentifier
        ).summary
    }

    private func eventActionRow(symbol: String, title: String, isEmpty: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(isEmpty ? AppTheme.ColorToken.accent : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func categoryConfiguration(for category: IdeaCategory) -> some View {
        switch category {
        case .link:
            Section {
                TextField("Website address", text: $linkAddress)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Title", text: $title)

                TextField("Description (optional)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Website")
            } footer: {
                if !linkAddress.isEmpty && normalizedLinkURL == nil {
                    Text("Enter a valid website address.")
                        .foregroundStyle(AppTheme.ColorToken.destructive)
                } else {
                    Text("Paste a website address. Gatherory adds https:// when it’s omitted.")
                }
            }

        case .event:
            Section("Event Category") {
                EventCategoryStrip(selection: $eventCategory)
            }

            Section {
                EventPurposeSelector(selection: $eventPurpose)
            } header: {
                Text("Purpose")
            } footer: {
                if eventCategory == .honeymoon {
                    Text("Honeymoon events include the hosts only.")
                }
            }

            Section {
                AttireStylePicker(selection: $attireStyle)

                TextField(
                    "Colors, fabrics, or guidance (optional)",
                    text: $attireRestrictions,
                    axis: .vertical
                )
                .lineLimit(2...5)
            } header: {
                Text("Attire")
            } footer: {
                Text("Choose Any when this event doesn’t need attire guidance.")
            }

            Section {
                Button {
                    isEditingEventDateAndTime = true
                } label: {
                    eventActionRow(
                        symbol: "calendar",
                        title: includesProposedDate ? eventScheduleSummary : "Add Date & Time",
                        isEmpty: !includesProposedDate
                    )
                }
                .buttonStyle(.plain)

                if includesProposedDate {
                    Button {
                        includesProposedDate = false
                        eventProposedEndDate = nil
                    } label: {
                        Label("Clear Date", systemImage: "calendar.badge.minus")
                    }
                    .foregroundStyle(.secondary)
                }

                Button {
                    isEditingEventLocation = true
                } label: {
                    eventActionRow(
                        symbol: "mappin.and.ellipse",
                        title: eventLocation?.title ?? "Add Location",
                        isEmpty: eventLocation == nil
                    )
                }
                .buttonStyle(.plain)
            } header: {
                Text("When & Where")
            } footer: {
                Text("Date and location are optional. Approved ideas with a date become events automatically.")
            }

        case .registry:
            Section {
                optionStrip(
                    RegistryCategory.allCases,
                    selection: $registryCategory,
                    title: \.title,
                    symbol: \.symbol
                )

                MoneyAmountField(
                    amount: $registryPrice,
                    title: "Price",
                    placeholder: "Optional",
                    symbol: registryCategory.symbol,
                    style: .prominent,
                    currencyCode: workspace.currencyCode
                )

                Stepper("Quantity: \(registryQuantity)", value: $registryQuantity, in: 1...20)
            } header: {
                Text("Registry Idea")
            } footer: {
                Text("Add a gift, fund, or experience for the planning team to review before it’s shared with guests.")
            }

        case .venue:
            Section {
                optionStrip(
                    VenueSetting.allCases,
                    selection: $venueSetting,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("City, neighborhood, or area (optional)", text: $venueArea)

                TextField("Guest capacity (optional)", text: $venueCapacity)
                    .keyboardType(.numberPad)
            } header: {
                Text("Venue Details")
            } footer: {
                Text("Capture the setting and approximate size now. A precise event address can be added after the venue is selected.")
            }

        case .attire:
            Section {
                AttireStylePicker(selection: $attireStyle)

                TextField(
                    "Restrictions or guidance (optional)",
                    text: $attireRestrictions,
                    axis: .vertical
                )
                .lineLimit(3...6)
            } header: {
                Text("Attire Style")
            } footer: {
                Text("Choose the closest style, or choose Any to leave the dress code open. Add color, fabric, or other guidance below.")
            }

        case .food:
            Section {
                optionStrip(
                    FoodIdeaType.allCases,
                    selection: $foodType,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Number of servings (optional)", text: $foodServings)
                    .keyboardType(.numberPad)

                TextField(
                    "Dietary considerations (optional)",
                    text: $dietaryNotes,
                    axis: .vertical
                )
                .lineLimit(2...5)
            } header: {
                Text("Food & Cake Details")
            } footer: {
                Text("Choose what kind of food idea this is. Serving count and dietary considerations help collaborators compare practical options.")
            }

        case .flowers:
            Section {
                optionStrip(
                    FlowerFocus.allCases,
                    selection: $flowerFocus,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Colors or flower palette (optional)", text: $flowerPalette, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Flower Details")
            } footer: {
                Text("Choose where this floral idea belongs and describe the colors or varieties that matter.")
            }

        case .photography:
            Section {
                optionStrip(
                    PhotographyStyle.allCases,
                    selection: $photographyStyle,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Coverage hours (optional)", text: $photographyHours)
                    .keyboardType(.numberPad)

                TextField("Moments or shots to prioritize (optional)", text: $photographyPriorities, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Photography Details")
            } footer: {
                Text("Describe the visual style and the moments that should receive the most attention.")
            }

        case .decor:
            Section {
                optionStrip(
                    DecorFocus.allCases,
                    selection: $decorFocus,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Colors, materials, or finish (optional)", text: $decorPalette, axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Decor Details")
            } footer: {
                Text("Choose the part of the event this idea supports, then note its colors or materials.")
            }

        case .invitations:
            Section {
                optionStrip(
                    InvitationFormat.allCases,
                    selection: $invitationFormat,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Quantity (optional)", text: $invitationQuantity)
                    .keyboardType(.numberPad)

                TextField("Paper, printing, or delivery notes (optional)", text: $invitationNotes, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Invitation Details")
            } footer: {
                Text("Specify the format and any production details collaborators should consider.")
            }

        case .honeymoon:
            Section {
                optionStrip(
                    TripStyle.allCases,
                    selection: $tripStyle,
                    title: \.title,
                    symbol: \.symbol
                )

                TextField("Destination (optional)", text: $tripDestination)

                TextField("Number of nights (optional)", text: $tripNights)
                    .keyboardType(.numberPad)
            } header: {
                Text("Honeymoon Details")
            } footer: {
                Text("A destination can stay open while the group explores a preferred trip style.")
            }

        case .music:
            Section {
                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: "person.3.sequence.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 44, height: 44)
                        .background(
                            AppTheme.ColorToken.accent.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(workspace.selectedEventTitle) Playlist")
                            .font(.headline)

                        Text(
                            musicTracks.isEmpty
                                ? "Ready for its first song"
                                : "\(musicTracks.count) \(musicTracks.count == 1 ? "song" : "songs")"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                ForEach(musicTracks) { track in
                    MusicTrackRow(track: track)
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                musicTracks.removeAll { $0.id == track.id }
                            }
                        }
                }

                Button {
                    isPickingMusic = true
                } label: {
                    Label(
                        musicTracks.isEmpty ? "Add Songs" : "Add More Songs",
                        systemImage: "music.note.badge.plus"
                    )
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                }
            } header: {
                Text("Shared Event Playlist")
            } footer: {
                Text("Gatherory keeps one playlist for this event. Everyone participating in the event can contribute songs.")
            }

        case .other:
            EmptyView()
        }
    }

    private func select(_ category: IdeaCategory) {
        withAnimation(.snappy) {
            if self.category != category {
                showOnInvitation = category.defaultInvitationVisibility == .shownToGuests
            }
            self.category = category
            if category == .music {
                loadEventPlaylistIfNeeded()
            } else {
                editingMusicPlaylistID = nil
            }
            if isChoosingCategory {
                beginEditing()
            }
        }
    }

    private func beginEditing() {
        withAnimation(.snappy) {
            isChoosingCategory = false
            setDetent(.large)
        }
    }

    private func switchToMainEventAndContinue() {
        workspace.selectEventContext(.main)
        select(.event)
    }

    private func saveIdea() {
        if ideaBeingEdited == nil {
            workspace.addIdea(editedIdea)
        } else {
            workspace.updateIdea(editedIdea)
        }
        dismiss()
    }

    private func loadEventPlaylistIfNeeded() {
        showOnInvitation = true
        guard existingIdea == nil,
              let playlist = workspace.musicPlaylist(for: workspace.selectedEventID) else {
            return
        }

        editingMusicPlaylistID = playlist.id
        title = playlist.title
        note = playlist.note
        imageData = playlist.imageData
        musicTracks = playlist.musicTracks
    }

    private func appendPickedSongs(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        for song in songs {
            let track = MusicTrack(appleMusicSong: song)
            guard !musicTracks.contains(where: { $0.id == track.id }) else { continue }
            musicTracks.append(track)
        }
        pickedSongs.removeAll()
    }
}

private struct AttireStyleSilhouette: View {
    let style: AttireStyle
    let color: Color

    var body: some View {
        Canvas { context, size in
            if style == .any {
                drawNeutralFigure(in: &context, size: size, xOffset: -size.width * 0.15, scale: 0.78)
                drawNeutralFigure(in: &context, size: size, xOffset: size.width * 0.15, scale: 0.78)
                return
            }

            context.fill(
                Path(ellipseIn: CGRect(
                    x: size.width * 0.38,
                    y: size.height * 0.03,
                    width: size.width * 0.24,
                    height: size.width * 0.24
                )),
                with: .color(color)
            )

            var garment = Path()
            switch style {
            case .blackTie:
                garment.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.54, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.42, y: size.height * 0.68))
                garment.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.68))
                garment.closeSubpath()

            case .formal:
                garment.move(to: CGPoint(x: size.width * 0.39, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.61, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.96))
                garment.addLine(to: CGPoint(x: size.width * 0.16, y: size.height * 0.96))
                garment.closeSubpath()

            case .cocktail:
                garment.move(to: CGPoint(x: size.width * 0.36, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.29))
                garment.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.70))
                garment.addLine(to: CGPoint(x: size.width * 0.26, y: size.height * 0.70))
                garment.closeSubpath()
                garment.addRect(CGRect(x: size.width * 0.33, y: size.height * 0.68, width: size.width * 0.10, height: size.height * 0.29))
                garment.addRect(CGRect(x: size.width * 0.57, y: size.height * 0.68, width: size.width * 0.10, height: size.height * 0.29))

            case .garden:
                garment.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.30))
                garment.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.90))
                garment.addQuadCurve(
                    to: CGPoint(x: size.width * 0.22, y: size.height * 0.90),
                    control: CGPoint(x: size.width * 0.50, y: size.height * 1.04)
                )
                garment.closeSubpath()

            case .casual:
                garment.move(to: CGPoint(x: size.width * 0.25, y: size.height * 0.31))
                garment.addLine(to: CGPoint(x: size.width * 0.75, y: size.height * 0.31))
                garment.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.56, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.97))
                garment.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.63))
                garment.addLine(to: CGPoint(x: size.width * 0.34, y: size.height * 0.63))
                garment.closeSubpath()

            case .any:
                break
            }
            context.fill(garment, with: .color(color))

            if style == .blackTie {
                var lapels = Path()
                lapels.move(to: CGPoint(x: size.width * 0.38, y: size.height * 0.31))
                lapels.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.47))
                lapels.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.31))
                context.stroke(lapels, with: .color(color.opacity(0.45)), lineWidth: 2)

                let bow = Path(roundedRect: CGRect(
                    x: size.width * 0.43,
                    y: size.height * 0.29,
                    width: size.width * 0.14,
                    height: size.height * 0.07
                ), cornerRadius: 2)
                context.fill(bow, with: .color(color))
            }

            if style == .garden {
                var leaf = Path()
                leaf.addEllipse(in: CGRect(
                    x: size.width * 0.57,
                    y: size.height * 0.50,
                    width: size.width * 0.12,
                    height: size.height * 0.18
                ))
                context.stroke(leaf, with: .color(color.opacity(0.55)), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawNeutralFigure(
        in context: inout GraphicsContext,
        size: CGSize,
        xOffset: CGFloat,
        scale: CGFloat
    ) {
        let centerX = size.width * 0.5 + xOffset
        let headSize = size.width * 0.22 * scale
        context.fill(
            Path(ellipseIn: CGRect(
                x: centerX - headSize / 2,
                y: size.height * 0.08,
                width: headSize,
                height: headSize
            )),
            with: .color(color)
        )

        var body = Path()
        body.move(to: CGPoint(x: centerX - size.width * 0.16 * scale, y: size.height * 0.35))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.16 * scale, y: size.height * 0.35))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.11 * scale, y: size.height * 0.70))
        body.addLine(to: CGPoint(x: centerX + size.width * 0.06 * scale, y: size.height * 0.96))
        body.addLine(to: CGPoint(x: centerX - size.width * 0.06 * scale, y: size.height * 0.96))
        body.addLine(to: CGPoint(x: centerX - size.width * 0.11 * scale, y: size.height * 0.70))
        body.closeSubpath()
        context.fill(body, with: .color(color))
    }
}

#Preview {
    NavigationStack {
        IdeasView()
            .environment(WeddingWorkspace.sample)
            .environment(MusicCatalog())
            .environment(MusicPreviewPlayer())
    }
}
