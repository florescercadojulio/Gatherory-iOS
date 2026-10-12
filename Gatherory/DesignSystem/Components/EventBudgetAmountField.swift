import SwiftUI

enum MoneyInputFormatter {
    static func decimal(from text: String, locale: Locale = .current) -> Decimal? {
        let groupingSeparator = locale.groupingSeparator ?? ","
        let decimalSeparator = locale.decimalSeparator ?? "."
        let normalized = text
            .replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: decimalSeparator, with: ".")
            .filter { $0.isNumber || $0 == "." }

        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func integer(from text: String, locale: Locale = .current) -> Int? {
        guard let decimal = decimal(from: text, locale: locale) else { return nil }
        return NSDecimalNumber(decimal: decimal).intValue
    }

    static func editingText(
        from text: String,
        allowsFraction: Bool = true,
        locale: Locale = .current
    ) -> String {
        guard !text.isEmpty else { return "" }

        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        var ungrouped = text.replacingOccurrences(of: groupingSeparator, with: "")

        if decimalSeparator != "." {
            ungrouped = ungrouped.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        let containsDecimal = allowsFraction && ungrouped.contains(".")
        let pieces = ungrouped.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integerDigits = String(pieces.first ?? "").filter(\.isNumber)
        let fractionDigits: String = allowsFraction && pieces.count > 1
            ? String(String(pieces[1]).filter(\.isNumber).prefix(2))
            : ""

        guard !integerDigits.isEmpty || containsDecimal else { return "" }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0

        let integer = NSDecimalNumber(string: integerDigits.isEmpty ? "0" : integerDigits)
        let groupedInteger = formatter.string(from: integer) ?? integerDigits

        guard containsDecimal else { return groupedInteger }
        return groupedInteger + decimalSeparator + fractionDigits
    }

    static func editingText(from amount: Decimal?, locale: Locale = .current) -> String {
        guard let amount else { return "" }
        return editingText(
            from: NSDecimalNumber(decimal: amount).stringValue,
            locale: locale
        )
    }
}

struct MoneyAmountField: View {
    enum Style {
        case labeled
        case prominent
    }

    @Binding var amount: String
    var title: String
    var placeholder = "Optional"
    var symbol = "dollarsign"
    var allowsFraction = true
    var style: Style = .labeled
    var currencyCode = Locale.current.currency?.identifier ?? "USD"

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.currencyCode = currencyCode
        return formatter.currencySymbol ?? currencyCode
    }

    var body: some View {
        Group {
            switch style {
            case .labeled:
                LabeledContent(title) {
                    amountField
                        .frame(minWidth: 110)
                }

            case .prominent:
                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 30)

                    Text(currencySymbol)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)

                    amountField
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                }
                .frame(minHeight: 54)
            }
        }
        .onChange(of: amount) { _, updatedValue in
            let formatted = MoneyInputFormatter.editingText(
                from: updatedValue,
                allowsFraction: allowsFraction
            )
            if formatted != updatedValue {
                amount = formatted
            }
        }
    }

    private var amountField: some View {
        TextField(placeholder, text: $amount)
            .keyboardType(allowsFraction ? .decimalPad : .numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .accessibilityLabel(title)
    }
}

/// Kept as the semantic entry point for budget limits while sharing all input
/// and formatting behavior with every other money field in the app.
struct EventBudgetAmountField: View {
    @Binding var amount: String
    var title = "Budget Limit"
    var currencyCode = Locale.current.currency?.identifier ?? "USD"

    var body: some View {
        MoneyAmountField(
            amount: $amount,
            title: title,
            currencyCode: currencyCode
        )
    }
}
