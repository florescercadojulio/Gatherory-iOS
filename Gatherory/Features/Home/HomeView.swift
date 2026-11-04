import SwiftUI

struct HomeEventContextPresentation {
    enum Kind {
        case mainEvent
        case subevent
    }

    let kind: Kind
    let statusTitle: String
    let statusSymbol: String

    var contextTitle: String {
        switch kind {
        case .mainEvent: String(localized: "Main event")
        case .subevent: String(localized: "Subevent")
        }
    }

    var accessibilityLabel: String {
        "\(contextTitle), \(statusTitle)"
    }

    func parentContextTitle(mainEventTitle: String, mainEventIsVisible: Bool) -> String? {
        guard case .subevent = kind, mainEventIsVisible else { return nil }
        return String(localized: "Part of \(mainEventTitle)")
    }

    func cardAccessibilityLabel(
        title: String,
        date: String,
        location: String?,
        subtitle: String?,
        parentContext: String? = nil
    ) -> String {
        [title, contextTitle, statusTitle, parentContext, date, location.map { "at \($0)" }, subtitle]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct HomeInvitationShareRequest: Identifiable {
    let reference: EventReference
    let accountID: String?
    let localGuestProfileID: UUID?
    let principalGeneration: UInt64
    let workspaceID: UUID

    var id: String { "\(reference.id)-\(principalGeneration)" }
}

private struct HomeEventManagementRoute: Identifiable, Hashable {
    let id = UUID()
    let reference: EventReference
    let initialDestination: EventManagementDestination?
}

struct HomeView: View {
    var homeReselectionTrigger = 0
    var onExitWorkspace: (() -> Void)?

    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication: AuthenticationSession?
    @Environment(ImageSafetyStore.self) private var imageSafety
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSavingBlueprint = false
    @State private var viewportHeight: CGFloat = 0
    @State private var isPresentingInvitationSharing = false
    @State private var detailInvitationShareRequest: HomeInvitationShareRequest?
    @State private var eventManagementRoute: HomeEventManagementRoute?
    @State private var csvExportRequest: EventCSVExportRequest?
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
    @AppStorage(HomeEventLayout.preferenceKey) private var persistedHomeLayout = HomeEventLayout.overview.rawValue

    private var homeLayout: HomeEventLayout {
        HomeEventLayout(persistedValue: persistedHomeLayout)
    }

    private var homeEventContexts: [EventReference] {
        let projection = HomeEventsOverviewProjection(workspace: workspace)
        return (projection.mainEventIsVisible ? [.main] : [])
            + projection.childEvents.map { .subevent($0.id) }
    }

    private let pullToCreateThreshold: CGFloat = 200
    private let pullToCreateItemHeight: CGFloat = 184
    private let pullToCreateRevealInset: CGFloat = 56

    private var daysRemaining: Int {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: workspace.mainEventTimeZoneIdentifier) ?? .autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        let eventDay = calendar.startOfDay(for: workspace.mainEventStartsAt)
        return max(calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0, 0)
    }

    private var eventHeroHeight: CGFloat {
        LayoutDimensions.heroHeight(availableHeight: viewportHeight,
                                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var mainEventTimingLabel: String {
        if workspace.isScopedEvent, !workspace.mainEventHasScheduledDate {
            return String(localized: "Date to be decided")
        }
        return switch workspace.currentMainEventStatus {
        case .draft:
            AppCopy.Home.daysAway(daysRemaining)
        case .ongoing:
            String(localized: "Happening now")
        case .finished:
            String(localized: "Past event")
        case .cancelled:
            AppCopy.Lifecycle.cancelled
        }
    }

    var body: some View {
        Group {
            if homeLayout == .cards {
                cardsScrollView
            } else if workspace.isMainEventDeleted {
                noMainEventPlaceholder
            } else {
                HomeEventsOverviewView(
                    actions: { reference in
                        eventActions(for: reference, includesDestructiveActions: false)
                    },
                    onOpenEvent: openEvent,
                    onManageEvent: { presentEventManagement(for: $0) },
                    onRefresh: {
                        await cloudSync.synchronize(trigger: .manual)
                    },
                    transitionNamespace: invitationTransition
                )
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle(workspace.isMainEventDeleted ? String(localized: "Home") : workspace.selectedEventTitle)
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .overlay(alignment: .trailing) {
            if homeLayout == .cards, homeEventContexts.count > 1 {
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

            if workspace.canManageInvitations(for: workspace.selectedEventReference) {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingInvitationSharing = true
                    } label: {
                        Label("Share Invitation", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("Invite people to the selected event")
                    .accessibilityIdentifier("home-share-invitation")
                }
            }

            AdaptiveToolbarActions {
                if homeLayout == .cards, workspace.showsPlanningInterface {
                    NavigationLink {
                        EventAnnouncementsView(eventID: workspace.selectedEventID)
                    } label: {
                        Label(AnnouncementCopy.title, systemImage: "megaphone")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(AnnouncementCopy.title)
                    .accessibilityIdentifier("home.updates")
                }

                if workspace.isMainEventDeleted, workspace.showsPlanningInterface {
                    Button("Create event", systemImage: "plus") {
                        editorTarget = .main
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                    .frame(width: 44, height: 44)
                } else if workspace.showsPlanningInterface {
                    if workspace.isMainEventContext {
                        Button("Add event", systemImage: "calendar.badge.plus") {
                            addEventIdeaDetent = .large
                            isAddingEventIdea = true
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                        .tint(.primary)
                        .frame(width: 44, height: 44)
                    }
                }

                AccountToolbarButton(monochrome: true, avatarSize: 28)
                    .frame(width: 44, height: 44)
            }
        }
        .navigationDestination(item: $openedEventReference) { reference in
            invitationDetail(for: reference)
        }
        .sheet(isPresented: $isSavingBlueprint) {
            NavigationStack {
                BlueprintCreateShareView(
                    eventID: workspace.mainEventID,
                    workspace: workspace,
                    createsShareLink: false,
                    startsWithReview: true
                )
            }
            .presentationDetents([.large])
        }
        .navigationDestination(item: $eventManagementRoute) { route in
            EventManagementView(reference: route.reference, initialDestination: route.initialDestination)
                .environment(workspace)
        }
        .fullScreenCover(isPresented: $isPresentingInvitationSharing) {
            CollaborationInviteView()
                .environment(workspace)
        }
        .onChange(of: authentication?.principalGeneration) { _, _ in
            detailInvitationShareRequest = nil
            eventManagementRoute = nil
        }
        .onChange(of: workspace.mainEventID) { _, _ in
            detailInvitationShareRequest = nil
            eventManagementRoute = nil
        }
        .onChange(of: isDetailInvitationShareRequestValid) { _, isValid in
            if !isValid { detailInvitationShareRequest = nil }
        }
        .modifier(EventCSVExportPresentation(request: $csvExportRequest))
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
        .onAppear {
            if HomeEventLayout(rawValue: persistedHomeLayout) == nil {
                persistedHomeLayout = HomeEventLayout.overview.rawValue
            }
        }
        .task(id: homeLayout) {
            guard homeLayout == .cards else { return }
            visibleScrollTarget = nil
            await Task.yield()
            guard !Task.isCancelled, homeLayout == .cards else { return }
            // Read after the layout settles so a rapid mode change cannot
            // restore a stale event captured by an earlier task.
            let selectedReference = workspace.selectedEventReference
            let reference = homeEventContexts.contains(selectedReference)
                ? selectedReference
                : homeEventContexts.first
            visibleScrollTarget = reference.map { .event($0) }
        }
        .onChange(of: persistedHomeLayout) { oldValue, newValue in
            handleHomeLayoutChange(from: HomeEventLayout(persistedValue: oldValue),
                                   to: HomeEventLayout(persistedValue: newValue))
        }
        .onChange(of: workspace.selectedEventReference) { _, reference in
            let target = HomeScrollTarget.event(reference)
            guard homeLayout == .cards,
                  !isHandlingHomeReselection,
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
        .appHaptic(.selection, trigger: scrubbedEventIndex) { _, index in index != nil }
        .appHaptic(.impact, trigger: pullToCreateHaptic)
        .onDisappear {
            homeReselectionTask?.cancel()
            eventSwitcherFadeTask?.cancel()
        }
    }

    private var cardsScrollView: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    if workspace.isMainEventDeleted {
                        noMainEventPlaceholder
                    } else {
                        ForEach(homeEventContexts, id: \.self) { reference in
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .refreshable {
            await cloudSync.synchronize(trigger: .manual)
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $visibleScrollTarget, anchor: .center)
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
            guard homeLayout == .cards else { return }
            currentScrollOffset = geometry.offset
            isPullToCreateRegionVisible = geometry.pullToCreateDistance > 0
            updateEventSwitcherReveal(offset: geometry.offset)
            updateEventContextAtSwipeStart(offset: geometry.offset)
            updatePullToCreate(distance: geometry.pullToCreateDistance)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            guard homeLayout == .cards else { return }
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
        .appSoftScrollEdges()
    }

    private var noMainEventPlaceholder: some View {
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
                .foregroundStyle(AppTheme.ColorToken.onAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.section)
    }

    private func invitationDetail(for reference: EventReference) -> some View {
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
                ToolbarItem(placement: .topBarLeading) {
                    if workspace.canManageInvitations(for: reference) {
                        Button {
                            presentDetailInvitationSharing(for: reference)
                        } label: {
                            Label("Share Invitation", systemImage: "square.and.arrow.up")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityHint("Invite people to this event")
                        .accessibilityIdentifier("invitation-share-invitation")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if canEdit(reference) || workspace.eventRemovalAction(for: reference) != nil || workspace.canCancelEvent(reference) || canExport(.schedule, for: reference) || canExport(.guestList, for: reference) {
                        Menu(AppCopy.EventRemoval.actions, systemImage: "ellipsis") {
                            eventActions(for: reference)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("invitation.actions")
                    }
                }
            }
            .fullScreenCover(item: $detailInvitationShareRequest) { request in
                CollaborationInviteView(reference: request.reference)
                    .environment(workspace)
            }
            .navigationTransition(.zoom(sourceID: reference, in: invitationTransition))
    }

    private func eventHero(for reference: EventReference) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
        let eventStatus = status(for: reference)
        let contextPresentation = HomeEventContextPresentation(
            kind: reference == .main ? .mainEvent : .subevent,
            statusTitle: eventStatus.title,
            statusSymbol: eventStatus.symbol
        )
        let formattedDate = EventScheduleFormatter.string(
            from: date(for: reference),
            includesTime: false,
            timeZoneIdentifier: timeZoneIdentifier(for: reference),
            dateStyle: .long
        )
        let parentContext = contextPresentation.parentContextTitle(
            mainEventTitle: workspace.title,
            mainEventIsVisible: homeEventContexts.contains(.main)
        )
        let secondaryText = secondaryLabel(for: reference)
        let showsSecondaryText = parentContext == nil
            || timelineItem(for: reference)?.purpose != .eventExperience
        return GeometryReader { proxy in
            let footerHeight: CGFloat = EventManagementAccess.canOpen(reference: reference, in: workspace) ? 56 : 0
            let primaryContentHeight = max(eventHeroHeight - footerHeight, 0)
            VStack(spacing: 0) {
                Button {
                    openEvent(reference)
                } label: {
                    WorkspaceEventHero(title: title(for: reference)) {
                        eventArtwork(for: reference)
                            .frame(width: proxy.size.width, height: primaryContentHeight)
                            .clipped()
                    } people: {
                        if !eventPeople(for: reference).isEmpty {
                            attendeeSummary(for: reference)
                        }
                    } metadata: {
                        Text(EventScheduleFormatter.string(
                            from: date(for: reference),
                            includesTime: false,
                            timeZoneIdentifier: timeZoneIdentifier(for: reference),
                            dateStyle: .full
                        ))
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

                        if let parentContext {
                            Text(parentContext)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(2)
                        }

                        if showsSecondaryText {
                            Text(secondaryText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    } badge: {
                        EmptyView()
                    }
                    .frame(width: proxy.size.width, height: primaryContentHeight)
                    .clipped()
                }
                .buttonStyle(.plain)
                .contentShape(.interaction, Rectangle())
                .accessibilityHint("Opens event details")
                .accessibilityIdentifier(reference == .main ? "home.event.main" : "home.event.child")
                .accessibilityLabel(
                    contextPresentation.cardAccessibilityLabel(
                        title: title(for: reference),
                        date: formattedDate,
                        location: location(for: reference)?.formatted,
                        subtitle: showsSecondaryText ? secondaryText : nil,
                        parentContext: parentContext
                    )
                )
                .frame(width: proxy.size.width, height: primaryContentHeight)
                if EventManagementAccess.canOpen(reference: reference, in: workspace) {
                    Rectangle()
                        .fill(AppTheme.ColorToken.cardBorder)
                        .frame(height: 0.5)
                    eventManageButton(reference)
                        .frame(maxWidth: .infinity, minHeight: footerHeight - 0.5, maxHeight: footerHeight - 0.5)
                        .background(AppTheme.ColorToken.surface)
                }
            }
            .frame(width: proxy.size.width, height: eventHeroHeight)
            .clipShape(cardShape)
            .overlay {
                cardShape.stroke(AppTheme.ColorToken.cardBorder, lineWidth: 0.5)
            }
            .shadow(color: AppTheme.ColorToken.mediaScrim.opacity(0.12), radius: 12, y: 6)
            .contentShape(.contextMenuPreview, cardShape)
            .matchedTransitionSource(id: reference, in: invitationTransition) { source in
                source.clipShape(cardShape)
            }
            .contextMenu {
                eventActions(for: reference, includesDestructiveActions: false)
            }
            .accessibilityElement(children: .contain)
        }
        .frame(height: eventHeroHeight)
    }

    @ViewBuilder
    private func eventActions(for reference: EventReference, includesDestructiveActions: Bool = true) -> some View {
        if canExport(.schedule, for: reference) {
            EventScheduleShareButton {
                csvExportRequest = EventCSVExportRequest.make(
                    kind: .schedule, workspace: workspace, reference: reference, authentication: authentication
                )
            }
        }
        if canExport(.guestList, for: reference) {
            EventGuestListExportButton {
                csvExportRequest = EventCSVExportRequest.make(
                    kind: .guestList, workspace: workspace, reference: reference, authentication: authentication
                )
            }
        }
        if reference == .main, BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL, workspace: workspace) != nil {
            Button(BlueprintCopy.saveBlueprint, systemImage: "square.and.arrow.down") {
                isSavingBlueprint = true
            }
        }
        if canEdit(reference) {
            Button("Edit Event", systemImage: "pencil") {
                editorTarget = editorTarget(for: reference)
            }
        }
        if includesDestructiveActions {
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
    }

    private func eventManageButton(_ reference: EventReference) -> some View {
        Button {
            presentEventManagement(for: reference)
        } label: {
            HStack(spacing: AppTheme.Spacing.compact) {
                Text("Manage")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: AppTheme.Spacing.standard)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, minHeight: 55.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.manage.\(reference.id)")
    }

    private func presentEventManagement(for reference: EventReference, destination: EventManagementDestination? = nil) {
        guard EventManagementAccess.canOpen(reference: reference, in: workspace) else { return }
        eventManagementRoute = HomeEventManagementRoute(reference: reference, initialDestination: destination)
    }

    private func canExport(_ kind: EventCSVExportKind, for reference: EventReference) -> Bool {
        EventCSVExportRequest.canExport(
            kind: kind, workspace: workspace, reference: reference, authentication: authentication
        )
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
            return AppCopy.Home.peopleGoing(confirmedCount)
        }

        return AppCopy.Home.peopleInvited(totalCount)
    }

    private var eventContextSwitcher: some View {
        EventContextRail(
            itemIDs: homeEventContexts,
            selectedID: visibleEventReference ?? workspace.selectedEventReference,
            previewIndex: scrubbedEventIndex,
            title: title(for:),
            annotation: { reference in
                guard reference != .main || workspace.mainEventHasScheduledDate else { return nil }
                return EventScheduleFormatter.string(
                    from: date(for: reference),
                    includesTime: false,
                    timeZoneIdentifier: timeZoneIdentifier(for: reference)
                )
            },
            onPreview: { reference in
                guard let index = homeEventContexts.firstIndex(of: reference) else { return }
                previewEvent(at: index)
            },
            onCommit: { reference in
                guard let index = homeEventContexts.firstIndex(of: reference) else { return }
                commitScrubbedEvent(at: index)
            }
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

        let activeReference = homeLayout == .cards
            ? visibleEventReference ?? workspace.selectedEventReference
            : workspace.selectedEventReference
        let requestedReference: EventReference = if activeReference == .main {
            workspace.currentOrNextChildEventReference() ?? homeEventContexts.first ?? .main
        } else {
            .main
        }
        let targetReference = homeEventContexts.contains(requestedReference)
            ? requestedReference
            : homeEventContexts.first ?? workspace.selectedEventReference

        workspace.selectEventContext(targetReference)
        guard homeLayout == .cards else {
            isHandlingHomeReselection = false
            return
        }
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

    private func handleHomeLayoutChange(from oldLayout: HomeEventLayout, to newLayout: HomeEventLayout) {
        guard oldLayout != newLayout else { return }

        homeReselectionTask?.cancel()
        homeReselectionTask = nil
        isHandlingHomeReselection = false
        eventSwitcherFadeTask?.cancel()
        eventSwitcherFadeTask = nil
        eventSwitcherOpacity = 0
        isScrollInteractionActive = false
        scrollInteractionStartOffset = nil
        swipeOriginEventReference = nil
        didUpdateContextForSwipe = false
        isScrubbingEvents = false
        scrubbedEventIndex = nil
        isPullToCreateRegionVisible = false
        isRestoringFromPullToCreate = false
        resetPullToCreate()

        if newLayout == .cards {
            // The task keyed to the new layout clears and restores the current
            // selection after Cards has reinstalled its target layout.
            visibleScrollTarget = nil
        }
    }

    private func openEvent(_ reference: EventReference) {
        guard homeEventContexts.contains(reference) else { return }
        workspace.selectEventContext(reference)
        openedEventReference = reference
    }

    private func previewEvent(at index: Int) {
        guard homeLayout == .cards else { return }
        let references = homeEventContexts
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
        guard homeLayout == .cards else { return }
        let references = homeEventContexts
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
        guard homeLayout == .cards,
              homeEventContexts.count > 1,
              isScrollInteractionActive,
              let startOffset = scrollInteractionStartOffset else { return }

        let progress = min(abs(offset - startOffset) / 72, 1)
        guard progress > eventSwitcherOpacity else { return }

        withAnimation(.easeOut(duration: 0.12)) {
            eventSwitcherOpacity = progress
        }
    }

    private func revealEventSwitcher() {
        guard homeLayout == .cards,
              homeEventContexts.count > 1 else { return }
        eventSwitcherFadeTask?.cancel()
        eventSwitcherFadeTask = nil

        withAnimation(.easeOut(duration: 0.16)) {
            eventSwitcherOpacity = 1
        }
    }

    private func scheduleEventSwitcherFade() {
        guard homeLayout == .cards, eventSwitcherOpacity > 0 else { return }
        eventSwitcherFadeTask?.cancel()

        eventSwitcherFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled,
                  homeLayout == .cards,
                  !isScrollInteractionActive,
                  !isScrubbingEvents else { return }

            withAnimation(.easeOut(duration: 0.28)) {
                eventSwitcherOpacity = 0
            }
        }
    }

    private func commitVisibleScrollTarget() {
        guard homeLayout == .cards,
              case .some(.event(let reference)) = visibleScrollTarget else { return }
        workspace.selectEventContext(reference)
    }

    private func updateEventContextAtSwipeStart(offset: CGFloat) {
        guard homeLayout == .cards,
              isScrollInteractionActive,
              !isScrubbingEvents,
              !didUpdateContextForSwipe,
              let startOffset = scrollInteractionStartOffset,
              let originReference = swipeOriginEventReference else { return }

        let delta = offset - startOffset
        guard abs(delta) >= 8 else { return }

        let references = homeEventContexts
        guard let originIndex = references.firstIndex(of: originReference) else { return }

        let destinationIndex = delta > 0 ? originIndex + 1 : originIndex - 1
        didUpdateContextForSwipe = true

        guard references.indices.contains(destinationIndex) else { return }
        workspace.selectEventContext(references[destinationIndex])
    }

    private func updatePullToCreate(distance: CGFloat) {
        guard homeLayout == .cards,
              workspace.canManageMainEvent,
              isScrollInteractionActive else { return }

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
        guard shouldCreate, homeLayout == .cards else { return }

        Task { @MainActor in
            await Task.yield()
            guard homeLayout == .cards else { return }
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
              let lastReference = homeEventContexts.last else { return }

        isRestoringFromPullToCreate = true
        let target = HomeScrollTarget.event(lastReference)

        // Reassigning the same ScrollPosition ID is ignored. Clear it for one
        // update so releasing the pull always settles on the final event card.
        visibleScrollTarget = nil

        Task { @MainActor in
            await Task.yield()
            guard homeLayout == .cards else {
                isRestoringFromPullToCreate = false
                return
            }
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
        reference == .main ? workspace.title : timelineItem(for: reference)?.title ?? String(localized: "Event")
    }

    private func date(for reference: EventReference) -> Date {
        reference == .main ? workspace.mainEventStartsAt : timelineItem(for: reference)?.scheduledAt ?? workspace.mainEventStartsAt
    }

    private func timeZoneIdentifier(for reference: EventReference) -> String {
        reference == .main
            ? workspace.mainEventTimeZoneIdentifier
            : timelineItem(for: reference)?.timeZoneIdentifier ?? workspace.mainEventTimeZoneIdentifier
    }

    private func presentDetailInvitationSharing(for reference: EventReference) {
        guard openedEventReference == reference,
              workspace.canManageInvitations(for: reference),
              let authentication,
              !authentication.isSigningOut else { return }

        let accountID = authentication.currentUser?.id
        let localGuestProfileID = authentication.localGuestProfile?.id
        let isAuthenticatedHost: Bool
        if let accountID {
            isAuthenticatedHost = workspace.hasAuthenticatedViewer(accountID: accountID)
        } else {
            isAuthenticatedHost = false
        }
        let isLocalGuestHost = authentication.isGuestMode
            && localGuestProfileID != nil
            && localGuestProfileID == workspace.localGuestProfileID
        guard isAuthenticatedHost || isLocalGuestHost else { return }

        detailInvitationShareRequest = HomeInvitationShareRequest(
            reference: reference,
            accountID: accountID,
            localGuestProfileID: isAuthenticatedHost ? nil : localGuestProfileID,
            principalGeneration: authentication.principalGeneration,
            workspaceID: workspace.mainEventID
        )
    }

    private var isDetailInvitationShareRequestValid: Bool {
        guard let request = detailInvitationShareRequest,
              let authentication,
              openedEventReference == request.reference else { return false }
        let hasSameAuthenticatedPrincipal = request.accountID.map {
            authentication.currentUser?.id == $0
                && workspace.hasAuthenticatedViewer(accountID: $0)
        } ?? false
        let hasSameLocalGuestPrincipal = request.localGuestProfileID.map {
            authentication.isGuestMode
                && authentication.localGuestProfile?.id == $0
                && workspace.localGuestProfileID == $0
        } ?? false
        return (hasSameAuthenticatedPrincipal || hasSameLocalGuestPrincipal)
            && authentication.principalGeneration == request.principalGeneration
            && !authentication.isSigningOut
            && workspace.mainEventID == request.workspaceID
            && workspace.canManageInvitations(for: request.reference)
    }

    private func location(for reference: EventReference) -> EventLocation? {
        reference == .main ? workspace.mainEventLocation : timelineItem(for: reference)?.eventLocation
    }

    private func secondaryLabel(for reference: EventReference) -> String {
        if reference == .main { return mainEventTimingLabel }
        guard let item = timelineItem(for: reference) else { return String(localized: "Subevent") }
        return item.purpose.title
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

private struct MainEventEditorView: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var status: MainEventStatus = .ongoing
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
                    Text("This removes the main event and its sub-events from planning Home.")
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
            status = workspace.mainEventStatus.editorValue
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
