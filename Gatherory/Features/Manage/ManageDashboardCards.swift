import SwiftUI

struct ManageEventSelector: View {
    let events: [ManageEventSummary]
    let selected: ManageEventSummary
    @Binding var selection: EventReference

    var body: some View {
        Group {
            if events.count > 1 {
                Menu {
                    Picker("Event", selection: $selection) {
                        ForEach(events) { Text($0.title).tag($0.reference) }
                    }
                } label: {
                    contextLabel(showsDisclosure: true)
                }
                .accessibilityLabel("Event")
                .accessibilityValue(selected.title)
            } else {
                contextLabel(showsDisclosure: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .buttonStyle(.plain)
    }

    private func contextLabel(showsDisclosure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .accessibilityHidden(true)
            Text(selected.title).font(.headline)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if showsDisclosure {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct ManageEventScopeAccessory: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Binding var selection: EventReference

    private var references: [EventReference] { ManageEventSummary.references(in: workspace) }

    private var selectedTitle: String {
        workspace.eventTitle(for: eventID(for: selection))
    }

    var body: some View {
        Menu {
            Picker("Event", selection: $selection) {
                ForEach(references, id: \.self) { reference in
                    Text(workspace.eventTitle(for: eventID(for: reference)))
                        .tag(reference)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text(selectedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("Manage event filter")
        .accessibilityValue(selectedTitle)
        .accessibilityHint("Choose which event to manage")
    }

    private func eventID(for reference: EventReference) -> UUID {
        switch reference {
        case .main: workspace.mainEventID
        case .subevent(let eventID): eventID
        case .idea: workspace.mainEventID
        }
    }
}

/// One navigation target; exact currency values remain available to VoiceOver.
struct ManageBudgetCard: View {
    let spent: ManageMetric
    let remaining: ManageMetric
    let spentAmount: Decimal
    let budgetAmount: Decimal?
    let budgetTotal: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Budget").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 5)
            budgetRing.frame(maxWidth: .infinity)
            remainingSummary
            Spacer(minLength: 5)
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private var budgetRing: some View {
        let spentValue = max(NSDecimalNumber(decimal: spentAmount).doubleValue, 0)
        let budgetValue = max(NSDecimalNumber(decimal: budgetAmount ?? .zero).doubleValue, 0)
        let isOverBudget = budgetAmount != nil && spentValue > budgetValue
        let progress = budgetValue > 0 ? min(spentValue / budgetValue, 1) : (isOverBudget ? 1 : 0)
        return ZStack {
            Circle()
                .stroke(AppTheme.ColorToken.textSecondary.opacity(0.18), style: StrokeStyle(lineWidth: 8, lineCap: .round))

            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        isOverBudget ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.accent,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 1) {
                Text(budgetAmount == nil ? "—" : spent.value)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isOverBudget ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(budgetAmount == nil ? "No budget" : "of \(budgetTotal ?? "—")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isOverBudget ? AppTheme.ColorToken.destructive : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if budgetAmount != nil {
                    Text(spent.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .frame(width: 116, height: 116)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget usage")
        .accessibilityValue(budgetAmount == nil ? "No budget set. Spent \(spent.value)." : "Spent \(spent.value). \(remaining.label) \(remaining.value).")
    }

    private var isOverBudget: Bool {
        guard let budgetAmount else { return false }
        return spentAmount > budgetAmount
    }

    private var remainingSummary: some View {
        VStack(spacing: 1) {
            Text(budgetAmount == nil ? "No budget set" : remaining.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(budgetAmount == nil ? "—" : remaining.value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(remaining.isWarning ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(
        title: String,
        value: String,
        alignment: HorizontalAlignment,
        valueColor: Color = AppTheme.ColorToken.textPrimary
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}
