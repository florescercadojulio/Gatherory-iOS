import PostHog
import SwiftUI

enum EventEditorMode {
    case main
    case subevent(TimelineItem?)
}

private func attireValues(from description: String) -> (style: AttireStyle, guidance: String) {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let style = AttireStyle.allCases
        .filter({ $0 != .any })
        .first(where: {
            trimmed.range(
                of: $0.title,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) != nil
        }) else {
        return (.any, trimmed)
    }

    let suffix = trimmed.dropFirst(style.title.count)
        .trimmingCharacters(in: CharacterSet(charactersIn: " ·—-:"))
    return (style, suffix)
}

private func attireDescription(style: AttireStyle, guidance: String) -> String {
    let trimmedGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
    return switch (style, trimmedGuidance.isEmpty) {
    case (.any, true): ""
    case (.any, false): trimmedGuidance
    case (_, true): style.title
    case (_, false): "\(style.title) · \(trimmedGuidance)"
    }
}

private func decimalAmount(from input: String) -> Decimal? {
    MoneyInputFormatter.decimal(from: input)
}

private extension TimelineCategory {
    var expenseCategory: EventExpenseCategory {
        switch self {
        case .venue, .ceremony:
            .venue
        case .foodTasting, .rehearsal:
            .foodAndDrink
        case .photography:
            .photography
        case .honeymoon:
            .travel
        case .attireFitting:
            .attire
        case .weddingShower:
            .gifts
        case .bachelorBachelorette, .reception:
            .entertainment
        case .other:
            .other
        }
    }
}

/// Shared by event creation and event ideas so choosing an event type feels
/// identical regardless of where the flow starts.
struct EventCategoryStrip: View {
    @Binding var selection: TimelineCategory

    private var orderedCategories: [TimelineCategory] {
        [.other] + TimelineCategory.allCases.filter { $0 != .other }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ForEach(orderedCategories) { option in
                    let isSelected = selection == option

                    Button {
                        withAnimation(.snappy) {
                            selection = option
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option == .other ? "circle.slash" : option.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)

                            Text(option == .other ? "None" : option.title)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundStyle(isSelected ? AppTheme.ColorToken.onAccent : .primary)
                        .frame(width: 98, height: 76)
                        .background(
                            isSelected ? option.artworkAccent : AppTheme.ColorToken.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .strokeBorder(
                                    isSelected ? option.artworkAccent : AppTheme.ColorToken.cardBorder,
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option == .other ? "No category" : option.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Event categories")
    }
}

struct EventPurposeSelector: View {
    @Binding var selection: EventPurpose
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppTheme.Spacing.compact) { purposeTiles }
            } else {
                HStack(spacing: AppTheme.Spacing.compact) { purposeTiles }
            }
        }
        .padding(2)
        .accessibilityLabel("Event purpose")
    }

