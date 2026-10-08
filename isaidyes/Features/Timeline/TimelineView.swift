import SwiftUI

struct TimelineView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @State private var isAddingTimelineItem = false
    @State private var selectedTimelineItemID: UUID?
    @Namespace private var timelineTransition

    private var upcoming: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .upcoming }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var completed: [TimelineItem] {
        workspace.timeline
            .filter { $0.status == .complete }
            .sorted { $0.scheduledAt > $1.scheduledAt }
    }

    var body: some View {
        List {
            weddingDateSection

            Section {
                ForEach(upcoming) { item in
                    Button {
                        selectedTimelineItemID = item.id
                    } label: {
                        TimelineRow(
                            item: item,
                            transitionNamespace: timelineTransition
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(AppTheme.Layout.listRowInsets)
                    .accessibilityHint("Opens event details")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Complete", systemImage: "checkmark") {
                            withAnimation {
                                workspace.toggleTimelineItem(item)
                            }
                        }
                        .tint(.green)
                    }
                }
            } header: {
                Text("Coming up")
            }

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { item in
                        Button {
                            selectedTimelineItemID = item.id
                        } label: {
                            TimelineRow(
                                item: item,
                                transitionNamespace: timelineTransition
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(AppTheme.Layout.listRowInsets)
                        .accessibilityHint("Opens event details")
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Undo", systemImage: "arrow.uturn.backward") {
                                withAnimation {
                                    workspace.toggleTimelineItem(item)
                                }
                            }
                            .tint(AppTheme.ColorToken.accent)
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
                TextField("What is it?", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        focusedField = .location
                    }
            } header: {
                Label("What", systemImage: "text.cursor")
            }

            Section("Image") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: category.symbol
                )
            }

            Section {
                Picker("Category", selection: $category) {
                    ForEach(TimelineCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            } header: {
                Label("Why", systemImage: "square.grid.2x2.fill")
            } footer: {
                Text("Choose the wedding moment this event supports.")
            }

            Section {
                DatePicker(
                    "Date and time",
                    selection: $scheduledAt,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } header: {
                Label("When", systemImage: "calendar.badge.clock")
            }

            Section {
                TextField("Location or video call", text: $location)
                    .textContentType(.fullStreetAddress)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .location)
            } header: {
                Label("Where", systemImage: "mappin.and.ellipse")
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
                Label("Who", systemImage: "person.2.fill")
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

private struct TimelineRow: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let item: TimelineItem
    let transitionNamespace: Namespace.ID

    private var participantNames: String {
        let names = workspace.members
            .filter { item.participantIDs.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "Unassigned" : names.formatted()
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.standard) {
            TimelineArtworkThumbnail(item: item)
                .matchedTransitionSource(id: item.id, in: transitionNamespace)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .strikethrough(item.status == .complete)
                    .foregroundStyle(item.status == .complete ? .secondary : .primary)

                Text("\(item.category.title) · \(item.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)

                Label(item.location, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if dynamicTypeSize.isAccessibilitySize {
                    Label(participantNames, systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if item.status == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Completed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineArtworkThumbnail: View {
    let item: TimelineItem

    var body: some View {
        TimelineArtwork(item: item, progressiveBlurRadius: 0)
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
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
                title: "When",
                value: item.scheduledAt.formatted(date: .long, time: .shortened),
                symbol: "calendar"
            )

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: "Where",
                value: item.location,
                symbol: "mappin.and.ellipse"
            )

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: "Who",
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

#Preview {
    NavigationStack {
        TimelineView()
            .environment(WeddingWorkspace.sample)
    }
}
