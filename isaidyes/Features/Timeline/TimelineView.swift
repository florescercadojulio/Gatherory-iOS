import SwiftUI
import UIKit

struct TimelineView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isAddingTimelineItem = false
    @State private var selectedTimelineItemID: UUID?
    @Namespace private var timelineTransition

    private var upcoming: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .upcoming }
            .sorted(by: chronologicallyBefore)
    }

    private var completed: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .complete }
            .sorted { lhs, rhs in
                chronologicallyBefore(rhs, lhs)
            }
    }

    private func chronologicallyBefore(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                eventCollection(
                    title: "Upcoming",
                    items: upcoming,
                    emptyTitle: "No upcoming events",
                    emptyDescription: "Add an event to start building the wedding timeline."
                )

                if !completed.isEmpty {
                    eventCollection(
                        title: "Completed",
                        items: completed,
                        emptyTitle: "No completed events",
                        emptyDescription: "Completed events appear here."
                    )
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add event", systemImage: "plus") {
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $selectedTimelineItemID) { itemID in
            TimelineEventDetailView(
                itemID: itemID,
                transitionNamespace: timelineTransition
            )
        }
    }

    @ViewBuilder
    private func eventCollection(
        title: String,
        items: [TimelineItem],
        emptyTitle: String,
        emptyDescription: String
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())

                Spacer(minLength: AppTheme.Spacing.compact)

                Text(items.count, format: .number)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(items.count == 1 ? "1 event" : "\(items.count) events")
            }

            if items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "calendar",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.section)
            } else {
                MasonryLayout(
                    columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                    spacing: 12,
                    layoutDirection: layoutDirection
                ) {
                    ForEach(items) { item in
                        eventButton(item)
                    }
                }
            }
        }
    }

    private func eventButton(_ item: TimelineItem) -> some View {
        Button {
            selectedTimelineItemID = item.id
        } label: {
            TimelineCollectionCard(
                item: item,
                transitionNamespace: timelineTransition
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens event details")
        .accessibilityAction(named: item.status == .complete ? "Undo Complete" : "Mark Complete") {
            withAnimation {
                workspace.toggleTimelineItem(item)
            }
        }
        .contextMenu {
            Button(
                item.status == .complete ? "Undo Complete" : "Mark Complete",
                systemImage: item.status == .complete ? "arrow.uturn.backward" : "checkmark.circle"
            ) {
                withAnimation {
                    workspace.toggleTimelineItem(item)
                }
            }
        }
    }
}

private struct AddTimelineItemView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: TimelineCategory = .venue
    @State private var scheduledAt = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var location = ""
    @State private var selectedParticipantIDs: Set<UUID> = []
    @State private var imageData: Data?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
        case location
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLocation: String {
        location.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextField("Event name", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        focusedField = .location
                    }
            } header: {
                Label("Event Name", systemImage: "text.cursor")
            }

            Section("Photo") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: category.symbol,
                    suggestedConcept: "Wedding \(category.title.lowercased()) event artwork for \(trimmedTitle.isEmpty ? "our celebration" : trimmedTitle)"
                )
            }

            Section {
                Picker("Event type", selection: $category) {
                    ForEach(TimelineCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            } header: {
                Label("Event Type", systemImage: "square.grid.2x2.fill")
            } footer: {
                Text("Choose the kind of wedding event.")
            }

            Section {
                DatePicker(
                    "Date and time",
                    selection: $scheduledAt,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } header: {
                Label("Date & Time", systemImage: "calendar.badge.clock")
            }

            Section {
                TextField("Location or video call", text: $location)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .location)
            } header: {
                Label("Location", systemImage: "mappin.and.ellipse")
            }

            Section {
                ForEach(workspace.planningMembers) { member in
                    Button {
                        toggle(member)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.standard) {
                            Text(member.initials)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.ColorToken.accent, in: Circle())
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .foregroundStyle(.primary)
                                Text(member.participantRole.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            if selectedParticipantIDs.contains(member.id) {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedParticipantIDs.contains(member.id) ? "Selected" : "Not selected")
                }
            } header: {
                Label("Planning Team", systemImage: "person.2.fill")
            } footer: {
                Text("Hosts and collaborators can be assigned. Guests stay on the invitation list.")
            }
        }
        .navigationTitle("New Event")
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
                            category: category,
                            scheduledAt: scheduledAt,
                            location: trimmedLocation,
                            participantIDs: Array(selectedParticipantIDs),
                            imageData: imageData
                        )
                    )
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty || trimmedLocation.isEmpty || selectedParticipantIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            selectedParticipantIDs = Set(
                workspace.members
                    .filter { $0.participantRole == .host }
                    .map(\.id)
            )
            scheduledAt = max(scheduledAt, Date.now)
            focusedField = .title
        }
    }

    private func toggle(_ member: WeddingMember) {
        if selectedParticipantIDs.contains(member.id) {
            selectedParticipantIDs.remove(member.id)
        } else {
            selectedParticipantIDs.insert(member.id)
        }
    }
}

