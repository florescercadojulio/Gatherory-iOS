import SwiftUI

/// The original welcome precedes the optional tour. A workspace is created only after the
/// person selects the bundled Movie Night card in the real Explore tab.
struct MovieNightOnboardingView: View {
    let onStartTour: () -> Void
    let onSkipCreation: () -> Void

    @Environment(\.currentUserAccount) private var account
    @State private var isStarting = false
    @State private var welcomeAccountID: String?

    var body: some View {
        NavigationStack {
            Group {
                if let ownerID = account?.id, !ownerID.isEmpty {
                    if welcomeAccountID == ownerID {
                        GeometryReader { geometry in
                            ScrollView {
                                introduction
                                    .padding(24)
                                    .frame(maxWidth: 480)
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                    } else {
                        OnboardingWelcomePrimer {
                            guard account?.id == ownerID else { return }
                            welcomeAccountID = ownerID
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(AppTheme.ColorToken.accent)
    }

    private var introduction: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 16)
            Image(systemName: "popcorn.fill")
                .font(.system(size: 68))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Plan a Movie Night")
                    .font(.largeTitle.bold())
                Text("Try a short guided tour. Add ideas, make a decision, and put an activity on your schedule.")
                    .foregroundStyle(.secondary)
                Text("Your practice event is yours to keep or delete from Events whenever you like.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                Button(action: startTour) {
                    HStack {
                        if isStarting { ProgressView() }
                        Text("Start tour")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(isStarting || account == nil)
                .accessibilityIdentifier("movieNightOnboarding.start")
                Button("Skip", action: onSkipCreation)
                    .frame(minHeight: 44)
                    .disabled(isStarting)
                    .accessibilityIdentifier("movieNightOnboarding.skip")
            }
        }
    }

    private func startTour() {
        guard !isStarting, let account, welcomeAccountID == account.id else { return }
        isStarting = true
        defer { isStarting = false }
        ContextualPrimerStore().reset(accountID: account.id)
        MovieNightTourDiscoveryStore().begin(accountID: account.id)
        onStartTour()
    }
}
