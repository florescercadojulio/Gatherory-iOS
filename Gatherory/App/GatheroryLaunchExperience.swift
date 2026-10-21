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
    @Environment(NotificationController.self) private var notifications
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenDecideTimelinePrimer") private var hasSeenDecideTimelinePrimer = false
    @State private var isShowingSplash = true
    @State private var completedOnboardingIdentity: SessionPreparationIdentity?
    @State private var preparation = SessionPreparationCoordinator()
    @State private var hasRestoredAuthentication = false
    @State private var preparationAttempt = 0
    @State private var restorationSignInRequested = false
    @State private var confirmsDeviceRemoval = false
    @State private var showsGuestAccount = false
    @State private var notificationNavigation = NotificationNavigationState()
    @State private var notificationSessionGeneration = UUID()

    private var sessionIdentity: String {
        authentication.currentUser?.id ?? authentication.localGuestProfile?.storageID ?? "signed-out"
    }

    private var preparationRequest: SessionPreparationRequest {
        SessionPreparationRequest(account: authentication.currentUser, guestProfile: authentication.localGuestProfile)
    }

    private var isSessionReady: Bool {
        !authentication.deletionCleanup.blocksEntry && !authentication.isSessionRestorationUnavailable && !authentication.guestDiscardNeedsAttention &&
            preparation.isReady(for: preparationRequest.identity)
    }
    private var preparationRecovery: SessionPreparationRecovery? { preparation.recovery(for: preparationRequest.identity) }

    private var authenticationFlowDestination: AuthenticationFlowDestination {
        AuthenticationFlowChain.default.destination(for: AuthenticationFlowContext(
            guestSignInRequested: authentication.isGuestSignInRequested,
            guestImportNeedsSignIn: preparationRecovery == .originalAccountRequired,
            hasPendingGuestImport: authentication.hasPendingGuestImport,
            pendingSharedBlueprintToken: sharedBlueprintLinks.pendingToken,
            pendingInvitationToken: invitations.pendingToken,
            invitationRequiresAuthentication: invitations.requiresAuthentication,
            isGuestMode: authentication.isGuestMode,
            isAuthenticated: authentication.isAuthenticated,
            guestPreparationFailed: preparationRecovery != nil,
            preparedIdentityMatches: isSessionReady,
            hasGuestInvitations: !guestInvitations.events.isEmpty,
            didJoinInvitationThisSession: invitations.didJoinThisSession,
            alwaysShowsOnboarding: AppRuntimeConfiguration.alwaysShowsOnboarding,
            completedOnboardingThisSession: completedOnboardingIdentity == preparationRequest.identity,
            usesRemoteAccountState: AppRuntimeConfiguration.usesRemoteAccountState,
            accountOnboardingState: cloudSync.accountOnboardingState,
            sessionRestorationUnavailable: authentication.isSessionRestorationUnavailable,
            restorationSignInRequested: restorationSignInRequested,
            guestDiscardNeedsAttention: authentication.guestDiscardNeedsAttention,
            accountPreparationFailed: authentication.isAuthenticated && preparationRecovery != nil,
            accountDeletionCleanupPending: authentication.deletionCleanup.blocksEntry
        ))
    }

    var body: some View {
        @Bindable var authentication = authentication
        ZStack {
            Group {
                switch authenticationFlowDestination {
                case .guestSignIn:
                    NavigationStack {
                        AuthenticationView(allowsGuestContinuation: false)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button(AppCopy.Common.cancel) { authentication.cancelGuestSignIn() }
                                }
                            }
                    }
                case .guestRecovery(let needsSignIn), .invitationRecovery(let needsSignIn):
                    guestRecovery(needsSignIn: needsSignIn)
                case .guestImporting:
                    ProgressView(GuestCopy.linking)
                case .sharedBlueprintAuthentication:
                    NavigationStack {
                        AuthenticationView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Back", systemImage: "chevron.left") { sharedBlueprintLinks.dismiss() }
                                }
                            }
                    }
                case .sharedBlueprintLoading, .invitationLoading, .guestLoading, .accountLoading:
                    AccountOnboardingLoadingView()
                case .sharedBlueprintPreview(let token):
                    BlueprintSharedPreviewView(token: token)
                        .id("shared-blueprint-\(token)-\(authentication.currentUser?.id ?? "signed-out")")
                case .invitationAuthentication:
                    NavigationStack {
                        AuthenticationView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Back", systemImage: "chevron.left") { invitations.requiresAuthentication = false }
                                }
                            }
                    }
                case .invitation(let token):
                    NativeInvitationView(token: token).id(token)
                case .authentication:
                    if authentication.isSessionRestorationUnavailable {
                        NavigationStack {
                            AuthenticationView(allowsGuestContinuation: false)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button(AppCopy.Common.back) { restorationSignInRequested = false }
                                    }
                                }
                        }
                    } else {
                        AuthenticationView()
                    }
                case .sessionRestorationRecovery:
                    sessionRestorationRecovery
                case .guestDiscardRecovery:
                    guestDiscardRecovery
                case .accountRecovery:
                    accountPreparationRecovery
                case .accountDeletionCleanup:
                    accountDeletionCleanupRecovery
                case .app:
                    AppRootView()
                case .onboarding:
                    OnboardingView(onCreateWorkspace: finishOnboarding, onSkipCreation: completeOnboarding)
                case .remoteAccount:
                    remoteAccountExperience
                }
            }
            .transition(.opacity)

            if isShowingSplash {
                GatheroryAnimatedSplash(reduceMotion: reduceMotion)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(notificationNavigation)
        .onChange(of: sessionIdentity) { _, _ in
            notificationSessionGeneration = UUID()
            notificationNavigation.destination = nil
            notificationNavigation.attendanceAnnouncement = nil
            completedOnboardingIdentity = nil
            restorationSignInRequested = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasRestoredAuthentication,
                  !authentication.isProcessing, !authentication.isSigningOut,
                  isSessionReady else { return }
            Task {
                guard !authentication.isProcessing, !authentication.isSigningOut,
                      isSessionReady else { return }
                await notifications.activate(identity: authentication.notificationPrincipal)
            }
        }
        .sheet(isPresented: $showsGuestAccount) {
            NavigationStack { LocalGuestAccountView() }
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
        .alert(DeletionCleanupCopy.requestFailedTitle, isPresented: $authentication.accountDeletionNeedsAttention) {
            Button(AppCopy.Common.close, role: .cancel) {}
        } message: { Text(DeletionCleanupCopy.requestFailedHelp) }
        .task {
            SessionLifecycleActions(
                authentication: authentication, library: workspaceLibrary,
                persistence: persistence, cloudSync: cloudSync,
                guestInvitations: guestInvitations, notifications: notifications, imageSafety: imageSafety
            ).install()
            notifications.onRouteIntent = { intent in
                let principal = notifications.activePrincipal
                let generation = notificationSessionGeneration
                Task {
                    guard principal != nil, authentication.notificationPrincipal == principal,
                          generation == notificationSessionGeneration else { return }
                    await openNotification(intent)
                }
            }
            notifications.onRefreshRequested = {
                Task {
                    guard isSessionReady else { return }
                    let principal = authentication.notificationPrincipal
                    if authentication.isAuthenticated { await cloudSync.synchronize(trigger: .backgroundRefresh) }
                    guard authentication.notificationPrincipal == principal else { return }
                    await guestInvitations.refresh(force: true)
                }
            }
            guard isShowingSplash else { return }

            let milliseconds = reduceMotion
                ? LaunchExperienceTiming.reducedMotionMilliseconds
                : LaunchExperienceTiming.standardMilliseconds
            let minimumSplash = Task {
                try? await Task.sleep(for: .milliseconds(milliseconds))
            }

            await authentication.deletionCleanup.retry()
            await authentication.restoreSession()
            hasRestoredAuthentication = true
            await minimumSplash.value
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: LaunchExperienceTiming.exitAnimationSeconds)) {
                isShowingSplash = false
            }
        }
        .task(id: "\(hasRestoredAuthentication)|\(sessionIdentity)|\(authentication.isSessionRestorationUnavailable)|\(authentication.deletionCleanup.blocksEntry)|\(preparationAttempt)") {
            // Never synchronize using a cached profile before its bearer
            // session has resolved to the canonical account identity.
            guard hasRestoredAuthentication, !authentication.deletionCleanup.blocksEntry, !authentication.isSessionRestorationUnavailable,
                  !authentication.guestDiscardNeedsAttention else { return }
            invitations.resetJoinedSession()
            let request = preparationRequest
            await preparation.prepare(request, using: LiveSessionPreparationServices(
                authentication: authentication, library: workspaceLibrary,
                cloudSync: cloudSync, persistence: persistence,
                guestInvitations: guestInvitations, notifications: notifications
            ), isCurrent: {
                // Guest cleanup intentionally removes the profile while the
                // validated account remains the owner of this preparation.
                preparationRequest.identity == request.identity && !authentication.isSigningOut &&
                    !authentication.guestDiscardNeedsAttention && !authentication.deletionCleanup.blocksEntry
            })
        }
    }

    private func openNotification(_ intent: NotificationRouteIntent) async {
        guard !authentication.isProcessing, !authentication.isSigningOut,
              isSessionReady,
              let principal = authentication.notificationPrincipal else { return }
        let generation = notificationSessionGeneration
        let principalGeneration = authentication.principalGeneration
        let previousSync = cloudSync.lastSuccessfulSyncAt
        if authentication.isAuthenticated {
            await cloudSync.synchronize(trigger: .manual)
        }
        await guestInvitations.refresh(force: true)
        guard !Task.isCancelled, generation == notificationSessionGeneration,
              principalGeneration == authentication.principalGeneration,
              !authentication.isProcessing, !authentication.isSigningOut,
              authentication.notificationPrincipal == principal,
              isSessionReady else { return }
        let refreshedPlans = cloudSync.lastSuccessfulSyncAt != previousSync && cloudSync.lastError == nil
        let destination = AuthorizedNotificationDestination.resolve(
            intent,
            workspaces: refreshedPlans ? workspaceLibrary.workspaces : [],
            attendanceEventIDs: guestInvitations.errorMessage == nil ? Set(guestInvitations.events.map(\.id)) : []
        )
        switch destination {
        case .announcement(let workspaceID, let reference, let announcementID):
            guard let workspace = workspaceLibrary.workspaces.first(where: { $0.mainEventID == workspaceID }) else { return }
            guestInvitations.selectedEventID = nil
            workspace.selectEventContext(reference)
            notificationNavigation.destination = NotificationPlanningDestination(
                workspaceID: workspaceID, reference: reference, todoID: nil, announcementID: announcementID
            )
            workspaceLibrary.open(workspace)
        case .attendanceAnnouncement(let eventID, let announcementID):
            workspaceLibrary.closeWorkspace()
            notificationNavigation.attendanceAnnouncement = NotificationAttendanceAnnouncementDestination(
                eventID: eventID, announcementID: announcementID
            )
            guestInvitations.selectedEventID = eventID
        case .planning(let workspaceID, let reference, let todoID):
            guard let workspace = workspaceLibrary.workspaces.first(where: { $0.mainEventID == workspaceID }) else { return }
            guestInvitations.selectedEventID = nil
            workspace.selectEventContext(reference)
            notificationNavigation.destination = NotificationPlanningDestination(
                workspaceID: workspaceID, reference: reference, todoID: todoID
            )
            workspaceLibrary.open(workspace)
        case .attendance(let eventID):
            workspaceLibrary.closeWorkspace()
            guestInvitations.selectedEventID = eventID
        case nil: break
        }
    }

    private func guestRecovery(needsSignIn: Bool) -> some View {
        ContentUnavailableView {
            Label(GuestCopy.linkingFailed, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(needsSignIn
                 ? (authentication.isAuthenticated ? SessionFlowCopy.originalAccountHelp : GuestCopy.finishSavingHelp)
                 : GuestCopy.linkingHelp)
        } actions: {
            if needsSignIn {
                if authentication.isGuestMode {
                    Button(GuestCopy.signInToSave) { authentication.requestGuestSignIn() }
                    Button(GuestCopy.leave, role: .destructive) { showsGuestAccount = true }
                }
            } else { Button(AppCopy.Common.retry) { preparationAttempt += 1 } }
            if authentication.isAuthenticated {
                Button("Sign Out") { Task { await authentication.signOut(keepingPendingChanges: true) } }
            }
        }
    }

    private var sessionRestorationRecovery: some View {
        ContentUnavailableView {
            Label(SessionFlowCopy.restorationTitle, systemImage: "wifi.exclamationmark")
        } description: {
            Text(SessionFlowCopy.restorationHelp)
        } actions: {
            Button(AppCopy.Common.retry) { Task { await authentication.restoreSession() } }
                .buttonStyle(.borderedProminent)
            Button("Sign In") { restorationSignInRequested = true }
        }
        .disabled(authentication.isProcessing)
    }

    private var accountDeletionCleanupRecovery: some View {
        let cleanup = authentication.deletionCleanup
        return ContentUnavailableView {
            Label(DeletionCleanupCopy.title, systemImage: "trash.circle")
        } description: {
            Text(cleanup.journalUnreadable ? DeletionCleanupCopy.unavailableHelp
                 : (cleanup.needsConfirmation
                    ? (authentication.isProcessing ? DeletionCleanupCopy.waitingHelp : DeletionCleanupCopy.interruptedHelp)
                    : (cleanup.record?.phase == .deviceRemovalConfirmed ? DeletionCleanupCopy.deviceRemovalHelp : DeletionCleanupCopy.help)))
        } actions: {
            if authentication.isProcessing || cleanup.isCleaning {
                ProgressView()
            } else if cleanup.needsConfirmation {
                Button(DeletionCleanupCopy.removeFromDevice, role: .destructive) { confirmsDeviceRemoval = true }
            } else {
                Button(AppCopy.Common.retry) {
                    Task {
                        if cleanup.journalUnreadable { cleanup.reload() }
                        await cleanup.retry()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .confirmationDialog(DeletionCleanupCopy.removeTitle, isPresented: $confirmsDeviceRemoval, titleVisibility: .visible) {
            Button(DeletionCleanupCopy.removeFromDevice, role: .destructive) {
                Task { await cleanup.confirmDeviceRemoval() }
            }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: { Text(DeletionCleanupCopy.interruptedHelp) }
    }

    private var guestDiscardRecovery: some View {
        ContentUnavailableView {
            Label(SessionFlowCopy.removalTitle, systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(SessionFlowCopy.removalHelp)
        } actions: {
            Button(AppCopy.Common.retry) {
                Task { try? await authentication.discardGuestSession() }
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(authentication.isProcessing)
    }

    private var accountPreparationRecovery: some View {
        ContentUnavailableView {
            Label("Couldn’t Load Your Account", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(SessionFlowCopy.preparationHelp)
        } actions: {
            Button(AppCopy.Common.retry) { preparationAttempt += 1 }
                .buttonStyle(.borderedProminent)
            Button("Sign Out") { Task { await authentication.signOut(keepingPendingChanges: true) } }
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
            completedOnboardingIdentity = preparationRequest.identity
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                completedOnboardingIdentity = preparationRequest.identity
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
