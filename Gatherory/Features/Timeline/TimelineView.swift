import SwiftUI
import UIKit

struct TimelineView: View {
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var filter: TimelineFilter = .all
    @State private var isAddingTimelineItem = false
    @State private var selectedTimelineItemID: UUID?
    @Namespace private var timelineTransition

    private var filteredEvents: [TimelineItem] {
        workspace.timeline
            .filter(filter.includes)
            .sorted { lhs, rhs in
                if filter != .completed,
                   lhs.hasScheduledDate != rhs.hasScheduledDate {
                    return !lhs.hasScheduledDate
                }
                return filter == .completed
                    ? chronologicallyBefore(rhs, lhs)
                    : chronologicallyBefore(lhs, rhs)
        }
    }

    private func chronologicallyBefore(_ lhs: TimelineItem, _ rhs: TimelineItem) -> Bool {
        if lhs.scheduledAt == rhs.scheduledAt {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return lhs.scheduledAt < rhs.scheduledAt
    }

    var body: some View {
        Group {
            if workspace.isMainEventContext {
                ScrollView {
                    eventCollection
                        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                        .padding(.top, AppTheme.Layout.screenTop)
                        .padding(.bottom, AppTheme.Layout.screenBottom)
                }
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
            } else {
                mainEventRequiredView
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            if workspace.isMainEventContext {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if let onExitWorkspace {
                        WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                    }

                    Menu {
                        ForEach(TimelineFilter.allCases) { option in
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
                    .accessibilityLabel("Filter timeline")
                    .accessibilityValue(filter.title)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add event", systemImage: "plus") {
                        isAddingTimelineItem = true
                    }
                    .labelStyle(.iconOnly)
                }
            } else if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton()
            }
        }
        .sheet(isPresented: $isAddingTimelineItem) {
            NavigationStack {
                EventEditorView(mode: .subevent(nil))
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

    private var mainEventRequiredView: some View {
        ContentUnavailableView {
            Label("Main Event Timeline", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Timeline management is available from the main event context.")
        } actions: {
            Button("Switch to Main Event") {
                workspace.selectEventContext(.main)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Layout.screenHorizontal)
    }

    @ViewBuilder
    private var eventCollection: some View {
        if filteredEvents.isEmpty {
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
                ForEach(filteredEvents) { item in
                    eventButton(item)
                }
            }
        }
    }

    private func eventButton(_ item: TimelineItem) -> some View {
        TimelineEventCard(
            item: item,
            transitionNamespace: timelineTransition,
            showsPlanningStatus: true
        ) {
            selectedTimelineItemID = item.id
        }
        .accessibilityAction(named: item.completionStatus == .complete ? "Undo Complete" : "Mark Complete") {
            withAnimation {
                workspace.toggleTimelineItem(item)
            }
        }
        .contextMenu {
            if item.status == .archived {
                Button("Restore as Draft", systemImage: "arrow.uturn.backward") {
                    withAnimation {
                        workspace.setEventStatus(.draft, for: item)
                    }
                }
            } else {
                Button(
                    item.completionStatus == .complete ? "Undo Complete" : "Mark Complete",
                    systemImage: item.completionStatus == .complete ? "arrow.uturn.backward" : "checkmark.circle"
                ) {
                    withAnimation {
                        workspace.toggleTimelineItem(item)
                    }
                }

                Button("Archive Event", systemImage: "archivebox") {
                    withAnimation {
                        workspace.setEventStatus(.archived, for: item)
                    }
                }
            }
        }
    }
}

enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case needsDate
    case upcoming
    case completed
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .needsDate: "Needs Date"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .archived: "Archive"
        }
    }

    var symbol: String {
        switch self {
        case .all: "calendar"
        case .needsDate: "calendar.badge.exclamationmark"
        case .upcoming: "calendar.badge.clock"
        case .completed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: "No events yet"
        case .needsDate: "Everything is scheduled"
        case .upcoming: "No upcoming events"
        case .completed: "No completed events"
        case .archived: "No archived events"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all: "Add an event to start building the timeline."
        case .needsDate: "Approved event ideas without dates appear here."
        case .upcoming: "New and scheduled events appear here."
        case .completed: "Events appear here after they are marked complete."
        case .archived: "Archived events appear here."
        }
    }

    func includes(_ item: TimelineItem) -> Bool {
        switch self {
        case .all:
            item.status != .archived
        case .needsDate:
            item.status != .archived && !item.hasScheduledDate
        case .upcoming:
            item.status != .archived
                && item.completionStatus == .upcoming
                && item.hasScheduledDate
        case .completed:
            item.status != .archived
                && item.completionStatus == .complete
                && item.hasScheduledDate
        case .archived:
            item.status == .archived
        }
    }
}

private struct TimelineItemEditorView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let originalItem: TimelineItem?

    @State private var title: String
    @State private var category: TimelineCategory
    @State private var purpose: EventPurpose
    @State private var status: EventStatus
    @State private var scheduledAt: Date
    @State private var endsAt: Date?
    @State private var isAllDay: Bool
    @State private var timeZoneIdentifier: String
    @State private var isEditingDateAndTime = false
    @State private var eventLocation: EventLocation?
    @State private var isEditingLocation = false
    @State private var selectedParticipantIDs: Set<UUID>
    @State private var imageData: Data?
    @FocusState private var focusedField: Field?

    private enum Field {
        case title
    }

    init(item: TimelineItem? = nil) {
        originalItem = item
        _title = State(initialValue: item?.title ?? "")
        _category = State(initialValue: item?.category ?? .other)
        _purpose = State(initialValue: item?.purpose ?? .planning)
        _status = State(initialValue: item?.status ?? .approved)
        _scheduledAt = State(
            initialValue: item?.scheduledAt
                ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)
                ?? .now
        )
        _endsAt = State(initialValue: item?.endsAt)
        _isAllDay = State(initialValue: item?.isAllDay ?? false)
        _timeZoneIdentifier = State(
            initialValue: item?.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier
        )
        _eventLocation = State(initialValue: item?.eventLocation)
        _selectedParticipantIDs = State(initialValue: Set(item?.participantIDs ?? []))
        _imageData = State(initialValue: item?.imageData)
    }

