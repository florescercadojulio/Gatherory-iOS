import SwiftUI

enum EventEditorMode {
    case main
    case subevent(TimelineItem?)
}

/// One editor for creating and editing every event in the two-level hierarchy.
struct EventEditorView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let mode: EventEditorMode

    @State private var title: String
    @State private var category: TimelineCategory
    @State private var purpose: EventPurpose
    @State private var mainStatus: MainEventStatus
    @State private var childStatus: EventStatus
    @State private var startsAt: Date
    @State private var endsAt: Date?
    @State private var isAllDay: Bool
    @State private var timeZoneIdentifier: String
    @State private var eventLocation: EventLocation?
    @State private var imageData: Data?
    @State private var eventDescription: String
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
    @State private var expenseEditorTarget: EventExpenseEditorTarget?
    @State private var isAllocatingBudget = false

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
        _endsAt = State(initialValue: item?.endsAt)
        _isAllDay = State(initialValue: item?.isAllDay ?? false)
        _timeZoneIdentifier = State(initialValue: item?.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier)
        _eventLocation = State(initialValue: item?.eventLocation)
        _imageData = State(initialValue: item?.imageData)
        _eventDescription = State(initialValue: item?.eventDescription ?? "")
        _dressCode = State(initialValue: item?.dressCode ?? "")
        _eventExpenses = State(initialValue: [])
        _usesBudget = State(initialValue: item?.budgetCap != nil)
        _mainBudgetAmount = State(initialValue: "")
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
        return switch category {
        case .venue: purpose == .planning ? "Venue Visit" : "Venue"
        case .foodTasting: "Food Tasting"
        case .attireFitting: "Attire Fitting"
        case .weddingShower: "Wedding Shower"
        case .bachelorBachelorette: "Bachelor or Bachelorette Party"
        case .rehearsal: "Wedding Rehearsal"
        case .ceremony: "Ceremony"
        case .reception: "Reception"
        case .other: purpose == .planning ? "Planning Event" : "Event"
        }
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
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = mainBudgetAmount
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized)
    }

    private var currentAllocatedBudget: Decimal {
        workspace.allocatedBudgetTotal
    }

    private var mainBudgetIsValid: Bool {
        mainBudgetAmount.isEmpty
            || (parsedMainBudget.map { $0 > .zero && $0 >= currentAllocatedBudget } ?? false)
    }

    var body: some View {
        Form {
            if !isMainEvent {
                Section("Event Type") {
                    categoryGrid
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("Purpose") {
                    purposePicker
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                TextField(isMainEvent ? "Event name" : "Custom name (optional)", text: $title)
                    .textInputAutocapitalization(.words)

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
                Text(isMainEvent ? "Main Event" : "Event")
            } footer: {
                if !isMainEvent && trimmedTitle.isEmpty {
                    Text("The event will be named “\(resolvedTitle)”.")
                }
            }

            Section("Cover") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: isMainEvent ? "heart.fill" : category.symbol,
                    fallbackAssetName: isMainEvent || category == .venue ? "WeddingVenueHero" : nil,
                    fallbackColors: isMainEvent ? nil : category.artworkColors,
                    fallbackAccent: isMainEvent ? AppTheme.ColorToken.accent : category.artworkAccent,
                    suggestedConcept: "Event artwork for \(resolvedTitle)"
                )
            }

            Section("Date and Location") {
                Button {
                    isEditingDateAndTime = true
                } label: {
                    editorRow(
                        symbol: "calendar.badge.clock",
                        title: isAllDay ? "All-day" : "Date and Time",
                        value: scheduleSummary
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isEditingLocation = true
                } label: {
                    editorRow(
                        symbol: "mappin.and.ellipse",
                        title: "Location",
                        value: eventLocation?.formatted ?? "Add Location"
                    )
                }
                .buttonStyle(.plain)
            }

            if isMainEvent {
                Section {
                    TextField("Budget cap", text: $mainBudgetAmount)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Workspace Budget (Optional)")
                } footer: {
                    if !mainBudgetIsValid && currentAllocatedBudget > .zero {
                        Text("At least \(currentAllocatedBudget.formatted(.currency(code: currencyCode))) is already allocated to events.")
                    } else {
                        Text("This cap powers budget signals across the workspace.")
                    }
                }
            } else if workspace.workspaceBudgetCap != nil {
                Section {
                    Toggle("Uses a budget", isOn: $usesBudget)

                    if usesBudget {
                        LabeledContent(
                            "Allocated",
                            value: currentChildBudget.formatted(
                                .currency(code: currencyCode)
                            )
                        )

                        if originalItem?.budgetCap != nil {
                            Button("Allocate Budget", systemImage: "arrow.left.arrow.right") {
                                isAllocatingBudget = true
                            }
                        }
                    }
                } header: {
                    Text("Budget")
                } footer: {
                    Text(
                        usesBudget
                            ? "Allocate existing workspace budget without changing the workspace cap."
                            : "Leave this off for events that don't need spending."
                    )
                }
            }

            Section {
                if eventExpenses.isEmpty {
                    Text("No costs added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(eventExpenses) { expense in
                        Button {
                            expenseEditorTarget = EventExpenseEditorTarget(expense: expense)
                        } label: {
                            expenseRow(expense)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteExpenses)
                }

                Button("Add Cost", systemImage: "plus.circle") {
                    expenseEditorTarget = EventExpenseEditorTarget(expense: nil)
                }
            } header: {
                HStack {
                    Text("Costs")
                    Spacer()
                    if !eventExpenses.isEmpty {
                        Text(eventCostTotal, format: .currency(code: currencyCode))
                    }
                }
            } footer: {
                Text("Track estimates, commitments, and payments for this event.")
            }

            Section {
                TextField("Dress code (optional)", text: $dressCode)
                    .textInputAutocapitalization(.sentences)

                TextEditor(text: $eventDescription)
                    .frame(minHeight: 110, alignment: .topLeading)
                    .accessibilityLabel("Event description")
                    .onChange(of: eventDescription) { _, value in
                        if value.count > 750 { eventDescription = String(value.prefix(750)) }
                    }

                Text("\(eventDescription.count)/750")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } header: {
                Text("Guest Details")
            } footer: {
                Text("This information appears in the event invitation.")
            }

            if !isMainEvent {
                Section {
                    ForEach(workspace.members) { member in
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
                    Text("Participants")
                } footer: {
                    Text("New events start with everyone from the main event. Changes here only affect this event.")
                }
            }

            if isMainEvent && workspace.canDeleteMainEvent && !workspace.isMainEventDeleted {
                Section {
                    Button("Delete Event", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text("The main event can only be deleted while it is a draft.")
                }
            }
        }
        .navigationTitle(isCreating || workspace.isMainEventDeleted ? "New Event" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isCreating ? "Schedule" : "Save") { save() }
                    .disabled(
                        isMainEvent
                            ? trimmedTitle.isEmpty || !mainBudgetIsValid
                            : selectedParticipantIDs.isEmpty
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
        .sheet(item: $expenseEditorTarget) { target in
            NavigationStack {
                EventExpenseEditorView(
                    expense: target.expense,
                    eventID: expenseEventID,
                    onSave: upsertExpense
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .confirmationDialog("Delete this event?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                workspace.deleteMainEvent()
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
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private func expenseRow(_ expense: EventExpense) -> some View {
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

    private var scheduleSummary: String {
        let start = startsAt.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened)
        guard let endsAt else { return start }
        return "\(start) – \(endsAt.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened))"
    }

    private static let categoryOrder: [TimelineCategory] = [
        .other,
        .venue,
        .foodTasting,
        .attireFitting,
        .weddingShower,
        .bachelorBachelorette,
        .rehearsal,
        .ceremony,
        .reception
    ]

    private func editorRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol).foregroundStyle(AppTheme.ColorToken.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).foregroundStyle(value == "Add Location" ? AppTheme.ColorToken.accent : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private var categoryGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3),
            spacing: 8
        ) {
            ForEach(Self.categoryOrder) { option in
                eventTypeTile(option)
            }
        }
        .padding(2)
        .accessibilityLabel("Event types")
    }

    private func eventTypeTile(_ option: TimelineCategory) -> some View {
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
        let tiles = ForEach(EventPurpose.allCases) { option in
            selectionTile(
                title: option.title,
                symbol: option.symbol,
                tint: AppTheme.ColorToken.accent,
                isSelected: purpose == option,
                detail: option.description
            ) { purpose = option }
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { tiles }.padding(2)
        } else {
            HStack(spacing: 8) { tiles }.padding(2)
        }
    }

    private func selectionTile(
        title: String,
        symbol: String,
        tint: Color,
        isSelected: Bool,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            VStack(alignment: detail == nil ? .center : .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                if let detail {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: detail == nil ? 78 : 104, alignment: detail == nil ? .center : .leading)
            .padding(8)
            .background(isSelected ? tint.opacity(0.14) : AppTheme.ColorToken.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? tint : AppTheme.ColorToken.cardBorder, lineWidth: isSelected ? 2 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func loadMainEventIfNeeded() {
        guard !didLoadMain else { return }
        title = workspace.title
        mainStatus = workspace.mainEventStatus
        startsAt = workspace.weddingDate
        endsAt = workspace.mainEventEndsAt
        isAllDay = workspace.mainEventIsAllDay
        timeZoneIdentifier = workspace.mainEventTimeZoneIdentifier
        eventLocation = workspace.mainEventLocation
        imageData = workspace.mainEventImageData
        dressCode = workspace.dressCode
        eventDescription = workspace.eventMessage
        mainBudgetAmount = workspace.workspaceBudgetCap.map {
            NSDecimalNumber(decimal: $0).stringValue
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
            _ = workspace.updateWorkspaceBudgetCap(parsedMainBudget)
            workspace.updateMainEvent(
                title: trimmedTitle,
                status: mainStatus,
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier,
                eventLocation: eventLocation,
                imageData: imageData,
                dressCode: dressCode.trimmingCharacters(in: .whitespacesAndNewlines),
                message: eventDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else {
            let item = TimelineItem(
                id: draftEventID,
                title: resolvedTitle,
                category: category,
                purpose: purpose,
                scheduledAt: startsAt,
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
                dressCode: dressCode.trimmingCharacters(in: .whitespacesAndNewlines),
                budgetCap: usesBudget ? (originalItem?.budgetCap ?? .zero) : nil
            )
            if originalItem == nil { workspace.addTimelineItem(item) } else { workspace.updateTimelineItem(item) }
        }
        workspace.replaceExpenses(eventExpenses, forEventID: expenseEventID)
        dismiss()
    }

    private func upsertExpense(_ expense: EventExpense) {
        if let index = eventExpenses.firstIndex(where: { $0.id == expense.id }) {
            eventExpenses[index] = expense
        } else {
            eventExpenses.append(expense)
        }
    }

    private func deleteExpenses(at offsets: IndexSet) {
        eventExpenses.remove(atOffsets: offsets)
    }

    private func toggle(_ member: WeddingMember) {
        if selectedParticipantIDs.contains(member.id) {
            selectedParticipantIDs.remove(member.id)
        } else {
            selectedParticipantIDs.insert(member.id)
        }
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
        onSave: @escaping (EventExpense) -> Void
    ) {
        self.expense = expense
        self.eventID = eventID
        self.onSave = onSave
        _title = State(initialValue: expense?.title ?? "")
        _amount = State(
            initialValue: expense.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? ""
        )
        _category = State(initialValue: expense?.category ?? .other)
        _status = State(initialValue: expense?.status ?? .estimated)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAmount: Decimal? {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = amount
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized)
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

                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
            }

            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(EventExpenseCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $status) {
                    ForEach(EventExpenseStatus.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
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
