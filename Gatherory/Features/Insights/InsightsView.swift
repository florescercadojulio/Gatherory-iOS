import Charts
import SwiftUI

struct InsightsView: View {
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var allocationTarget: BudgetAllocationTarget?

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
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
                totalCard

                if workspace.workspaceBudgetCap != nil {
                    budgetSignal
                    budgetAllocation
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
            ToolbarItem(placement: .principal) {
                EventContextLabel(section: "Insights", eventTitle: workspace.title)
            }

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
            Label("Total Event Cost", systemImage: "sum")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(workspace.workspaceCostTotal, format: .currency(code: currencyCode))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .monospacedDigit()

            Text("Across the main event and every sub-event")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(background: AppTheme.ColorToken.surface, padding: AppTheme.Spacing.spacious)
        .accessibilityElement(children: .combine)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Cost Status")
                .font(AppTheme.Typography.sectionTitle)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
                ),
                spacing: AppTheme.Spacing.compact
            ) {
                ForEach(EventExpenseStatus.allCases) { status in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(status.title, systemImage: status.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(
                            workspace.costTotal(status: status),
                            format: .currency(code: currencyCode).precision(.fractionLength(0))
                        )
                        .font(.headline)
                        .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                    .appCard(
                        background: AppTheme.ColorToken.elevatedSurface,
                        padding: AppTheme.Spacing.compact
                    )
                    .accessibilityElement(children: .combine)
                }
            }
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
            HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isOverBudget ? "Over Budget" : "Budget Remaining",
                        systemImage: isOverBudget
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOverBudget ? Color.red : Color.green)

                    Text(
                        abs(remaining),
                        format: .currency(code: currencyCode).precision(.fractionLength(0))
                    )
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()

                    if isOverBudget {
                        Text("above the workspace cap")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: AppTheme.Spacing.standard)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cap, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                        .font(.headline)
                        .monospacedDigit()
                }
            }

            ProgressView(value: min(progress, 1))
                .tint(isOverBudget ? .red : AppTheme.ColorToken.accent)
                .accessibilityLabel("Budget used")
                .accessibilityValue("\(Int(progress * 100)) percent")

            Text("\(workspace.workspaceCostTotal.formatted(.currency(code: currencyCode))) spent across all events")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .appCard(background: AppTheme.ColorToken.surface)
        .accessibilityElement(children: .contain)
    }

    private var budgetAllocation: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Budget Allocation")
                    .font(AppTheme.Typography.sectionTitle)
                Text("Tap an event to add or subtract budget.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Pool")
                        .font(.subheadline.weight(.semibold))
                    Text("Ready to allocate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.Spacing.compact)

                Text(
                    workspace.freeBudgetPool,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.headline)
                .monospacedDigit()
            }
            .appCard(background: AppTheme.ColorToken.surface)
            .accessibilityElement(children: .combine)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                ),
                spacing: AppTheme.Spacing.compact
            ) {
                ForEach(budgetSummaries) { summary in
                    Button {
                        allocationTarget = BudgetAllocationTarget(reference: summary.reference)
                    } label: {
                        budgetTile(summary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens budget allocation for this event")
                }
            }

            if budgetSummaries.count == 1 {
                Text("Turn on “Uses a budget” while editing a sub-event to allocate part of this budget to it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func budgetTile(_ summary: EventBudgetSummary) -> some View {
        let remaining = summary.allocation - summary.spent
        let isOverBudget = remaining < .zero

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
                Image(systemName: summary.symbol)
                    .foregroundStyle(
                        summary.isMainEvent
                            ? AppTheme.ColorToken.accent
                            : AppTheme.ColorToken.textSecondary
                    )
                    .frame(width: 24)

                Text(summary.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
            }

            Text(
                summary.allocation,
                format: .currency(code: currencyCode).precision(.fractionLength(0))
            )
            .font(.title3.weight(.bold))
            .foregroundStyle(.primary)
            .monospacedDigit()

            Text("Allocated")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Label(
                isOverBudget
                    ? "\(abs(remaining).formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) over"
                    : "\(remaining.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) left",
                systemImage: isOverBudget ? "exclamationmark.circle.fill" : "circle.dashed"
            )
            .font(.caption)
            .foregroundStyle(isOverBudget ? Color.red : AppTheme.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .appCard(background: AppTheme.ColorToken.elevatedSurface)
        .accessibilityElement(children: .combine)
    }

    private var eventBreakdown: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 3) {
                Text("By Event")
                    .font(AppTheme.Typography.sectionTitle)
                Text("Where the event total is accumulating")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart(costSummaries) { summary in
                BarMark(
                    x: .value("Cost", summary.doubleAmount),
                    y: .value("Event", summary.title)
                )
                .foregroundStyle(
                    summary.isMainEvent
                        ? AppTheme.ColorToken.accent
                        : AppTheme.ColorToken.accent.opacity(0.55)
                )
                .cornerRadius(6)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let eventTitle = value.as(String.self) {
                            Text(eventTitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(height: max(CGFloat(costSummaries.count) * 48, 120))
            .accessibilityLabel("Cost by event")
            .accessibilityValue(
                costSummaries
                    .map { "\($0.title), \($0.amount.formatted(.currency(code: currencyCode)))" }
                    .joined(separator: "; ")
            )

            VStack(spacing: 0) {
                ForEach(costSummaries) { summary in
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: summary.symbol)
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        Text(summary.title)
                            .lineLimit(2)

                        Spacer(minLength: AppTheme.Spacing.compact)

                        Text(summary.amount, format: .currency(code: currencyCode))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .frame(minHeight: 52)
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
            Text("Cost Details")
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
