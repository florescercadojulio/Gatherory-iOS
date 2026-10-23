#if DEBUG
import SwiftUI

/// A local-only canvas for checking app themes against direct semantic tokens
/// and native controls. The picker state never reaches app preferences.
private struct AppColorThemePlayground: View {
    @State private var selectedTheme: AppColorThemeChoice = .gatheroryBlue
    @State private var selectedScheme: ColorScheme
    @State private var remindersEnabled = true
    @State private var selectedPlanningStyle = PlanningStyle.shared

    init(initialScheme: ColorScheme) {
        _selectedScheme = State(initialValue: initialScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    controls
                    tokenSamples
                    artworkAndAvatar
                    nativeControls
                    budgetSample
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.vertical, AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("Theme Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .appColorTheme(selectedTheme)
        .environment(\.appContentColorScheme, selectedScheme)
        .preferredColorScheme(selectedScheme)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Picker("Theme", selection: $selectedTheme) {
                ForEach(AppColorThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)

            Picker("Appearance", selection: $selectedScheme) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
        }
        .padding(AppTheme.Spacing.standard)
        .themePreviewCard()
    }

    private var tokenSamples: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Semantic colors")
                .font(.headline)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            HStack(spacing: AppTheme.Spacing.compact) {
                tokenSwatch("Accent", color: AppTheme.ColorToken.accent)
                tokenSwatch("Secondary", color: AppTheme.ColorToken.accentSecondary)
                tokenSwatch("Tertiary", color: AppTheme.ColorToken.accentTertiary)
            }

            HStack(spacing: AppTheme.Spacing.compact) {
                tokenSwatch("Success", color: AppTheme.ColorToken.success)
                tokenSwatch("Warning", color: AppTheme.ColorToken.warning)
                tokenSwatch("Destructive", color: AppTheme.ColorToken.destructive)
            }
        }
        .padding(AppTheme.Spacing.standard)
        .themePreviewCard()
    }

    private var artworkAndAvatar: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            ProgressiveArtwork(
                symbol: "sparkles",
                colors: IdeaCategory.event.artworkColors,
                accent: AppTheme.ColorToken.accent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 8,
                blurStart: 0.55
            )
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            VStack(spacing: AppTheme.Spacing.compact) {
                UserAvatarView(account: nil, size: 58)
                Text("Avatar fallback")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 132)
            .themePreviewCard()
        }
    }

    private var nativeControls: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Native controls")
                .font(.headline)
                .foregroundStyle(AppTheme.ColorToken.textPrimary)

            Button("Primary action", systemImage: "sparkles") {}
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.ColorToken.onAccent)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Reminders enabled", isOn: $remindersEnabled)

            Picker("Planning style", selection: $selectedPlanningStyle) {
                ForEach(PlanningStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(AppTheme.Spacing.standard)
        .themePreviewCard()
    }

    private var budgetSample: some View {
        ManageBudgetCard(
            spent: ManageMetric(value: "$1,240", label: "Spent"),
            remaining: ManageMetric(value: "$760", label: "Remaining"),
            spentAmount: 1_240,
            budgetAmount: 2_000,
            budgetTotal: "$2,000"
        )
    }

    private func tokenSwatch(_ title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.ColorToken.cardBorder, lineWidth: 1)
                }
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.ColorToken.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PlanningStyle: String, CaseIterable, Identifiable {
    case shared
    case relaxed
    case detailed

    var id: Self { self }

    var title: String {
        switch self {
        case .shared: "Shared"
        case .relaxed: "Relaxed"
        case .detailed: "Detailed"
        }
    }
}

private extension View {
    func themePreviewCard() -> some View {
        background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .strokeBorder(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
            }
    }
}

private struct AppColorThemeGallery: View {
    let scheme: ColorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.compact) {
                    ForEach(AppColorThemeChoice.allCases) { choice in
                        themeRow(choice)
                    }
                }
                .padding(AppTheme.Layout.screenHorizontal)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.ColorToken.background.ignoresSafeArea())
            .navigationTitle("Theme Gallery")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.appContentColorScheme, scheme)
        .preferredColorScheme(scheme)
    }

    private func themeRow(_ choice: AppColorThemeChoice) -> some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: 4) {
                Text(choice.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                Text("Accent · success · warning")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                Circle().fill(AppTheme.ColorToken.accent)
                Circle().fill(AppTheme.ColorToken.success)
                Circle().fill(AppTheme.ColorToken.warning)
            }
            .frame(width: 82, height: 24)
            .accessibilityLabel("Theme semantic color samples")
        }
        .padding(AppTheme.Spacing.standard)
        .themePreviewCard()
        .appColorTheme(choice)
    }
}

#Preview("Themes · Light") {
    AppColorThemeGallery(scheme: .light)
}

#Preview("Themes · Dark") {
    AppColorThemeGallery(scheme: .dark)
}

#Preview("Theme · Interactive Light") {
    AppColorThemePlayground(initialScheme: .light)
}

#Preview("Theme · Interactive Dark") {
    AppColorThemePlayground(initialScheme: .dark)
}
#endif
