import SwiftUI

enum MovieNightTourProgression {
    static func nextStep(
        from step: MovieNightTourStep,
        snackIdeaID: UUID?,
        eventIdeaID: UUID?,
        availableIdeaIDs: Set<UUID>,
        lovedIdeaIDs: Set<UUID>,
        chosenIdeaIDs: Set<UUID>,
        linkedEventIdeaIDs: Set<UUID>
    ) -> MovieNightTourStep {
        guard let snackIdeaID, let eventIdeaID,
              availableIdeaIDs.contains(snackIdeaID), availableIdeaIDs.contains(eventIdeaID) else {
            return .completed
        }
        guard step != .completed, step != .previewUsed else { return step }
        // Follow the plan's current truth, including Undo or a revoked choice.
        guard lovedIdeaIDs.contains(snackIdeaID) else { return .ideas }
        guard chosenIdeaIDs.contains(snackIdeaID) else { return .loveIt }
        return linkedEventIdeaIDs.contains(eventIdeaID) ? .schedule : .approve
    }

    static func canComplete(
        snackIdeaID: UUID?, eventIdeaID: UUID?, availableIdeaIDs: Set<UUID>, lovedIdeaIDs: Set<UUID>,
        chosenIdeaIDs: Set<UUID>, linkedEventIdeaIDs: Set<UUID>
    ) -> Bool {
        guard let snackIdeaID, let eventIdeaID,
              availableIdeaIDs.contains(snackIdeaID), availableIdeaIDs.contains(eventIdeaID) else { return false }
        return nextStep(from: .ideas, snackIdeaID: snackIdeaID, eventIdeaID: eventIdeaID,
                 availableIdeaIDs: availableIdeaIDs,
                 lovedIdeaIDs: lovedIdeaIDs, chosenIdeaIDs: chosenIdeaIDs,
                 linkedEventIdeaIDs: linkedEventIdeaIDs) == .schedule
    }
}

