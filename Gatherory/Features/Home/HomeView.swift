import SwiftUI

struct HomeView: View {
    var homeReselectionTrigger = 0
    var onExitWorkspace: (() -> Void)?

    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isComposingNote = false
    @State private var isPresentingInvitationSharing = false
    @State private var editorTarget: HomeEventEditorTarget?
    @State private var isAddingEventIdea = false
    @State private var addEventIdeaDetent: PresentationDetent = .large
    @State private var openedEventReference: EventReference?
    @State private var visibleScrollTarget: HomeScrollTarget?
    @State private var scrubbedEventIndex: Int?
    @State private var isScrubbingEvents = false
    @State private var pullToCreateProgress: CGFloat = 0
    @State private var isPullToCreateArmed = false
    @State private var pullToCreateHaptic = 0
    @State private var isPullToCreateRegionVisible = false
    @State private var isRestoringFromPullToCreate = false
    @State private var isScrollInteractionActive = false
    @State private var currentScrollOffset: CGFloat = 0
    @State private var scrollInteractionStartOffset: CGFloat?
    @State private var swipeOriginEventReference: EventReference?
    @State private var didUpdateContextForSwipe = false
    @State private var isHandlingHomeReselection = false
    @State private var homeReselectionTask: Task<Void, Never>?
    @State private var eventSwitcherFadeTask: Task<Void, Never>?
    @State private var eventSwitcherOpacity = 0.0
    @State private var pendingDetailRemoval: HomeEventRemovalRequest?
    @State private var isRemovalUnavailable = false
    @Namespace private var invitationTransition

    private let pullToCreateThreshold: CGFloat = 200
    private let pullToCreateItemHeight: CGFloat = 184
    private let pullToCreateRevealInset: CGFloat = 56

    private var pendingJoinCount: Int {
        guard workspace.canManageInvitations(for: workspace.selectedEventReference) else { return 0 }
        return workspace.joinRequestStore.requests(eventID: workspace.selectedEventID, accountID: authentication.currentUser?.id).count
    }