    private var purposeTiles: some View {
        ForEach(EventPurpose.allCases) { option in
            let isSelected = selection == option

            Button {
                withAnimation(.snappy) {
                    selection = option
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(option.title, systemImage: option.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    Text(option.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                .padding(8)
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
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }
}

/// One editor for creating and editing every event in the two-level hierarchy.
struct EventEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    let mode: EventEditorMode

    @State private var title: String
    @State private var category: TimelineCategory
    @State private var purpose: EventPurpose
    @State private var mainStatus: MainEventStatus
    @State private var childStatus: EventStatus
    @State private var startsAt: Date
    @State private var hasScheduledDate: Bool
    @State private var endsAt: Date?
    @State private var isAllDay: Bool
    @State private var timeZoneIdentifier: String
    @State private var eventLocation: EventLocation?
    @State private var imageData: Data?
    @State private var eventDescription: String
    @State private var attireStyle: AttireStyle
    @State private var dressCode: String
    @State private var eventExpenses: [EventExpense]
    @State private var usesBudget: Bool
    @State private var mainBudgetAmount: String
    @State private var selectedParticipantIDs: Set<UUID>
    @State private var isEditingDateAndTime = false
    @State private var isEditingLocation = false
    @State private var isConfirmingDeletion = false
    @State private var didLoadMain = false
    @State private var didLoadExpenses = false
    @State private var isEditingBudget = false
    @State private var isEditingCosts = false
    @State private var isChoosingEventType = false

    private let draftEventID: UUID

    init(mode: EventEditorMode) {
        self.mode = mode
        let item: TimelineItem? = if case .subevent(let item) = mode { item } else { nil }
        draftEventID = item?.id ?? UUID()
        _title = State(initialValue: item?.title ?? "")
        _category = State(initialValue: item?.category ?? .other)
        _purpose = State(initialValue: item?.purpose ?? .planning)
        _mainStatus = State(initialValue: .draft)
        _childStatus = State(initialValue: item?.status ?? .approved)
        _startsAt = State(initialValue: item?.scheduledAt ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _hasScheduledDate = State(initialValue: item?.hasScheduledDate ?? true)
        _endsAt = State(initialValue: item?.endsAt)
        _isAllDay = State(initialValue: item?.isAllDay ?? false)
        _timeZoneIdentifier = State(initialValue: item?.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier)
        _eventLocation = State(initialValue: item?.eventLocation)
        _imageData = State(initialValue: item?.imageData)
        _eventDescription = State(initialValue: item?.eventDescription ?? "")
        let attire = attireValues(from: item?.dressCode ?? "")
        _attireStyle = State(initialValue: attire.style)
        _dressCode = State(initialValue: attire.guidance)
        _eventExpenses = State(initialValue: [])
        _usesBudget = State(initialValue: item?.budgetCap != nil)
        _mainBudgetAmount = State(
            initialValue: item?.budgetCap.map {
                MoneyInputFormatter.editingText(
                    from: NSDecimalNumber(decimal: $0).stringValue,
                    allowsFraction: false
                )
            } ?? ""
        )
        _selectedParticipantIDs = State(initialValue: Set(item?.participantIDs ?? []))
    }

    private var originalItem: TimelineItem? {
        if case .subevent(let item) = mode { item } else { nil }
    }

    private var isMainEvent: Bool {
        if case .main = mode { true } else { false }
    }

    private var isCreating: Bool {
        !isMainEvent && originalItem == nil
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedTitle: String {
        guard trimmedTitle.isEmpty else { return trimmedTitle }
        return category == .other
            ? (purpose == .planning ? "Planning Event" : "Event")
            : category.title
    }

    private var expenseEventID: UUID {
        isMainEvent ? workspace.mainEventID : draftEventID
    }

    private var eventCostTotal: Decimal {
        eventExpenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var currentChildBudget: Decimal {
        guard let originalItem else { return .zero }
        return workspace.budgetCap(for: .subevent(originalItem.id)) ?? .zero
    }

    private var parsedMainBudget: Decimal? {
        guard !mainBudgetAmount.isEmpty else { return nil }
        return MoneyInputFormatter.decimal(from: mainBudgetAmount)
    }

    private var currentAllocatedBudget: Decimal {
        workspace.allocatedBudgetTotal
    }

    private var mainBudgetIsValid: Bool {
        mainBudgetAmount.isEmpty
            || (parsedMainBudget.map { $0 > .zero && $0 >= currentAllocatedBudget } ?? false)
    }

    private var childBudgetIsValid: Bool {
        guard !isMainEvent, originalItem?.budgetCap == nil else { return true }
        guard let parsedMainBudget else { return mainBudgetAmount.isEmpty }
        return parsedMainBudget > .zero && parsedMainBudget <= availableForNewEvent
    }

    private var eventIdentitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(isMainEvent ? "Event Name" : "Custom Name (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(
                    isMainEvent ? "Name your event" : "Use the suggested name",
                    text: $title
                )
                .textInputAutocapitalization(.words)
            }

            if isMainEvent {
                Picker("Status", selection: $mainStatus) {
                    ForEach(MainEventStatus.allCases) { status in
                        Label(status.title, systemImage: status.symbol).tag(status)
                    }
                }
                Text(mainStatus.detail).font(.footnote).foregroundStyle(.secondary)
            } else {
                Picker("Planning Status", selection: $childStatus) {
                    ForEach(EventStatus.allCases.filter { $0 != .archived }) { status in
                        Label(status.title, systemImage: status.symbol).tag(status)
                    }
                }
            }
        } header: {
            Text(isMainEvent ? "Main Event" : "Event Details")
        } footer: {
            if !isMainEvent && trimmedTitle.isEmpty {
                Text("The event will be named “\(resolvedTitle)”.")
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var eventTypeSection: some View {
        Section {
            Button {
                withAnimation(.snappy) {
                    isChoosingEventType.toggle()
                }
            } label: {
                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: category == .other ? "circle.slash" : category.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(category.artworkAccent)
                        .frame(width: 48, height: 48)
                        .background(
                            category.artworkAccent.opacity(0.12),
                            in: RoundedRectangle(
                                cornerRadius: AppTheme.Radius.control,
                                style: .continuous
                            )
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(category == .other ? "Choose a Type" : category.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ColorToken.textPrimary)

                        Text(isChoosingEventType ? "Choose below" : "Tap to change")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    }

                    Spacer(minLength: AppTheme.Spacing.compact)

                    Image(systemName: isChoosingEventType ? "chevron.up" : "chevron.down")
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
                category == .other ? "Choose an event type" : "Event type, \(category.title)"
            )
            .accessibilityHint(
                isChoosingEventType ? "Hides event types" : "Shows available event types"
            )

            if isChoosingEventType {
                EventCategoryStrip(selection: $category)
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Picker("Purpose", selection: $purpose) {
                ForEach(EventPurpose.allCases) { option in
                    Text(option.shortTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Event Type")
        } footer: {
            Text(purpose.description)
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var attireSection: some View {
        Section {
            AttireStylePicker(selection: $attireStyle)

            TextField("Colors, fabrics, or guidance (optional)", text: $dressCode, axis: .vertical)
                .textInputAutocapitalization(.sentences)
                .lineLimit(2...5)
        } header: {
            Text("Attire")
        } footer: {
            Text("Choose Any when this event doesn’t need attire guidance.")
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var whenAndWhereSection: some View {
        Section("When & Where") {
            Button {
                isEditingDateAndTime = true
            } label: {
                if !isMainEvent && !hasScheduledDate {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Date & Time")
                                .foregroundStyle(AppTheme.ColorToken.accent)
                            Text("Required before this event appears on Home")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                } else {
                    EventScheduleRow(
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
            }
            .buttonStyle(.plain)

            Button {
                isEditingLocation = true
            } label: {
                editorRow(
                    symbol: "mappin.and.ellipse",
                    title: "Location",
                    value: eventLocation?.formatted ?? "Add Location",
                    isEmphasized: eventLocation == nil
                )
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var participantsSection: some View {
        Section {
            ForEach(eventParticipantOptions) { member in
                Button {
                    toggle(member)
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        ParticipantAvatarView(member: member, size: 34)

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
                .accessibilityValue(
                    selectedParticipantIDs.contains(member.id) ? "Selected" : "Not selected"
                )
            }
        } header: {
            Text("People")
        } footer: {
            if category == .honeymoon {
                Text("Honeymoons start with the hosts only.")
            } else {
                Text("Everyone starts selected from the main event. Changes here only affect this event.")
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    private var eventCardSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField(
                    "Tell guests what to expect (optional)",
                    text: $eventDescription,
                    axis: .vertical
                )
                .textInputAutocapitalization(.sentences)
                .lineLimit(3...8)
                .onChange(of: eventDescription) { _, value in
                    if value.count > 750 { eventDescription = String(value.prefix(750)) }
                }
            }

            Text("\(eventDescription.count)/750")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)

            PhotoAttachmentPicker(
                imageData: $imageData,
                emptySymbol: isMainEvent ? IdeaCategory.event.symbol : category.symbol,
                fallbackColors: isMainEvent ? IdeaCategory.event.artworkColors : category.artworkColors,
                fallbackAccent: isMainEvent ? IdeaCategory.event.artworkAccent : category.artworkAccent,
                suggestedConcept: "Event artwork for \(resolvedTitle)"
            )
        } header: {
            Text("Event Card")
        } footer: {
            if isMainEvent || purpose == .eventExperience {
                Text("The description and cover appear in the event details guests can see.")
            } else {
                Text("The description and cover help collaborators recognize this planning event.")
            }
        }
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    var body: some View {
        Form {
            if !isMainEvent {
                eventTypeSection
            }

            eventIdentitySection

            whenAndWhereSection

            if !isMainEvent {
                participantsSection
            }

            eventCardSection

            if isMainEvent || purpose == .eventExperience || attireStyle != .any || !dressCode.isEmpty {
                attireSection
            }

            Section {
                if !workspace.isScopedEvent && (isMainEvent || workspace.workspaceBudgetCap != nil) {
                    Button {
                        isEditingBudget = true
                    } label: {
                        planningRow(
                            symbol: "chart.pie.fill",
                            title: "Budget",
                            value: budgetSummary
                        )
                    }
                    .buttonStyle(.plain)
                } else if !workspace.isScopedEvent {
                    planningRow(
                        symbol: "chart.pie.fill",
                        title: "Budget",
                        value: "Set Workspace Budget First",
                        isAvailable: false
                    )
                }

                Button {
                    isEditingCosts = true
                } label: {
                    planningRow(
                        symbol: "list.bullet.rectangle.portrait",
                        title: "Cost",
                        value: costSummary
                    )
                }
                .buttonStyle(.plain)
            } header: {
                Text("Planning")
            } footer: {
                if workspace.isScopedEvent {
                    Text("Costs stay with this event.")
                } else if isMainEvent || workspace.workspaceBudgetCap != nil {
                    Text("Budget is the spending limit. Cost is what you expect to spend.")
                } else {
                    Text("Set a workspace budget on the main event first, then allocate part of it here. You can still track this event’s expected cost now.")
                }
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            if isMainEvent && workspace.canDeleteMainEvent && !workspace.isMainEventDeleted {
                Section {
                    Button("Delete Event", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text("The main event can only be deleted while it is a draft.")
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            }
        }
        .appKeyboardDismissal()
        .formStyle(.grouped)
        .contentMargins(.top, AppTheme.Spacing.compact, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle(isCreating || workspace.isMainEventDeleted ? "New Event" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isCreating ? "Schedule" : "Save") { save() }
                    .disabled(
                        isMainEvent
                            ? trimmedTitle.isEmpty || !mainBudgetIsValid
                            : selectedParticipantIDs.isEmpty || !childBudgetIsValid
                    )
                    .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier
            ) { start, end, allDay, timeZone in
                startsAt = start
                hasScheduledDate = true
                endsAt = end
                isAllDay = allDay
                timeZoneIdentifier = timeZone
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingLocation) {
            EventLocationEditorView(location: eventLocation) { eventLocation = $0 }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingBudget) {
            NavigationStack {
                EventBudgetSettingsView(
                    isMainEvent: isMainEvent,
                    originalItem: originalItem,
                    initialUsesBudget: usesBudget,
                    initialMainBudgetAmount: mainBudgetAmount,
                    allocatedWorkspaceBudget: currentAllocatedBudget,
                    availableForNewEvent: availableForNewEvent
                ) { updatedUsesBudget, updatedMainBudgetAmount in
                    usesBudget = updatedUsesBudget
                    mainBudgetAmount = updatedMainBudgetAmount
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingCosts) {
            NavigationStack {
                EventCostsEditorView(
                    expenses: $eventExpenses,
                    eventID: expenseEventID,
                    suggestedTitle: resolvedTitle,
                    suggestedCategory: category.expenseCategory
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete this event?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                workspace.deleteMainEvent()
                PostHogSDK.shared.capture("main_event_deleted")
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes its schedule and shared event moments.")
        }
        .task {
            if isMainEvent {
                loadMainEventIfNeeded()
            } else if isCreating && selectedParticipantIDs.isEmpty {
                selectedParticipantIDs = Set(workspace.mainEventParticipantIDs)
            }
            loadExpensesIfNeeded()
        }
        .onChange(of: category) { previousCategory, updatedCategory in
            guard !isMainEvent else { return }
            if isChoosingEventType {
                withAnimation(.snappy) {
                    isChoosingEventType = false
                }
            }
            if updatedCategory == .honeymoon {
                purpose = .eventExperience
                selectedParticipantIDs = Set(hostParticipantIDs)
            } else if previousCategory == .honeymoon, isCreating {
                selectedParticipantIDs = Set(workspace.mainEventParticipantIDs)
            }
        }
    }

    private var hostParticipantIDs: [UUID] {
        workspace.members
            .filter { $0.participantRole == .host }
            .map(\.id)
    }

    private var eventParticipantOptions: [WorkspaceMember] {
        category == .honeymoon
            ? workspace.members.filter { $0.participantRole == .host }
            : workspace.members
    }

    private var currencyCode: String {
        workspace.currencyCode
    }

    private var budgetSummary: String {
        if isMainEvent {
            return parsedMainBudget?.formatted(.currency(code: currencyCode)) ?? "Not Set"
        }
        guard workspace.workspaceBudgetCap != nil else { return "Workspace Budget Not Set" }
        guard usesBudget, let parsedMainBudget else { return "Not Set" }
        if originalItem == nil { return parsedMainBudget.formatted(.currency(code: currencyCode)) }
        return currentChildBudget.formatted(.currency(code: currencyCode))
    }

    private var availableForNewEvent: Decimal {
        workspace.freeBudgetPool + (workspace.mainEventBudgetCap ?? .zero)
    }

    private var costSummary: String {
        guard !eventExpenses.isEmpty else { return "Not Set" }
        let total = eventCostTotal.formatted(.currency(code: currencyCode))
        return "\(total) · \(eventExpenses.count) \(eventExpenses.count == 1 ? "item" : "items")"
    }

    private func planningRow(
        symbol: String,
        title: String,
        value: String,
        isAvailable: Bool = true
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .foregroundStyle(
                    isAvailable
                        ? AppTheme.ColorToken.accent
                        : AppTheme.ColorToken.textSecondary
                )
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isAvailable {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            isAvailable
                ? "Opens \(title.lowercased()) settings"
                : "Set a workspace budget on the main event before allocating a budget to this event"
        )
    }

    private func editorRow(
        symbol: String,
        title: String,
        value: String,
        isEmphasized: Bool = false
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol).foregroundStyle(AppTheme.ColorToken.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value)
                    .foregroundStyle(isEmphasized ? AppTheme.ColorToken.accent : .primary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityHint("Opens location editor")
    }

    private func loadMainEventIfNeeded() {
        guard !didLoadMain else { return }
        title = workspace.title
        mainStatus = workspace.mainEventStatus
        startsAt = workspace.mainEventStartsAt
        endsAt = workspace.mainEventEndsAt
        isAllDay = workspace.mainEventIsAllDay
        timeZoneIdentifier = workspace.mainEventTimeZoneIdentifier
        eventLocation = workspace.mainEventLocation
        imageData = workspace.mainEventImageData
        let attire = attireValues(from: workspace.dressCode)
        attireStyle = attire.style
        dressCode = attire.guidance
        eventDescription = workspace.eventMessage
        mainBudgetAmount = workspace.workspaceBudgetCap.map {
            MoneyInputFormatter.editingText(
                from: NSDecimalNumber(decimal: $0).stringValue,
                allowsFraction: false
            )
        } ?? ""
        didLoadMain = true
    }

    private func loadExpensesIfNeeded() {
        guard !didLoadExpenses else { return }
        eventExpenses = workspace.expenses(forEventID: expenseEventID)
        didLoadExpenses = true
    }

    private func save() {
        if isMainEvent {
            if !workspace.isScopedEvent {
                _ = workspace.updateWorkspaceBudgetCap(parsedMainBudget)
            }
            workspace.updateMainEvent(
                title: trimmedTitle,
                status: mainStatus,
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier,
                eventLocation: eventLocation,
                imageData: imageData,
                dressCode: attireDescription(style: attireStyle, guidance: dressCode),
                message: eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            let item = TimelineItem(
                id: draftEventID,
                title: resolvedTitle,
                category: category,
                purpose: purpose,
                scheduledAt: startsAt,
                schedulingState: hasScheduledDate ? .scheduled : .unscheduled,
                eventLocation: eventLocation,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier,
                participantIDs: Array(selectedParticipantIDs),
                parentEventID: workspace.mainEventID,
                status: childStatus,
                completionStatus: originalItem?.completionStatus ?? .upcoming,
                response: originalItem?.response,
                linkedIdeaID: originalItem?.linkedIdeaID,
                imageData: imageData,
                eventDescription: eventDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                dressCode: attireDescription(style: attireStyle, guidance: dressCode),
                budgetCap: usesBudget ? (originalItem?.budgetCap ?? .zero) : nil
            )
            if originalItem == nil {
                workspace.addTimelineItem(item)
                workspace.allocateInitialBudget(parsedMainBudget, to: item.id)
            } else {
                let needsInitialAllocation = originalItem?.budgetCap == nil && usesBudget
                workspace.updateTimelineItem(item)
                if needsInitialAllocation {
                    workspace.allocateInitialBudget(parsedMainBudget, to: item.id)
                }
            }
        }
        workspace.replaceExpenses(eventExpenses, forEventID: expenseEventID)
        PostHogSDK.shared.capture(
            isCreating ? "event_created" : "event_updated",
            properties: [
                "is_main_event": isMainEvent,
                "has_scheduled_date": hasScheduledDate,
                "uses_budget": usesBudget
            ]
        )
        dismiss()
    }

    private func toggle(_ member: WorkspaceMember) {
        if selectedParticipantIDs.contains(member.id) {
            selectedParticipantIDs.remove(member.id)
        } else {
            selectedParticipantIDs.insert(member.id)
        }
    }
}

/// Keeps the financial decision focused: a budget is an optional limit, not a cost entry.
private struct EventBudgetSettingsView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    let isMainEvent: Bool
    let originalItem: TimelineItem?
    let allocatedWorkspaceBudget: Decimal
    let availableForNewEvent: Decimal
    let onSave: (Bool, String) -> Void

    @State private var usesBudget: Bool
    @State private var mainBudgetAmount: String
    @State private var isAllocatingBudget = false

    init(
        isMainEvent: Bool,
        originalItem: TimelineItem?,
        initialUsesBudget: Bool,
        initialMainBudgetAmount: String,
        allocatedWorkspaceBudget: Decimal,
        availableForNewEvent: Decimal,
        onSave: @escaping (Bool, String) -> Void
    ) {
        self.isMainEvent = isMainEvent
        self.originalItem = originalItem
        self.allocatedWorkspaceBudget = allocatedWorkspaceBudget
        self.availableForNewEvent = availableForNewEvent
        self.onSave = onSave
        _usesBudget = State(initialValue: initialUsesBudget)
        _mainBudgetAmount = State(initialValue: initialMainBudgetAmount)
    }

    private var currencyCode: String {
        workspace.currencyCode
    }

    private var parsedMainBudget: Decimal? {
        guard !mainBudgetAmount.isEmpty else { return nil }
        return MoneyInputFormatter.decimal(from: mainBudgetAmount)
    }

    private var mainBudgetIsValid: Bool {
        mainBudgetAmount.isEmpty
            || (parsedMainBudget.map { $0 > .zero && $0 >= allocatedWorkspaceBudget } ?? false)
    }

    private var childBudgetIsValid: Bool {
        guard !isMainEvent, originalItem?.budgetCap == nil else { return true }
        guard let parsedMainBudget else { return mainBudgetAmount.isEmpty }
        return parsedMainBudget > .zero && parsedMainBudget <= availableForNewEvent
    }

    private var budgetIsValid: Bool {
        isMainEvent ? mainBudgetIsValid : childBudgetIsValid
    }

    private var currentAllocation: Decimal {
        guard let originalItem else { return .zero }
        return workspace.budgetCap(for: .subevent(originalItem.id)) ?? .zero
    }

    var body: some View {
        Form {
            if isMainEvent {
                Section {
                    EventBudgetAmountField(
                        amount: $mainBudgetAmount,
                        currencyCode: workspace.currencyCode
                    )

                    if allocatedWorkspaceBudget > .zero {
                        LabeledContent("Already Allocated") {
                            Text(
                                allocatedWorkspaceBudget,
                                format: .currency(code: currencyCode)
                            )
                            .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Workspace Budget")
                } footer: {
                    if !mainBudgetIsValid {
                        Text("The limit cannot be lower than the amount already allocated to events.")
                            .foregroundStyle(AppTheme.ColorToken.destructive)
                    } else {
                        Text("This optional limit powers remaining-budget and over-budget signals across the workspace.")
                    }
                }
            } else if originalItem == nil {
                Section {
                    EventBudgetAmountField(
                        amount: $mainBudgetAmount,
                        currencyCode: workspace.currencyCode
                    )
                } header: {
                    Text("Event Budget")
                } footer: {
                    if !childBudgetIsValid {
                        Text("Enter an amount up to \(availableForNewEvent.formatted(.currency(code: currencyCode))), or leave it blank.")
                            .foregroundStyle(AppTheme.ColorToken.destructive)
                    } else {
                        Text("This amount is allocated from the workspace when the event is scheduled.")
                    }
                }
            } else {
                Section {
                    if usesBudget {
                        LabeledContent("Current Allocation") {
                            Text(currentAllocation, format: .currency(code: currencyCode))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        Button("Change Allocation", systemImage: "arrow.left.arrow.right") {
                            isAllocatingBudget = true
                        }

                        Button("Remove Budget", systemImage: "trash", role: .destructive) {
                            usesBudget = false
                            mainBudgetAmount = ""
                        }
                    } else {
                        EventBudgetAmountField(
                            amount: $mainBudgetAmount,
                            currencyCode: workspace.currencyCode
                        )
                    }
                } header: {
                    Text("Event Budget")
                } footer: {
                    if usesBudget {
                        Text("Use budget allocation to move funds between this event, the main event, and the unallocated pool.")
                    } else if !childBudgetIsValid {
                        Text("Enter an amount up to \(availableForNewEvent.formatted(.currency(code: currencyCode))), or leave it blank.")
                            .foregroundStyle(AppTheme.ColorToken.destructive)
                    } else {
                        Text("Set an amount to add this event to the workspace budget.")
                    }
                }
            }
        }
        .appKeyboardDismissal()
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    let updatedUsesBudget = originalItem?.budgetCap == nil
                        ? parsedMainBudget != nil
                        : usesBudget
                    onSave(updatedUsesBudget, mainBudgetAmount)
                    dismiss()
                }
                .disabled(!budgetIsValid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $isAllocatingBudget) {
            if let originalItem {
                NavigationStack {
                    BudgetAllocationView(target: .subevent(originalItem.id))
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// A small ledger kept out of the main event form so setup remains about the event itself.
private struct EventCostsEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @Binding var expenses: [EventExpense]
    let eventID: UUID
    let suggestedTitle: String
    let suggestedCategory: EventExpenseCategory

    @State private var editorTarget: EventExpenseEditorTarget?
    @State private var quickAmount = ""

    private var currencyCode: String {
        workspace.currencyCode
    }

    private var total: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var parsedQuickAmount: Decimal? {
        decimalAmount(from: quickAmount)
    }

    private var canSetEstimate: Bool {
        parsedQuickAmount.map { $0 > .zero } ?? false
    }

    var body: some View {
        Form {
            if expenses.isEmpty {
                Section {
                    MoneyAmountField(
                        amount: $quickAmount,
                        title: "Estimated Cost",
                        placeholder: "0.00",
                        symbol: suggestedCategory.symbol,
                        style: .prominent,
                        currencyCode: workspace.currencyCode
                    )

                    Button("Set Estimated Cost", systemImage: "checkmark.circle.fill") {
                        setQuickEstimate()
                    }
                    .disabled(!canSetEstimate)
                    .fontWeight(.semibold)
                } header: {
                    Text("Estimated Cost")
                } footer: {
                    Text("Saved as an estimate for \(suggestedTitle). Details can be changed later.")
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            } else {
                Section {
                    LabeledContent("Tracked Total") {
                        Text(total, format: .currency(code: currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Includes estimated, committed, and paid costs.")
                }
                .listRowBackground(AppTheme.ColorToken.surface)

                Section("Cost Items") {
                    ForEach(expenses) { expense in
                        Button {
                            editorTarget = EventExpenseEditorTarget(expense: expense)
                        } label: {
                            costRow(expense)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteExpenses)

                    Button("Add Another Cost", systemImage: "plus.circle") {
                        editorTarget = EventExpenseEditorTarget(expense: nil)
                    }
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            }
        }
        .formStyle(.grouped)
        .appKeyboardDismissal()
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle(expenses.isEmpty ? "Set Cost" : "Costs")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                EventExpenseEditorView(
                    expense: target.expense,
                    eventID: eventID,
                    suggestedTitle: suggestedTitle,
                    suggestedCategory: suggestedCategory,
                    onSave: upsertExpense
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func costRow(_ expense: EventExpense) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: expense.category.symbol)
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .foregroundStyle(.primary)
                Text("\(expense.category.title) · \(expense.status.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            Text(expense.amount, format: .currency(code: currencyCode))
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edits this cost")
    }

    private func upsertExpense(_ expense: EventExpense) {
        if let index = expenses.firstIndex(where: { $0.id == expense.id }) {
            expenses[index] = expense
        } else {
            expenses.append(expense)
        }
    }

    private func setQuickEstimate() {
        guard let parsedQuickAmount, parsedQuickAmount > .zero else { return }
        expenses.append(
            EventExpense(
                eventID: eventID,
                title: suggestedTitle,
                amount: parsedQuickAmount,
                category: suggestedCategory,
                status: .estimated
            )
        )
        quickAmount = ""
        dismiss()
    }

    private func deleteExpenses(at offsets: IndexSet) {
        expenses.remove(atOffsets: offsets)
    }
}

private struct EventExpenseEditorTarget: Identifiable {
    let id: UUID
    let expense: EventExpense?

    init(expense: EventExpense?) {
        self.expense = expense
        id = expense?.id ?? UUID()
    }
}

private struct EventExpenseEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var amount: String
    @State private var category: EventExpenseCategory
    @State private var status: EventExpenseStatus

    let expense: EventExpense?
    let eventID: UUID
    let onSave: (EventExpense) -> Void

    init(
        expense: EventExpense?,
        eventID: UUID,
        suggestedTitle: String,
        suggestedCategory: EventExpenseCategory,
        onSave: @escaping (EventExpense) -> Void
    ) {
        self.expense = expense
        self.eventID = eventID
        self.onSave = onSave
        _title = State(initialValue: expense?.title ?? suggestedTitle)
        _amount = State(
            initialValue: expense.map {
                MoneyInputFormatter.editingText(from: NSDecimalNumber(decimal: $0.amount).stringValue)
            } ?? ""
        )
        _category = State(initialValue: expense?.category ?? suggestedCategory)
        _status = State(initialValue: expense?.status ?? .estimated)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAmount: Decimal? {
        decimalAmount(from: amount)
    }

    private var canSave: Bool {
        guard let parsedAmount else { return false }
        return !trimmedTitle.isEmpty && parsedAmount > .zero
    }

    var body: some View {
        Form {
            Section("Cost") {
                TextField("Name", text: $title)
                    .textInputAutocapitalization(.sentences)

                MoneyAmountField(
                    amount: $amount,
                    title: "Amount",
                    placeholder: "Amount",
                    currencyCode: workspace.currencyCode
                )
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(EventExpenseCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Status") {
                Picker("Status", selection: $status) {
                    ForEach(EventExpenseStatus.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .appKeyboardDismissal()
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle(expense == nil ? "Add Cost" : "Edit Cost")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        guard let parsedAmount else { return }
        onSave(
            EventExpense(
                id: expense?.id ?? UUID(),
                eventID: eventID,
                sourceIdeaID: expense?.sourceIdeaID,
                title: trimmedTitle,
                amount: parsedAmount,
                category: category,
                status: status,
                createdAt: expense?.createdAt ?? .now
            )
        )
        dismiss()
    }
}