/// A compact, account-bound guide that advances only when the installed plan
/// contains the corresponding real user action.
struct MovieNightTourCoach: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(WorkspacePersistenceController.self) private var persistence
    @Environment(\.currentUserAccount) private var account
    @Environment(\.movieNightTourWindowGeometry) private var windowGeometry

    @Binding var selectedTab: WorkspaceTab
    var targetFrames: [MovieNightTourTarget: CGRect] = [:]
    var viewport: CGRect = .zero
    var targetViewport: CGRect = .zero
    var ideasFilter: String? = nil
    @State private var bubbleSize = CGSize(width: 320, height: 190)
    @State private var progress: MovieNightTourProgress?
    @State private var progressOwnerID: String?
    /// Local guide cursor; the receipt continues to track only observed plan actions.
    @State private var browsingStep: MovieNightTourStep?
    @State private var exitRequest: MovieNightTourExitRequest?
    @State private var showsExitPrompt = false
    @State private var removalFailed = false

    private let store = MovieNightTourStore()

    private var ownerID: String? { account?.id }
    private var workspaceSignal: String {
        guard let progress, progress.step != .completed else { return workspace.mainEventID.uuidString }
        let ideas = workspace.ideas.map { "\($0.id)|\($0.eventID?.uuidString ?? "root")|\($0.category.rawValue)|\($0.status.rawValue)" }.joined(separator: ";")
        let responses = workspace.ideaResponses
            .filter { $0.userID == ownerID }
            .map { "\($0.ideaID)|\($0.choice?.rawValue ?? "none")" }
            .joined(separator: ";")
        let scheduled = workspace.timeline.compactMap { item in
            item.linkedIdeaID.map { "\($0)|\(item.id)|\(item.schedulingState?.rawValue ?? "scheduled")" }
        }.joined(separator: ";")
        return "\(workspace.mainEventID)|\(ideas)|\(responses)|\(scheduled)"
    }

    private var progressMatchesWorkspace: Bool {
        guard let ownerID, ownerID == progressOwnerID, let progress else { return false }
        return !ownerID.isEmpty && progress.installedWorkspaceID == workspace.mainEventID
            && !workspace.isMainEventDeleted && !workspace.currentMainEventStatus.isReadOnly
            && workspace.currentViewerMember(for: .main)?.participantRole == .host
            && workspace.currentViewerMember(for: .main)?.invitationStatus == .active
    }

    private var linkedEventIdeaIDs: Set<UUID> {
        Set(workspace.timeline.filter {
            $0.parentEventID == workspace.mainEventID && $0.status == .approved && $0.hasScheduledDate
        }.compactMap(\.linkedIdeaID))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            if progressMatchesWorkspace, let progress, progress.step != .completed {
                floatingGuide(for: displayedStep)
                    .transition(.opacity)
                    .background {
                        if let windowGeometry,
                           let target = target(for: displayedStep),
                           MovieNightTourTabTargetPolicy.navigationControl(for: target) != nil {
                            MovieNightTourTabTargetProbe(target: target, tracker: windowGeometry)
                        }
                    }
            }
        }
        .task(id: "\(ownerID ?? "")|\(workspaceSignal)") {
            refreshProgress()
            reconcileObservedActions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .movieNightTourDidRestart)) { notification in
            guard notification.userInfo?["accountID"] as? String == ownerID,
                  notification.userInfo?["workspaceID"] as? UUID == workspace.mainEventID else { return }
            browsingStep = nil
            refreshProgress()
            reconcileObservedActions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextualPrimerTourDidFinish)) { notification in
            guard notification.userInfo?["accountID"] as? String == ownerID else { return }
            refreshProgress()
        }
        .onChange(of: selectedTab) { _, _ in reconcileObservedActions() }
        .onChange(of: ownerID) { _, _ in
            showsExitPrompt = false
            exitRequest = nil
            removalFailed = false
            browsingStep = nil
            refreshProgress()
        }
        .onChange(of: workspace.mainEventID) { _, _ in
            showsExitPrompt = false
            exitRequest = nil
            removalFailed = false
            browsingStep = nil
            refreshProgress()
        }
        .onChange(of: progress?.step) { _, _ in
            browsingStep = nil
            reconcileObservedActions()
        }
        .alert("Keep your Movie Night event?", isPresented: $showsExitPrompt, presenting: exitRequest) { request in
            Button("Keep event", role: .cancel) { finishExit(request, removingEvent: false) }
                .accessibilityIdentifier("movieNightTour.keepEvent")
            Button("Remove event", role: .destructive) { finishExit(request, removingEvent: true) }
                .accessibilityIdentifier("movieNightTour.removeEvent")
        } message: { _ in
            Text("You can keep your practice event or remove it from your events.")
        }
    }

    private var displayedStep: MovieNightTourStep {
        guard let progress else { return .previewUsed }
        return MovieNightTourNavigationPolicy.boundedStep(
            browsingStep, actualProgress: progress.step
        ) ?? progress.step
    }

    private func target(for step: MovieNightTourStep) -> MovieNightTourTarget? {
        MovieNightTourTargetPolicy.target(
            for: step,
            selectedTab: selectedTab,
            ideasFilter: ideasFilter,
            snackIdeaID: progress?.snackIdeaID,
            eventIdeaID: progress?.eventIdeaID,
            isReviewingEarlier: isReviewingEarlier(step)
        )
    }

    private func targetTitle(_ target: MovieNightTourTarget?) -> String {
        switch target {
        case .idea(let id), .decision(let id): workspace.ideas.first { $0.id == id }?.title ?? ""
        case .ideasFilter: String(localized: "Ideas filter")
        case .exploreTab: ExploreCopy.title
        case .ideasTab: AppCopy.Tab.ideas
        case .decideTab: AppCopy.Tab.decide
        case .homeTab: AppCopy.Tab.home
        case .movieNightBlueprint: String(localized: "Movie Night")
        case .viewport, .discoveryDialog, nil: ""
        }
    }

    @ViewBuilder
    private func floatingGuide(for step: MovieNightTourStep) -> some View {
        let target = target(for: step)
        let width = min(320, max(0, viewport.width - 24))
        let bounds = viewport.insetBy(dx: 12, dy: 12)
        let placement = MovieNightTourOverlayLayout.place(
            target: target.flatMap { targetFrames[$0] }, viewport: bounds,
            bubbleSize: CGSize(width: width, height: bubbleSize.height),
            targetViewport: targetViewport
        )
        ZStack(alignment: .topLeading) {
            if placement.targetIsVisible, !isNativeTabTarget(target),
               let measuredFrame = target.flatMap({ targetFrames[$0] }) {
                let frame = measuredFrame.intersection(targetViewport)
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: String(format: String(localized: "movieNightTour.focus", defaultValue: "Guide focus: %@"), targetTitle(target))))
                    .accessibilityIdentifier("movieNightTour.focus")
                    .accessibilityHidden(isNativeTabTarget(target))
                    .allowsHitTesting(false)
            }
            if let start = placement.pointerStart, let end = placement.pointerEnd {
                MovieNightTourPointer(start: start, end: end)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            coachDialog(for: step)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                .position(x: placement.bubbleFrame.midX, y: placement.bubbleFrame.midY)
                .accessibilityIdentifier("movieNightTour.overlay")
                .accessibilityValue(step.rawValue)
        }
    }

    private func coachDialog(for step: MovieNightTourStep) -> some View {
        let focusedTarget = target(for: step)
        return VStack(alignment: .leading, spacing: 8) {
            Text(message(for: step))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("movieNightTour.instruction")
#if DEBUG
            tabFocusDiagnostic(for: focusedTarget)
#endif
            if removalFailed {
                Text("The practice event could not be removed. Try again or keep it for now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movieNightTour.removal.error")
            }
            MovieNightTourFooter(
                canGoPrevious: MovieNightTourNavigationPolicy.previousStep(from: step) != nil,
                canGoNext: canGoNext(from: step),
                nextIsFinish: MovieNightTourNavigationPolicy.canFinish(
                    from: step,
                    actualProgress: progress?.step ?? .previewUsed,
                    actionsAreComplete: movieIsScheduled
                ),
                onPrevious: { browsePrevious(from: step) },
                onSkip: skipTour,
                onNext: { browseNext(from: step) }
            )
        }
        .padding(14)
        .background { MovieNightTourBackdrop() }
        .accessibilityElement(children: .contain)
    }

    private func message(for step: MovieNightTourStep) -> String {
        switch step {
        case .previewUsed:
            selectedTab == .decide
                ? String(localized: "movieNightTour.intro", defaultValue: "Your Blueprint is now your own plan. Let’s look at its ideas.")
                : String(localized: "Tap Decide to start choosing ideas.")
        case .ideas:
            if isReviewingEarlier(step) {
                String(localized: "Decide is where you share what you like. Your responses are saved.")
            } else if selectedTab != .decide {
                String(localized: "Let's find an idea you love. Open Decide with me.")
            } else if let id = progress?.snackIdeaID, targetFrames[.decision(id)] != nil {
                String(localized: "Swipe right on Popcorn bar to Love It.")
            } else {
                String(localized: "Swipe up through the ideas until you find Popcorn bar.")
            }
        case .loveIt:
            if isReviewingEarlier(step) {
                String(localized: "Liked keeps the ideas you loved together. Your approval is saved.")
            } else if selectedTab != .ideas {
                String(localized: "Your Love It is saved! Let's find it in Ideas.")
            } else if ideasFilter != "liked" {
                String(localized: "Tap the filter and choose Liked to find your favorites.")
            } else {
                String(localized: "Press and hold Popcorn bar, then choose Approve.")
            }
        case .approve:
            if isReviewingEarlier(step) {
                String(localized: "Scheduled ideas appear on your event’s Home tab.")
            } else if selectedTab != .ideas {
                String(localized: "Open Ideas with me to find Watch the movie.")
            } else if ideasFilter != IdeaFilter.all.rawValue {
                String(localized: "Choose All in the filter to find Watch the movie.")
            } else {
                String(localized: "Press and hold Watch the movie, then choose Schedule.")
            }
        case .schedule:
            selectedTab == .home
                ? String(localized: "Your ideas and decisions are saved. Your first plan is ready!")
                : String(localized: "Your activity is scheduled. Open Home to see your plan.")
        case .completed: ""
        }
    }

    private func isReviewingEarlier(_ step: MovieNightTourStep) -> Bool {
        MovieNightTourNavigationPolicy.isReviewingEarlierStep(
            step, actualProgress: progress?.step ?? .previewUsed
        )
    }

    private func canGoNext(from step: MovieNightTourStep) -> Bool {
        guard let progress else { return false }
        if MovieNightTourNavigationPolicy.canFinish(
            from: step, actualProgress: progress.step, actionsAreComplete: movieIsScheduled
        ) { return true }
        if step == .previewUsed { return true }
        if MovieNightTourNavigationPolicy.nextStep(from: step, actualProgress: progress.step) != nil {
            return true
        }
        return selectedTab != requiredTab(for: step)
    }

    private func browsePrevious(from step: MovieNightTourStep) {
        guard let previous = MovieNightTourNavigationPolicy.previousStep(from: step) else { return }
        browsingStep = previous
        navigate(to: requiredTab(for: previous))
    }

    private func browseNext(from step: MovieNightTourStep) {
        guard let progress else { return }
        if MovieNightTourNavigationPolicy.canFinish(
            from: step, actualProgress: progress.step, actionsAreComplete: movieIsScheduled
        ) {
            completeTour()
            return
        }
        if step == .previewUsed {
            browsingStep = .ideas
            navigate(to: .ideas)
            return
        }
        if let next = MovieNightTourNavigationPolicy.nextStep(from: step, actualProgress: progress.step) {
            browsingStep = next
            navigate(to: requiredTab(for: next))
            return
        }
        navigate(to: requiredTab(for: step))
    }

    private func requiredTab(for step: MovieNightTourStep) -> WorkspaceTab {
        switch step {
        case .previewUsed: .home
        case .ideas: .decide
        case .loveIt, .approve, .schedule, .completed: .ideas
        }
    }

    private func isNativeTabTarget(_ target: MovieNightTourTarget?) -> Bool {
        guard let target else { return false }
        return MovieNightTourTabTargetPolicy.labels(for: target) != nil
    }