private struct TimelineCollectionCard: View {
    let item: TimelineItem
    let transitionNamespace: Namespace.ID

    private var artworkAspectRatio: CGFloat {
        if let imageData = item.imageData,
           let image = UIImage(data: imageData),
           image.size.height > 0 {
            return min(max(image.size.width / image.size.height, 0.72), 1.35)
        }

        if item.category == .venue,
           let image = UIImage(named: "WeddingVenueHero"),
           image.size.height > 0 {
            return min(max(image.size.width / image.size.height, 0.72), 1.35)
        }

        return item.category.collectionAspectRatio
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TimelineArtwork(item: item, progressiveBlurRadius: 22)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(0.12), location: 0.55),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(3)
                    .strikethrough(item.status == .complete)

                Text(item.scheduledAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption.weight(.medium))
                    .lineLimit(2)

                Label(item.location, systemImage: "mappin")
                    .font(.caption)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)

            if item.status == .complete {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.green, in: Circle())
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.compact)
                .accessibilityHidden(true)
            }
        }
        .aspectRatio(artworkAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .matchedTransitionSource(id: item.id, in: transitionNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.status == .complete ? "Completed" : "Upcoming")
    }
}

private struct MasonryLayout: Layout {
    let columnCount: Int
    let spacing: CGFloat
    let layoutDirection: LayoutDirection

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? 0
        let measurements = measurements(for: subviews, width: width)
        return CGSize(width: width, height: measurements.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let measurements = measurements(for: subviews, width: bounds.width)

        for (index, subview) in subviews.enumerated() {
            let placement = measurements.placements[index]
            let visualColumn = layoutDirection == .leftToRight
                ? placement.column
                : measurements.columns - 1 - placement.column
            let x = bounds.minX + CGFloat(visualColumn) * (measurements.columnWidth + spacing)
            let point = CGPoint(x: x, y: bounds.minY + placement.y)

            subview.place(
                at: point,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: measurements.columnWidth, height: nil)
            )
        }
    }

    private func measurements(for subviews: Subviews, width: CGFloat) -> Measurements {
        let columns = max(columnCount, 1)
        let availableWidth = max(width - (CGFloat(columns - 1) * spacing), 0)
        let columnWidth = availableWidth / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat.zero, count: columns)
        var placements: [Placement] = []

        for subview in subviews {
            let column = columnHeights.enumerated().min { lhs, rhs in
                lhs.element < rhs.element
            }?.offset ?? 0
            let size = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: nil)
            )

            placements.append(Placement(column: column, y: columnHeights[column]))
            columnHeights[column] += size.height + spacing
        }

        let height = max((columnHeights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing), 0)
        return Measurements(
            columns: columns,
            columnWidth: columnWidth,
            height: height,
            placements: placements
        )
    }

    private struct Measurements {
        let columns: Int
        let columnWidth: CGFloat
        let height: CGFloat
        let placements: [Placement]
    }

    private struct Placement {
        let column: Int
        let y: CGFloat
    }
}

