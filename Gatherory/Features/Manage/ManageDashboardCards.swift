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

/// One navigation target; exact currency values remain available to VoiceOver.
struct ManageBudgetCard: View {
    let spent: ManageMetric
    let remaining: ManageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Budget").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(spent.value).font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                Text(spent.label).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(remaining.value).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(remaining.isWarning ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(remaining.label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(AppTheme.ColorToken.textPrimary)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 28))
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}
