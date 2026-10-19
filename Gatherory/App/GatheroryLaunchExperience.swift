import SwiftUI
import UIKit

enum LaunchExperienceTiming {
    static let standardMilliseconds = 1_400
    static let reducedMotionMilliseconds = 300
    static let exitAnimationSeconds = 0.22
}

struct GatheroryLaunchContainer: View {
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(WorkspaceLibrary.self) private var workspaceLibrary
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(InvitationRouter.self) private var invitations
    @Environment(BlueprintSharedTemplateRouter.self) private var sharedBlueprintLinks
    @Environment(GuestInvitationStore.self) private var guestInvitations
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenDecideTimelinePrimer") private var hasSeenDecideTimelinePrimer = false
    @State private var isShowingSplash = true
    @State private var completedOnboardingThisSession = false
    @State private var preparedAccountID: String?
    @State private var hasRestoredAuthentication = false

    private var shouldShowLocalOnboarding: Bool {
        guard !completedOnboardingThisSession else { return false }
        return AppRuntimeConfiguration.alwaysShowsOnboarding || !hasCompletedOnboarding
    }

    var body: some View {
        @Bindable var authentication = authentication
        ZStack {
            Group {
                if let token = sharedBlueprintLinks.pendingToken {
                    if !authentication.isAuthenticated {
                        NavigationStack {
                            AuthenticationView()
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Back", systemImage: "chevron.left") { sharedBlueprintLinks.dismiss() }
                                    }
                                }
                        }
                    } else if preparedAccountID != authentication.currentUser?.id {
                        AccountOnboardingLoadingView()
                    } else {
                        BlueprintSharedPreviewView(token: token)
                            .id("shared-blueprint-\(token)-\(authentication.currentUser?.id ?? "signed-out")")
                    }
                } else if let token = invitations.pendingToken {
                    if invitations.requiresAuthentication && !authentication.isAuthenticated {
                        NavigationStack {
                            AuthenticationView()
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Back", systemImage: "chevron.left") { invitations.requiresAuthentication = false }
                                    }
                                }
                        }
                    } else if authentication.isAuthenticated && preparedAccountID != authentication.currentUser?.id {
                        // Invitation routing must not race the previous account's
                        // teardown or the new account's workspace activation.
                        AccountOnboardingLoadingView()
                    } else { NativeInvitationView(token: token).id(token) }
                } else if !authentication.isAuthenticated {
                    AuthenticationView()
                } else if preparedAccountID != authentication.currentUser?.id {
                    AccountOnboardingLoadingView()
                } else if !guestInvitations.events.isEmpty || invitations.didJoinThisSession {
                    AppRootView()
                } else if AppRuntimeConfiguration.alwaysShowsOnboarding && !completedOnboardingThisSession {
                    OnboardingView(onCreateWorkspace: finishOnboarding, onSkipCreation: completeOnboarding)
                } else if AppRuntimeConfiguration.usesRemoteAccountState {
                    remoteAccountExperience
                } else if shouldShowLocalOnboarding {
                    OnboardingView(onCreateWorkspace: finishOnboarding, onSkipCreation: completeOnboarding)
                } else {
                    AppRootView()
                }
            }
            .transition(.opacity)

            if isShowingSplash {
                GatheroryAnimatedSplash(reduceMotion: reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .disabled(authentication.isSigningOut)
        .overlay {
            if authentication.isSigningOut {
                ProgressView("Finishing sign out…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .alert("Couldn’t Finish Syncing", isPresented: $authentication.signOutNeedsAttention) {
            Button("Try Again") { Task { await authentication.signOut() } }
            Button("Sign Out Anyway", role: .destructive) {
                Task { await authentication.signOut(keepingPendingChanges: true) }
            }
            Button("Stay Signed In", role: .cancel) {}
        } message: {
            Text("Some changes may still need syncing. If you sign out now, saved changes stay on this device for this account. Sign back in to finish syncing before removing the app.")
        }
        .task {
            authentication.prepareForSignOut = { keepingPendingChanges in
                try await cloudSync.prepareForSignOut(keepingPendingChanges: keepingPendingChanges)
                await guestInvitations.activate(account: nil)
            }
            guard isShowingSplash else { return }

            let milliseconds = reduceMotion
                ? LaunchExperienceTiming.reducedMotionMilliseconds
                : LaunchExperienceTiming.standardMilliseconds
            let minimumSplash = Task {
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }

            await authentication.restoreSession()
            hasRestoredAuthentication = true
            if !AppRuntimeConfiguration.usesRemoteAccountState,
               !workspaceLibrary.workspaces.isEmpty,
               !AppRuntimeConfiguration.alwaysShowsOnboarding {
                hasCompletedOnboarding = true
            }
            await minimumSplash.value
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: LaunchExperienceTiming.exitAnimationSeconds)) {
                isShowingSplash = false
            }
        }
        .task(id: "\(hasRestoredAuthentication)|\(authentication.currentUser?.id ?? "signed-out")") {
            // Never synchronize using a cached profile before its bearer
            // session has resolved to the canonical account identity.
            guard hasRestoredAuthentication else { return }
            invitations.resetJoinedSession()
            completedOnboardingThisSession = false
            preparedAccountID = nil
            let account = authentication.currentUser
            await cloudSync.activate(
                userID: account?.id,
                seedData: AppRuntimeConfiguration.seedsDevelopmentData
            )
            guard authentication.currentUser?.id == account?.id else { return }
            await guestInvitations.activate(account: AppRuntimeConfiguration.usesRemoteAccountState ? account : nil)
            guard authentication.currentUser?.id == account?.id else { return }
            preparedAccountID = account?.id
            if !AppRuntimeConfiguration.usesRemoteAccountState,
               !workspaceLibrary.workspaces.isEmpty,
               !AppRuntimeConfiguration.alwaysShowsOnboarding {
                hasCompletedOnboarding = true
            }
        }
    }

    @ViewBuilder
    private var remoteAccountExperience: some View {
        if guestInvitations.isRefreshing {
            AccountOnboardingLoadingView()
        } else if guestInvitations.errorMessage != nil && workspaceLibrary.workspaces.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t Load Your Account", systemImage: "icloud.slash")
            } description: {
                Text(guestInvitations.errorMessage ?? "")
            } actions: {
                Button("Try Again") { Task { await guestInvitations.refresh(force: true); await cloudSync.retryInitialBootstrap() } }
                Button("Sign Out", role: .destructive) { Task { await authentication.signOut() } }
            }
        } else {
        switch cloudSync.accountOnboardingState {
        case .signedOut, .resolving:
            AccountOnboardingLoadingView()
        case .needsOnboarding:
            OnboardingView(onCreateWorkspace: finishOnboarding, onSkipCreation: completeOnboarding)
        case .complete:
            AppRootView()
        case .unavailable:
            ContentUnavailableView {
                Label("Couldn’t Load Your Account", systemImage: "icloud.slash")
            } description: {
                Text("Gatherory needs to check your account before deciding where to continue.")
            } actions: {
                Button("Try Again") {
                    Task { await cloudSync.retryInitialBootstrap() }
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    // Bootstrap may be unavailable even though a stale local
                    // session still identifies an account. Always leave an
                    // escape hatch so the user can authenticate again.
                    Task { await authentication.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        }
    }

    private func finishOnboarding(with workspace: PlanningWorkspace) {
        workspaceLibrary.add(workspace)
        // Workspace creation is a transaction boundary, not a debounced edit.
        // Persisting here guarantees the local archive and durable outbox entry
        // exist before onboarding transitions to the workspace experience.
        persistence.flush(workspaceLibrary)
        completeOnboarding()
    }

    private func completeOnboarding() {
        // Decide education belongs to the onboarding journey. Development
        // builds force onboarding, so completing that flow should make the
        // contextual primer eligible again. In production onboarding only
        // completes once, preserving the primer's one-time behavior.
        hasSeenDecideTimelinePrimer = false
        cloudSync.markOnboardingCompletedLocally()

        if reduceMotion {
            hasCompletedOnboarding = true
            completedOnboardingThisSession = true
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                hasCompletedOnboarding = true
                completedOnboardingThisSession = true
            }
        }
    }
}

/// Account preparation is real work, not a timed splash or a second onboarding step.
/// Keep the artwork local so this screen never adds network work to account loading.
struct AccountOnboardingLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    artwork
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 156 : 256)

                    VStack(spacing: 16) {
                        Text("Gatherory")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(AppCopy.Primer.AccountLoading.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)

                        Text(AppCopy.Primer.AccountLoading.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
                    .padding(.top, 12)

                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 520, minHeight: max(0, geometry.size.height))
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(AppTheme.ColorToken.background.ignoresSafeArea())
    }

    private var artwork: some View {
        ZStack {
            if reduceMotion {
                loadingMark
            } else {
                loadingMark
                    .keyframeAnimator(
                        initialValue: LoadingMarkMotion(),
                        repeating: scenePhase == .active
                    ) { content, value in
                        content
                            .rotationEffect(.degrees(value.rotation))
                            .offset(y: value.offsetY)
                    } keyframes: { _ in
                        KeyframeTrack(\.rotation) {
                            LinearKeyframe(360, duration: 2.1)
                        }
                        KeyframeTrack(\.offsetY) {
                            CubicKeyframe(-16, duration: 0.7)
                            CubicKeyframe(0, duration: 0.55)
                            CubicKeyframe(-5, duration: 0.3)
                            CubicKeyframe(0, duration: 0.3)
                            LinearKeyframe(0, duration: 0.25)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppCopy.Primer.AccountLoading.status)
        .accessibilityIdentifier("account-loading-status")
    }

    private var loadingMark: some View {
        Image("GatheroryLaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 120 : 176,
                   height: dynamicTypeSize.isAccessibilitySize ? 120 : 176)
    }

    private struct LoadingMarkMotion {
        var rotation: Double = 0
        var offsetY: CGFloat = 0
    }
}

#Preview("Account loading · Light") {
    AccountOnboardingLoadingView().preferredColorScheme(.light)
}

#Preview("Account loading · Dark") {
    AccountOnboardingLoadingView().preferredColorScheme(.dark)
}