#if DEBUG
    @ViewBuilder
    private func tabFocusDiagnostic(for target: MovieNightTourTarget?) -> some View {
        if ProcessInfo.processInfo.arguments.contains("-ResetMovieNightTourUITestState"),
           let target, isNativeTabTarget(target), let localFrame = targetFrames[target],
           targetViewport.intersects(localFrame),
           let host = windowGeometry?.windowFrame(for: .viewport) {
            let frame = localFrame.offsetBy(dx: host.minX, dy: host.minY)
            let label = String(format:
                String(localized: "movieNightTour.focus", defaultValue: "Guide focus: %@"),
                targetTitle(target))
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityValue("[\(frame.minX),\(frame.minY),\(frame.width),\(frame.height)]")
                .accessibilityIdentifier("movieNightTour.tabFocus")
                .allowsHitTesting(false)
        }
    }
#endif

    private func navigate(to tab: WorkspaceTab) {
        guard selectedTab != tab else { return }
        selectedTab = tab
    }

    private func refreshProgress() {
        guard let ownerID, !ownerID.isEmpty else {
            progress = nil
            progressOwnerID = nil
            return
        }
        progress = store.progress(accountID: ownerID)
        progressOwnerID = ownerID
    }

    private func reconcileObservedActions() {
        guard progressMatchesWorkspace, let progress, let ownerID else { return }
        var currentStep = progress.step
        if currentStep == .previewUsed, selectedTab != .home { currentStep = .ideas }
        currentStep = MovieNightTourProgression.nextStep(
            from: currentStep,
            snackIdeaID: progress.snackIdeaID,
            eventIdeaID: progress.eventIdeaID,
            availableIdeaIDs: Set(workspace.ideas.map(\.id)),
            lovedIdeaIDs: Set(workspace.ideaResponses.filter { $0.userID == ownerID && $0.choice == .love }.map(\.ideaID)),
            chosenIdeaIDs: Set(workspace.ideas.filter { $0.status == .chosen }.map(\.id)),
            linkedEventIdeaIDs: linkedEventIdeaIDs
        )
        if currentStep != progress.step {
            store.advance(accountID: ownerID, to: currentStep)
            self.progress = store.progress(accountID: ownerID)
            if currentStep == .completed {
                ContextualPrimerStore.announceTourFinished(accountID: ownerID)
            }
        }
    }

    private var movieIsScheduled: Bool {
        MovieNightTourProgression.canComplete(
            snackIdeaID: progress?.snackIdeaID, eventIdeaID: progress?.eventIdeaID,
            availableIdeaIDs: Set(workspace.ideas.map(\.id)),
            lovedIdeaIDs: Set(workspace.ideaResponses.filter { $0.userID == ownerID && $0.choice == .love }.map(\.ideaID)),
            chosenIdeaIDs: Set(workspace.ideas.filter { $0.status == .chosen }.map(\.id)),
            linkedEventIdeaIDs: linkedEventIdeaIDs
        )
    }

    private func advance(to step: MovieNightTourStep) {
        guard let ownerID, progressMatchesWorkspace else { return }
        store.advance(accountID: ownerID, to: step)
        refreshProgress()
        if step == .completed {
            ContextualPrimerStore.announceTourFinished(accountID: ownerID)
        }
    }

    private func completeTour() {
        guard movieIsScheduled else { return }
        requestExit()
    }

    private func skipTour() { requestExit() }

    private func requestExit() {
        guard let ownerID, progressMatchesWorkspace else { return }
        exitRequest = MovieNightTourExitRequest(accountID: ownerID, workspaceID: workspace.mainEventID)
        showsExitPrompt = true
    }

    private func finishExit(_ request: MovieNightTourExitRequest, removingEvent: Bool) {
        guard let account, account.id == request.accountID,
              persistence.activeUserID == request.accountID,
              workspace.mainEventID == request.workspaceID,
              store.progress(accountID: request.accountID)?.installedWorkspaceID == request.workspaceID else {
            exitRequest = nil
            return
        }
        if removingEvent {
            do {
                try MovieNightTourCompletion.removePracticeWorkspace(
                    account: account, workspaceID: request.workspaceID,
                    library: library, persistence: persistence, store: store
                )
            } catch {
                exitRequest = nil
                removalFailed = true
                return
            }
        } else {
            store.advance(accountID: request.accountID, to: .completed)
        }
        exitRequest = nil
        removalFailed = false
        refreshProgress()
        selectedTab = .home
        ContextualPrimerStore.announceTourFinished(accountID: request.accountID)
    }
}

