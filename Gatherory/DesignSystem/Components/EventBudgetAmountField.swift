import SwiftUI

/// The shared budget-limit entry used by scheduled events and event ideas.
struct EventBudgetAmountField: View {
    @Binding var amount: String
    var title = "Budget Limit"

    var body: some View {
        LabeledContent(title) {
            TextField("Optional", text: $amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 110)
                .accessibilityLabel(title)
        }
    }
}
