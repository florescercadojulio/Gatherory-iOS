import SwiftUI

/// Read-only projections for navigation. Selecting a tool never changes Home's
/// event selection or writes an archive/outbox mutation.
@MainActor
struct ManageEventSummary: Identifiable {
    let reference: EventReference
    let eventID: UUID
    let title: String
    let spent: Decimal
    let budget: Decimal?
    let goingCount: Int
    let awaitingRSVPCount: Int
    let collaboratorCount: Int
    let attendance: ManageAttendanceSummary
    let canManageInvitations: Bool
    let canSendNote: Bool

    var id: UUID { eventID }

    static func references(in workspace: PlanningWorkspace) -> [EventReference] {
        guard workspace.showsPlanningInterface else { return [] }
        let main: [EventReference] = workspace.isMainEventDeleted ? [] : [.main]
        guard !workspace.isScopedEvent else { return main }
        return main + workspace.childEvents.map { .subevent($0.id) }
    }

    init?(workspace: PlanningWorkspace, reference: EventReference) {
        guard Self.references(in: workspace).contains(reference) else { return nil }
        self.reference = reference
        switch reference {
        case .main: eventID = workspace.mainEventID
        case .subevent(let id): eventID = id
        case .idea: return nil
        }
        title = workspace.eventTitle(for: eventID)
        spent = workspace.costTotal(for: reference)
        budget = workspace.budgetCap(for: reference)
        let people = workspace.participants(for: reference)
        attendance = ManageAttendanceSummary(participants: people)
        goingCount = people.filter { $0.attendance == .going }.count
        awaitingRSVPCount = people.filter { $0.attendance == .invited }.count
        collaboratorCount = people.filter { $0.participantRole != .guest }.count
        canManageInvitations = workspace.canManageInvitations(for: reference)
        canSendNote = workspace.canSendNote(to: reference)
    }
}
private enum ManageDestination: Hashable {
    case budget(EventReference)
}

struct ManageView: View {
    var isActive = true
    var onExitWorkspace: (() -> Void)?
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var selection: EventReference = .main
    @State private var hasInitializedSelection = false
    @State private var successfulTakeHaptic = 0
    @State private var todoTakeFailed = false

