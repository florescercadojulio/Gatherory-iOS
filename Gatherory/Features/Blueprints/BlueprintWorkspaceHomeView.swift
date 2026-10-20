import SwiftUI

/// Uses Home's event cards and vertical paging without a live workspace session.
struct BlueprintWorkspaceHomeView: View {
    let content: BlueprintPreviewContent
    let category: BlueprintBrowseCategory
    let usesSavedPreview: Bool
    let onSelectEvent: (BlueprintPreviewEventID) -> Void
    var onEditEvent: ((BlueprintPreviewEventID) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var eventTransition
    @Namespace private var scrollSpace
    @State private var selectedEvent: BlueprintPreviewEventID?
    @State private var scrollTargetID: BlueprintPreviewEventID?
    @State private var railTracking = BlueprintPreviewRailTracking()

    private var heroHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 720 : 640 }
    private var railItems: [BlueprintPreviewEventRailItem] { BlueprintPreviewEventRailItem.items(from: content) }
    private var railSelection: BlueprintPreviewEventID { railTracking.selection(fallback: .main) }
    private var previewedEventIndex: Int? { railTracking.scrubbedID.flatMap { content.eventIDs.firstIndex(of: $0) } }

    init(content: BlueprintPreviewContent, category: BlueprintBrowseCategory, usesSavedPreview: Bool,
         onEditEvent: ((BlueprintPreviewEventID) -> Void)? = nil,
         onSelectEvent: @escaping (BlueprintPreviewEventID) -> Void) {
        self.content = content
        self.category = category
        self.usesSavedPreview = usesSavedPreview
        self.onEditEvent = onEditEvent
        self.onSelectEvent = onSelectEvent
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.standard) {
                    if usesSavedPreview {
                        Label(BlueprintCopy.savedPreviewExplanation, systemImage: "wifi.slash")
                            .font(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(content.eventIDs) { id in
                        if let event = content.event(for: id) {
                            eventCard(event, id: id)
                                .id(id)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.top, AppTheme.Layout.screenTop)
                .padding(.bottom, AppTheme.Layout.screenBottom)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrollTargetID, anchor: .center)
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting {
                    railTracking.beginDirectScroll()
                }
            }
            .onPreferenceChange(BlueprintPreviewCardFrames.self) { frames in
                if let id = BlueprintPreviewRailTracking.centeredID(
                    orderedIDs: content.eventIDs, frames: frames, viewportHeight: viewport.size.height
                ) {
                    railTracking.observe(id)
                }
            }
            .appSoftScrollEdges()
            .background(AppTheme.ColorToken.background)
            .overlay(alignment: .trailing) {
                if content.eventIDs.count > 1 {
                    EventContextRail(
                        itemIDs: content.eventIDs,
                        selectedID: railSelection,
                        previewIndex: previewedEventIndex,
                        title: { id in railItem(for: id)?.title ?? "Event" },
                        annotation: { id in railItem(for: id)?.title },
                        onPreview: previewRailSelection,
                        onCommit: commitRailSelection,
                        usesCompactBubble: true,
                        accessibilityAnnotation: { id in railItem(for: id)?.annotation }
                    )
                }
            }
        }
        .coordinateSpace(name: scrollSpace)
        .sensoryFeedback(.selection, trigger: railSelection)
        .onChange(of: content.eventIDs) { _, ids in
            if !ids.contains(railSelection) {
                railTracking = BlueprintPreviewRailTracking()
                scrollTargetID = .main
                onSelectEvent(.main)
            }
            if let selectedEvent, !ids.contains(selectedEvent) { self.selectedEvent = nil }
        }
        .onChange(of: railSelection) { _, id in onSelectEvent(id) }
        .navigationDestination(item: $selectedEvent) { id in
            if let event = content.event(for: id) {
                let artwork = BlueprintPreviewEventArtwork.resolve(
                    id: id,
                    rawCategory: event.category,
                    browseCategory: category
                )
                if reduceMotion {
                    BlueprintWorkspaceEventDetail(event: event, artwork: artwork)
                        .toolbar { eventEditToolbar(id: id) }
                } else {
                    BlueprintWorkspaceEventDetail(event: event, artwork: artwork)
                        .toolbar { eventEditToolbar(id: id) }
                        .navigationTransition(.zoom(sourceID: id, in: eventTransition))
                }
            }
        }
    }

