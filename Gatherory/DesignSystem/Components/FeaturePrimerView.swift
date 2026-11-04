import SwiftUI

/// Brief, branded education using the original welcome screen’s visual language.
struct FeaturePrimerView<Content: View>: View {
    let title: String
    let continueIdentifier: String
    let continueAction: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 32)

                    VStack(spacing: AppTheme.Spacing.spacious) {
                        Image("GatheroryLaunchMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 108, height: 108)
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("primer.heading")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("primer.brandHeader")
                    .padding(.bottom, AppTheme.Spacing.section + AppTheme.Spacing.compact)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                        content()
                    }
                    .frame(maxWidth: 520, alignment: .leading)

                    Spacer(minLength: AppTheme.Spacing.section)
                }
                .padding(.horizontal, AppTheme.Spacing.spacious)
                .padding(.top, AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)

            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(AppCopy.Common.continueAction, action: continueAction)
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .foregroundStyle(AppTheme.ColorToken.onAccent)
                .controlSize(.large)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .accessibilityIdentifier(continueIdentifier)
                .padding(.horizontal, AppTheme.Spacing.spacious)
                .padding(.vertical, AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity)
                .background(AppTheme.ColorToken.background)
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
        .tint(AppTheme.ColorToken.accent)
    }
}

struct FeaturePrimerRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