private struct MovieNightTourExitRequest {
    let accountID: String
    let workspaceID: UUID
}

/// A compact footer with full-size native hit targets and a centered skip action.
struct MovieNightTourFooter: View {
    var canGoPrevious: Bool
    var canGoNext: Bool
    var nextIsFinish: Bool = false
    var onPrevious: () -> Void
    var onSkip: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Text(String(localized: "Previous", defaultValue: "Previous"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .disabled(!canGoPrevious)
            .accessibilityLabel(Text(String(localized: "Previous", defaultValue: "Previous")))
            .accessibilityIdentifier("movieNightTour.previous")

            Button(action: onSkip) {
                Text(String(localized: "Skip tour", defaultValue: "Skip tour"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("movieNightTour.skip")

            Button(action: onNext) {
                Text(nextButtonTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .disabled(!canGoNext)
            .accessibilityLabel(Text(nextAccessibilityLabel))
            .accessibilityIdentifier("movieNightTour.next")
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.primary)
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var nextButtonTitle: String {
        nextIsFinish
            ? String(localized: "Finish tour", defaultValue: "Finish tour")
            : String(localized: "Next", defaultValue: "Next")
    }

    private var nextAccessibilityLabel: String { nextButtonTitle }
}

struct MovieNightTourPointer: Shape {
    let start: CGPoint
    let end: CGPoint
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let wing: CGFloat = 7
        path.move(to: CGPoint(x: end.x - wing * cos(angle - .pi / 5), y: end.y - wing * sin(angle - .pi / 5)))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: end.x - wing * cos(angle + .pi / 5), y: end.y - wing * sin(angle + .pi / 5)))
        return path
    }
}
