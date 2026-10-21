import PostHog
import SwiftUI

private struct TodoEditorSelection: Identifiable {
    let id = UUID()
    let todo: EventTodo?
}

private enum TodoListFilter: String, CaseIterable, Identifiable {
    case upcoming
    case completed
    var id: String { rawValue }
}

/// This tool holds its event reference instead of changing Home's selection.
struct ManageTodosView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.currentUserAccount) private var account
    let reference: EventReference
    @State private var editor: TodoEditorSelection?
    @State private var listFilter: TodoListFilter = .upcoming
    @State private var saveFailed = false
    @State private var successfulMutationHaptic = 0
    @State private var selectionHaptic = 0

    private var items: [EventTodo] { workspace.todos(for: reference) }
    private var visibleItems: [EventTodo] {
        items.filter { $0.isCompleted == (listFilter == .completed) }
    }
    private var canEdit: Bool {
        workspace.canEditTodos(for: reference) && library.workspaces.contains { $0 === workspace }
    }
    private var eventTitle: String { ManageEventSummary(workspace: workspace, reference: reference)?.title ?? "" }
    private var timeZone: TimeZone {
        let identifier: String
        if case .subevent(let id) = reference {
            identifier = workspace.timeline.first { $0.id == id }?.timeZoneIdentifier ?? workspace.mainEventTimeZoneIdentifier
        } else {
            identifier = workspace.mainEventTimeZoneIdentifier
        }
        return TimeZone(identifier: identifier) ?? .current
    }

    var body: some View {
        Group {
            if workspace.canReadTodos(for: reference) {
                VStack(spacing: AppTheme.Spacing.compact) {
                    Text(eventTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                        .padding(.top, AppTheme.Spacing.compact)
                    Picker(TodoCopy.listFilter, selection: $listFilter) {
                        Text(TodoCopy.upcoming).tag(TodoListFilter.upcoming)
                        Text(TodoCopy.completed).tag(TodoListFilter.completed)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(TodoCopy.listFilter)
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)

                    List {
                        Section {
                            if visibleItems.isEmpty {
                                if listFilter == .upcoming {
                                    ContentUnavailableView(TodoCopy.upcomingEmpty, systemImage: "checklist",
                                        description: Text(items.isEmpty
                                            ? (canEdit ? TodoCopy.emptyHelp : TodoCopy.emptyReadOnly)
                                            : TodoCopy.upcomingEmptyHelp))
                                } else {
                                    ContentUnavailableView(TodoCopy.completedEmpty, systemImage: "checkmark.circle")
                                }
                            }
                            ForEach(visibleItems) { row($0) }
                        }
                        .listRowBackground(AppTheme.ColorToken.surface)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.ColorToken.background)
                    .refreshable { await cloudSync.synchronize(trigger: .manual) }
                }
                .background(AppTheme.ColorToken.background)
            } else {
                ContentUnavailableView(TodoCopy.unavailable, systemImage: "lock",
                    description: Text(TodoCopy.unavailableHelp))
            }
        }
        .navigationTitle(TodoCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(TodoCopy.add, systemImage: "plus") { editor = TodoEditorSelection(todo: nil) }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .sheet(item: $editor) { selection in
            TodoEditorView(todo: selection.todo, timeZone: timeZone, destinationTitle: eventTitle, canEdit: canEdit,
                eligibleAssignees: workspace.eligibleTodoAssignees(for: reference),
                assigneeName: { todo in
                    guard todo.assigneePersonID != nil else { return TodoCopy.unassigned }
                    return workspace.todoAssigneeName(for: todo) ?? TodoCopy.assigneeUnavailable
                },
                onSave: { title, dueDate, websiteURL, assigneePersonID in
                    let didSave = persist {
                        if let todo = selection.todo {
                            return workspace.updateTodo(
                                id: todo.id, title: title, dueDate: dueDate,
                                websiteURL: websiteURL, assigneePersonID: assigneePersonID
                            )
                        }
                        return workspace.addTodo(
                            title: title, dueDate: dueDate, websiteURL: websiteURL,
                            assigneePersonID: assigneePersonID, to: reference
                        ) != nil
                    }
                    if didSave {
                        PostHogSDK.shared.capture(
                            selection.todo == nil ? "todo_created" : "todo_updated",
                            properties: [
                                "has_due_date": dueDate != nil,
                                "is_assigned": assigneePersonID != nil
                            ]
                        )
                        if selection.todo == nil { listFilter = .upcoming }
                    }
                    return didSave
                },
                onDelete: {
                    guard let todo = selection.todo else { return false }
                    let didDelete = persist({ workspace.deleteTodo(id: todo.id) }, feedback: .selection)
                    if didDelete { PostHogSDK.shared.capture("todo_deleted") }
                    return didDelete
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: account?.id) { _, _ in
            editor = nil
            listFilter = .upcoming
        }
        .onChange(of: canEdit) { _, allowed in if !allowed { editor = nil } }
        .sensoryFeedback(.success, trigger: successfulMutationHaptic)
        .sensoryFeedback(.selection, trigger: selectionHaptic)
        .alert(TodoCopy.saveFailed, isPresented: $saveFailed) {
            Button(AppCopy.Common.close, role: .cancel) {}
        } message: { Text(TodoCopy.saveFailedHelp) }
    }

    private func row(_ todo: EventTodo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    let isUndo = todo.isCompleted
                    let didPersist = persist(
                        { workspace.setTodoCompleted(id: todo.id, isCompleted: !isUndo) },
                        feedback: isUndo ? .selection : .success
                    )
                    if didPersist, !isUndo {
                        PostHogSDK.shared.capture("todo_completed")
                    } else if !didPersist {
                        saveFailed = true
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(todo.isCompleted ? Color.secondary : AppTheme.ColorToken.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!canEdit)
                .accessibilityLabel((todo.isCompleted ? TodoCopy.markIncomplete : TodoCopy.markComplete) + ": " + todo.title)
                .accessibilityValue(todo.isCompleted ? TodoCopy.completed : "")

                VStack(alignment: .leading, spacing: 2) {
                    Button { editor = TodoEditorSelection(todo: todo) } label: {
                        HStack(spacing: 8) {
                            Text(todo.title)
                                .foregroundStyle(todo.isCompleted ? Color.secondary : AppTheme.ColorToken.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if !todo.isCompleted {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    if let dueDate = todo.dueDate,
                       let date = TodoDatePresentation.date(dueDate, timeZone: timeZone) {
                        Text(TodoCopy.due(TodoDatePresentation.display(date, timeZone: timeZone)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if todo.assigneePersonID != nil {
                        let member = workspace.todoAssignee(for: todo)
                        let name = member?.name ?? TodoCopy.assigneeUnavailable
                        HStack(spacing: 6) {
                            if let member { ParticipantAvatarView(member: member, size: 24) }
                            Text(TodoCopy.assignedTo(name))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            let website = safeWebsiteURL(todo.websiteURL)
            let canTake = !todo.isCompleted && canEdit && workspace.canTakeTodo(id: todo.id)
            if canTake || website != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        if canTake { todoTakeButton(todo) }
                        if let website { websiteLink(website) }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if canTake { todoTakeButton(todo) }
                        if let website { websiteLink(website) }
                    }
                }
                .padding(.leading, 54)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(AppTheme.ColorToken.surface)
    }

    @ViewBuilder
    private func todoTakeButton(_ todo: EventTodo) -> some View {
        Button {
            if !persist({ workspace.takeTodo(id: todo.id) }) { saveFailed = true }
        } label: {
            Label {
                Text(TodoCopy.takeShort)
            } icon: {
                if let viewer = workspace.currentViewerMember(for: reference) {
                    ParticipantAvatarView(member: viewer, size: 22)
                } else {
                    Image(systemName: "person.badge.plus")
                }
            }
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(TodoCopy.take)
    }

    private func websiteLink(_ url: URL) -> some View {
        Link(destination: url) {
            Label(TodoCopy.openWebsite, systemImage: "arrow.up.right.square")
                .font(.subheadline)
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func safeWebsiteURL(_ rawValue: String?) -> URL? {
        guard let normalized = EventTodo.normalizedWebsiteURL(rawValue),
              EventTodo.isValidWebsiteURL(normalized),
              let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }

    /// Match other local editors: save the archive and outbox together, rolling
    /// the observable model back if durable persistence fails.
    private enum TodoFeedback { case success, selection }

    private func persist(_ mutation: () -> Bool, feedback: TodoFeedback = .success) -> Bool {
        guard canEdit else { return false }
        let previous = workspace.todos
        guard mutation() else { return false }
        do {
            try persistence.saveChanges(in: library)
            switch feedback {
            case .success: successfulMutationHaptic &+= 1
            case .selection: selectionHaptic &+= 1
            }
            return true
        } catch {
            workspace.todos = previous
            return false
        }
    }
}

private struct TodoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanningWorkspace.self) private var workspace
    let todo: EventTodo?
    let timeZone: TimeZone
    let destinationTitle: String
    let canEdit: Bool
    let eligibleAssignees: [WorkspaceMember]
    let assigneeName: (EventTodo) -> String
    let onSave: (String, String?, String?, UUID?) -> Bool
    let onDelete: () -> Bool
    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var websiteURL: String
    @State private var assigneePersonID: UUID?
    @State private var showsDatePicker = false
    @State private var saveFailed = false
    @State private var confirmsDeletion = false
    @State private var itemChanged = false
    @FocusState private var isFocused: Bool

    init(todo: EventTodo?, timeZone: TimeZone, destinationTitle: String, canEdit: Bool,
         eligibleAssignees: [WorkspaceMember], assigneeName: @escaping (EventTodo) -> String,
         onSave: @escaping (String, String?, String?, UUID?) -> Bool,
         onDelete: @escaping () -> Bool) {
        self.todo = todo
        self.timeZone = timeZone
        self.destinationTitle = destinationTitle
        self.canEdit = canEdit
        self.eligibleAssignees = eligibleAssignees
        self.assigneeName = assigneeName
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: todo?.title ?? "")
        _hasDueDate = State(initialValue: todo?.dueDate != nil)
        _dueDate = State(initialValue: todo?.dueDate.flatMap { TodoDatePresentation.date($0, timeZone: timeZone) } ?? Date())
        _websiteURL = State(initialValue: todo?.websiteURL ?? "")
        _assigneePersonID = State(initialValue: todo?.assigneePersonID)
    }

    private var normalizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validTitle: Bool { EventTodo.normalizedTitle(title) != nil }
    private var validWebsiteURL: Bool { EventTodo.isValidWebsiteURL(websiteURL) }

    var body: some View {
        NavigationStack {
            Form {
                Section(todo == nil ? TodoCopy.addingTo : TodoCopy.event) {
                    Label(destinationTitle, systemImage: "calendar")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ColorToken.textPrimary)
                        .frame(minHeight: AppTheme.Layout.minimumTouchTarget, alignment: .leading)
                        .accessibilityLabel(
                            todo == nil
                                ? TodoCopy.addingTodoTo(destinationTitle)
                                : "\(TodoCopy.event): \(destinationTitle)"
                        )
                }
                .listRowBackground(AppTheme.ColorToken.surface)
                Section(TodoCopy.taskSection) {
                    TextField(TodoCopy.name, text: $title, axis: .vertical)
                        .focused($isFocused)
                        .textInputAutocapitalization(.sentences)
                    if normalizedTitle.unicodeScalars.count > 200 {
                        Text(TodoCopy.invalidTitle).font(.footnote).foregroundStyle(.red)
                    }
                }
                .listRowBackground(AppTheme.ColorToken.surface)
                Section(TodoCopy.dueDate) {
                    Button { showsDatePicker = true } label: {
                        HStack {
                            Text(hasDueDate ? TodoCopy.changeDueDate : TodoCopy.addDueDate)
                            Spacer()
                            if hasDueDate {
                                Text(TodoDatePresentation.display(dueDate, timeZone: timeZone))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!canEdit)
                }
                .listRowBackground(AppTheme.ColorToken.surface)
                Section(TodoCopy.assignee) {
                    Picker(TodoCopy.assignee, selection: $assigneePersonID) {
                        Text(TodoCopy.unassigned).tag(Optional<UUID>.none)
                        if let currentID = todo?.assigneePersonID,
                           !eligibleAssignees.contains(where: { $0.id == currentID }),
                           let todo {
                            Text(assigneeName(todo)).tag(Optional(currentID))
                        }
                        ForEach(eligibleAssignees) { member in
                            HStack(spacing: 8) {
                                ParticipantAvatarView(member: member, size: 24)
                                Text(member.name)
                            }
                            .tag(Optional(member.id))
                        }
                    }
                    .disabled(!canEdit)
                }
                .listRowBackground(AppTheme.ColorToken.surface)
                Section(TodoCopy.website) {
                    TextField(TodoCopy.websitePlaceholder, text: $websiteURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !validWebsiteURL {
                        Text(TodoCopy.invalidWebsite).font(.footnote).foregroundStyle(.red)
                    }
                    if let url = safeWebsiteURL(websiteURL) {
                        Link(TodoCopy.openWebsite, destination: url)
                    }
                }
                .listRowBackground(AppTheme.ColorToken.surface)
                if todo != nil {
                    Section {
                        Button(TodoCopy.delete, role: .destructive) { confirmsDeletion = true }
                    }
                    .listRowBackground(AppTheme.ColorToken.surface)
                }
            }
            .disabled(!canEdit)
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle(todo == nil ? TodoCopy.newTitle : TodoCopy.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(todo == nil ? AppCopy.Common.add : AppCopy.Common.save) {
                        if let todo, workspace.todos.first(where: { $0.id == todo.id }) != todo {
                            itemChanged = true
                            return
                        }
                        if onSave(
                            normalizedTitle,
                            hasDueDate ? TodoDatePresentation.iso(dueDate, timeZone: timeZone) : nil,
                            websiteURL,
                            assigneePersonID
                        ) {
                            dismiss()
                        } else { saveFailed = true }
                    }
                    .disabled(!canEdit || !validTitle || !validWebsiteURL)
                }
            }
            .onAppear { isFocused = todo == nil }
            .sheet(isPresented: $showsDatePicker) {
                TodoDueDatePicker(
                    initialDate: hasDueDate ? dueDate : Date(),
                    timeZone: timeZone,
                    canRemove: hasDueDate,
                    onDone: { selectedDate in
                        dueDate = selectedDate
                        hasDueDate = true
                        showsDatePicker = false
                    },
                    onRemove: {
                        hasDueDate = false
                        showsDatePicker = false
                    }
                )
            }
            .confirmationDialog(TodoCopy.confirmDelete, isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button(TodoCopy.delete, role: .destructive) {
                    guard let todo,
                          workspace.todos.first(where: { $0.id == todo.id }) == todo else {
                        itemChanged = true
                        return
                    }
                    if onDelete() { dismiss() } else { saveFailed = true }
                }
                Button(AppCopy.Common.cancel, role: .cancel) {}
            } message: { Text(TodoCopy.deleteHelp) }
            .alert(TodoCopy.saveFailed, isPresented: $saveFailed) {
                Button(AppCopy.Common.close, role: .cancel) {}
            } message: { Text(TodoCopy.saveFailedHelp) }
            .alert(TodoCopy.itemChangedTitle, isPresented: $itemChanged) {
                Button(AppCopy.Common.close, role: .cancel) {}
            } message: { Text(TodoCopy.itemChangedHelp) }
        }
    }

    private func safeWebsiteURL(_ rawValue: String) -> URL? {
        guard let normalized = EventTodo.normalizedWebsiteURL(rawValue),
              EventTodo.isValidWebsiteURL(normalized),
              let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              components.user == nil, components.password == nil,
              let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }
}

private struct TodoDueDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date
    let timeZone: TimeZone
    let canRemove: Bool
    let onDone: (Date) -> Void
    let onRemove: () -> Void

    init(initialDate: Date, timeZone: TimeZone, canRemove: Bool,
         onDone: @escaping (Date) -> Void, onRemove: @escaping () -> Void) {
        _selection = State(initialValue: initialDate)
        self.timeZone = timeZone
        self.canRemove = canRemove
        self.onDone = onDone
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(TodoCopy.dueDate, selection: $selection, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.timeZone, timeZone)
                    if canRemove {
                        Button(TodoCopy.removeDueDate) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
                .listRowBackground(AppTheme.ColorToken.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.ColorToken.background)
            .navigationTitle(TodoCopy.dueDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(TodoCopy.done) {
                        onDone(selection)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

enum TodoDatePresentation {
    static func date(_ value: String, timeZone: TimeZone) -> Date? {
        let formatter = isoFormatter(timeZone)
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
    static func iso(_ date: Date, timeZone: TimeZone) -> String { isoFormatter(timeZone).string(from: date) }
    static func display(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    private static func isoFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