private struct TimelineArtwork: View {
    let item: TimelineItem
    var progressiveBlurRadius: CGFloat = 22

    var body: some View {
        MediaArtwork(
            imageData: item.imageData,
            assetName: item.imageData == nil && item.category == .venue ? "WeddingVenueHero" : nil,
            symbol: item.category.symbol,
            colors: item.category.artworkColors,
            accent: item.category.artworkAccent,
            ambientBlurRadius: progressiveBlurRadius == 0 ? 4 : 10,
            progressiveBlurRadius: progressiveBlurRadius,
            blurStart: 0.44
        )
    }
}

private struct TimelineEventDetailView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false

    let itemID: UUID
    let transitionNamespace: Namespace.ID

    private var item: TimelineItem? {
        workspace.timeline.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                TimelineEventDetailScreen(item: item)
            } else {
                ContentUnavailableView("Event unavailable", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("Event details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Event actions", systemImage: "ellipsis") {
                        Button(
                            item.status == .complete ? "Undo Complete" : "Mark Complete",
                            systemImage: item.status == .complete ? "arrow.uturn.backward" : "checkmark.circle"
                        ) {
                            withAnimation {
                                workspace.toggleTimelineItem(item)
                            }
                        }

                        Divider()

                        Button("Delete Event", systemImage: "trash", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            if let item {
                Button("Delete Event", role: .destructive) {
                    workspace.deleteTimelineItem(item)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the event from the shared timeline for everyone.")
        }
        .navigationTransition(.zoom(sourceID: itemID, in: transitionNamespace))
    }
}

private struct TimelineEventDetailScreen: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let item: TimelineItem

    private var participantNames: String {
        let names = workspace.members
            .filter { item.participantIDs.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "Unassigned" : names.formatted()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TimelineArtwork(
                    item: item,
                    progressiveBlurRadius: reduceTransparency ? 0 : 22
                )
                .ignoresSafeArea()

                readingScrim

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                        Spacer(minLength: max(proxy.size.height * 0.42, 260))
                        identity
                        metadata
                    }
                    .frame(
                        width: max(proxy.size.width - (AppTheme.Layout.screenHorizontal * 2), 0),
                        alignment: .leading
                    )
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

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label(item.category.title, systemImage: item.category.symbol)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: AppTheme.Spacing.compact)

                Label(
                    item.status == .complete ? "Completed" : "Upcoming",
                    systemImage: item.status == .complete ? "checkmark.circle.fill" : "calendar"
                )
                .font(.caption.weight(.semibold))
            }

            Text(item.title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            TimelineMetadataRow(
                title: "Date & Time",
                value: item.scheduledAt.formatted(date: .long, time: .shortened),
                symbol: "calendar"
            )

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: "Location",
                value: item.location,
                symbol: "mappin.and.ellipse"
            )

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: "Planning Team",
                value: participantNames,
                symbol: "person.2.fill"
            )
        }
        .padding(.vertical, 4)
        .background(
            reduceTransparency ? AnyShapeStyle(.black.opacity(0.82)) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct TimelineMetadataRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.standard) {
                metadataLabel

                Spacer(minLength: AppTheme.Spacing.compact)

                metadataValue
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                metadataLabel
                metadataValue
                    .multilineTextAlignment(.leading)
            }
        }
        .font(.body)
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, AppTheme.Spacing.compact)
        .frame(minHeight: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metadataLabel: some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var metadataValue: some View {
        Text(value)
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension TimelineCategory {
    var collectionAspectRatio: CGFloat {
        switch self {
        case .venue: 0.84
        case .foodTasting: 1.18
        case .attireFitting: 0.76
        case .weddingShower: 0.92
        case .bachelorBachelorette: 0.78
        case .rehearsal: 1.12
        case .ceremony: 0.74
        case .reception: 1.0
        case .other: 1.20
        }
    }
}

#Preview {
    NavigationStack {
        TimelineView()
            .environment(WeddingWorkspace.sample)
    }
}
