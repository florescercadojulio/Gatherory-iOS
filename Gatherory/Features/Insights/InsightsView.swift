import SwiftUI

struct InsightsView: View {
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @State private var allocationTarget: BudgetAllocationTarget?

    private var currencyCode: String {
        workspace.currencyCode
    }

    private var costSummaries: [EventCostSummary] {
        let main = EventCostSummary(
            id: workspace.mainEventID,
            title: workspace.title,
            symbol: "heart.fill",
            amount: workspace.costTotal(for: .main),
            isMainEvent: true
        )

        let childEvents = workspace.timeline
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .map { event in
                EventCostSummary(
                    id: event.id,
                    title: event.title,
                    symbol: event.category.symbol,
                    amount: workspace.costTotal(for: .subevent(event.id)),
                    isMainEvent: false
                )
            }

        return ([main] + childEvents).filter { $0.amount > .zero }
    }

    private var recentExpenses: [EventExpense] {
        workspace.eventExpenses.sorted { $0.createdAt > $1.createdAt }
    }

    private var budgetSummaries: [EventBudgetSummary] {
        let main = EventBudgetSummary(
            reference: .main,
            title: workspace.title,
            symbol: "heart.fill",
            allocation: workspace.mainEventBudgetCap ?? .zero,
            spent: workspace.costTotal(for: .main),
            isMainEvent: true
        )

        let children = workspace.childEvents.compactMap { event -> EventBudgetSummary? in
            guard let allocation = event.budgetCap else { return nil }
            return EventBudgetSummary(
                reference: .subevent(event.id),
                title: event.title,
                symbol: event.category.symbol,
                allocation: allocation,
                spent: workspace.costTotal(for: .subevent(event.id)),
                isMainEvent: false
            )
        }

        return [main] + children
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                if workspace.workspaceBudgetCap == nil {
                    totalCard
                } else {
                    budgetSignal
                }

                if workspace.eventExpenses.isEmpty {
                    ContentUnavailableView(
                        "No Costs Yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Add costs while editing an event to see the full picture here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.section)
                } else {
                    statusSummary
                    eventBreakdown
                }

                if workspace.workspaceBudgetCap != nil {
                    budgetAllocation
                }

                if !workspace.eventExpenses.isEmpty {
                    costDetails
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }
            }

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

            Text(workspace.workspaceCostTotal, format: .currency(code: currencyCode))
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
                            workspace.costTotal(status: status),
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
        let cap = workspace.workspaceBudgetCap ?? .zero
        let remaining = cap - workspace.workspaceCostTotal
        let isOverBudget = remaining < .zero
        let progress = cap > .zero
            ? NSDecimalNumber(decimal: workspace.workspaceCostTotal / cap).doubleValue
            : 0

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Spent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(workspace.workspaceCostTotal, format: .currency(code: currencyCode))
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
                    Button {
                        allocationTarget = BudgetAllocationTarget(reference: summary.reference)
                    } label: {
                        budgetRow(summary)
                    }
                    .buttonStyle(.plain)
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
        if eventID == workspace.mainEventID {
            return workspace.title
        }
        return workspace.timeline.first(where: { $0.id == eventID })?.title ?? "Event"
    }
}

private struct EventCostSummary: Identifiable {
    let id: UUID
    let title: String
    let symbol: String
    let amount: Decimal
    let isMainEvent: Bool

    var doubleAmount: Double {
        NSDecimalNumber(decimal: amount).doubleValue
    }
}

private struct EventBudgetSummary: Identifiable {
    let reference: EventReference
    let title: String
    let symbol: String
    let allocation: Decimal
    let spent: Decimal
    let isMainEvent: Bool

    var id: String { reference.id }
}

private struct BudgetAllocationTarget: Identifiable {
    let reference: EventReference

    var id: String { reference.id }
}
