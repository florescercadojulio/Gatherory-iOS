import SwiftUI

/// One primary action on the sheet surface, outside the grouped form rows.
struct BlueprintSetupActionBar: View {
    let title: String
    var isWorking = false
    var isEnabled = true
    var guidance: String? = nil
    var errorMessage: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppTheme.ColorToken.destructive)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let guidance {
                Text(guidance)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                HStack(spacing: AppTheme.Spacing.compact) {
                    if isWorking { ProgressView() }
                    Text(title)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(isEnabled && !isWorking ? AppTheme.ColorToken.onAccent : Color.secondary)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
            .disabled(!isEnabled || isWorking)
            .accessibilityIdentifier("blueprint.setup.primaryAction")
        }
        .padding(.horizontal, AppTheme.Spacing.spacious)
        .padding(.vertical, AppTheme.Spacing.standard)
        .adaptiveReadingWidth(680)
    }
}

struct BlueprintSetupDateRow: View {
    let title: String
    let dateLabel: String
    let isConfirmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BlueprintSetupDateRowContent(title: title, dateLabel: dateLabel, isConfirmed: isConfirmed)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isConfirmed ? BlueprintCopy.confirmedDate : BlueprintCopy.confirmDate)
    }
}

struct BlueprintSetupDateRowContent: View {
    let title: String
    let dateLabel: String
    let isConfirmed: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppTheme.Spacing.compact)
            if isConfirmed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.ColorToken.success)
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Exercises the actual presentation components without an account or install.
private struct BlueprintSetupSheetPreview: View {
    @State private var mainConfirmed = false
    @State private var childConfirmed = false

    init(initiallyConfirmed: Bool = false) {
        _mainConfirmed = State(initialValue: initiallyConfirmed)
        _childConfirmed = State(initialValue: initiallyConfirmed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BlueprintSetupDateRow(
                        title: BlueprintCopy.dateTime,
                        dateLabel: Date.now.formatted(date: .abbreviated, time: .shortened),
                        isConfirmed: mainConfirmed
                    ) { mainConfirmed.toggle() }
                } header: {
                    Text(verbatim: "Garden celebration")
                }
                Section(BlueprintCopy.children) {
                    BlueprintSetupDateRow(
                        title: "Welcome drinks",
                        dateLabel: Date.now.addingTimeInterval(-86_400).formatted(date: .abbreviated, time: .shortened),
                        isConfirmed: childConfirmed
                    ) { childConfirmed.toggle() }
                }
            }
            .formStyle(.grouped)
            .listSectionSpacing(.custom(20))
            .navigationTitle(BlueprintCopy.starter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.close) {}
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                BlueprintSetupActionBar(
                    title: BlueprintCopy.install,
                    isEnabled: mainConfirmed && childConfirmed,
                    guidance: !mainConfirmed ? BlueprintCopy.confirmMainDateToContinue
                        : !childConfirmed ? BlueprintCopy.confirmEventDatesToContinue : nil
                ) {}
            }
        }
        .tint(AppTheme.ColorToken.accent)
    }
}

#Preview("Use Blueprint · Light") {
    BlueprintSetupSheetPreview().preferredColorScheme(.light)
}

#Preview("Use Blueprint · Dark") {
    BlueprintSetupSheetPreview().preferredColorScheme(.dark)
}

#Preview("Use Blueprint · Ready") {
    BlueprintSetupSheetPreview(initiallyConfirmed: true).preferredColorScheme(.light)
}
