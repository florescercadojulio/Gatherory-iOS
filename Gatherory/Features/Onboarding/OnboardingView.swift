import SwiftUI

struct OnboardingView: View {
    var onCreateWorkspace: (WeddingWorkspace) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var page = Page.welcome
    @State private var isCreatingWorkspace = false

    var body: some View {
        ZStack {
            AppTheme.ColorToken.background
                .ignoresSafeArea()

            Group {
                switch page {
                case .welcome:
                    welcomePage
                        .transition(pageTransition)
                case .create:
                    createPage
                        .transition(pageTransition)
                }
            }
        }
        .tint(AppTheme.ColorToken.accent)
        .animation(reduceMotion ? nil : .smooth(duration: 0.42), value: page)
        .sheet(isPresented: $isCreatingWorkspace) {
            NavigationStack {
                NewWorkspaceView(onWorkspaceCreated: onCreateWorkspace)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.section) {
                Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 52)

                VStack(spacing: AppTheme.Spacing.standard) {
                    Image("GatheroryLaunchMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 108, height: 108)
                        .accessibilityHidden(true)

                    Text("Welcome to Gatherory")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    OnboardingFeature(
                        symbol: "envelope.open.fill",
                        title: "Received an invitation?",
                        message: "Open the link you were sent to view the event and respond."
                    )

                    OnboardingFeature(
                        symbol: "rectangle.stack.badge.plus",
                        title: "Planning something?",
                        message: "Create an event and bring everyone, every idea, and every detail together."
                    )
                }
                .frame(maxWidth: 520)

                Spacer(minLength: AppTheme.Spacing.spacious)

                VStack(spacing: AppTheme.Spacing.compact) {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .accessibilityHidden(true)

                    Text("Your event can include names, dates, locations, budgets, and participants. You decide who can join and collaborate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.spacious)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity, minHeight: 690)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            Button("Continue") {
                page = .create
            }
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 560)
            .padding(.horizontal, AppTheme.Spacing.spacious)
            .padding(.top, AppTheme.Spacing.compact)
            .padding(.bottom, AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity)
        }
    }

    private var createPage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 24 : 34) {
                    ZStack(alignment: .topLeading) {
                        onboardingArtwork(width: proxy.size.width)

                        Button("Back", systemImage: "chevron.backward") {
                            page = .welcome
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .padding(.leading, AppTheme.Spacing.standard)
                        .padding(.top, AppTheme.Spacing.compact)
                    }

                    VStack(spacing: AppTheme.Spacing.standard) {
                        Text("Welcome to")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("Gatherory")
                            .font(.system(.largeTitle, design: .default, weight: .bold))

                        Text("Create a beautiful home for your event, then shape every plan with the people who matter.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    .padding(.horizontal, AppTheme.Spacing.spacious)

                    Button("Create an Event") {
                        isCreatingWorkspace = true
                    }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, AppTheme.Spacing.spacious)
                    .padding(.bottom, AppTheme.Spacing.spacious)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func onboardingArtwork(width: CGFloat) -> some View {
        let availableWidth = min(width, 700)
        let cardWidth = min(max((availableWidth - 58) / 2, 156), 292)
        let cardHeight = dynamicTypeSize.isAccessibilitySize ? 250.0 : 340.0

        HStack(spacing: 18) {
            OnboardingEventPreview(
                title: "Avery & Morgan",
                date: "June 13",
                location: "Ann Arbor, MI",
                assetName: "WeddingVenueHero",
                colors: [AppTheme.ColorToken.navy, AppTheme.ColorToken.lilac],
                width: cardWidth,
                height: cardHeight
            )
            .rotationEffect(.degrees(-2))

            OnboardingEventPreview(
                title: "Weekend Away",
                date: "September 18",
                location: "Traverse City, MI",
                assetName: nil,
                colors: [AppTheme.ColorToken.accent, AppTheme.ColorToken.mint],
                width: cardWidth,
                height: cardHeight
            )
            .rotationEffect(.degrees(2))
        }
        .frame(width: cardWidth * 2 + 18)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight + 42)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Examples of event workspaces in Gatherory")
    }

    private enum Page {
        case welcome
        case create
    }
}

private struct OnboardingFeature: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingEventPreview: View {
    let title: String
    let date: String
    let location: String
    let assetName: String?
    let colors: [Color]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            MediaArtwork(
                imageData: nil,
                assetName: assetName,
                symbol: "sparkles",
                colors: colors,
                accent: .white,
                progressiveBlurRadius: 0
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.16), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 5) {
                HStack(spacing: -6) {
                    ForEach(["AM", "J", "R"], id: \.self) { initials in
                        Text(initials)
                            .font(.caption2.bold())
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))
                    }
                }

                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(date)
                    .font(.subheadline.weight(.semibold))

                Text(location)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(AppTheme.Spacing.standard)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
    }
}

#Preview("Gatherory Welcome") {
    OnboardingView()
        .environment(WorkspaceLibrary.sample)
}