    private func refreshJoinRequests(force: Bool = false) async {
        guard workspace.canManageInvitations(for: workspace.selectedEventReference),
              let accountID = authentication.currentUser?.id else { return }
        await workspace.joinRequestStore.refresh(eventID: workspace.selectedEventID, accountID: accountID, force: force)
    }

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.mainEventStartsAt).day ?? 0, 0)
    }

    private var eventHeroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 720 : 640
    }

    private var mainEventTimingLabel: String {
        switch workspace.currentMainEventStatus {
        case .draft:
            "\(daysRemaining) days away"
        case .ongoing:
            "Happening now"
        case .finished:
            "Past event"
        case .cancelled:
            AppCopy.Lifecycle.cancelled
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    if workspace.isMainEventDeleted {
                        ContentUnavailableView {
                            Label("No Main Event", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("Create the event that anchors this gathering.")
                        } actions: {
                            if workspace.showsPlanningInterface {
                                Button("Create Event", systemImage: "plus") {
                                    editorTarget = .main
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.section)
                    } else {
                        ForEach(workspace.visibleEventContexts, id: \.self) { reference in
                            eventHero(for: reference)
                                .id(HomeScrollTarget.event(reference))
                        }
                    }
                }
                .scrollTargetLayout()

                if workspace.canManageMainEvent, !workspace.isMainEventDeleted {
                    PullToCreateEventIndicator(
                        progress: pullToCreateProgress,
                        isArmed: isPullToCreateArmed
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: pullToCreateItemHeight)
                    .opacity(pullToCreateProgress)
                    .scaleEffect(0.86 + (0.14 * pullToCreateProgress))
                    .offset(y: 24 * (1 - pullToCreateProgress))
                    .accessibilityHidden(pullToCreateProgress <= 0.01)
                    .accessibilityHint("Pull until the progress ring closes, then release")
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await cloudSync.synchronize(trigger: .manual)
            await refreshJoinRequests(force: true)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $visibleScrollTarget, anchor: .center)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .overlay(alignment: .trailing) {
            if workspace.visibleEventContexts.count > 1 {
                eventContextSwitcher
                    // Like a scroll indicator, the rail stays interactive at
                    // rest but becomes visually discoverable through motion.
                    .opacity(eventSwitcherOpacity)
            }
        }
        .toolbar {
            if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }
            }

            if workspace.canManageEvent(workspace.selectedEventReference) {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingInvitationSharing = true
                    } label: {
                        Label("Share Invitation", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            // Decorate the label, not the toolbar control: the
                            // entire button remains the interactive surface.
                            .overlay(alignment: .topTrailing) {
                                if pendingJoinCount > 0 {
                                    JoinRequestCountBadge(count: pendingJoinCount)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .accessibilityHint("Invite people to the selected event")
                    .accessibilityIdentifier("home-share-invitation")
                    .accessibilityValue(pendingJoinCount > 0 ? String(localized: "Join Requests") + ": " + pendingJoinCount.formatted() : "")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if workspace.isMainEventDeleted, workspace.showsPlanningInterface {
                    Button("Create event", systemImage: "plus") {
                        editorTarget = .main
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                } else if workspace.showsPlanningInterface {
                    Button("Send a note", systemImage: "megaphone") {
                        isComposingNote = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .tint(.primary)

                    if workspace.isMainEventContext {
                        Button("Add event", systemImage: "calendar.badge.plus") {
                            addEventIdeaDetent = .large
                            isAddingEventIdea = true
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                        .tint(.primary)
                    }
                }

                AccountToolbarButton(monochrome: true)
            }
        }
        .navigationDestination(item: $openedEventReference) { reference in
            EventInvitationScreen(reference: reference)
                .navigationTitle("Invitation")
                .navigationBarTitleDisplayMode(.inline)
                .appClearNavigationBar()
                .appImageDetailAppearance()
                .modifier(HomeEventRemovalConfirmation(
                    request: $pendingDetailRemoval,
                    isUnavailable: $isRemovalUnavailable,
                    isActive: openedEventReference != nil,
                    onConfirm: confirmRemoval
                ))
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if reference == .main, workspace.showsPlanningInterface {
                            NavigationLink {
                                WorkspaceSettingsView()
                            } label: {
                                Label("Workspace Settings", systemImage: "gearshape")
                                    .labelStyle(.iconOnly)
                            }
                        }

                        if canEdit(reference) || workspace.eventRemovalAction(for: reference) != nil || workspace.canCancelEvent(reference) {
                            Menu(AppCopy.EventRemoval.actions, systemImage: "ellipsis") {
                                eventActions(for: reference)
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
                .navigationTransition(
                    .zoom(sourceID: reference, in: invitationTransition)
                )
        }
        .sheet(isPresented: $isComposingNote) {
            NoteComposerView(event: workspace.selectedEventReference,
                             eventID: workspace.selectedEventID,
                             title: workspace.selectedEventTitle)
                .environment(workspace)
        }
        .fullScreenCover(isPresented: $isPresentingInvitationSharing, onDismiss: {
            Task { await refreshJoinRequests(force: true) }
        }) {
            CollaborationInviteView()
                .environment(workspace)
        }
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                EventEditorView(mode: editorMode(for: target))
            }
            .environment(workspace)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAddingEventIdea) {
            NavigationStack {
                IdeaEditorView(initialCategory: .event) { detent in
                    withAnimation(.snappy) {
                        addEventIdeaDetent = detent
                    }
                }
            }
            .environment(workspace)
            .presentationDetents([.medium, .large], selection: $addEventIdeaDetent)
            .presentationDragIndicator(.visible)
        }
        .task(id: "\(workspace.selectedEventID)|\(authentication.currentUser?.id ?? "")|\(scenePhase)") {
            guard scenePhase == .active else { return }
            // Let fast card swipes settle; navigation never waits for the network.
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await refreshJoinRequests()
        }
        .task {
            // ScrollPosition needs the target layout to exist before it can
            // resolve a non-leading event during the initial presentation.
            await Task.yield()
            visibleScrollTarget = .event(workspace.selectedEventReference)
        }
        .onScrollGeometryChange(for: HomeScrollGeometry.self) { geometry in
            let itemTop = geometry.contentSize.height
                - AppTheme.Layout.screenBottom
                - pullToCreateItemHeight
            return HomeScrollGeometry(
                offset: geometry.contentOffset.y,
                pullToCreateDistance: max(
                    geometry.visibleRect.maxY - itemTop - pullToCreateRevealInset,
                    0
                )
            )
        } action: { _, geometry in
            currentScrollOffset = geometry.offset
            isPullToCreateRegionVisible = geometry.pullToCreateDistance > 0
            updateEventSwitcherReveal(offset: geometry.offset)
            updateEventContextAtSwipeStart(offset: geometry.offset)
            updatePullToCreate(distance: geometry.pullToCreateDistance)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if newPhase == .interacting {
                homeReselectionTask?.cancel()
                isHandlingHomeReselection = false
                isScrollInteractionActive = true
                scrollInteractionStartOffset = currentScrollOffset
                swipeOriginEventReference = visibleEventReference ?? workspace.selectedEventReference
                didUpdateContextForSwipe = false
                eventSwitcherFadeTask?.cancel()
                eventSwitcherFadeTask = nil
                eventSwitcherOpacity = 0
            }

            if oldPhase == .interacting, newPhase != .interacting {
                isScrollInteractionActive = false
                completePullToCreateIfNeeded()
                restoreLastEventAfterPullIfNeeded()
            }

            guard newPhase == .idle,
                  !isScrubbingEvents,
                  !isHandlingHomeReselection else { return }

            if isPullToCreateRegionVisible {
                restoreLastEventAfterPullIfNeeded()
                return
            }

            commitVisibleScrollTarget()
            scrollInteractionStartOffset = nil
            swipeOriginEventReference = nil
            didUpdateContextForSwipe = false
            scheduleEventSwitcherFade()
        }
        .onChange(of: workspace.selectedEventReference) { _, reference in
            let target = HomeScrollTarget.event(reference)
            guard !isHandlingHomeReselection,
                  !isScrollInteractionActive,
                  !isScrubbingEvents,
                  visibleScrollTarget != target else { return }
            withAnimation(.snappy) {
                visibleScrollTarget = target
            }
        }
        .onChange(of: homeReselectionTrigger) { _, _ in
            handleHomeReselection()
        }
        .sensoryFeedback(.selection, trigger: scrubbedEventIndex)
        .sensoryFeedback(.success, trigger: pullToCreateHaptic)
        .onDisappear {
            homeReselectionTask?.cancel()
            eventSwitcherFadeTask?.cancel()
        }
    }

    private func eventHero(for reference: EventReference) -> some View {
        GeometryReader { proxy in
            Button {
                openedEventReference = reference
            } label: {
                ZStack(alignment: .bottom) {
                    eventArtwork(for: reference)
                        .frame(width: proxy.size.width, height: eventHeroHeight)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.34),
                            .init(color: .black.opacity(reduceTransparency ? 0.24 : 0.08), location: 0.52),
                            .init(color: .black.opacity(reduceTransparency ? 0.76 : 0.46), location: 0.76),
                            .init(color: .black.opacity(reduceTransparency ? 0.90 : 0.70), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: AppTheme.Spacing.standard) {
                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 120 : 220)

                        if !eventPeople(for: reference).isEmpty {
                            attendeeSummary(for: reference)
                        }

                        VStack(spacing: 8) {
                            Text(title(for: reference))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(
                                date(for: reference),
                                format: .dateTime.weekday(.wide).month(.wide).day().year()
                            )
                            .font(.headline)
                            .multilineTextAlignment(.center)

                            if let eventLocation = location(for: reference) {
                                Label(eventLocation.title, systemImage: "mappin.and.ellipse")
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(2)
                                    .accessibilityLabel("Location, \(eventLocation.formatted)")
                            }

                            Text(secondaryLabel(for: reference))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
                    }
                    .foregroundStyle(.white)
                    .padding(AppTheme.Spacing.spacious)

                    VStack {
                        HStack {
                            EventContextStatusBadge(
                                title: status(for: reference).title,
                                symbol: status(for: reference).symbol,
                                context: reference == .main ? "Main event" : "Subevent"
                            )

                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(AppTheme.Spacing.spacious)
                }
                .frame(width: proxy.size.width, height: eventHeroHeight)
                .clipped()
                .matchedTransitionSource(id: reference, in: invitationTransition)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens event details")
            .accessibilityLabel(
                "\(title(for: reference)), \(date(for: reference).formatted(date: .long, time: .omitted)), " +
                (location(for: reference).map { "at \($0.formatted). " } ?? "") +
                secondaryLabel(for: reference)
            )
            .frame(width: proxy.size.width, height: eventHeroHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 0.5)
            }
            .accessibilityElement(children: .contain)
        }
        .frame(height: eventHeroHeight)
    }

    @ViewBuilder
    private func eventActions(for reference: EventReference) -> some View {
        if canEdit(reference) {
            Button("Edit Event", systemImage: "pencil") {
                editorTarget = editorTarget(for: reference)
            }
        }
        if workspace.canCancelEvent(reference) {
            Button(AppCopy.Lifecycle.cancelEvent, systemImage: "calendar.badge.minus", role: .destructive) {
                pendingDetailRemoval = HomeEventRemovalRequest(reference: reference, action: .cancelEvent, title: title(for: reference))
            }
        }
        if let action = workspace.eventRemovalAction(for: reference) {
            if canEdit(reference) { Divider() }
            Button(action.title, systemImage: action.symbol, role: .destructive) {
                pendingDetailRemoval = HomeEventRemovalRequest(
                    reference: reference, action: action, title: title(for: reference)
                )
            }
        }
    }

    private func confirmRemoval(_ request: HomeEventRemovalRequest) {
        pendingDetailRemoval = nil
        let changed = request.action == .cancelEvent ? workspace.cancelEvent(request.reference)
            : workspace.removeEventFromHome(request.reference, expecting: request.action)
        guard changed else {
            isRemovalUnavailable = true
            return
        }
        if openedEventReference == request.reference { openedEventReference = nil }
        scrubbedEventIndex = nil
        isScrubbingEvents = false
        pullToCreateProgress = 0
        isPullToCreateArmed = false
        visibleScrollTarget = workspace.isMainEventDeleted ? nil : .event(workspace.selectedEventReference)
    }

    @ViewBuilder
    private func eventArtwork(for reference: EventReference) -> some View {
        let item = timelineItem(for: reference)
        let category = item?.category ?? .ceremony

        MediaArtwork(
            imageData: imageSafety.visibleImageData(reference == .main ? workspace.mainEventImageData : item?.imageData,
                assetID: reference == .main ? workspace.mainEventMediaAssetID : item?.mediaAssetID),
            remoteURL: nil,
            symbol: reference == .main ? IdeaCategory.event.symbol : category.symbol,
            colors: reference == .main ? IdeaCategory.event.artworkColors : category.artworkColors,
            accent: reference == .main ? IdeaCategory.event.artworkAccent : category.artworkAccent,
            ambientBlurRadius: 10,
            progressiveBlurRadius: 24,
            blurStart: 0.48
        )
    }

    private func attendeeSummary(for reference: EventReference) -> some View {
        let people = eventPeople(for: reference)
        let confirmedPeople = people.filter { $0.attendance == .going }
        let displayedPeople = confirmedPeople.isEmpty ? people : confirmedPeople

        return VStack(spacing: 8) {
            HStack(spacing: -10) {
                ForEach(displayedPeople.prefix(5)) { member in
                    ParticipantAvatarView(member: member, size: 40, style: .hero)
                }
            }

            Text(eventPeopleLabel(confirmedCount: confirmedPeople.count, totalCount: people.count))
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private func eventPeople(for reference: EventReference) -> [WorkspaceMember] {
        workspace.participants(for: reference)
    }

    private func eventPeopleLabel(confirmedCount: Int, totalCount: Int) -> String {
        if confirmedCount > 0 {
            return confirmedCount == 1 ? "1 person going" : "\(confirmedCount) people going"
        }

        return totalCount == 1 ? "1 person invited" : "\(totalCount) people invited"
    }

    private var eventContextSwitcher: some View {
        EventContextSwitcher(
            references: workspace.visibleEventContexts,
            selectedReference: visibleEventReference ?? workspace.selectedEventReference,
            previewIndex: scrubbedEventIndex,
            title: title(for:),
            date: date(for:),
            onPreview: previewEvent(at:),
            onCommit: commitScrubbedEvent(at:)
        )
    }

    private var visibleEventReference: EventReference? {
        guard case .some(.event(let reference)) = visibleScrollTarget else { return nil }
        return reference
    }

    private func handleHomeReselection() {
        homeReselectionTask?.cancel()
        isScrubbingEvents = false
        scrubbedEventIndex = nil
        isHandlingHomeReselection = true

        let activeReference = visibleEventReference ?? workspace.selectedEventReference
        let targetReference: EventReference = if activeReference == .main {
            workspace.currentOrNextChildEventReference() ?? workspace.visibleEventContexts.first ?? .main
        } else {
            .main
        }

        workspace.selectEventContext(targetReference)
        // A selected system tab performs its own scroll-to-top action. Clear
        // the binding first, then restore our shortcut destination after that
        // action so the event jump wins even when it was already selected.
        visibleScrollTarget = nil

        homeReselectionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) {
                visibleScrollTarget = .event(targetReference)
            }

            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            isHandlingHomeReselection = false
            homeReselectionTask = nil
        }
    }

    private func previewEvent(at index: Int) {
        let references = workspace.visibleEventContexts
        guard references.indices.contains(index) else { return }

        revealEventSwitcher()
        isScrubbingEvents = true
        guard scrubbedEventIndex != index else { return }
        scrubbedEventIndex = index
        withAnimation(.snappy(duration: 0.22)) {
            visibleScrollTarget = .event(references[index])
        }
    }

    private func commitScrubbedEvent(at index: Int) {
        let references = workspace.visibleEventContexts
        guard references.indices.contains(index) else {
            isScrubbingEvents = false
            scrubbedEventIndex = nil
            return
        }

        let reference = references[index]
        visibleScrollTarget = .event(reference)
        workspace.selectEventContext(reference)
        isScrubbingEvents = false
        scrubbedEventIndex = nil
        scheduleEventSwitcherFade()
    }

    private func updateEventSwitcherReveal(offset: CGFloat) {
        guard workspace.visibleEventContexts.count > 1,
              isScrollInteractionActive,
              let startOffset = scrollInteractionStartOffset else { return }

        let progress = min(abs(offset - startOffset) / 72, 1)
        guard progress > eventSwitcherOpacity else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            eventSwitcherOpacity = progress
        }
    }

    private func revealEventSwitcher() {
        guard workspace.visibleEventContexts.count > 1 else { return }
        eventSwitcherFadeTask?.cancel()
        eventSwitcherFadeTask = nil

        withAnimation(.easeOut(duration: 0.16)) {
            eventSwitcherOpacity = 1
        }
    }

    private func scheduleEventSwitcherFade() {
        guard eventSwitcherOpacity > 0 else { return }
        eventSwitcherFadeTask?.cancel()

        eventSwitcherFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled, !isScrollInteractionActive, !isScrubbingEvents else { return }

            withAnimation(.easeOut(duration: 0.28)) {
                eventSwitcherOpacity = 0
            }
        }
    }

    private func commitVisibleScrollTarget() {
        guard case .some(.event(let reference)) = visibleScrollTarget else { return }
        workspace.selectEventContext(reference)
    }

    private func updateEventContextAtSwipeStart(offset: CGFloat) {
        guard isScrollInteractionActive,
              !isScrubbingEvents,
              !didUpdateContextForSwipe,
              let startOffset = scrollInteractionStartOffset,
              let originReference = swipeOriginEventReference else { return }

        let delta = offset - startOffset
        guard abs(delta) >= 8 else { return }

        let references = workspace.visibleEventContexts
        guard let originIndex = references.firstIndex(of: originReference) else { return }

        let destinationIndex = delta > 0 ? originIndex + 1 : originIndex - 1
        didUpdateContextForSwipe = true

        guard references.indices.contains(destinationIndex) else { return }
        workspace.selectEventContext(references[destinationIndex])
    }

    private func updatePullToCreate(distance: CGFloat) {
        guard workspace.canManageMainEvent, isScrollInteractionActive else { return }

        let progress = min(max(distance / pullToCreateThreshold, 0), 1)
        let wasArmed = isPullToCreateArmed

        pullToCreateProgress = progress
        isPullToCreateArmed = progress >= 1

        if isPullToCreateArmed, !wasArmed {
            pullToCreateHaptic += 1
        }
    }

    private func completePullToCreateIfNeeded() {
        let shouldCreate = isPullToCreateArmed && pullToCreateProgress >= 1
        resetPullToCreate()
        guard shouldCreate else { return }

        Task { @MainActor in
            await Task.yield()
            addEventIdeaDetent = .large
            isAddingEventIdea = true
        }
    }

    private func resetPullToCreate() {
        pullToCreateProgress = 0
        isPullToCreateArmed = false
    }

    private func restoreLastEventAfterPullIfNeeded() {
        guard isPullToCreateRegionVisible,
              !isRestoringFromPullToCreate,
              let lastReference = workspace.visibleEventContexts.last else { return }

        isRestoringFromPullToCreate = true
        let target = HomeScrollTarget.event(lastReference)

        // Reassigning the same ScrollPosition ID is ignored. Clear it for one
        // update so releasing the pull always settles on the final event card.
        visibleScrollTarget = nil

        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy) {
                visibleScrollTarget = target
            }

            try? await Task.sleep(for: .milliseconds(350))
            isPullToCreateRegionVisible = false
            isRestoringFromPullToCreate = false
        }
    }

    private func timelineItem(for reference: EventReference) -> TimelineItem? {
        guard case .subevent(let id) = reference else { return nil }
        return workspace.timeline.first(where: { $0.id == id })
    }

    private func title(for reference: EventReference) -> String {
        reference == .main ? workspace.title : timelineItem(for: reference)?.title ?? "Event"
    }

    private func date(for reference: EventReference) -> Date {
        reference == .main ? workspace.mainEventStartsAt : timelineItem(for: reference)?.scheduledAt ?? workspace.mainEventStartsAt
    }

    private func location(for reference: EventReference) -> EventLocation? {
        reference == .main ? workspace.mainEventLocation : timelineItem(for: reference)?.eventLocation
    }

    private func secondaryLabel(for reference: EventReference) -> String {
        if reference == .main { return mainEventTimingLabel }
        guard let item = timelineItem(for: reference) else { return "Subevent" }
        return item.purpose == .planning ? "Planning & Scouting" : "Part of the Event"
    }

    private func status(for reference: EventReference) -> (title: String, symbol: String) {
        if reference == .main {
            return (workspace.currentMainEventStatus.title, workspace.currentMainEventStatus.symbol)
        }
        guard let item = timelineItem(for: reference) else { return ("Event", "calendar") }
        return (item.status.title, item.status.symbol)
    }

    private func canEdit(_ reference: EventReference) -> Bool {
        switch reference {
        case .main:
            workspace.canManageMainEvent
        case .subevent:
            workspace.canManageEvent(reference)
        case .idea:
            false
        }
    }

    private func editorTarget(for reference: EventReference) -> HomeEventEditorTarget? {
        switch reference {
        case .main: .main
        case .subevent(let id): .subevent(id)
        case .idea: nil
        }
    }

    private func editorMode(for target: HomeEventEditorTarget) -> EventEditorMode {
        switch target {
        case .main:
            .main
        case .subevent(let id):
            .subevent(workspace.timeline.first(where: { $0.id == id }))
        }
    }

}

private struct HomeEventRemovalRequest {
    let reference: EventReference
    let action: EventRemovalAction
    let title: String
}

/// A confirmation belongs to the visible screen, not its offscreen navigation parent.
/// Only event details presents removal; Home remains a browsing surface.
private struct HomeEventRemovalConfirmation: ViewModifier {
    @Binding var request: HomeEventRemovalRequest?
    @Binding var isUnavailable: Bool
    var isActive: Bool
    var onConfirm: (HomeEventRemovalRequest) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                request?.title ?? AppCopy.EventRemoval.actions,
                isPresented: Binding(
                    get: { isActive && request != nil },
                    set: { if isActive && !$0 { request = nil } }
                ),
                presenting: request
            ) { request in
                Button(request.action.title, role: .destructive) { onConfirm(request) }
                Button(AppCopy.Common.cancel, role: .cancel) {}
            } message: { request in
                Text(request.action.confirmationMessage)
            }
            .alert(
                AppCopy.EventRemoval.unavailableTitle,
                isPresented: Binding(
                    get: { isActive && isUnavailable },
                    set: { if isActive { isUnavailable = $0 } }
                )
            ) {
                Button(AppCopy.Common.done, role: .cancel) {}
            } message: {
                Text(AppCopy.EventRemoval.unavailableMessage)
            }
    }
}

private enum HomeScrollTarget: Hashable {
    case event(EventReference)
}

private struct HomeScrollGeometry: Equatable {
    let offset: CGFloat
    let pullToCreateDistance: CGFloat
}

private struct PullToCreateEventIndicator: View {
    let progress: CGFloat
    let isArmed: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.22), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AppTheme.ColorToken.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                if isArmed {
                    Circle()
                        .fill(AppTheme.ColorToken.accent)
                        .padding(5)
                }

                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        isArmed ? AppTheme.ColorToken.onAccent : AppTheme.ColorToken.accent
                    )
                    .symbolEffect(.bounce, value: isArmed)
            }
            .frame(width: 54, height: 54)

            VStack(spacing: 2) {
                Text(isArmed ? "Release to Add Event Idea" : "Add an Event Idea")
                    .font(.headline)

                Text("Keep pulling to propose what comes next.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 290)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isArmed ? "Release to add an event idea" : "Pull to add an event idea")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// A compact event index inspired by Camera Control. Its tapered housing docks
/// to the trailing edge, while candle marks communicate the current event and
/// its neighbors without competing with the invitation artwork.
private struct EventContextSwitcher: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let references: [EventReference]
    let selectedReference: EventReference
    let previewIndex: Int?
    let title: (EventReference) -> String
    let date: (EventReference) -> Date
    let onPreview: (Int) -> Void
    let onCommit: (Int) -> Void

    private var currentIndex: Int {
        if let previewIndex, references.indices.contains(previewIndex) {
            return previewIndex
        }
        return references.firstIndex(of: selectedReference) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                ZStack(alignment: .trailing) {
                    EventIndexDockShape()
                        .fill(colorScheme == .light ? .thickMaterial : .regularMaterial)
                        .overlay {
                            EventIndexDockShape()
                                .stroke(
                                    Color.primary.opacity(colorScheme == .light ? 0.26 : 0.18),
                                    lineWidth: 0.5
                                )
                        }

                    VStack(spacing: 0) {
                        ForEach(references.indices, id: \.self) { index in
                            let isSelected = index == currentIndex

                            HStack(spacing: 0) {
                                Spacer(minLength: 0)

                                EventIndexCandle()
                                    .fill(
                                        isSelected
                                            ? AppTheme.ColorToken.accent
                                            : Color.primary.opacity(candleOpacity(at: index))
                                    )
                                    .frame(
                                        width: candleWidth(at: index),
                                        height: isSelected ? 6 : 4
                                    )
                                    .animation(
                                        reduceMotion ? nil : .snappy(duration: 0.22),
                                        value: currentIndex
                                    )
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.trailing, 2)
                }
                // Keep the visible control entirely in the page gutter. The
                // invitation cards use the same horizontal inset, so the dock
                // meets their outside edge instead of floating over artwork.
                .frame(width: AppTheme.Layout.screenHorizontal)
            }
            // GeometryReader provides the 44-point interaction lane, but a
            // ZStack otherwise adopts its child's narrow width. Expand it
            // explicitly so the visible dock is aligned to the lane's—and
            // therefore the device's—trailing edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        onPreview(index(at: value.location.y, height: proxy.size.height))
                    }
                    .onEnded { value in
                        onCommit(index(at: value.location.y, height: proxy.size.height))
                    }
            )
        }
        // The visual dock is deliberately narrow, but this keeps its drag
        // target at Apple's recommended minimum size.
        .frame(width: AppTheme.Layout.minimumTouchTarget, height: 196)
        .overlay(alignment: .trailing) {
            if let previewIndex, references.indices.contains(previewIndex) {
                let reference = references[previewIndex]
                eventDateBubble(for: reference)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: previewIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Event switcher")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tap or drag along the rail to select an event")
        .accessibilityAdjustableAction { direction in
            let nextIndex: Int
            switch direction {
            case .increment:
                nextIndex = min(currentIndex + 1, references.count - 1)
            case .decrement:
                nextIndex = max(currentIndex - 1, 0)
            @unknown default:
                return
            }
            onPreview(nextIndex)
            onCommit(nextIndex)
        }
    }

    private var accessibilityValue: String {
        guard references.indices.contains(currentIndex) else { return "No event" }
        let reference = references[currentIndex]
        return "\(title(reference)), \(currentIndex + 1) of \(references.count)"
    }

    private func eventDateBubble(for reference: EventReference) -> some View {
        Text(date(reference), format: .dateTime.month(.abbreviated).day().year())
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(width: 164)
            .frame(minHeight: 32)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
            }
            .offset(x: -AppTheme.Layout.minimumTouchTarget)
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
            .allowsHitTesting(false)
    }

    private func candleWidth(at index: Int) -> CGFloat {
        switch abs(index - currentIndex) {
        case 0: AppTheme.Layout.screenHorizontal - 2
        case 1: 8
        default: 4
        }
    }

    private func candleOpacity(at index: Int) -> Double {
        abs(index - currentIndex) == 1 ? 0.62 : 0.34
    }

    private func index(at yPosition: CGFloat, height: CGFloat) -> Int {
        guard !references.isEmpty, height > 0 else { return 0 }
        let clampedY = min(max(yPosition, 0), height - 0.001)
        return min(Int((clampedY / height) * CGFloat(references.count)), references.count - 1)
    }
}