    private func eventCard(_ event: BlueprintPreviewEventContent, id: BlueprintPreviewEventID) -> some View {
        let artwork = BlueprintPreviewEventArtwork.resolve(
            id: id,
            rawCategory: event.category,
            browseCategory: category
        )
        return GeometryReader { proxy in
            Button {
                onSelectEvent(id)
                selectedEvent = id
            } label: {
                WorkspaceEventHero(title: event.title) {
                    MediaArtwork(
                        imageData: nil,
                        symbol: artwork.symbol,
                        colors: artwork.colors,
                        accent: artwork.accent,
                        progressiveBlurRadius: 0
                    )
                    .frame(width: LayoutDimensions.nonnegative(proxy.size.width), height: heroHeight)
                    .clipped()
                } people: {
                    EmptyView()
                } metadata: {
                    if id == .main,
                       let creatorName = content.creatorName,
                       !creatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(BlueprintCopy.creatorByline(creatorName))
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    if let proposal = event.scheduleProposal,
                       let schedule = BlueprintReviewPresentation.schedule(
                            dayOffset: proposal.dayOffset,
                            localTime: proposal.localTime
                       ) {
                        Text(String.localizedStringWithFormat(BlueprintCopy.previewSuggestedScheduleFormat, schedule))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    }
                    if let summary = event.summary, !summary.isEmpty {
                        Text(summary).font(.subheadline).lineLimit(3)
                            .multilineTextAlignment(.center)
                    }
                } badge: { EmptyView() }
                .frame(width: LayoutDimensions.nonnegative(proxy.size.width), height: heroHeight)
                .clipped()
                .matchedTransitionSource(id: id, in: eventTransition)
            }
            .buttonStyle(.plain)
            .clipShape(.rect(cornerRadius: AppTheme.Radius.hero))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.hero)
                    .stroke(.white.opacity(0.20), lineWidth: 0.5)
            }
            .accessibilityHint("Opens event details")
            .contextMenu {
                if let onEditEvent {
                    Button(AppCopy.Common.edit, systemImage: "pencil") { onEditEvent(id) }
                }
            }
            .preference(key: BlueprintPreviewCardFrames.self, value: [id: proxy.frame(in: .named(scrollSpace))])
        }
        .frame(height: heroHeight)
    }

    private func railItem(for id: BlueprintPreviewEventID) -> BlueprintPreviewEventRailItem? {
        railItems.first { $0.id == id }
    }

    @ToolbarContentBuilder
    private func eventEditToolbar(id: BlueprintPreviewEventID) -> some ToolbarContent {
        if let onEditEvent {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppCopy.Common.edit, systemImage: "pencil") { onEditEvent(id) }
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func commitRailSelection(_ id: BlueprintPreviewEventID) {
        guard content.eventIDs.contains(id) else { return }
        railTracking.commit(id)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            scrollTargetID = id
        }
    }

    private func previewRailSelection(_ id: BlueprintPreviewEventID) {
        guard content.eventIDs.contains(id), railTracking.scrubbedID != id else { return }
        railTracking.preview(id)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            scrollTargetID = id
        }
    }
}

private nonisolated struct BlueprintPreviewCardFrames: PreferenceKey {
    static var defaultValue: [BlueprintPreviewEventID: CGRect] { [:] }

    static func reduce(value: inout [BlueprintPreviewEventID: CGRect], nextValue: () -> [BlueprintPreviewEventID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