    private var isEditing: Bool {
        originalItem != nil
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedTitle: String {
        trimmedTitle.isEmpty ? suggestedTitle : trimmedTitle
    }

    private var suggestedTitle: String {
        switch category {
        case .venue:
            purpose == .planning ? "Venue Visit" : "Venue"
        case .foodTasting:
            "Food Tasting"
        case .photography:
            "Photography"
        case .honeymoon:
            "Honeymoon"
        case .attireFitting:
            "Attire Fitting"
        case .weddingShower:
            "Wedding Shower"
        case .bachelorBachelorette:
            "Bachelor or Bachelorette Party"
        case .rehearsal:
            "Wedding Rehearsal"
        case .ceremony:
            "Ceremony"
        case .reception:
            "Reception"
        case .other:
            purpose == .planning ? "Planning Event" : "Event"
        }
    }

    var body: some View {
        Form {
            Section {
                categoryGrid
                    .listRowInsets(categoryGridInsets)
                    .listRowBackground(Color.clear)
            } header: {
                Text("Event Type")
            } footer: {
                Text("Choose what is happening. You can still give it a custom name below.")
            }

            Section {
                if category == .honeymoon {
                    Label("Part of the Event", systemImage: EventPurpose.eventExperience.symbol)
                        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                } else {
                    purposePicker
                        .listRowInsets(categoryGridInsets)
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("Purpose")
            } footer: {
                Text(
                    category == .honeymoon
                        ? "A honeymoon is an event experience for the hosts."
                        : purpose.description
                )
            }

            Section {
                TextField("Custom name (optional)", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        focusedField = nil
                    }
            } header: {
                Text("Event Name")
            } footer: {
                Text("Leave this blank to use “\(suggestedTitle)”.")
            }

            if isEditing {
                Section {
                    Picker("Planning status", selection: $status) {
                        ForEach(EventStatus.allCases.filter { $0 != .archived }) { option in
                            Label(option.title, systemImage: option.symbol)
                                .tag(option)
                        }
                    }
                } header: {
                    Label("Planning Status", systemImage: "checklist")
                } footer: {
                    Text("Only approved events appear on the guest invitation.")
                }
            }

            Section {
                Button {
                    focusedField = nil
                    isEditingDateAndTime = true
                } label: {
                    EventScheduleRow(
                        startsAt: scheduledAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
                .buttonStyle(.plain)
            } header: {
                Text("Schedule")
            }

            Section {
                Button {
                    isEditingLocation = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            if let eventLocation {
                                Text(eventLocation.title)
                                    .foregroundStyle(.primary)
                                if !eventLocation.detail.isEmpty {
                                    Text(eventLocation.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            } else {
                                Text("Add Location")
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Location")
            } footer: {
                Text("Optional. Search Apple Maps, then add a unit or familiar place name if useful.")
            }

            Section("Photo") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: category.symbol,
                    fallbackAssetName: category == .venue ? "WeddingVenueHero" : nil,
                    fallbackColors: category.artworkColors,
                    fallbackAccent: category.artworkAccent,
                    suggestedConcept: "Wedding \(category.title.lowercased()) event artwork for \(resolvedTitle)"
                )
            }

            Section {
                ForEach(eventParticipantOptions) { member in
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
                Label("Participants", systemImage: "person.3.fill")
            } footer: {
                if category == .honeymoon {
                    Text("Honeymoons start with the hosts only.")
                } else {
                    Text("New events start with everyone from the main event. Changes here only affect this event.")
                }
            }

        }
        .navigationTitle(isEditing ? "Edit Event" : "New Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Schedule") {
                    let updatedItem = TimelineItem(
                        id: originalItem?.id ?? UUID(),
                        title: resolvedTitle,
                        category: category,
                        purpose: purpose,
                        scheduledAt: scheduledAt,
                        eventLocation: eventLocation,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier,
                        participantIDs: Array(selectedParticipantIDs),
                        parentEventID: originalItem?.parentEventID,
                        status: status,
                        completionStatus: originalItem?.completionStatus ?? .upcoming,
                        response: originalItem?.response,
                        linkedIdeaID: originalItem?.linkedIdeaID,
                        imageData: imageData
                    )

                    if isEditing {
                        workspace.updateTimelineItem(updatedItem)
                    } else {
                        workspace.addTimelineItem(updatedItem)
                    }
                    dismiss()
                }
                .disabled(selectedParticipantIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: scheduledAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier
            ) { updatedStartsAt, updatedEndsAt, updatedIsAllDay, updatedTimeZoneIdentifier in
                scheduledAt = updatedStartsAt
                endsAt = updatedEndsAt
                isAllDay = updatedIsAllDay
                timeZoneIdentifier = updatedTimeZoneIdentifier
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingLocation) {
            EventLocationEditorView(location: eventLocation) { updatedLocation in
                eventLocation = updatedLocation
            }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard !isEditing else { return }
            selectedParticipantIDs = Set(workspace.mainEventParticipantIDs)
            scheduledAt = max(scheduledAt, Date.now)
        }
        .onChange(of: category) { previousCategory, updatedCategory in
            if updatedCategory == .honeymoon {
                purpose = .eventExperience
                selectedParticipantIDs = Set(hostParticipantIDs)
            } else if previousCategory == .honeymoon, !isEditing {
                selectedParticipantIDs = Set(workspace.mainEventParticipantIDs)
            }
        }
    }

    private var hostParticipantIDs: [UUID] {
        workspace.members
            .filter { $0.participantRole == .host }
            .map(\.id)
    }

    private var eventParticipantOptions: [WeddingMember] {
        category == .honeymoon
            ? workspace.members.filter { $0.participantRole == .host }
            : workspace.members
    }

    private static let categoryOrder: [TimelineCategory] = [
        .other,
        .venue,
        .foodTasting,
        .photography,
        .honeymoon,
        .attireFitting,
        .weddingShower,
        .bachelorBachelorette,
        .rehearsal,
        .ceremony,
        .reception
    ]

    private var categoryGridInsets: EdgeInsets {
        EdgeInsets(
            top: AppTheme.Spacing.compact,
            leading: 0,
            bottom: AppTheme.Spacing.compact,
            trailing: 0
        )
    }

    private var categoryGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
            ),
            spacing: AppTheme.Spacing.compact
        ) {
            ForEach(Self.categoryOrder) { option in
                categoryTile(option)
            }
        }
        .padding(2)
        .accessibilityLabel("Event types")
    }

    private func categoryTile(_ option: TimelineCategory) -> some View {
        let isSelected = category == option

        return Button {
            withAnimation(.snappy) {
                category = option
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: option.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : option.artworkAccent)
                        .frame(width: 38, height: 38)
                        .background(
                            isSelected ? option.artworkAccent : Color.clear,
                            in: Circle()
                        )
                        .background(.regularMaterial, in: Circle())

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white, AppTheme.ColorToken.accent)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(option.title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 76)
            .padding(4)
            .background(
                isSelected ? option.artworkAccent.opacity(0.14) : AppTheme.ColorToken.elevatedSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? option.artworkAccent : AppTheme.ColorToken.cardBorder,
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects the \(option.title.lowercased()) event type")
    }

    @ViewBuilder
    private var purposePicker: some View {
        let content = ForEach(EventPurpose.allCases) { option in
            let isSelected = purpose == option

            Button {
                withAnimation(.snappy) {
                    purpose = option
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(option.title, systemImage: option.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                .padding(AppTheme.Spacing.compact)
                .background(
                    isSelected ? AppTheme.ColorToken.accent.opacity(0.14) : AppTheme.ColorToken.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.cardBorder,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: AppTheme.Spacing.compact) {
                content
            }
            .padding(2)
        } else {
            HStack(spacing: AppTheme.Spacing.compact) {
                content
            }
            .padding(2)
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

struct EventDateTimeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var startsAt: Date
    @State private var endsAt: Date?
    @State private var isAllDay: Bool
    @State private var timeZoneIdentifier: String

    let save: (Date, Date?, Bool, String) -> Void

    init(
        startsAt: Date,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        save: @escaping (Date, Date?, Bool, String) -> Void
    ) {
        _startsAt = State(initialValue: startsAt)
        _endsAt = State(initialValue: endsAt)
        _isAllDay = State(initialValue: isAllDay)
        _timeZoneIdentifier = State(initialValue: timeZoneIdentifier)
        self.save = save
    }

    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("All-day", isOn: $isAllDay)

                    datePickerRow(
                        title: "Starts",
                        selection: $startsAt
                    )

                    if endsAt != nil {
                        datePickerRow(
                            title: "Ends",
                            selection: endDateBinding
                        )

                        Button("Remove End", systemImage: "minus.circle", role: .destructive) {
                            endsAt = nil
                        }
                    } else {
                        Button("Add End", systemImage: "plus.circle") {
                            endsAt = defaultEndDate
                        }
                    }
                }

                Section {
                    Picker("Time Zone", selection: $timeZoneIdentifier) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(timeZoneLabel(for: identifier))
                                .tag(identifier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .environment(\.timeZone, selectedTimeZone)
            .navigationTitle("Date and Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        let schedule = normalizedSchedule
                        save(
                            schedule.startsAt,
                            schedule.endsAt,
                            schedule.isAllDay,
                            schedule.timeZoneIdentifier
                        )
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onChange(of: startsAt) { _, newStart in
            guard let endsAt, endsAt < newStart else { return }
            self.endsAt = defaultEndDate
        }
        .onChange(of: endsAt) { _, newEnd in
            guard let newEnd, newEnd < startsAt else { return }
            endsAt = startsAt
        }
    }

    @ViewBuilder
    private func datePickerRow(
        title: String,
        selection: Binding<Date>
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text(title)
                    .font(.headline)

                DatePicker(
                    "Date",
                    selection: selection,
                    displayedComponents: .date
                )

                if !isAllDay {
                    DatePicker(
                        "Time",
                        selection: selection,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: AppTheme.Spacing.compact) {
                Text(title)

                Spacer(minLength: AppTheme.Spacing.compact)

                DatePicker(
                    "\(title) date",
                    selection: selection,
                    displayedComponents: .date
                )
                .labelsHidden()

                if !isAllDay {
                    DatePicker(
                        "\(title) time",
                        selection: selection,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        }
    }

    private var defaultEndDate: Date {
        guard !isAllDay else { return startsAt }
        return Calendar.current.date(byAdding: .hour, value: 1, to: startsAt) ?? startsAt
    }

    private var endDateBinding: Binding<Date> {
        Binding(
            get: { endsAt ?? defaultEndDate },
            set: { endsAt = $0 }
        )
    }

    private func timeZoneLabel(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else { return identifier }
        let name = timeZone.localizedName(for: .generic, locale: .current) ?? identifier
        return "\(name) (\(gmtOffset(for: timeZone)))"
    }

    private func gmtOffset(for timeZone: TimeZone) -> String {
        let seconds = timeZone.secondsFromGMT(for: startsAt)
        let sign = seconds < 0 ? "−" : "+"
        let absoluteSeconds = abs(seconds)
        let hours = absoluteSeconds / 3_600
        let minutes = (absoluteSeconds % 3_600) / 60
        return minutes == 0
            ? "GMT\(sign)\(hours)"
            : "GMT\(sign)\(hours):\(String(format: "%02d", minutes))"
    }

    private var normalizedSchedule: EventSchedule {
        EventSchedule(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        ).normalized
    }
}

struct EventSchedule: Equatable {
    var startsAt: Date
    var endsAt: Date?
    var isAllDay: Bool
    var timeZoneIdentifier: String

    var normalized: EventSchedule {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent

        let normalizedStart = isAllDay ? calendar.startOfDay(for: startsAt) : startsAt
        let candidateEnd = endsAt.map { isAllDay ? calendar.startOfDay(for: $0) : $0 }
        let normalizedEnd = candidateEnd.map { max($0, normalizedStart) }

        return EventSchedule(
            startsAt: normalizedStart,
            endsAt: normalizedEnd,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    var summary: String {
        let start = EventScheduleFormatter.string(
            from: startsAt,
            includesTime: !isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
        guard let endsAt else {
            return isAllDay ? "\(start) · All-day" : start
        }

        let end = EventScheduleFormatter.string(
            from: endsAt,
            includesTime: !isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
        return "\(start) – \(end)"
    }
}

private enum EventScheduleFormatter {
    static func string(
        from date: Date,
        includesTime: Bool,
        timeZoneIdentifier: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = includesTime ? .short : .none
        return formatter.string(from: date)
    }
}

struct EventScheduleRow: View {
    let startsAt: Date
    let endsAt: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String

    private var schedule: EventSchedule {
        EventSchedule(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(isAllDay ? "All-day" : "Date and Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(schedule.summary)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if !isAllDay {
                    Text(timeZoneName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAllDay ? "All-day schedule" : "Date and time")
        .accessibilityValue(schedule.summary)
        .accessibilityHint("Opens schedule editor")
    }

    private var timeZoneName: String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return timeZoneIdentifier
        }
        return timeZone.localizedName(for: .generic, locale: .current) ?? timeZoneIdentifier
    }
}

struct TimelineCollectionCard: View {
    let item: TimelineItem
    let transitionNamespace: Namespace.ID
    var showsPlanningStatus = true
    var cardAspectRatio: CGFloat? = nil

    private var scheduleSummary: String {
        guard item.hasScheduledDate else { return "Date not set" }
        let start = item.scheduledAt.formatted(
            date: .abbreviated,
            time: item.isAllDay ? .omitted : .shortened
        )
        return item.isAllDay ? "\(start) · All-day" : start
    }

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
                    .strikethrough(item.completionStatus == .complete)

                Text(scheduleSummary)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.36), radius: 5, y: 2)
            .padding(AppTheme.Spacing.standard)

            if item.completionStatus == .complete {
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

            if showsPlanningStatus {
                VStack {
                    HStack {
                        EventStatusBadge(status: item.status)

                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(AppTheme.Spacing.compact)
            }
        }
        .aspectRatio(cardAspectRatio ?? artworkAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .matchedTransitionSource(id: item.id, in: transitionNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            "\(item.purpose.title), \(item.hasScheduledDate ? (item.completionStatus == .complete ? "Completed" : "Upcoming") : "Needs a date")"
        )
    }
}

struct TimelineEventCard: View {
    let item: TimelineItem
    let transitionNamespace: Namespace.ID
    var showsPlanningStatus = true
    var cardAspectRatio: CGFloat? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            TimelineCollectionCard(
                item: item,
                transitionNamespace: transitionNamespace,
                showsPlanningStatus: showsPlanningStatus,
                cardAspectRatio: cardAspectRatio
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens event details")
    }
}

struct EventStatusBadge: View {
    let status: EventStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .appImageOverlayAppearance()
            .accessibilityLabel("Event status: \(status.title)")
    }
}

struct EventResponseControl: View {
    let selection: EventResponse?
    let select: (EventResponse) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                controls
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                controls
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        ForEach(EventResponse.allCases) { option in
            Button {
                select(option)
            } label: {
                Label(option.title, systemImage: option.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
            .tint(selection == option ? AppTheme.ColorToken.accent : .secondary)
            .foregroundStyle(selection == option ? AppTheme.ColorToken.accent : .primary)
            .accessibilityValue(selection == option ? "Selected" : "Not selected")
        }
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
            ambientBlurRadius: progressiveBlurRadius == 0 ? 4 : 12,
            progressiveBlurRadius: progressiveBlurRadius == 0 ? 0 : 32,
            blurStart: 0.24
        )
    }
}

private struct TimelineEventDetailView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDeletion = false
    @State private var isEditingEvent = false

    let itemID: UUID
    let transitionNamespace: Namespace.ID

    private var item: TimelineItem? {
        workspace.timeline.first { $0.id == itemID }
    }

    var body: some View {
        Group {
            if let item {
                EventInvitationScreen(reference: .subevent(item.id))
            } else {
                ContentUnavailableView("Event unavailable", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("Event details")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .appImageNavigationBarAppearance()
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Event actions", systemImage: "ellipsis") {
                        Button("Edit Event", systemImage: "pencil") {
                            isEditingEvent = true
                        }

                        if item.status == .archived {
                            Button("Restore as Draft", systemImage: "arrow.uturn.backward") {
                                withAnimation {
                                    workspace.setEventStatus(.draft, for: item)
                                }
                            }
                        } else {
                            Button(
                                item.completionStatus == .complete ? "Undo Complete" : "Mark Complete",
                                systemImage: item.completionStatus == .complete ? "arrow.uturn.backward" : "checkmark.circle"
                            ) {
                                withAnimation {
                                    workspace.toggleTimelineItem(item)
                                }
                            }

                            Button("Archive Event", systemImage: "archivebox") {
                                withAnimation {
                                    workspace.setEventStatus(.archived, for: item)
                                }
                                dismiss()
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
        .sheet(isPresented: $isEditingEvent) {
            if let item {
                NavigationStack {
                    EventEditorView(mode: .subevent(item))
                }
            }
        }
        .navigationTransition(.zoom(sourceID: itemID, in: transitionNamespace))
    }
}

enum TimelineEventAudience {
    case planning
    case invitation
}

struct TimelineEventReadOnlyView: View {
    @Environment(WeddingWorkspace.self) private var workspace

    let item: TimelineItem
    let transitionNamespace: Namespace.ID

    private var currentItem: TimelineItem {
        workspace.timeline.first { $0.id == item.id } ?? item
    }

    var body: some View {
        EventInvitationScreen(reference: .subevent(currentItem.id))
            .navigationTitle("Event details")
            .navigationBarTitleDisplayMode(.inline)
            .appClearNavigationBar()
            .appImageNavigationBarAppearance()
            .navigationTransition(.zoom(sourceID: item.id, in: transitionNamespace))
    }
}

struct TimelineEventDetailScreen: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var weather = EventWeatherModel()

    let item: TimelineItem
    let audience: TimelineEventAudience

    private var participantNames: String {
        let participantIDs = Set(item.participantIDs)
        let names = workspace.members.filter { member in
            guard participantIDs.contains(member.id) else { return false }
            switch audience {
            case .planning:
                return member.participantRole != .guest
            case .invitation:
                return member.participantRole == .host
            }
        }
            .map(\.name)
        return names.isEmpty
            ? (audience == .planning ? "Unassigned" : "Your hosts")
            : names.formatted()
    }

    private var weatherRequestID: String {
        [
            item.id.uuidString,
            item.scheduledAt.timeIntervalSinceReferenceDate.formatted(),
            item.eventLocation?.latitude?.formatted() ?? "no-latitude",
            item.eventLocation?.longitude?.formatted() ?? "no-longitude"
        ]
        .joined(separator: "|")
    }

    private var scheduleSummary: String {
        EventSchedule(
            startsAt: item.scheduledAt,
            endsAt: item.endsAt,
            isAllDay: item.isAllDay,
            timeZoneIdentifier: item.timeZoneIdentifier
        ).summary
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
                        Color.clear
                            .frame(height: max(proxy.size.height * 0.38, 240))
                            .accessibilityHidden(true)

                        identity

                        if audience == .invitation {
                            attendanceCard
                        }

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
        .task(id: weatherRequestID) {
            await weather.load(for: item)
        }
    }

    private var readingScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(reduceTransparency ? 0.52 : 0.32), location: 0),
                .init(color: .black.opacity(reduceTransparency ? 0.18 : 0.08), location: 0.16),
                .init(color: .clear, location: 0.28),
                .init(color: .black.opacity(reduceTransparency ? 0.36 : 0.20), location: 0.40),
                .init(color: .black.opacity(reduceTransparency ? 0.68 : 0.46), location: 0.58),
                .init(color: .black.opacity(reduceTransparency ? 0.82 : 0.62), location: 0.78),
                .init(color: .black.opacity(reduceTransparency ? 0.92 : 0.78), location: 1)
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
                    item.completionStatus == .complete ? "Completed" : "Upcoming",
                    systemImage: item.completionStatus == .complete ? "checkmark.circle.fill" : "calendar"
                )
                .font(.caption.weight(.semibold))
            }

            Text(item.title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.44), radius: 8, y: 2)
    }

    private var attendanceCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Label("Will you join us?", systemImage: "envelope.open.fill")
                .font(.headline)

            EventResponseControl(selection: item.response) { response in
                withAnimation(.snappy) {
                    workspace.setResponse(response, for: item)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(AppTheme.Spacing.standard)
        .background(
            reduceTransparency
                ? AnyShapeStyle(.black.opacity(0.92))
                : AnyShapeStyle(.thickMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .appImageOverlayAppearance()
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            TimelineMetadataRow(
                title: "Date & Time",
                value: scheduleSummary,
                symbol: "calendar"
            )

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: "Event Purpose",
                value: item.purpose.title,
                symbol: item.purpose.symbol
            )

            Divider()
                .padding(.leading, 44)

            if let location = item.location {
                TimelineMetadataRow(
                    title: "Location",
                    value: location,
                    symbol: "mappin.and.ellipse"
                )

                Divider()
                    .padding(.leading, 44)
            }

            TimelineWeatherRow(
                phase: weather.phase,
                attribution: weather.attribution
            ) {
                Task {
                    await weather.load(for: item)
                }
            }

            Divider()
                .padding(.leading, 44)

            TimelineMetadataRow(
                title: audience == .planning ? "Planning Team" : "Hosted By",
                value: participantNames,
                symbol: "person.2.fill"
            )
        }
        .padding(.vertical, AppTheme.Spacing.compact)
        .background(
            reduceTransparency ? AnyShapeStyle(.black.opacity(0.90)) : AnyShapeStyle(.thickMaterial),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .appImageOverlayAppearance()
    }
}

struct TimelineWeatherRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let phase: EventWeatherPhase
    let attribution: EventWeatherAttribution?
    let retry: () -> Void

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                loadingRow
            case .forecast(let forecast):
                forecastRow(forecast)
            case .missingLocation:
                TimelineMetadataRow(
                    title: "Forecast",
                    value: "Add a mapped location",
                    symbol: "cloud.sun"
                )
            case .outsideForecastRange:
                TimelineMetadataRow(
                    title: "Forecast",
                    value: "Available closer to the event",
                    symbol: "cloud.sun"
                )
            case .pastEvent:
                TimelineMetadataRow(
                    title: "Forecast",
                    value: "Event has passed",
                    symbol: "cloud.sun"
                )
            case .unavailable:
                unavailableRow
            }
        }
    }

    private var loadingRow: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: "cloud.sun")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Forecast")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: AppTheme.Spacing.compact) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading weather…")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func forecastRow(_ forecast: EventWeatherForecast) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Forecast")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                Text(forecast.conditionDescription)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        temperatureSummary(forecast)
                        precipitationSummary(forecast)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        temperatureSummary(forecast)
                        precipitationSummary(forecast)
                    }
                }

                if let attribution {
                    weatherAttribution(attribution)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 14)
        .frame(minHeight: 76)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func temperatureSummary(_ forecast: EventWeatherForecast) -> some View {
        Text("H: \(forecast.highTemperatureText)  L: \(forecast.lowTemperatureText)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("High \(forecast.highTemperatureText), low \(forecast.lowTemperatureText)")
    }

    private func precipitationSummary(_ forecast: EventWeatherForecast) -> some View {
        Label(forecast.precipitationChanceText, systemImage: "drop.fill")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.72))
            .accessibilityLabel("\(forecast.precipitationChanceText) chance of precipitation")
    }

    private func weatherAttribution(_ attribution: EventWeatherAttribution) -> some View {
        Link(destination: attribution.legalPageURL) {
            AsyncImage(
                url: colorScheme == .light
                    ? attribution.combinedMarkLightURL
                    : attribution.combinedMarkDarkURL
            ) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(attribution.serviceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 22, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weather data attribution")
        .accessibilityHint("Opens Apple Weather data sources")
    }

    private var unavailableRow: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.standard) {
            Image(systemName: "cloud.sun")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Forecast")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))

                Text("Weather unavailable")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 0)

            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .frame(minWidth: AppTheme.Layout.minimumTouchTarget, minHeight: AppTheme.Layout.minimumTouchTarget)
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
    }
}

private struct TimelineMetadataRow: View {
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
        }
        .padding(.horizontal, AppTheme.Spacing.standard)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private extension TimelineCategory {
    var collectionAspectRatio: CGFloat {
        switch self {
        case .venue: 0.84
        case .foodTasting: 1.18
        case .photography: 1.08
        case .honeymoon: 0.82
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