/// A horizontal mark that is narrower toward the center of the display and
/// fuller at the screen edge. The curved ends keep the transition soft.
private struct EventIndexCandle: Shape {
    func path(in rect: CGRect) -> Path {
        let leadingHalfHeight = rect.height * 0.28
        let midpoint = rect.midY
        let radius = min(rect.height / 2, 3)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: midpoint - leadingHalfHeight))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: midpoint),
            control1: CGPoint(x: rect.minX, y: midpoint - leadingHalfHeight),
            control2: CGPoint(x: rect.minX, y: midpoint - leadingHalfHeight / 2)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: midpoint + leadingHalfHeight),
            control1: CGPoint(x: rect.minX, y: midpoint + leadingHalfHeight / 2),
            control2: CGPoint(x: rect.minX, y: midpoint + leadingHalfHeight)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// A rounded trapezoid whose full-height side sits at the screen edge and
/// whose shorter side faces inward toward the event content.
private struct EventIndexDockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let taper = min(rect.height * 0.08, 14)
        let innerRadius = min(rect.width * 0.18, 4)
        let inverseRadius = min(rect.width * 0.36, 8)

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - inverseRadius, y: rect.minY + inverseRadius),
            control1: CGPoint(x: rect.maxX, y: rect.minY + inverseRadius * 0.55),
            control2: CGPoint(
                x: rect.maxX - inverseRadius * 0.45,
                y: rect.minY + inverseRadius
            )
        )
        path.addLine(to: CGPoint(x: rect.minX + innerRadius, y: rect.minY + taper))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + taper + innerRadius),
            control: CGPoint(x: rect.minX, y: rect.minY + taper)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - taper - innerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + innerRadius, y: rect.maxY - taper),
            control: CGPoint(x: rect.minX, y: rect.maxY - taper)
        )
        path.addLine(
            to: CGPoint(x: rect.maxX - inverseRadius, y: rect.maxY - inverseRadius)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(
                x: rect.maxX - inverseRadius * 0.45,
                y: rect.maxY - inverseRadius
            ),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - inverseRadius * 0.55)
        )
        path.closeSubpath()
        return path
    }
}