    private var references: [EventReference] { ManageEventSummary.references(in: workspace) }
    private var reference: EventReference { references.contains(selection) ? selection : references.first ?? .main }
    private var summary: ManageEventSummary? { ManageEventSummary(workspace: workspace, reference: reference) }
    private var nextTodo: EventTodo? { workspace.nextTodo(for: reference) }
    private var todoTimeZone: TimeZone {
        let identifier: String
        if case .subevent(let id) = reference {
            identifier = workspace.timeline.first { $0.id == id }?.timeZoneIdentifier
                ?? workspace.mainEventTimeZoneIdentifier
        } else {
            identifier = workspace.mainEventTimeZoneIdentifier
        }
        return TimeZone(identifier: identifier) ?? .current
    }
    private var approvalMetric: ManageMetric {
        guard let summary, summary.canManageInvitations else {
            return ManageMetric(value: "—", label: String(localized: "Manager only"))
        }
        let store = workspace.joinRequestStore
        if store.error(eventID: summary.eventID, accountID: authentication.currentUser?.id) != nil {
            return ManageMetric(value: "—", label: String(localized: "Requests unavailable"))
        }
        return ManageMetric(
            value: store.requestCount(eventID: summary.eventID, accountID: authentication.currentUser?.id)?.formatted() ?? "—",
            label: String(localized: "Awaiting approval")
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.spacious) {
                if let summary {
                    ManageEventSelector(
                        events: references.compactMap { ManageEventSummary(workspace: workspace, reference: $0) },
                        selected: summary, selection: $selection
                    )

                    ManageDashboardLayout(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                                          layoutDirection: layoutDirection) {
                        NavigationLink(value: ManageDestination.budget(reference)) {
                            ManageBudgetCard(
                                spent: ManageMetric(value: summary.spent.formatted(.currency(code: workspace.currencyCode)), label: String(localized: "Spent")),
                                remaining: .remaining(spent: summary.spent, budget: summary.budget, currencyCode: workspace.currencyCode)
                            )
                        }
                        ManageGuestsCard(summary: summary)
                        ManageCollaboratorsCard(summary: summary, approval: approvalMetric)
                    }
                    if workspace.canReadTodos(for: reference) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            NavigationLink {
                                ManageTodosView(reference: reference)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label(TodoCopy.title, systemImage: "checklist")
                                            .font(.headline)
                                        Spacer()
                                        Image(systemName: "chevron.right").accessibilityHidden(true)
                                    }
                                    if let nextTodo {
                                        Divider().padding(.vertical, 4)
                                        Text(todoPreviewHeading(for: nextTodo))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        HStack(alignment: .top, spacing: 10) {
                                            if let assignee = workspace.todoAssignee(for: nextTodo) {
                                                ParticipantAvatarView(member: assignee, size: 32)
                                            }
                                            Text(nextTodo.title)
                                                .font(.body)
                                                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                                .lineLimit(2)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            if let dueDate = nextTodo.dueDate,
                                               let date = TodoDatePresentation.date(dueDate, timeZone: todoTimeZone) {
                                                Text(TodoCopy.due(TodoDatePresentation.display(date, timeZone: todoTimeZone)))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text(TodoCopy.previewEmpty)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if let nextTodo, workspace.canTakeTodo(id: nextTodo.id) {
                                Button {
                                    takeTodo(nextTodo.id)
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
                                .tint(AppTheme.ColorToken.accent)
                                .accessibilityLabel(TodoCopy.take)
                                .disabled(!workspace.canEditTodos(for: reference) || !library.workspaces.contains { $0 === workspace })
                            }
                        }
                        .padding(AppTheme.Spacing.spacious)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                    }
                    ManageNotesPreview(reference: reference)
                    if !workspace.visibleGuides(for: reference).isEmpty {
                        NavigationLink {
                            ExperienceGuidanceView(reference: reference)
                        } label: {
                            HStack {
                                Label("Planning Guide", systemImage: "book.closed")
                                Spacer()
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            .font(.headline)
                            .padding(AppTheme.Spacing.spacious)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                        }
                    }
                } else {
                    ContentUnavailableView("Manage", systemImage: "lock", description: Text("No planning event is available."))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .background(AppTheme.ColorToken.background)
        .appSoftScrollEdges()
        .navigationTitle(AppCopy.Tab.manage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) { WorkspaceLibraryToolbarButton(action: onExitWorkspace) }
            }
            ToolbarItem(placement: .topBarTrailing) { AccountToolbarButton() }
        }
        .navigationDestination(for: ManageDestination.self) { destination in
            switch destination {
            case .budget(let reference): BudgetView(reference: reference)
            }
        }
        .onAppear {
            if !hasInitializedSelection {
                selection = references.contains(workspace.selectedEventReference) ? workspace.selectedEventReference : references.first ?? .main
                hasInitializedSelection = true
            }
        }
        .onChange(of: references) { _, values in
            if !values.contains(selection) { selection = values.first ?? .main }
        }
        .task(id: "\(summary?.eventID.uuidString ?? "")|\(authentication.currentUser?.id ?? "")|\(summary?.canManageInvitations == true)|\(scenePhase)|\(isActive)") {
            await refreshRequests()
        }
        .refreshable { await refreshRequests(force: true) }
        .sensoryFeedback(.success, trigger: successfulTakeHaptic)
        .alert(TodoCopy.saveFailed, isPresented: $todoTakeFailed) {
            Button(AppCopy.Common.close, role: .cancel) {}
        } message: { Text(TodoCopy.saveFailedHelp) }
    }

    private func refreshRequests(force: Bool = false) async {
        guard isActive, scenePhase == .active, let summary, summary.canManageInvitations,
              let accountID = authentication.currentUser?.id else { return }
        await workspace.joinRequestStore.refresh(eventID: summary.eventID, accountID: accountID, force: force)
    }

    private func todoPreviewHeading(for todo: EventTodo) -> String {
        guard let viewerID = workspace.currentViewerMember(for: reference)?.id else { return TodoCopy.availableToTake }
        return todo.assigneePersonID == viewerID ? TodoCopy.yourNext : TodoCopy.availableToTake
    }

    private func takeTodo(_ id: UUID) {
        guard workspace.canEditTodos(for: reference), library.workspaces.contains(where: { $0 === workspace }),
              workspace.canTakeTodo(id: id) else { return }
        let previous = workspace.todos
        guard workspace.takeTodo(id: id) else { return }
        do {
            try persistence.saveChanges(in: library)
            successfulTakeHaptic &+= 1
        } catch {
            workspace.todos = previous
            todoTakeFailed = true
        }
    }
}

struct ManageMetric {
    let value: String
    let label: String
    var isWarning = false

    static func remaining(spent: Decimal, budget: Decimal?, currencyCode: String) -> Self {
        guard let budget else {
            return Self(value: "—", label: String(localized: "No budget set"))
        }
        let remaining = budget - spent
        return Self(
            value: abs(remaining).formatted(.currency(code: currencyCode)),
            label: remaining < .zero ? String(localized: "Over budget") : String(localized: "Remaining"),
            isWarning: remaining < .zero
        )
    }
}
