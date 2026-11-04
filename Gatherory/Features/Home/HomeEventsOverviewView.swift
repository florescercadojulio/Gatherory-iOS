import SwiftUI

/// The events a Home overview is allowed to render for a workspace.
@MainActor
struct HomeEventsOverviewProjection {
    let mainEventIsVisible: Bool
    let childEvents: [TimelineItem]

    init(workspace: PlanningWorkspace, now: Date = .now) {
        let visibleReferences = workspace.visibleEventContexts
        let rootIsAvailable = !workspace.isMainEventDeleted

        mainEventIsVisible = rootIsAvailable && visibleReferences.contains(.main)
        guard rootIsAvailable else {
            childEvents = []
            return
        }

        childEvents = visibleReferences.compactMap { reference in
            guard case .subevent(let id) = reference else { return nil }
            return workspace.timeline.first {
                $0.id == id
                    && $0.parentEventID == workspace.mainEventID
                    && $0.status != .archived
            }
        }.sorted { EventDateOrdering.key(for: $0, now: now) < EventDateOrdering.key(for: $1, now: now) }
    }
}

/// A compact, single-scroll Home presentation containing only events the
/// current viewer is authorized to see.
struct HomeEventsOverviewView<Actions: View>: View {
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(ImageSafetyStore.self) private var imageSafety

    @ViewBuilder var actions: (EventReference) -> Actions
    let onOpenEvent: (EventReference) -> Void
    let onManageEvent: (EventReference) -> Void
    let onRefresh: () async -> Void
    let transitionNamespace: Namespace.ID

