import SwiftUI

struct HomeView: View {
    var homeReselectionTrigger = 0
    var onExitWorkspace: (() -> Void)?

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isComposingNote = false
    @State private var editorTarget: HomeEventEditorTarget?
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
    @Namespace private var invitationTransition

    private let pullToCreateThreshold: CGFloat = 200
    private let pullToCreateItemHeight: CGFloat = 184
    private let pullToCreateRevealInset: CGFloat = 56

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.weddingDate).day ?? 0, 0)
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
                            Button("Create Event", systemImage: "plus") {
                                editorTarget = .main
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.section)
                    } else {
                        ForEach(workspace.availableEventContexts, id: \.self) { reference in
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
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $visibleScrollTarget, anchor: .center)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .overlay(alignment: .trailing) {
            if workspace.availableEventContexts.count > 1 {
                eventDateScrubber
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if let onExitWorkspace {
                    WorkspaceLibraryToolbarButton(action: onExitWorkspace)
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                if workspace.isMainEventDeleted {
                    Button("Create event", systemImage: "plus") {
                        editorTarget = .main
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .tint(.primary)
                } else {
                    Button("Send a note", systemImage: "megaphone") {
                        isComposingNote = true
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.primary)
                    .tint(.primary)

                    if workspace.isMainEventContext {
                        Button("Add event", systemImage: "calendar.badge.plus") {
                            editorTarget = .newSubevent
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
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if reference == .main, workspace.canManageMainEvent {
                            NavigationLink {
                                WorkspaceSettingsView()
                            } label: {
                                Label("Workspace Settings", systemImage: "gearshape")
                                    .labelStyle(.iconOnly)
                            }
                        }

                        if canEdit(reference) {
                            Button("Edit Event", systemImage: "pencil") {
                                editorTarget = editorTarget(for: reference)
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
            NoteComposerView()
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
    private func eventArtwork(for reference: EventReference) -> some View {
        let item = timelineItem(for: reference)
        let category = item?.category ?? .ceremony

        MediaArtwork(
            imageData: reference == .main ? workspace.mainEventImageData : item?.imageData,
            assetName: reference == .main || category == .venue ? "WeddingVenueHero" : nil,
            remoteURL: nil,
            symbol: category.symbol,
            colors: category.artworkColors,
            accent: category.artworkAccent,
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

    private func eventPeople(for reference: EventReference) -> [WeddingMember] {
        workspace.participants(for: reference)
    }

    private func eventPeopleLabel(confirmedCount: Int, totalCount: Int) -> String {
        if confirmedCount > 0 {
            return confirmedCount == 1 ? "1 person going" : "\(confirmedCount) people going"
        }

        return totalCount == 1 ? "1 person invited" : "\(totalCount) people invited"
    }

    private var eventDateScrubber: some View {
        EventDateScrubber(
            references: workspace.availableEventContexts,
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
            workspace.currentOrNextChildEventReference() ?? .main
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
        let references = workspace.availableEventContexts
        guard references.indices.contains(index) else { return }
        isScrubbingEvents = true
        guard scrubbedEventIndex != index else { return }
        scrubbedEventIndex = index
        withAnimation(.snappy(duration: 0.22)) {
            visibleScrollTarget = .event(references[index])
        }
    }

    private func commitScrubbedEvent(at index: Int) {
        let references = workspace.availableEventContexts
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

        let references = workspace.availableEventContexts
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
            editorTarget = .newSubevent
        }
    }

    private func resetPullToCreate() {
        pullToCreateProgress = 0
        isPullToCreateArmed = false
    }

    private func restoreLastEventAfterPullIfNeeded() {
        guard isPullToCreateRegionVisible,
              !isRestoringFromPullToCreate,
              let lastReference = workspace.availableEventContexts.last else { return }

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
        reference == .main ? workspace.weddingDate : timelineItem(for: reference)?.scheduledAt ?? workspace.weddingDate
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
        case .subevent(let id):
            workspace.timeline.contains(where: { $0.id == id })
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
        case .newSubevent:
            .subevent(nil)
        case .subevent(let id):
            .subevent(workspace.timeline.first(where: { $0.id == id }))
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
                Text(isArmed ? "Release to Add Event" : "Add an Event")
                    .font(.headline)

                Text("Keep pulling through the schedule to plan what comes next.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 290)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isArmed ? "Release to add an event" : "Pull to add an event")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// A compact, date-ordered event index. A neutral material rail keeps the
/// control legible over every cover image without competing with the event.
private struct EventDateScrubber: View {
    let references: [EventReference]
    let selectedReference: EventReference
    let previewIndex: Int?
    let title: (EventReference) -> String
    let date: (EventReference) -> Date
    let onPreview: (Int) -> Void
    let onCommit: (Int) -> Void

    private let railHeight: CGFloat = 196
    private let markerLimit = 14
    private let verticalInset: CGFloat = 8
    private let indexLaneWidth: CGFloat = 30
    private let indexTrailingInset: CGFloat = 6

    private var currentIndex: Int {
        if let previewIndex { return previewIndex }
        return references.firstIndex(of: selectedReference) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                    .frame(width: indexLaneWidth)

                if references.count <= markerLimit {
                    VStack(spacing: 0) {
                        ForEach(references.indices, id: \.self) { index in
                            let isCurrent = index == currentIndex
                            Capsule()
                                .fill(
                                    isCurrent
                                        ? Color.primary
                                        : Color.primary.opacity(0.36)
                                )
                                .frame(
                                    width: isCurrent ? 18 : 5,
                                    height: isCurrent ? 4 : 3
                                )
                                .clipShape(Capsule())
                                .frame(width: indexLaneWidth, alignment: .trailing)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, verticalInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, indexTrailingInset)
                } else {
                    ZStack(alignment: .trailing) {
                        Capsule()
                            .fill(Color.primary.opacity(0.22))
                            .frame(width: 2)
                            .padding(.vertical, verticalInset)
                            .offset(x: -9)

                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 18, height: 4)
                            .position(
                                x: indexLaneWidth - 9,
                                y: markerPosition(for: currentIndex, height: proxy.size.height)
                            )
                    }
                    .frame(width: indexLaneWidth, height: proxy.size.height, alignment: .trailing)
                    .padding(.trailing, indexTrailingInset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(width: 44, height: railHeight)
        .overlay(alignment: .leading) {
            if let previewIndex, references.indices.contains(previewIndex) {
                let reference = references[previewIndex]
                VStack(alignment: .leading) {
                    Text(date(reference), format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 140, alignment: .leading)
                .background(.regularMaterial, in: Capsule())
                .offset(x: -148)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Event index")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Swipe up or down to preview events, then release to select")
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
        return "\(title(reference)), \(date(reference).formatted(date: .abbreviated, time: .omitted))"
    }

    private func index(at yPosition: CGFloat, height: CGFloat) -> Int {
        guard references.count > 1 else { return 0 }
        let usableHeight = max(height - (verticalInset * 2), 1)
        let clamped = min(max(yPosition - verticalInset, 0), usableHeight)
        return Int((clamped / usableHeight * CGFloat(references.count - 1)).rounded())
    }

    private func markerPosition(for index: Int, height: CGFloat) -> CGFloat {
        guard references.count > 1 else { return height / 2 }
        let usableHeight = max(height - (verticalInset * 2), 1)
        return verticalInset + (CGFloat(index) / CGFloat(references.count - 1) * usableHeight)
    }
}

private enum HomeEventEditorTarget: Identifiable {
    case main
    case newSubevent
    case subevent(UUID)

    var id: String {
        switch self {
        case .main: "main"
        case .newSubevent: "new-subevent"
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
    @Environment(WeddingWorkspace.self) private var workspace
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
                    fallbackAssetName: "WeddingVenueHero",
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
            startsAt = workspace.weddingDate
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

private struct NoteComposerView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var isFocused: Bool

    private let characterLimit = 750

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 180, alignment: .topLeading)
                        .focused($isFocused)
                        .accessibilityLabel("Note")
                        .onChange(of: note) { _, newValue in
                            if newValue.count > characterLimit {
                                note = String(newValue.prefix(characterLimit))
                            }
                        }
                } header: {
                    Text("Message")
                } footer: {
                    HStack {
                        Text("Share an update with everyone coordinating \(workspace.selectedEventTitle).")

                        Spacer(minLength: AppTheme.Spacing.compact)

                        Text("\(note.count)/\(characterLimit)")
                            .monospacedDigit()
                            .accessibilityLabel("\(characterLimit - note.count) characters remaining")
                    }
                }
            }
            .navigationTitle("Send a Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        workspace.sendNote(trimmedNote)
                        dismiss()
                    }
                    .disabled(trimmedNote.isEmpty)
                }
            }
            .task {
                isFocused = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(WeddingWorkspace.sample)
    }
}
