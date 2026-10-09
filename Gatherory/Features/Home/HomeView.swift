import Glur
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct HomeView: View {
    var resetToMainEventTrigger = 0

    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isInvitingCollaborators = false
    @State private var isComposingNote = false
    @State private var editorTarget: HomeEventEditorTarget?
    @State private var openedEventReference: EventReference?
    @State private var visibleScrollTarget: HomeScrollTarget?
    @State private var scrubbedEventIndex: Int?
    @State private var isScrubbingEvents = false
    @State private var pullToCreateProgress: CGFloat = 0
    @State private var isPullToCreateArmed = false
    @State private var pullToCreateHaptic = 0
    @State private var isScrollInteractionActive = false
    @State private var currentScrollOffset: CGFloat = 0
    @State private var scrollInteractionStartOffset: CGFloat?
    @State private var swipeOriginEventReference: EventReference?
    @State private var didUpdateContextForSwipe = false
    @Namespace private var invitationTransition

    private let pullToCreateThreshold: CGFloat = 168
    private let pullToCreateItemHeight: CGFloat = 184
    private let pullToCreateRevealInset: CGFloat = 56

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.weddingDate).day ?? 0, 0)
    }

    private var goingMembers: [WeddingMember] {
        workspace.members.filter { $0.attendance == .going }
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
                    .accessibilityHint("Pull until the progress ring closes, then release")
                }
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
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
                    .padding(.trailing, 6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                eventCollaboratorButton
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
                .toolbarColorScheme(.dark, for: .navigationBar)
                .preferredColorScheme(.dark)
                .toolbar {
                    if canEdit(reference) {
                        ToolbarItem(placement: .topBarTrailing) {
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
        .fullScreenCover(isPresented: $isInvitingCollaborators) {
            CollaborationInviteView()
                .environment(workspace)
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
            updateEventContextAtSwipeStart(offset: geometry.offset)
            updatePullToCreate(distance: geometry.pullToCreateDistance)
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if newPhase == .interacting {
                isScrollInteractionActive = true
                scrollInteractionStartOffset = currentScrollOffset
                swipeOriginEventReference = visibleEventReference ?? workspace.selectedEventReference
                didUpdateContextForSwipe = false
            }

            if oldPhase == .interacting, newPhase != .interacting {
                isScrollInteractionActive = false
                completePullToCreateIfNeeded()
            }

            guard newPhase == .idle, !isScrubbingEvents else { return }
            commitVisibleScrollTarget()
            scrollInteractionStartOffset = nil
            swipeOriginEventReference = nil
            didUpdateContextForSwipe = false
        }
        .onChange(of: workspace.selectedEventReference) { _, reference in
            let target = HomeScrollTarget.event(reference)
            guard !isScrollInteractionActive,
                  !isScrubbingEvents,
                  visibleScrollTarget != target else { return }
            withAnimation(.snappy) {
                visibleScrollTarget = target
            }
        }
        .onChange(of: resetToMainEventTrigger) { _, _ in
            scrollToMainEvent()
        }
        .sensoryFeedback(.selection, trigger: scrubbedEventIndex)
        .sensoryFeedback(.success, trigger: pullToCreateHaptic)
    }

    private func eventHero(for reference: EventReference) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
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

                if reference == .main {
                    attendeeSummary
                }

                VStack(spacing: 8) {
                    Text(title(for: reference))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(date(for: reference), format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let eventLocation = location(for: reference) {
                        Label(eventLocation.formatted, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
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
            }
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
        if reference == .main {
            let artwork: Image = if let imageData = workspace.mainEventImageData,
                                let image = UIImage(data: imageData) {
                Image(uiImage: image)
            } else {
                Image("WeddingVenueHero")
            }

            if reduceTransparency {
                artwork.resizable().scaledToFill()
            } else {
                artwork
                    .resizable()
                    .scaledToFill()
                    .glur(
                    radius: 24,
                    mask: .linear(
                        stops: [
                            .init(intensity: 0, location: 0),
                            .init(intensity: 0, location: 0.48),
                            .init(intensity: 0.18, location: 0.60),
                            .init(intensity: 0.74, location: 0.78),
                            .init(intensity: 1, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    noise: 0.025
                    )
            }
        } else if let item = timelineItem(for: reference) {
            MediaArtwork(
                imageData: item.imageData,
                remoteURL: nil,
                symbol: item.category.symbol,
                colors: item.category.artworkColors,
                accent: item.category.artworkAccent,
                ambientBlurRadius: 10,
                progressiveBlurRadius: 24,
                blurStart: 0.42
            )
        } else {
            Color.secondary.opacity(0.16)
        }
    }

    private var attendeeSummary: some View {
        VStack(spacing: 8) {
            HStack(spacing: -10) {
                ForEach(goingMembers.prefix(5)) { member in
                    Text(member.initials)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }

            Text(goingMembers.count == 1 ? "1 person going" : "\(goingMembers.count) people going")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var eventCollaboratorButton: some View {
        let coordinators = workspace.selectedEventCoordinators

        return Button {
            isInvitingCollaborators = true
        } label: {
            HStack(spacing: -7) {
                ForEach(coordinators.prefix(3)) { member in
                    Text(member.initials)
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(.primary.opacity(0.24), lineWidth: 0.5))
                }

                if coordinators.count > 3 {
                    Text("+\(coordinators.count - 3)")
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(.primary.opacity(0.24), lineWidth: 0.5))
                }

                Image(systemName: "person.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(.thinMaterial, in: Circle())
                    .overlay(Circle().stroke(.primary.opacity(0.24), lineWidth: 0.5))
            }
            .padding(.horizontal, 4)
            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Event collaborators and invitations")
        .accessibilityValue("\(coordinators.count) coordinating \(workspace.selectedEventTitle)")
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

    private func scrollToMainEvent() {
        isScrubbingEvents = false
        scrubbedEventIndex = nil
        workspace.selectEventContext(.main)

        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy) {
                visibleScrollTarget = .event(.main)
            }
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
                    .foregroundStyle(isArmed ? .white : AppTheme.ColorToken.accent)
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

/// A compact date-ordered index inspired by the system section index.
/// Small collections show one marker per event; large collections use a
/// continuous track so rendering cost stays constant.
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

    private var currentIndex: Int {
        if let previewIndex { return previewIndex }
        return references.firstIndex(of: selectedReference) ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if references.count <= markerLimit {
                    VStack(spacing: 0) {
                        ForEach(references.indices, id: \.self) { index in
                            let reference = references[index]
                            let isMainEvent = reference == .main
                            let isCurrent = index == currentIndex
                            Circle()
                                .fill(
                                    isMainEvent
                                        ? Color.orange
                                        : isCurrent ? AppTheme.ColorToken.accent : Color.white.opacity(0.68)
                                )
                                .frame(
                                    width: isMainEvent ? 10 : isCurrent ? 9 : 4,
                                    height: isMainEvent ? 10 : isCurrent ? 9 : 4
                                )
                                .overlay {
                                    if isMainEvent || isCurrent {
                                        Circle()
                                            .stroke(.white.opacity(0.95), lineWidth: 1.5)
                                    }
                                }
                                .shadow(color: .black.opacity(0.34), radius: 1, y: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, verticalInset)
                } else {
                    let currentReference = references[currentIndex]
                    Capsule()
                        .fill(currentReference == .main ? Color.orange : AppTheme.ColorToken.accent)
                        .frame(width: 6, height: 20)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.95), lineWidth: 1.5)
                        }
                        .shadow(color: .black.opacity(0.34), radius: 1, y: 1)
                        .position(
                            x: proxy.size.width / 2,
                            y: markerPosition(for: currentIndex, height: proxy.size.height)
                        )
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
                VStack(alignment: .trailing) {
                    Text(date(reference), format: .dateTime.month(.abbreviated).day().year())
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 140, alignment: .trailing)
                .background(.black.opacity(0.78), in: Capsule())
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
            .environment(\.colorScheme, .dark)
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

    private var startSummary: String {
        startsAt.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened)
    }

    private var endSummary: String? {
        endsAt?.formatted(date: .abbreviated, time: isAllDay ? .omitted : .shortened)
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
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isAllDay ? "All-day" : "Starts")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(startSummary)
                                .foregroundStyle(.primary)

                            if let endSummary {
                                Text("Ends \(endSummary)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
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

enum InvitationTransitionID: Hashable {
    case mainEvent
}

private struct InvitationPreviewView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedScheduleItem: TimelineItem?
    @State private var selectedMomentPhoto: PhotosPickerItem?
    @State private var isEditingMainEvent = false
    @State private var weather = EventWeatherModel()

    let transitionNamespace: Namespace.ID
    @Namespace private var scheduleTransition

    private var hosts: [WeddingMember] {
        workspace.members.filter { $0.participantRole == .host }
    }

    private var goingMembers: [WeddingMember] {
        workspace.members.filter { $0.attendance == .going }
    }

    private var musicIdeas: [WeddingIdea] {
        workspace.ideas.filter {
            $0.category == .music && $0.status != .passed && $0.status != .archived
        }
    }

    private var responseDeadline: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: workspace.weddingDate)
            ?? workspace.weddingDate
    }

    private var schedule: [TimelineItem] {
        workspace.approvedChildEvents.filter {
            $0.purpose == .eventExperience
        }
    }

    private var weatherRequestID: String {
        [
            workspace.weddingDate.timeIntervalSinceReferenceDate.formatted(),
            workspace.mainEventLocation?.latitude?.formatted() ?? "no-latitude",
            workspace.mainEventLocation?.longitude?.formatted() ?? "no-longitude"
        ]
        .joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = max(
                proxy.size.height + proxy.safeAreaInsets.top,
                dynamicTypeSize.isAccessibilitySize ? 760 : 680
            )

            ZStack {
                InvitationFixedBackdrop(
                    imageData: workspace.mainEventImageData,
                    blurProgress: blurProgress,
                    reduceMotion: reduceMotion,
                    reduceTransparency: reduceTransparency
                )

                ScrollView {
                    LazyVStack(spacing: 0) {
                        invitationHero(height: heroHeight)

                        invitationInformation
                    }
                }
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(.black)
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if workspace.canAddEventMoments {
                    PhotosPicker(selection: $selectedMomentPhoto, matching: .images) {
                        Label("Add Photo", systemImage: "photo.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                }

                if workspace.canManageMainEvent {
                    Button("Edit Event", systemImage: "pencil") {
                        isEditingMainEvent = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
        .navigationTransition(
            .zoom(sourceID: InvitationTransitionID.mainEvent, in: transitionNamespace)
        )
        .navigationDestination(item: $selectedScheduleItem) { item in
            TimelineEventReadOnlyView(
                item: item,
                transitionNamespace: scheduleTransition
            )
        }
        .sheet(isPresented: $isEditingMainEvent) {
            NavigationStack {
                MainEventEditorView()
            }
            .environment(workspace)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedMomentPhoto) { _, item in
            guard let item else { return }

            Task {
                guard let imageData = try? await item.loadTransferable(type: Data.self) else { return }
                workspace.addMainEventMoment(imageData)
                selectedMomentPhoto = nil
            }
        }
        .task(id: weatherRequestID) {
            await weather.load(
                on: workspace.weddingDate,
                location: workspace.mainEventLocation
            )
        }
    }

    private var blurProgress: CGFloat {
        min(max(scrollOffset / 220, 0), 1)
    }

    private func invitationHero(height: CGFloat) -> some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 150 : 260)

            Text("Together with their families")
                .font(.subheadline.weight(.medium))

            Text(workspace.title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("invite you to celebrate with them")
                .font(.body)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                Text(
                    workspace.weddingDate,
                    format: .dateTime.weekday(.wide).month(.wide).day().year()
                )
                .font(.headline)

                if let eventLocation = workspace.mainEventLocation {
                    Text(eventLocation.title)
                        .font(.subheadline.weight(.semibold))

                    if !eventLocation.detail.isEmpty {
                        Text(eventLocation.detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.84))
                    }
                }
            }
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
        .padding(AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    private var invitationInformation: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            rsvpCard

            if workspace.currentMainEventStatus == .ongoing || workspace.currentMainEventStatus == .finished {
                momentsCard
            }

            lifecycleCard

            eventDetails
            scheduleCard
            musicCard
            dressCodeCard
            notesCard
        }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .padding(.top, AppTheme.Spacing.section)
        .padding(.bottom, AppTheme.Layout.screenBottom + AppTheme.Spacing.section)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var lifecycleCard: some View {
        switch workspace.currentMainEventStatus {
        case .draft, .ongoing:
            EmptyView()
        case .finished:
            InvitationSection(title: "A Past Event", symbol: "checkmark.seal.fill") {
                Text("This event is finished and preserved as a read-only memory.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var momentsCard: some View {
        InvitationSection(title: "Moments", symbol: "photo.on.rectangle.angled") {
            if workspace.mainEventMoments.isEmpty {
                Label("Share photos from the celebration using the photo button above.", systemImage: "photo.badge.plus")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                        GridItem(.flexible(), spacing: AppTheme.Spacing.compact)
                    ],
                    spacing: AppTheme.Spacing.compact
                ) {
                    ForEach(workspace.mainEventMoments) { moment in
                        if let image = UIImage(data: moment.imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .aspectRatio(0.82, contentMode: .fit)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: AppTheme.Radius.control,
                                        style: .continuous
                                    )
                                )
                                .accessibilityLabel("Photo added by \(moment.addedBy)")
                        }
                    }
                }
            }
        }
    }

    private var rsvpCard: some View {
        InvitationSection(
            title: workspace.currentMainEventStatus == .finished ? "Your Response" : "Will You Join Us?",
            symbol: "envelope.open.fill"
        ) {
            if workspace.currentMainEventStatus != .finished {
                Text("Kindly respond by \(responseDeadline.formatted(date: .long, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            responseButtons
                .disabled(workspace.currentMainEventStatus == .finished)

            if let response = workspace.mainEventResponse {
                Label(
                    response == .going ? "We can't wait to celebrate with you." : "Response saved for this event.",
                    systemImage: response.symbol
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(response == .going ? AppTheme.ColorToken.accent : .secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var responseButtons: some View {
        EventResponseControl(selection: workspace.mainEventResponse) { response in
            withAnimation(.snappy) {
                workspace.setMainEventResponse(response)
            }
        }
    }

    private var eventDetails: some View {
        InvitationSection(title: "Details", symbol: "calendar") {
            InvitationDetailRow(
                symbol: "calendar",
                title: "Date and Time",
                value: mainEventScheduleSummary
            )

            if let eventLocation = workspace.mainEventLocation {
                InvitationLocationView(location: eventLocation)

                TimelineWeatherRow(
                    phase: weather.phase,
                    attribution: weather.attribution
                ) {
                    Task {
                        await weather.load(
                            on: workspace.weddingDate,
                            location: workspace.mainEventLocation
                        )
                    }
                }
            }

            InvitationDetailRow(
                symbol: "person.2.fill",
                title: "Hosted By",
                value: hosts.map(\.name).formatted()
            )
        }
    }

    private var mainEventScheduleSummary: String {
        let start = workspace.weddingDate.formatted(
            date: .long,
            time: workspace.mainEventIsAllDay ? .omitted : .shortened
        )

        guard let endsAt = workspace.mainEventEndsAt else {
            return workspace.mainEventIsAllDay ? "\(start) · All-day" : start
        }

        return "\(start) – \(endsAt.formatted(date: .abbreviated, time: workspace.mainEventIsAllDay ? .omitted : .shortened))"
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Label("Schedule", systemImage: "clock.fill")
                .font(.title3.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 12) {
                    ForEach(schedule) { item in
                        TimelineEventCard(
                            item: item,
                            transitionNamespace: scheduleTransition,
                            showsPlanningStatus: false,
                            cardAspectRatio: 0.78
                        ) {
                            selectedScheduleItem = item
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in
                            dynamicTypeSize.isAccessibilitySize
                                ? length
                                : min(max(length * 0.78, 250), 340)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var musicCard: some View {
        InvitationSection(title: "Music", symbol: "music.note") {
            if musicIdeas.isEmpty {
                Text("The celebration soundtrack will appear here once it is ready.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(musicIdeas.prefix(3)) { idea in
                    InvitationDetailRow(
                        symbol: "music.note",
                        title: idea.musicTrack?.artistName ?? "Soundtrack",
                        value: idea.musicTrack?.title ?? idea.title
                    )
                }
            }
        }
    }

    private var dressCodeCard: some View {
        InvitationSection(title: "Dress Code", symbol: "tshirt.fill") {
            if workspace.dressCode.isEmpty {
                Text("No dress code has been added.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text(workspace.dressCode)
                    .font(.headline)
            }
        }
    }

    private var notesCard: some View {
        InvitationSection(title: "A Note From Us", symbol: "heart.text.square.fill") {
            Text(workspace.eventMessage.isEmpty ? "The hosts haven't added a note yet." : workspace.eventMessage)
            .font(.body)
            .foregroundStyle(.secondary)

            Label(
                goingMembers.count == 1
                    ? "1 guest is going"
                    : "\(goingMembers.count) guests are going",
                systemImage: "person.2.fill"
            )
            .font(.subheadline.weight(.semibold))
        }
    }

}

private struct InvitationLocationView: View {
    let location: EventLocation

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = location.latitude,
              let longitude = location.longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var mapsURL: URL? {
        guard let coordinate else { return nil }

        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: location.title)
        ]
        return components?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(location.formatted)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.Spacing.compact)

                if let mapsURL {
                    Link(destination: mapsURL) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .labelStyle(.iconOnly)
                            .frame(
                                minWidth: AppTheme.Layout.minimumTouchTarget,
                                minHeight: AppTheme.Layout.minimumTouchTarget
                            )
                    }
                    .accessibilityHint("Opens directions in Apple Maps")
                }
            }

            if let coordinate {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                    ),
                    interactionModes: [.pan, .zoom]
                ) {
                    Marker(location.title, coordinate: coordinate)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 220)
                .clipShape(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 0.5)
                }
                .accessibilityLabel("Map showing \(location.formatted)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct InvitationSection<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Label(title, systemImage: symbol)
                .font(.title3.bold())

            content
        }
        .padding(AppTheme.Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(
                cornerRadius: AppTheme.Radius.card,
                style: .continuous
            )

            if reduceTransparency {
                shape.fill(.black.opacity(0.92))
            } else {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(.black.opacity(0.46)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(reduceTransparency ? 0.12 : 0.22), lineWidth: 0.5)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct InvitationFixedBackdrop: View {
    let imageData: Data?
    let blurProgress: CGFloat
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            let activeBlurProgress = reduceMotion ? 0 : blurProgress
            let blurRadius = reduceTransparency ? 0 : 38 * activeBlurProgress
            let dimmingOpacity = reduceTransparency
                ? 0.82
                : 0.10 + (0.34 * blurProgress)

            ZStack {
                Color.black

                backdropImage
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1 + (0.06 * activeBlurProgress))
                    .blur(radius: blurRadius, opaque: true)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.02), location: 0),
                        .init(color: .black.opacity(dimmingOpacity * 0.42), location: 0.52),
                        .init(color: .black.opacity(dimmingOpacity), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Color.black.opacity(reduceMotion ? 0.12 * blurProgress : 0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var backdropImage: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image("WeddingVenueHero")
                .resizable()
                .scaledToFill()
        }
    }
}

private struct InvitationDetailRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}


#Preview {
    NavigationStack {
        HomeView()
            .environment(WeddingWorkspace.sample)
    }
}
