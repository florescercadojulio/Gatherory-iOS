import SwiftUI

/// A target-first budget editor. Add mode chooses where money comes from;
/// subtract mode chooses where the selected event's money should go.
struct BudgetAllocationView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let target: EventReference

    @State private var mode: BudgetAdjustmentMode = .add
    @State private var transferAmount = "100"
    @State private var feedback: BudgetTransferFeedback?
    @State private var completedTransferCount = 0

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var parsedTransferAmount: Decimal? {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = transferAmount
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalized), amount > .zero else { return nil }
        return amount
    }

    private var transferOptions: [BudgetAccount] {
        let eventReferences: [EventReference] = [.main] + workspace.childEvents.compactMap { event in
            event.budgetCap == nil ? nil : .subevent(event.id)
        }
        let eventAccounts = eventReferences
            .filter { $0 != target }
            .map(BudgetAccount.event)

        return [.freePool] + eventAccounts
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                workspaceSummary
                targetCard
                modePicker
                transferAmountControl
                transferOptionsSection
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.vertical, AppTheme.Layout.screenTop)
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Edit Budget")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sensoryFeedback(.success, trigger: completedTransferCount)
        .onChange(of: mode) { _, _ in feedback = nil }
    }

    private var workspaceSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.standard) {
            summaryValue(
                title: "Workspace Budget",
                value: workspace.workspaceBudgetCap ?? .zero,
                alignment: .leading
            )

            Spacer(minLength: AppTheme.Spacing.standard)

            summaryValue(
                title: "Free Pool",
                value: workspace.freeBudgetPool,
                alignment: .trailing
            )
        }
        .appCard(background: AppTheme.ColorToken.surface)
        .accessibilityElement(children: .combine)
    }

    private func summaryValue(
        title: String,
        value: Decimal,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode).precision(.fractionLength(0)))
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Label("Editing Allocation", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)

            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: symbol(for: target))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.ColorToken.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: target))
                        .font(.headline)
                        .lineLimit(2)
                    Text("Current allocation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.Spacing.compact)

                Text(
                    workspace.budgetCap(for: target) ?? .zero,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.headline)
                .monospacedDigit()
            }
        }
        .appCard(background: AppTheme.ColorToken.elevatedSurface)
        .accessibilityElement(children: .combine)
    }

    private var modePicker: some View {
        Picker("Adjustment", selection: $mode) {
            ForEach(BudgetAdjustmentMode.allCases) { option in
                Label(option.title, systemImage: option.symbol)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Choose whether to add to or subtract from this event's budget")
    }

    private var transferAmountControl: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Amount")
                .font(AppTheme.Typography.sectionTitle)

            HStack(spacing: AppTheme.Spacing.compact) {
                Button("Decrease", systemImage: "minus") {
                    adjustTransferAmount(by: -50)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.large)

                TextField("Amount", text: $transferAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                    .background(AppTheme.ColorToken.elevatedSurface, in: Capsule())
                    .accessibilityLabel("Transfer amount")

                Button("Increase", systemImage: "plus") {
                    adjustTransferAmount(by: 50)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let feedback {
                Label(
                    feedback.message,
                    systemImage: feedback.isError
                        ? "exclamationmark.circle"
                        : "checkmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(
                    feedback.isError ? Color.red : AppTheme.ColorToken.textSecondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transferOptionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(mode == .add ? "Take From" : "Send To")
                .font(AppTheme.Typography.sectionTitle)
            Text(instructionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.compact) {
                ForEach(transferOptions, id: \.self) { account in
                    accountTile(account)
                }
            }
        }
    }

    private var instructionText: String {
        switch mode {
        case .add:
            "Tap the free pool or another event to fund \(title(for: target))."
        case .subtract:
            "Tap where the budget removed from \(title(for: target)) should go."
        }
    }

    private func accountTile(_ account: BudgetAccount) -> some View {
        Button {
            performTransfer(with: account)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title(for: account), systemImage: symbol(for: account))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(
                    workspace.budgetBalance(for: account) ?? .zero,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()

                Text(mode == .add ? "Available" : "Current allocation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .appCard(background: AppTheme.ColorToken.elevatedSurface)
        }
        .buttonStyle(.plain)
        .disabled(!canTransfer(with: account))
        .accessibilityHint(accessibilityHint(for: account))
    }

    private func canTransfer(with account: BudgetAccount) -> Bool {
        guard let amount = parsedTransferAmount else { return false }
        switch mode {
        case .add:
            return (workspace.budgetBalance(for: account) ?? .zero) >= amount
        case .subtract:
            return (workspace.budgetCap(for: target) ?? .zero) >= amount
        }
    }

    private func accessibilityHint(for account: BudgetAccount) -> String {
        switch mode {
        case .add:
            "Moves the entered amount from \(title(for: account)) into this event"
        case .subtract:
            "Moves the entered amount from this event into \(title(for: account))"
        }
    }

    private func adjustTransferAmount(by change: Decimal) {
        let current = parsedTransferAmount ?? .zero
        let updated = max(Decimal(50), current + change)
        transferAmount = NSDecimalNumber(decimal: updated).stringValue
        feedback = nil
    }

    private func performTransfer(with account: BudgetAccount) {
        guard let amount = parsedTransferAmount else {
            feedback = BudgetTransferFeedback(
                message: "Enter an amount greater than zero.",
                isError: true
            )
            return
        }

        let source: BudgetAccount = mode == .add ? account : .event(target)
        let destination: BudgetAccount = mode == .add ? .event(target) : account

        guard workspace.transferBudget(amount, from: source, to: destination) else {
            let available = workspace.budgetBalance(for: source) ?? .zero
            feedback = BudgetTransferFeedback(
                message: "Only \(available.formatted(.currency(code: currencyCode))) is available from \(title(for: source)).",
                isError: true
            )
            return
        }

        let direction = mode == .add ? "Added" : "Moved"
        feedback = BudgetTransferFeedback(
            message: "\(direction) \(amount.formatted(.currency(code: currencyCode))) \(transferDescription(for: account)).",
            isError: false
        )
        completedTransferCount += 1
    }

    private func transferDescription(for account: BudgetAccount) -> String {
        switch mode {
        case .add:
            "from \(title(for: account))"
        case .subtract:
            "to \(title(for: account))"
        }
    }

    private func title(for account: BudgetAccount) -> String {
        switch account {
        case .freePool:
            "Free Pool"
        case .event(let reference):
            title(for: reference)
        }
    }

    private func symbol(for account: BudgetAccount) -> String {
        switch account {
        case .freePool:
            "tray.full.fill"
        case .event(let reference):
            symbol(for: reference)
        }
    }

    private func title(for reference: EventReference) -> String {
        switch reference {
        case .main:
            workspace.title
        case .subevent(let id):
            workspace.timeline.first(where: { $0.id == id })?.title ?? "Event"
        case .idea:
            "Idea"
        }
    }

    private func symbol(for reference: EventReference) -> String {
        switch reference {
        case .main:
            "heart.fill"
        case .subevent(let id):
            workspace.timeline.first(where: { $0.id == id })?.category.symbol ?? "calendar"
        case .idea:
            "lightbulb.fill"
        }
    }
}

private enum BudgetAdjustmentMode: String, CaseIterable, Identifiable {
    case add
    case subtract

    var id: Self { self }

    var title: String {
        switch self {
        case .add: "Add"
        case .subtract: "Subtract"
        }
    }

    var symbol: String {
        switch self {
        case .add: "plus"
        case .subtract: "minus"
        }
    }
}

private struct BudgetTransferFeedback {
    let message: String
    let isError: Bool
}