private enum HomeEventEditorTarget: Identifiable {
    case main
    case subevent(UUID)

    var id: String {
        switch self {
        case .main: "main"
        case .subevent(let id): "subevent-\(id.uuidString)"
        }
    }
}

private struct EventContextStatusBadge: View {
    let title: String
    let symbol: String
    let context: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(.ultraThinMaterial, in: Capsule())
            .appImageOverlayAppearance()
            .accessibilityLabel("\(context) status: \(title)")
    }
}

private struct MainEventEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var status: MainEventStatus = .draft
    @State private var startsAt = Date.now
    @State private var endsAt: Date?
    @State private var isAllDay = false
    @State private var timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
    @State private var eventLocation: EventLocation?
    @State private var imageData: Data?
    @State private var dressCode = ""
    @State private var message = ""
    @State private var isEditingDateAndTime = false
    @State private var isEditingLocation = false
    @State private var isConfirmingDeletion = false
    @State private var didLoad = false

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("Event") {
                TextField("Event name", text: $title)
                    .textInputAutocapitalization(.words)

                Picker("Status", selection: $status) {
                    ForEach(MainEventStatus.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }

                Text(status.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Cover") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: "calendar.badge.plus",
                    fallbackColors: IdeaCategory.event.artworkColors,
                    fallbackAccent: IdeaCategory.event.artworkAccent,
                    suggestedConcept: "Artwork for \(trimmedTitle.isEmpty ? "our gathering" : trimmedTitle)"
                )
            }

            Section {
                Button {
                    isEditingDateAndTime = true
                } label: {
                    EventScheduleRow(
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
                .buttonStyle(.plain)
            } header: {
                Text("Event Window")
            } footer: {
                Text("The event window also includes approved schedule items, including a later afterparty.")
            }

            Section {
                Button {
                    isEditingLocation = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            if let eventLocation {
                                Text(eventLocation.title)
                                    .foregroundStyle(.primary)

                                if !eventLocation.detail.isEmpty {
                                    Text(eventLocation.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            } else {
                                Text("Add Location")
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Location")
            } footer: {
                Text("Optional. Guests only see a location after you add one.")
            }

            Section("Invitation Details") {
                TextField("Dress code (optional)", text: $dressCode)
                    .textInputAutocapitalization(.sentences)

                TextEditor(text: $message)
                    .frame(minHeight: 120, alignment: .topLeading)
                    .accessibilityLabel("Message to guests")
                    .onChange(of: message) { _, newValue in
                        if newValue.count > 750 {
                            message = String(newValue.prefix(750))
                        }
                    }

                Text("\(message.count)/750")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if workspace.canDeleteMainEvent && !workspace.isMainEventDeleted {
                Section {
                    Button("Delete Event", systemImage: "trash", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                } footer: {
                    Text("A main event can only be deleted while it is still a draft.")
                }
            }
        }
        .navigationTitle(workspace.isMainEventDeleted ? "New Event" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(workspace.isMainEventDeleted ? "Add" : "Save") {
                    workspace.updateMainEvent(
                        title: trimmedTitle,
                        status: status,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier,
                        eventLocation: eventLocation,
                        imageData: imageData,
                        dressCode: dressCode.trimmingCharacters(in: .whitespacesAndNewlines),
                        message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier
            ) { updatedStart, updatedEnd, updatedAllDay, updatedTimeZone in
                startsAt = updatedStart
                endsAt = updatedEnd
                isAllDay = updatedAllDay
                timeZoneIdentifier = updatedTimeZone
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingLocation) {
            EventLocationEditorView(location: eventLocation) { updatedLocation in
                eventLocation = updatedLocation
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Event", role: .destructive) {
                workspace.deleteMainEvent()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also removes its schedule and shared event moments.")
        }
        .task {
            guard !didLoad else { return }
            title = workspace.title
            status = workspace.mainEventStatus
            startsAt = workspace.mainEventStartsAt
            endsAt = workspace.mainEventEndsAt
            isAllDay = workspace.mainEventIsAllDay
            timeZoneIdentifier = workspace.mainEventTimeZoneIdentifier
            eventLocation = workspace.mainEventLocation
            imageData = workspace.mainEventImageData
            dressCode = workspace.dressCode
            message = workspace.eventMessage
            didLoad = true
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(PlanningWorkspace.sample)
    }
}
