import SwiftUI

struct BudgetView: View {
    var reference: EventReference? = nil

    @Environment(PlanningWorkspace.self) private var workspace
    @State private var allocationTarget: BudgetAllocationTarget?

    private var projection: BudgetDestinationProjection {
        BudgetDestinationProjection.make(
            reference: reference,
            isScopedEvent: workspace.isScopedEvent,
            mainEventID: workspace.mainEventID,
            workspaceTitle: workspace.title,
            timeline: workspace.timeline,
            expenses: workspace.eventExpenses,
            workspaceBudgetCap: workspace.workspaceBudgetCap,
            mainEventBudgetCap: workspace.mainEventBudgetCap
        )
    }

    private var destinationAvailable: Bool {
        guard workspace.showsPlanningInterface else { return false }
        let availableReferences = ManageEventSummary.references(in: workspace)
        if let reference {
            return availableReferences.contains(reference)
        }
        return !workspace.isScopedEvent && availableReferences.contains(.main)
    }

    private var currencyCode: String {
        workspace.currencyCode
    }

    private var costSummaries: [EventCostSummary] {
        projection.costSummaries
    }

    private var recentExpenses: [EventExpense] {
        projection.expenses.sorted { $0.createdAt > $1.createdAt }
    }

    private var budgetSummaries: [EventBudgetSummary] {
        projection.budgetSummaries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                if !destinationAvailable || !projection.isValid {
                    ContentUnavailableView("Budget Unavailable", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                } else {
                    if !projection.isWorkspaceOverview {
                        Text(projection.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if projection.displayedBudgetCap == nil {
                        totalCard
                    } else {
                        budgetSignal
                    }

                    if projection.expenses.isEmpty {
                        ContentUnavailableView(
                            "No Costs Yet",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Add costs while editing an event to see the full picture here.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.section)
                    } else {
                        statusSummary
                        if projection.isWorkspaceOverview {
                            eventBreakdown
                        }
                    }

                    if projection.isWorkspaceOverview && projection.workspaceBudgetCap != nil {
                        budgetAllocation
                    }

                    if !projection.expenses.isEmpty {
                        costDetails
                    }

                    if !projection.isWorkspaceOverview && !workspace.isScopedEvent {
                        NavigationLink {
                            BudgetView(reference: nil)
                        } label: {
                            Label("Workspace Budget", systemImage: "chart.pie")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .appCard()
                    }
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle(projection.isWorkspaceOverview ? "Workspace Budget" : "Budget")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton()
            }
        }
        .sheet(item: $allocationTarget) { target in
            NavigationStack {
                BudgetAllocationView(target: target.reference)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Label("Total Spent", systemImage: "sum")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(projection.displayedSpent, format: .currency(code: currencyCode))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(background: AppTheme.ColorToken.surface, padding: AppTheme.Spacing.spacious)
        .accessibilityElement(children: .combine)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Spending Status")
                .font(AppTheme.Typography.sectionTitle)

            VStack(spacing: 0) {
                ForEach(EventExpenseStatus.allCases) { status in
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Label(status.title, systemImage: status.symbol)
                            .font(.body.weight(.medium))

                        Spacer(minLength: AppTheme.Spacing.compact)

                        Text(
                            projection.expenses
                                .filter { $0.status == status }
                                .reduce(Decimal.zero) { $0 + $1.amount },
                            format: .currency(code: currencyCode)
                        )
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    }
                    .frame(minHeight: 52)
                    .accessibilityElement(children: .combine)

                    if status != EventExpenseStatus.allCases.last {
                        Divider()
                    }
                }
            }
            .appCard(background: AppTheme.ColorToken.surface)
        }
    }

    private var budgetSignal: some View {
        let cap = projection.displayedBudgetCap ?? .zero
        let spent = projection.displayedSpent
        let remaining = cap - spent
        let isOverBudget = remaining < .zero
        let progress = cap > .zero
            ? NSDecimalNumber(decimal: spent / cap).doubleValue
            : 0

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Spent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(spent, format: .currency(code: currencyCode))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .monospacedDigit()

                Label(
                    isOverBudget ? "Over budget" : "Within budget",
                    systemImage: isOverBudget
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    isOverBudget
                        ? AppTheme.ColorToken.destructive
                        : AppTheme.ColorToken.success
                )
            }

            ProgressView(value: min(progress, 1))
                .tint(
                    isOverBudget
                        ? AppTheme.ColorToken.destructive
                        : AppTheme.ColorToken.accent
                )
                .accessibilityLabel("Budget used")
                .accessibilityValue("\(Int(progress * 100)) percent")

            HStack(spacing: 0) {
                budgetMetric(title: "Budget", amount: cap)

                Divider()
                    .padding(.horizontal, AppTheme.Spacing.standard)

                budgetMetric(
                    title: isOverBudget ? "Over" : "Remaining",
                    amount: abs(remaining),
                    valueColor: isOverBudget
                        ? AppTheme.ColorToken.destructive
                        : AppTheme.ColorToken.textPrimary
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .appCard(background: AppTheme.ColorToken.surface)
        .accessibilityElement(children: .contain)
    }

    private func budgetMetric(
        title: String,
        amount: Decimal,
        valueColor: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                amount,
                format: .currency(code: currencyCode).precision(.fractionLength(0))
            )
            .font(.headline)
            .foregroundStyle(valueColor)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budgetAllocation: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Budget Allocation")
                .font(AppTheme.Typography.sectionTitle)

            VStack(spacing: 0) {
                unallocatedBudgetRow

                Divider()

                ForEach(budgetSummaries) { summary in
                    let canEdit = BudgetAllocationPermissionPolicy.canEditAllocation(
                        in: workspace,
                        for: summary.reference
                    )
                    Button {
                        guard canEdit else { return }
                        allocationTarget = BudgetAllocationTarget(reference: summary.reference)
                    } label: {
                        budgetRow(summary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityHint("Opens budget allocation for this event")

                    if summary.id != budgetSummaries.last?.id {
                        Divider()
                    }
                }
            }
            .appCard(background: AppTheme.ColorToken.surface)

            if budgetSummaries.count == 1 {
                Text("Turn on “Uses a budget” while editing a sub-event to allocate part of this budget to it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unallocatedBudgetRow: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unallocated")
                    .font(.body.weight(.medium))
                Text("Available for any event")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    workspace.freeBudgetPool,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.body.weight(.semibold))
                .monospacedDigit()

                Text("available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    private func budgetRow(_ summary: EventBudgetSummary) -> some View {
        let remaining = summary.allocation - summary.spent
        let isOverBudget = remaining < .zero

        return HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: summary.symbol)
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(
                    isOverBudget
                        ? "\(abs(remaining).formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) over"
                        : "\(summary.spent.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) spent",
                    systemImage: isOverBudget ? "exclamationmark.circle.fill" : "banknote"
                )
                .font(.caption)
                .foregroundStyle(
                    isOverBudget
                        ? AppTheme.ColorToken.destructive
                        : AppTheme.ColorToken.textSecondary
                )
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    summary.allocation,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()

                Text("allocated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var eventBreakdown: some View {
        let largestAmount = max(costSummaries.map(\.doubleAmount).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Spending by Event")
                .font(AppTheme.Typography.sectionTitle)

            VStack(spacing: 0) {
                ForEach(costSummaries) { summary in
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        HStack(spacing: AppTheme.Spacing.standard) {
                            Image(systemName: summary.symbol)
                                .foregroundStyle(AppTheme.ColorToken.accent)
                                .frame(width: 28)

                            Text(summary.title)
                                .font(.body.weight(.medium))
                                .lineLimit(2)

                            Spacer(minLength: AppTheme.Spacing.compact)

                            Text(summary.amount, format: .currency(code: currencyCode))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        ProgressView(value: summary.doubleAmount, total: largestAmount)
                            .tint(
                                summary.isMainEvent
                                    ? AppTheme.ColorToken.accent
                                    : AppTheme.ColorToken.accent.opacity(0.55)
                            )
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if summary.id != costSummaries.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .appCard()
    }

    private var costDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Expenses")
                .font(AppTheme.Typography.sectionTitle)

            VStack(spacing: 0) {
                ForEach(recentExpenses) { expense in
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: expense.category.symbol)
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(expense.title)
                                .font(.body.weight(.medium))
                            Text("\(eventTitle(for: expense.eventID)) · \(expense.status.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: AppTheme.Spacing.compact)

                        Text(expense.amount, format: .currency(code: currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)

                    if expense.id != recentExpenses.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .appCard()
    }

    private func eventTitle(for eventID: UUID) -> String {
        projection.eventTitles[eventID] ?? "Event"
    }
}

struct EventCostSummary: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let amount: Decimal
    let isMainEvent: Bool

    var doubleAmount: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}

struct EventBudgetSummary: Identifiable {
    let reference: EventReference
    let title: String
    let symbol: String
    let allocation: Decimal
    let spent: Decimal
    let isMainEvent: Bool

    var id: String { reference.id }
}

/// A local, validated presentation projection for Budget destinations. It never
/// reads from sync or broad workspace totals; selected-event views are derived
/// only from records belonging to the exact event reference.
struct BudgetDestinationProjection {
    let isValid: Bool
    let isWorkspaceOverview: Bool
    let title: String
    let workspaceBudgetCap: Decimal?
    let displayedBudgetCap: Decimal?
    let displayedSpent: Decimal
    let expenses: [EventExpense]
    let costSummaries: [EventCostSummary]
    let budgetSummaries: [EventBudgetSummary]
    let eventTitles: [UUID: String]

    static func make(
        reference: EventReference?,
        isScopedEvent: Bool,
        mainEventID: UUID,
        workspaceTitle: String,
        timeline: [TimelineItem],
        expenses: [EventExpense],
        workspaceBudgetCap: Decimal?,
        mainEventBudgetCap: Decimal?
    ) -> BudgetDestinationProjection {
        let childEvents = timeline.sorted { $0.scheduledAt < $1.scheduledAt }
        var titles = [mainEventID: workspaceTitle]
        for event in childEvents {
            titles[event.id] = event.title
        }

        if reference == nil, !isScopedEvent {
            let costs = ([EventCostSummary(
                id: mainEventID,
                title: workspaceTitle,
                symbol: "heart.fill",
                amount: total(expenses, eventID: mainEventID),
                isMainEvent: true
            )] + childEvents.map { event in
                EventCostSummary(
                    id: event.id,
                    title: event.title,
                    symbol: event.category.symbol,
                    amount: total(expenses, eventID: event.id),
                    isMainEvent: false
                )
            }).filter { $0.amount > .zero }

            let budgets = [EventBudgetSummary(
                reference: .main,
                title: workspaceTitle,
                symbol: "heart.fill",
                allocation: mainEventBudgetCap ?? .zero,
                spent: total(expenses, eventID: mainEventID),
                isMainEvent: true
            )] + childEvents.compactMap { event -> EventBudgetSummary? in
                guard let allocation = event.budgetCap else { return nil }
                return EventBudgetSummary(
                    reference: .subevent(event.id),
                    title: event.title,
                    symbol: event.category.symbol,
                    allocation: allocation,
                    spent: total(expenses, eventID: event.id),
                    isMainEvent: false
                )
            }

            return BudgetDestinationProjection(
                isValid: true,
                isWorkspaceOverview: true,
                title: "Workspace Budget",
                workspaceBudgetCap: workspaceBudgetCap,
                displayedBudgetCap: workspaceBudgetCap,
                displayedSpent: expenses.reduce(.zero) { $0 + $1.amount },
                expenses: expenses,
                costSummaries: costs,
                budgetSummaries: budgets,
                eventTitles: titles
            )
        }

        // A scoped workspace's root is the selected child event. Reject child,
        // idea, missing, and unknown references so anomalous local records cannot
        // expand the view into sibling data.
        let selectedReference: EventReference
        if isScopedEvent {
            guard reference == .main else { return invalid }
            selectedReference = .main
        } else {
            guard let reference else { return invalid }
            switch reference {
            case .main:
                selectedReference = .main
            case .subevent(let id):
                guard childEvents.contains(where: { $0.id == id }) else { return invalid }
                selectedReference = .subevent(id)
            case .idea:
                return invalid
            }
        }

        let selectedID: UUID
        let selectedTitle: String
        let selectedSymbol: String
        let allocation: Decimal?
        let isMainEvent: Bool
        switch selectedReference {
        case .main:
            selectedID = mainEventID
            selectedTitle = workspaceTitle
            selectedSymbol = "heart.fill"
            allocation = mainEventBudgetCap
            isMainEvent = true
        case .subevent(let id):
            guard let event = childEvents.first(where: { $0.id == id }) else { return invalid }
            selectedID = id
            selectedTitle = event.title
            selectedSymbol = event.category.symbol
            allocation = event.budgetCap
            isMainEvent = false
        case .idea:
            return invalid
        }

        let selectedExpenses = expenses.filter { $0.eventID == selectedID }
        let spent = selectedExpenses.reduce(Decimal.zero) { $0 + $1.amount }
        let costs = spent > .zero ? [EventCostSummary(
            id: selectedID,
            title: selectedTitle,
            symbol: selectedSymbol,
            amount: spent,
            isMainEvent: isMainEvent
        )] : []
        let budgets = allocation.map { value in
            [EventBudgetSummary(
                reference: selectedReference,
                title: selectedTitle,
                symbol: selectedSymbol,
                allocation: value,
                spent: spent,
                isMainEvent: isMainEvent
            )]
        } ?? []

        return BudgetDestinationProjection(
            isValid: true,
            isWorkspaceOverview: false,
            title: selectedTitle,
            workspaceBudgetCap: nil,
            displayedBudgetCap: allocation,
            displayedSpent: spent,
            expenses: selectedExpenses,
            costSummaries: costs,
            budgetSummaries: budgets,
            eventTitles: [selectedID: selectedTitle]
        )
    }

    private static var invalid: BudgetDestinationProjection {
        BudgetDestinationProjection(
            isValid: false,
            isWorkspaceOverview: false,
            title: "",
            workspaceBudgetCap: nil,
            displayedBudgetCap: nil,
            displayedSpent: .zero,
            expenses: [],
            costSummaries: [],
            budgetSummaries: [],
            eventTitles: [:]
        )
    }

    private static func total(_ expenses: [EventExpense], eventID: UUID) -> Decimal {
        expenses.filter { $0.eventID == eventID }.reduce(.zero) { $0 + $1.amount }
    }
}

/// Allocation editing requires management permission on both the workspace
/// root and the exact target event. Scoped event workspaces never transfer
/// funds because their projection does not include the workspace accounts.
@MainActor
enum BudgetAllocationPermissionPolicy {
    static func canEditAllocation(
        in workspace: PlanningWorkspace,
        for target: EventReference
    ) -> Bool {
        guard !workspace.isScopedEvent,
              ManageEventSummary.references(in: workspace).contains(.main),
              workspace.canManageInvitations(for: .main),
              workspace.canManageInvitations(for: target),
              ManageEventSummary.references(in: workspace).contains(target) else {
            return false
        }

        return switch target {
        case .main, .subevent:
            true
        case .idea:
            false
        }
    }
}

private struct BudgetAllocationTarget: Identifiable {
    let reference: EventReference

    var id: String { reference.id }
}