    private var projection: HomeEventsOverviewProjection {
        HomeEventsOverviewProjection(workspace: workspace)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                    if projection.mainEventIsVisible {
                        mainEvent
                    }

                    if !projection.childEvents.isEmpty {
                        childEvents
                    }
                }
                .padding(.top, AppTheme.Layout.screenTop)
                .padding(.bottom, AppTheme.Layout.screenBottom)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .appSoftScrollEdges()
            .background(AppTheme.ColorToken.background)
            .refreshable { await onRefresh() }
            .accessibilityIdentifier("home.overview")
            .task(id: workspace.selectedEventReference) {
                let selectedReference = workspace.selectedEventReference
                guard projectionContains(selectedReference) else { return }
                let targetID = overviewTargetID(for: selectedReference)
                guard targetID != nil else { return }

                await Task.yield()
                guard !Task.isCancelled,
                      selectedReference == workspace.selectedEventReference,
                      projectionContains(selectedReference),
                      let targetID else { return }

                withAnimation(.easeInOut(duration: 0.25)) {
                    scrollProxy.scrollTo(targetID, anchor: .top)
                }
            }
        }
    }

    private func projectionContains(_ reference: EventReference) -> Bool {
        switch reference {
        case .main:
            return projection.mainEventIsVisible
        case .subevent(let id):
            return projection.childEvents.contains { $0.id == id }
        case .idea:
            return false
        }
    }

    private func overviewTargetID(for reference: EventReference) -> AnyHashable? {
        switch reference {
        case .main:
            return AnyHashable(EventReference.main)
        case .subevent(let id):
            guard let group = HomeEventsOverviewDayGroup.groups(for: projection.childEvents)
                .first(where: { $0.events.contains(where: { $0.id == id }) }) else { return nil }
            return AnyHashable("home.overview.day.\(group.id)")
        case .idea:
            return nil
        }
    }

    private var mainEvent: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)

        let eventButton = Button {
            onOpenEvent(.main)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                eventArtwork(for: .main)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text(workspace.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Label(mainEventDate, systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let time = mainEventTime.text, !workspace.mainEventIsAllDay {
                        Label(time, systemImage: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let location = nonempty(workspace.mainEventLocation?.title) {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let description = nonempty(workspace.eventMessage) {
                        Text(description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.primary)
                .padding(AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mainEventAccessibilityLabel)
        .accessibilityAddTraits(workspace.selectedEventReference == .main ? .isSelected : [])
        .accessibilityHint("Opens event details")
        .accessibilityIdentifier("home.overview.mainEvent")

        return VStack(spacing: 0) {
            eventButton
            if EventManagementAccess.canOpen(reference: .main, in: workspace) {
                manageFooter(for: .main)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.surface, in: shape)
        .clipShape(shape)
        .overlay { shape.stroke(.primary.opacity(0.12), lineWidth: 0.5) }
        .contentShape(.contextMenuPreview, shape)
        .matchedTransitionSource(id: EventReference.main, in: transitionNamespace) { source in
            source.clipShape(shape)
        }
        .contextMenu { actions(.main) }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .id(EventReference.main)
    }

    private var childEvents: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            ForEach(HomeEventsOverviewDayGroup.groups(for: projection.childEvents), id: \.id) { group in
                childEventDay(group)
            }
        }
    }

    private func childEventDay(_ group: HomeEventsOverviewDayGroup) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(group.title)
                .font(.title3.weight(.bold))
                .tracking(-0.2)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
                        ForEach(group.events) { event in
                            childEventCard(event)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
                .contentMargins(.horizontal, AppTheme.Layout.screenHorizontal, for: .scrollContent)
                .accessibilityIdentifier("home.overview.day.\(group.id)")
                .task(id: workspace.selectedEventReference) {
                    let selectedReference = workspace.selectedEventReference
                    guard case .subevent(let selectedID) = selectedReference,
                          group.events.contains(where: { $0.id == selectedID }) else { return }

                    await Task.yield()
                    guard !Task.isCancelled,
                          selectedReference == workspace.selectedEventReference,
                          group.events.contains(where: { $0.id == selectedID }) else { return }

                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo(selectedReference, anchor: .leading)
                    }
                }
            }
        }
        .id("home.overview.day.\(group.id)")
    }

    private func childEventCard(_ event: TimelineItem) -> some View {
        let reference = EventReference.subevent(event.id)

        let eventButton = Button {
            onOpenEvent(reference)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                eventArtwork(for: reference)
                    .frame(maxWidth: .infinity)
                    .frame(height: 172)
                    .clipped()

                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let eventTime = childEventTime(event).text {
                        Label(eventTime, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let location = nonempty(event.eventLocation?.title) {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.primary)
                .padding(AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect(cornerRadius: AppTheme.Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(childEventAccessibilityLabel(event))
        .accessibilityAddTraits(workspace.selectedEventReference == reference ? .isSelected : [])
        .accessibilityHint("Opens event details")
        .accessibilityIdentifier("home.overview.event.\(event.id.uuidString)")

        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        return VStack(spacing: 0) {
            eventButton
            if EventManagementAccess.canOpen(reference: reference, in: workspace) {
                manageFooter(for: reference)
            }
        }
        .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.78, 260) }
        .background(AppTheme.ColorToken.surface, in: shape)
        .clipShape(shape)
        .overlay { shape.stroke(.primary.opacity(0.12), lineWidth: 0.5) }
        .contentShape(.contextMenuPreview, shape)
        .matchedTransitionSource(id: reference, in: transitionNamespace) { source in
            source.clipShape(shape)
        }
        .contextMenu { actions(reference) }
        .id(reference)
    }

    private func manageFooter(for reference: EventReference) -> some View {
        Button {
            onManageEvent(reference)
        } label: {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("Manage")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, AppTheme.Spacing.standard)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.manage.\(reference.id)")
    }

    @ViewBuilder
    private func eventArtwork(for reference: EventReference) -> some View {
        let item = timelineItem(for: reference)
        let category = item?.category ?? .ceremony

        MediaArtwork(
            imageData: imageSafety.visibleImageData(
                reference == .main ? workspace.mainEventImageData : item?.imageData,
                assetID: reference == .main ? workspace.mainEventMediaAssetID : item?.mediaAssetID
            ),
            symbol: reference == .main ? IdeaCategory.event.symbol : category.symbol,
            colors: reference == .main ? IdeaCategory.event.artworkColors : category.artworkColors,
            accent: reference == .main ? IdeaCategory.event.artworkAccent : category.artworkAccent,
            ambientBlurRadius: 10,
            progressiveBlurRadius: 0,
            blurStart: 0.48
        )
    }

    private var mainEventDate: String {
        guard workspace.mainEventHasScheduledDate else {
            return String(localized: "Date to be decided")
        }
        return EventScheduleFormatter.string(
            from: workspace.mainEventStartsAt,
            includesTime: false,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
            dateStyle: .medium
        )
    }

    private var mainEventTime: HomeEventTimePresentation {
        HomeEventTimePresentation(
            startsAt: workspace.mainEventHasScheduledDate ? workspace.mainEventStartsAt : nil,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier
        )
    }

    private func childEventTime(_ event: TimelineItem) -> HomeEventTimePresentation {
        HomeEventTimePresentation(
            startsAt: event.schedulingState == .unscheduled ? nil : event.scheduledAt,
            endsAt: event.endsAt,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier
        )
    }

    private func timelineItem(for reference: EventReference) -> TimelineItem? {
        guard case .subevent(let id) = reference else { return nil }
        return projection.childEvents.first { $0.id == id }
    }

    private var mainEventAccessibilityLabel: String {
        [workspace.title, mainEventTime.accessibilityText ?? mainEventDate, nonempty(workspace.mainEventLocation?.title), nonempty(workspace.eventMessage)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func childEventAccessibilityLabel(_ event: TimelineItem) -> String {
        [event.title, childEventTime(event).accessibilityText ?? String(localized: "Date to be decided"), nonempty(event.eventLocation?.title)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
