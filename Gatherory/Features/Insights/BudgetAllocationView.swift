import SwiftUI

/// Edits the selected event's final allocation. The direction of the transfer
/// is derived from the proposed value so people only decide the result they want.
struct BudgetAllocationView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    let target: EventReference

    @State private var proposedAllocation = ""
    @State private var selectedAccount: BudgetAccount?
    @State private var feedbackMessage: String?
    @State private var didInitialize = false

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var currentAllocation: Decimal {
        workspace.budgetCap(for: target) ?? .zero
    }

    private var spentAmount: Decimal {
        workspace.costTotal(for: target)
    }

    private var parsedAllocation: Decimal? {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let normalized = proposedAllocation
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalized), amount >= .zero else { return nil }
        return amount
    }

    private var change: BudgetAllocationChange {
        guard let parsedAllocation else { return .invalid }
        let difference = parsedAllocation - currentAllocation
        if difference > .zero { return .increase(difference) }
        if difference < .zero { return .decrease(abs(difference)) }
        return .unchanged
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

    private var canSave: Bool {
        guard let selectedAccount else { return false }
        switch change {
        case .increase(let amount):
            return (workspace.budgetBalance(for: selectedAccount) ?? .zero) >= amount
        case .decrease:
            return true
        case .unchanged, .invalid:
            return false
        }
    }

    var body: some View {
        Form {
            Section("Event") {
                targetRow
            }

            Section {
                LabeledContent("Current Allocation") {
                    Text(
                        currentAllocation,
                        format: .currency(code: currencyCode).precision(.fractionLength(0))
                    )
                    .fontWeight(.semibold)
                    .monospacedDigit()
                }

                LabeledContent("New Allocation") {
                    TextField("Amount", text: $proposedAllocation)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .frame(minWidth: 110)
                        .accessibilityLabel("New allocation")
                }

                changeSummary
            } header: {
                Text("Allocation")
            } footer: {
                Text("Enter the total budget this event should have. Gatherory handles the transfer.")
            }

            if change.needsAccount {
                Section {
                    ForEach(transferOptions, id: \.self) { account in
                        accountRow(account)
                    }
                } header: {
                    Text(change.accountSectionTitle)
                } footer: {
                    Text(accountSectionHelp)
                }
            }

            if let feedbackMessage {
                Section {
                    Label(feedbackMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
            }
        }
        .appKeyboardDismissal()
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Event Budget")
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
        .task {
            guard !didInitialize else { return }
            proposedAllocation = NSDecimalNumber(decimal: currentAllocation).stringValue
            didInitialize = true
        }
        .onChange(of: proposedAllocation) { _, _ in
            feedbackMessage = nil
            chooseDefaultAccountIfNeeded()
        }
    }

    private var targetRow: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol(for: target))
                .font(.headline)
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.ColorToken.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: target))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text("\(spentAmount.formatted(.currency(code: currencyCode))) spent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var changeSummary: some View {
        switch change {
        case .increase(let amount):
            Label(
                "Add \(amount.formatted(.currency(code: currencyCode)))",
                systemImage: "arrow.down.circle.fill"
            )
            .foregroundStyle(AppTheme.ColorToken.accent)

        case .decrease(let amount):
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Release \(amount.formatted(.currency(code: currencyCode)))",
                    systemImage: "arrow.up.circle.fill"
                )
                .foregroundStyle(AppTheme.ColorToken.accent)

                if let parsedAllocation, parsedAllocation < spentAmount {
                    Label(
                        "This leaves the event \((spentAmount - parsedAllocation).formatted(.currency(code: currencyCode))) over budget.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

        case .unchanged:
            Label("No change", systemImage: "equal.circle")
                .foregroundStyle(.secondary)

        case .invalid:
            Label("Enter a valid amount", systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
    }

    private func accountRow(_ account: BudgetAccount) -> some View {
        let isSelected = selectedAccount == account
        let isAvailable = accountCanFundChange(account)

        return Button {
            guard isAvailable else { return }
            selectedAccount = account
            feedbackMessage = nil
        } label: {
            HStack(spacing: AppTheme.Spacing.standard) {
                Image(systemName: symbol(for: account))
                    .foregroundStyle(isAvailable ? AppTheme.ColorToken.accent : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: account))
                        .foregroundStyle(.primary)
                    Text(accountDetail(account))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: AppTheme.Spacing.compact)

                Text(
                    workspace.budgetBalance(for: account) ?? .zero,
                    format: .currency(code: currencyCode).precision(.fractionLength(0))
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAvailable ? .primary : .secondary)
                .monospacedDigit()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.accent : .secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func accountCanFundChange(_ account: BudgetAccount) -> Bool {
        switch change {
        case .increase(let amount):
            (workspace.budgetBalance(for: account) ?? .zero) >= amount
        case .decrease:
            true
        case .unchanged, .invalid:
            false
        }
    }

    private var accountSectionHelp: String {
        if case .increase = change,
           !transferOptions.contains(where: accountCanFundChange) {
            return "No single source can cover this increase. Enter a smaller allocation and make another transfer if needed."
        }
        return change.accountSectionHelp(for: title(for: target))
    }

    private func accountDetail(_ account: BudgetAccount) -> String {
        switch change {
        case .increase:
            account == .freePool ? "Unallocated budget" : "Available from this event"
        case .decrease:
            account == .freePool ? "Leave unallocated" : "Add to this event"
        case .unchanged, .invalid:
            ""
        }
    }

    private func chooseDefaultAccountIfNeeded() {
        guard change.needsAccount else {
            selectedAccount = nil
            return
        }

        if let selectedAccount, accountCanFundChange(selectedAccount) {
            return
        }

        if accountCanFundChange(.freePool) {
            selectedAccount = .freePool
        } else {
            selectedAccount = transferOptions.first(where: accountCanFundChange)
        }
    }

    private func save() {
        guard let selectedAccount else { return }

        let transfer: (amount: Decimal, source: BudgetAccount, destination: BudgetAccount)? = switch change {
        case .increase(let amount):
            (amount, selectedAccount, .event(target))
        case .decrease(let amount):
            (amount, .event(target), selectedAccount)
        case .unchanged, .invalid:
            nil
        }

        guard let transfer,
              workspace.transferBudget(
                transfer.amount,
                from: transfer.source,
                to: transfer.destination
              ) else {
            feedbackMessage = "That budget changed elsewhere. Review the amounts and try again."
            chooseDefaultAccountIfNeeded()
            return
        }

        dismiss()
    }

    private func title(for account: BudgetAccount) -> String {
        switch account {
        case .freePool:
            "Unallocated"
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

private enum BudgetAllocationChange: Equatable {
    case increase(Decimal)
    case decrease(Decimal)
    case unchanged
    case invalid

    var needsAccount: Bool {
        switch self {
        case .increase, .decrease:
            true
        case .unchanged, .invalid:
            false
        }
    }

    var accountSectionTitle: String {
        switch self {
        case .increase:
            "Fund Increase From"
        case .decrease:
            "Send Difference To"
        case .unchanged, .invalid:
            ""
        }
    }

    func accountSectionHelp(for eventTitle: String) -> String {
        switch self {
        case .increase:
            "Choose one source for the increase to \(eventTitle)."
        case .decrease:
            "Choose where the released budget should go."
        case .unchanged, .invalid:
            ""
        }
    }
}