#Preview("Account loading · Large text") {
    AccountOnboardingLoadingView().environment(\.dynamicTypeSize, .accessibility3)
}

private struct GatheroryAnimatedSplash: View {
    @State private var animationTrigger = false
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if reduceMotion {
                launchMark
            } else {
                animatedLaunchMark
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gatherory")
    }

    private var launchMark: some View {
        Image("GatheroryLaunchMark")
            .resizable()
            .scaledToFit()
            .frame(width: 184, height: 184)
    }

    private var animatedLaunchMark: some View {
        let accentColor = AppTheme.ColorToken.accent

        return launchMark
            .keyframeAnimator(
                initialValue: LaunchMarkMotion.initial,
                trigger: animationTrigger
            ) { content, value in
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(value.glowOpacity))
                        .frame(width: 146, height: 146)
                        .scaleEffect(value.glowScale)
                        .blur(radius: 30)

                    ZStack {
                        content

                        LinearGradient(
                            colors: [.clear, .white.opacity(0.72), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: 54, height: 230)
                        .rotationEffect(.degrees(20))
                        .offset(x: value.shineOffset)
                        .blendMode(.screen)
                        .mask { content }
                    }
                    .opacity(value.opacity)
                    .scaleEffect(value.scale)
                    .rotationEffect(.degrees(value.rotation))
                    .offset(y: value.offsetY)
                }
                .frame(width: 220, height: 220)
                .compositingGroup()
            } keyframes: { initial in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.2)
                }

                KeyframeTrack(\.scale) {
                    SpringKeyframe(
                        1.04,
                        duration: 0.55,
                        spring: Spring(duration: 0.55, bounce: 0.12)
                    )
                    CubicKeyframe(1, duration: 0.16)
                }

                KeyframeTrack(\.rotation) {
                    SpringKeyframe(
                        0,
                        duration: 0.65,
                        spring: Spring(duration: 0.65, bounce: 0.08)
                    )
                }

                KeyframeTrack(\.offsetY) {
                    SpringKeyframe(
                        0,
                        duration: 0.55,
                        spring: Spring(duration: 0.55, bounce: 0.08)
                    )
                }

                KeyframeTrack(\.glowScale) {
                    CubicKeyframe(1.18, duration: 0.5)
                    CubicKeyframe(1, duration: 0.2)
                }

                KeyframeTrack(\.glowOpacity) {
                    LinearKeyframe(0.14, duration: 0.22)
                    CubicKeyframe(0.07, duration: 0.48)
                }

                KeyframeTrack(\.shineOffset) {
                    LinearKeyframe(initial.shineOffset, duration: 0.32)
                    CubicKeyframe(190, duration: 0.52)
                }
            }
            .accessibilityHidden(true)
            .task {
                animationTrigger.toggle()
            }
    }
}

private struct LaunchMarkMotion {
    var opacity: Double
    var scale: CGFloat
    var rotation: Double
    var offsetY: CGFloat
    var glowScale: CGFloat
    var glowOpacity: Double
    var shineOffset: CGFloat

    static let initial = LaunchMarkMotion(
        opacity: 0,
        scale: 0.74,
        rotation: -14,
        offsetY: 18,
        glowScale: 0.72,
        glowOpacity: 0,
        shineOffset: -190
    )
}

#Preview {
//    GatheroryAnimatedSplash(reduceMotion: false)
    AccountOnboardingLoadingView()
}
