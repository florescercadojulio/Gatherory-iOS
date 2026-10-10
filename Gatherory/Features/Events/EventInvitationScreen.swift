import MapKit
import PhotosUI
import SwiftUI
import UIKit

/// The shared event experience used by the main event, timeline events, and event ideas.
/// Only the root event can expose a child schedule; subevents and ideas are leaves.
struct EventInvitationScreen: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedChild: TimelineItem?
    @State private var selectedMomentPhotos: [PhotosPickerItem] = []
    @State private var weather = EventWeatherModel()
    @Namespace private var childTransition

    let reference: EventReference

    private var presentation: EventPresentation? {
        switch reference {
        case .main:
            let hosts = workspace.members
                .filter { $0.participantRole == .host }
                .map(\.name)

            return EventPresentation(
                title: workspace.title,
                eyebrow: "Together with their families",
                categoryTitle: "Main Event",
                categorySymbol: "heart.fill",
                startsAt: workspace.weddingDate,
                endsAt: workspace.mainEventEndsAt,
                isAllDay: workspace.mainEventIsAllDay,
                timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
                location: workspace.mainEventLocation,
                imageData: workspace.mainEventImageData,
                fallbackAssetName: "WeddingVenueHero",
                colors: TimelineCategory.ceremony.artworkColors,
                accent: TimelineCategory.ceremony.artworkAccent,
                purpose: nil,
                statusTitle: workspace.currentMainEventStatus.title,
                statusSymbol: workspace.currentMainEventStatus.symbol,
                peopleLabel: "Hosted By",
                people: hosts.isEmpty ? ["Your hosts"] : hosts,
                response: workspace.mainEventResponse,
                permitsResponse: !workspace.currentMainEventStatus.isReadOnly,
                note: workspace.eventMessage,
                dressCode: workspace.dressCode,
                guestIdeas: workspace.invitationIdeas(for: reference),
                children: workspace.approvedChildEvents.filter { $0.purpose == .eventExperience },
                moments: workspace.moments(for: .main)
            )

        case .subevent(let id):
            guard let item = workspace.timeline.first(where: { $0.id == id }) else { return nil }
            let participantIDs = Set(item.participantIDs)
            let participants = workspace.members
                .filter {
                    guard participantIDs.contains($0.id) else { return false }
                    return item.purpose == .eventExperience
                        ? $0.participantRole == .host
                        : $0.participantRole != .guest
                }
                .map(\.name)

            return EventPresentation(
                title: item.title,
                eyebrow: item.purpose.title,
                categoryTitle: item.category.title,
                categorySymbol: item.category.symbol,
                startsAt: item.hasScheduledDate ? item.scheduledAt : nil,
                endsAt: item.endsAt,
                isAllDay: item.isAllDay,
                timeZoneIdentifier: item.timeZoneIdentifier,
                location: item.eventLocation,
                imageData: item.imageData,
                fallbackAssetName: item.category == .venue ? "WeddingVenueHero" : nil,
                colors: item.category.artworkColors,
                accent: item.category.artworkAccent,
                purpose: item.purpose,
                statusTitle: item.status.title,
                statusSymbol: item.status.symbol,
                peopleLabel: item.purpose == .eventExperience ? "Hosted By" : "Planning Team",
                people: participants.isEmpty
                    ? [item.purpose == .eventExperience ? "Your hosts" : "Planning team"]
                    : participants,
                response: item.response,
                permitsResponse: item.status != .archived,
                note: item.eventDescription,
                dressCode: item.dressCode,
                guestIdeas: workspace.invitationIdeas(for: reference),
                children: [],
                moments: workspace.moments(for: .subevent(id))
            )

        case .idea(let id):
            guard let idea = workspace.ideas.first(where: { $0.id == id }),
                  let configuration = idea.eventConfiguration else { return nil }

            return EventPresentation(
                title: idea.title,
                eyebrow: "Proposed \(configuration.purpose.shortTitle) Event",
                categoryTitle: configuration.category.title,
                categorySymbol: configuration.category.symbol,
                startsAt: configuration.proposedDate,
                endsAt: configuration.proposedEndDate,
                isAllDay: configuration.isAllDay,
                timeZoneIdentifier: configuration.timeZoneIdentifier,
                location: configuration.location,
                imageData: idea.imageData,
                fallbackAssetName: configuration.category == .venue ? "WeddingVenueHero" : nil,
                colors: configuration.category.artworkColors,
                accent: configuration.category.artworkAccent,
                purpose: configuration.purpose,
                statusTitle: idea.status.title,
                statusSymbol: idea.status.symbol,
                peopleLabel: "Proposed By",
                people: [idea.submittedBy],
                response: nil,
                permitsResponse: false,
                note: idea.note,
                dressCode: "",
                guestIdeas: [],
                children: [],
                moments: workspace.moments(for: .idea(id))
            )
        }
    }

    private var weatherRequestID: String {
        guard let presentation else { return reference.id }
        return [
            reference.id,
            presentation.startsAt?.timeIntervalSinceReferenceDate.formatted() ?? "no-date",
            presentation.location?.latitude?.formatted() ?? "no-latitude",
            presentation.location?.longitude?.formatted() ?? "no-longitude"
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if let presentation {
                GeometryReader { proxy in
                    let heroHeight = max(
                        proxy.size.height + proxy.safeAreaInsets.top,
                        dynamicTypeSize.isAccessibilitySize ? 760 : 680
                    )

                    ZStack {
                        EventInvitationBackdrop(
                            presentation: presentation,
                            blurProgress: blurProgress,
                            reduceMotion: reduceMotion,
                            reduceTransparency: reduceTransparency
                        )

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                hero(presentation, height: heroHeight)
                                information(presentation)
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
            } else {
                ContentUnavailableView("Event unavailable", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .background(.black)
        .navigationDestination(item: $selectedChild) { item in
            TimelineEventReadOnlyView(item: item, transitionNamespace: childTransition)
        }
        .task(id: weatherRequestID) {
            guard let presentation, let startsAt = presentation.startsAt else { return }
            await weather.load(on: startsAt, location: presentation.location)
        }
        .onChange(of: selectedMomentPhotos) { _, items in
            guard !items.isEmpty, workspace.canAddEventMoments(to: reference) else { return }

            Task {
                for item in items {
                    guard let imageData = try? await item.loadTransferable(type: Data.self) else { continue }
                    workspace.addEventMoment(imageData, to: reference)
                }
                selectedMomentPhotos = []
            }
        }
    }

    private var blurProgress: CGFloat {
        min(max(scrollOffset / 220, 0), 1)
    }

    private func hero(_ event: EventPresentation, height: CGFloat) -> some View {
        VStack(spacing: AppTheme.Spacing.standard) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 150 : 260)

            VStack(spacing: AppTheme.Spacing.standard) {
                Text(event.eyebrow)
                    .font(.subheadline.weight(.medium))

                Text(event.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if reference == .main {
                    Text("invite you to celebrate with them")
                        .font(.body)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 6) {
                    if let startsAt = event.startsAt {
                        Text(startsAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                            .font(.headline)
                    } else {
                        Text("Date to be decided")
                            .font(.headline)
                    }

                    if let location = event.location {
                        Text(location.title)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)

            if event.permitsResponse || event.response != nil {
                EventResponseControl(selection: event.response) { response in
                    withAnimation(.snappy) {
                        setResponse(response)
                    }
                }
                .disabled(!event.permitsResponse)
                .padding(.top, AppTheme.Spacing.compact)
                .appImageOverlayAppearance()
                .accessibilityLabel("Attendance response")
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
        .padding(AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func information(_ event: EventPresentation) -> some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            hostCard(event)
            timingCard(event)

            if let location = event.location {
                if event.startsAt != nil {
                    EventInvitationWeatherView(
                        phase: weather.phase,
                        attribution: weather.attribution,
                        eventDate: event.startsAt
                    ) {
                        Task {
                            guard let startsAt = event.startsAt else { return }
                            await weather.load(on: startsAt, location: event.location)
                        }
                    }
                }

                EventInvitationLocationView(location: location)
            }

            momentsCard(event.moments)

            if reference.canHaveChildren, !event.children.isEmpty {
                scheduleCard(event.children)
            }

            attireCard(event)

            ForEach(invitationIdeaGroups(for: event)) { group in
                invitationIdeaCard(group)
            }

            if !event.note.isEmpty {
                EventInvitationSection(
                    title: reference == .main ? "A Note From Us" : "About This Event",
                    symbol: "text.quote"
                ) {
                    Text(event.note)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, AppTheme.Layout.screenHorizontal)
        .padding(.top, AppTheme.Spacing.section)
        .padding(.bottom, AppTheme.Layout.screenBottom + AppTheme.Spacing.section)
        .foregroundStyle(.white)
        .appImageOverlayAppearance()
    }

    private func hostCard(_ event: EventPresentation) -> some View {
        EventInvitationFeatureCard {
            VStack(spacing: AppTheme.Spacing.standard) {
                Text(event.peopleLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))

                EventPeopleBubbles(names: event.people)

                Text(event.people.formatted())
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func timingCard(_ event: EventPresentation) -> some View {
        EventInvitationFeatureCard {
            VStack(spacing: AppTheme.Spacing.standard) {
                Label(event.categoryTitle, systemImage: event.categorySymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))

                Text(scheduleSummary(event))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppTheme.Spacing.compact) {
                        eventMetadataPill(event.statusTitle, symbol: event.statusSymbol)
                        if let purpose = event.purpose {
                            eventMetadataPill(purpose.shortTitle, symbol: purpose.symbol)
                        }
                    }

                    VStack(spacing: AppTheme.Spacing.compact) {
                        eventMetadataPill(event.statusTitle, symbol: event.statusSymbol)
                        if let purpose = event.purpose {
                            eventMetadataPill(purpose.shortTitle, symbol: purpose.symbol)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func attireCard(_ event: EventPresentation) -> some View {
        let options = attireOptions(for: event)
        if !options.isEmpty {
            EventInvitationSection(title: "Dress Code", symbol: "tshirt.fill") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    if options.count > 1 {
                        Text("Any of these styles are welcome.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    ForEach(options) { option in
                        HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.82))
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.title)
                                    .font(.headline)

                                if let detail = option.detail {
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(AppTheme.Spacing.compact)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.10), in: RoundedRectangle(
                            cornerRadius: AppTheme.Radius.control,
                            style: .continuous
                        ))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func invitationIdeaCard(_ group: InvitationIdeaGroup) -> some View {
        EventInvitationSection(title: group.category.title, symbol: group.category.symbol) {
            VStack(spacing: AppTheme.Spacing.compact) {
                ForEach(group.ideas) { idea in
                    HStack(alignment: .center, spacing: AppTheme.Spacing.compact) {
                        if let imageData = idea.imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(
                                    cornerRadius: AppTheme.Radius.control,
                                    style: .continuous
                                ))
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: group.category.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.82))
                                .frame(width: 58, height: 58)
                                .background(.white.opacity(0.10), in: RoundedRectangle(
                                    cornerRadius: AppTheme.Radius.control,
                                    style: .continuous
                                ))
                                .accessibilityHidden(true)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(idea.title)
                                .font(.headline)

                            if let detail = invitationDetail(for: idea) {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(3)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(AppTheme.Spacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.10), in: RoundedRectangle(
                        cornerRadius: AppTheme.Radius.control,
                        style: .continuous
                    ))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func attireOptions(for event: EventPresentation) -> [InvitationAttireOption] {
        var options: [InvitationAttireOption] = []
        var seen: Set<String> = []

        func append(title: String, detail: String? = nil, id: String) {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return }
            let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDetail = trimmedDetail.flatMap { $0.isEmpty ? nil : $0 }
            let key = "\(trimmedTitle.lowercased())|\(normalizedDetail?.lowercased() ?? "")"
            guard seen.insert(key).inserted else { return }
            options.append(InvitationAttireOption(id: id, title: trimmedTitle, detail: normalizedDetail))
        }

        append(title: event.dressCode, id: "event-dress-code")

        for idea in event.guestIdeas where idea.category == .attire {
            guard let configuration = idea.attireConfiguration else { continue }
            let title = configuration.style == .any
                ? (idea.title == "Attire" ? "Any attire" : idea.title)
                : configuration.style.title
            let details = [configuration.restrictions, idea.note]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare(title) != .orderedSame }
            append(
                title: title,
                detail: details.isEmpty ? nil : details.joined(separator: " · "),
                id: idea.id.uuidString
            )
        }

        return options
    }

    private func invitationIdeaGroups(for event: EventPresentation) -> [InvitationIdeaGroup] {
        IdeaCategory.allCases.compactMap { category in
            guard category != .attire else { return nil }
            let ideas = event.guestIdeas.filter { $0.category == category }
            return ideas.isEmpty ? nil : InvitationIdeaGroup(category: category, ideas: ideas)
        }
    }

    private func invitationDetail(for idea: WeddingIdea) -> String? {
        var details: [String] = []
        switch idea.configuration {
        case .standard:
            break
        case .attire:
            break
        case .venue(let configuration):
            details.append(configuration.setting.title)
            details.append(configuration.area)
        case .food(let configuration):
            details.append(configuration.type.title)
            details.append(configuration.dietaryNotes)
        case .flowers(let configuration):
            details.append(configuration.focus.title)
            details.append(configuration.palette)
        case .photography(let configuration):
            details.append(configuration.style.title)
            details.append(configuration.priorities)
        case .decor(let configuration):
            details.append(configuration.focus.title)
            details.append(configuration.paletteOrMaterials)
        case .invitations(let configuration):
            details.append(configuration.format.title)
            details.append(configuration.productionNotes)
        case .honeymoon(let configuration):
            details.append(configuration.style.title)
            details.append(configuration.destination)
        case .music(let configuration):
            details.append(contentsOf: configuration.tracks.prefix(3).map(\.title))
        case .event, .registry:
            break
        }
        details.append(idea.note)

        var seen: Set<String> = []
        let meaningfulDetails = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && $0.caseInsensitiveCompare(idea.title) != .orderedSame
                    && seen.insert($0.lowercased()).inserted
            }
        return meaningfulDetails.isEmpty ? nil : meaningfulDetails.joined(separator: " · ")
    }

    private func eventMetadataPill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private func scheduleCard(_ children: [TimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Label("Schedule", systemImage: "clock.fill")
                .font(.title3.bold())

            ScrollView(.horizontal) {
                LazyHStack(alignment: .center, spacing: 12) {
                    ForEach(children) { item in
                        TimelineEventCard(
                            item: item,
                            transitionNamespace: childTransition,
                            showsPlanningStatus: false,
                            cardAspectRatio: 0.78
                        ) {
                            selectedChild = item
                        }
                        .containerRelativeFrame(.horizontal) { length, _ in
                            dynamicTypeSize.isAccessibilitySize ? length : min(max(length * 0.78, 250), 340)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
    }

    private func momentsCard(_ moments: [EventMoment]) -> some View {
        EventInvitationFeatureCard {
            VStack(spacing: AppTheme.Spacing.standard) {
                Label("Shared Album", systemImage: "photo.on.rectangle.angled")
                    .font(.title3.bold())

                if moments.isEmpty {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(height: 112)

                    Text("Photos shared during the event will gather here.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                } else {
                    GeometryReader { proxy in
                        let visibleMoments = Array(moments.prefix(3))
                        let overlap: CGFloat = 24
                        let photoWidth = min(
                            118,
                            max(82, (proxy.size.width + overlap * CGFloat(visibleMoments.count - 1)) / CGFloat(visibleMoments.count))
                        )
                        let centerIndex = Double(visibleMoments.count - 1) / 2

                        HStack(spacing: -overlap) {
                            ForEach(Array(visibleMoments.enumerated()), id: \.element.id) { index, moment in
                                if let image = UIImage(data: moment.imageData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: photoWidth, height: min(photoWidth * 1.25, 148))
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: AppTheme.Radius.control,
                                                style: .continuous
                                            )
                                        )
                                        .overlay {
                                            RoundedRectangle(
                                                cornerRadius: AppTheme.Radius.control,
                                                style: .continuous
                                            )
                                            .stroke(.white.opacity(0.26), lineWidth: 0.5)
                                        }
                                        .rotationEffect(.degrees((Double(index) - centerIndex) * 5))
                                        .zIndex(Double(visibleMoments.count - index))
                                        .accessibilityLabel("Photo added by \(moment.addedBy)")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 158)
                }

                if workspace.canAddEventMoments(to: reference) {
                    PhotosPicker(
                        selection: $selectedMomentPhotos,
                        maxSelectionCount: 20,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .font(.headline)
                            .padding(.horizontal, AppTheme.Spacing.spacious)
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func scheduleSummary(_ event: EventPresentation) -> String {
        guard let startsAt = event.startsAt else { return "To be decided" }
        return EventSchedule(
            startsAt: startsAt,
            endsAt: event.endsAt,
            isAllDay: event.isAllDay,
            timeZoneIdentifier: event.timeZoneIdentifier
        ).summary
    }

    private func setResponse(_ response: EventResponse) {
        switch reference {
        case .main:
            workspace.setMainEventResponse(response)
        case .subevent(let id):
            guard let item = workspace.timeline.first(where: { $0.id == id }) else { return }
            workspace.setResponse(response, for: item)
        case .idea:
            break
        }
    }
}

private struct EventPresentation {
    let title: String
    let eyebrow: String
    let categoryTitle: String
    let categorySymbol: String
    let startsAt: Date?
    let endsAt: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let location: EventLocation?
    let imageData: Data?
    let fallbackAssetName: String?
    let colors: [Color]
    let accent: Color
    let purpose: EventPurpose?
    let statusTitle: String
    let statusSymbol: String
    let peopleLabel: String
    let people: [String]
    let response: EventResponse?
    let permitsResponse: Bool
    let note: String
    let dressCode: String
    let guestIdeas: [WeddingIdea]
    let children: [TimelineItem]
    let moments: [EventMoment]
}

private struct InvitationAttireOption: Identifiable {
    let id: String
    let title: String
    let detail: String?
}

private struct InvitationIdeaGroup: Identifiable {
    let category: IdeaCategory
    let ideas: [WeddingIdea]

    var id: IdeaCategory { category }
}

private struct EventInvitationBackdrop: View {
    let presentation: EventPresentation
    let blurProgress: CGFloat
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            let activeProgress = reduceMotion ? 0 : blurProgress
            ZStack {
                Color.black
                artwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1 + (0.06 * activeProgress))
                    .blur(radius: reduceTransparency ? 0 : 38 * activeProgress, opaque: true)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.02), location: 0),
                        .init(color: .black.opacity(0.18 + 0.18 * blurProgress), location: 0.55),
                        .init(color: .black.opacity(0.64 + 0.18 * blurProgress), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageData = presentation.imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let fallbackAssetName = presentation.fallbackAssetName {
            Image(fallbackAssetName)
                .resizable()
                .scaledToFill()
        } else {
            MediaArtwork(
                imageData: nil,
                symbol: presentation.categorySymbol,
                colors: presentation.colors,
                accent: presentation.accent,
                ambientBlurRadius: 8,
                progressiveBlurRadius: 0,
                blurStart: 1
            )
        }
    }
}

private struct EventInvitationFeatureCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let contentPadding: CGFloat
    @ViewBuilder let content: Content

    init(
        contentPadding: CGFloat = AppTheme.Spacing.spacious,
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                if reduceTransparency {
                    shape.fill(.black.opacity(0.92))
                } else {
                    shape
                        .fill(.regularMaterial)
                        .overlay(shape.fill(.black.opacity(0.38)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(.white.opacity(reduceTransparency ? 0.14 : 0.22), lineWidth: 0.5)
            }
            .foregroundStyle(.white)
    }
}

private struct EventPeopleBubbles: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(names.prefix(5).enumerated()), id: \.offset) { index, name in
                Text(initials(for: name))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(bubbleColor(at: index), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 2))
                    .accessibilityHidden(true)
            }

            if names.count > 5 {
                Text("+\(names.count - 5)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.18), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 2))
                    .accessibilityHidden(true)
            }
        }
    }

    private func initials(for name: String) -> String {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return String(initials).uppercased()
    }

    private func bubbleColor(at index: Int) -> Color {
        let palette: [Color] = [.blue, .indigo, .teal, .purple, .cyan]
        return palette[index % palette.count].opacity(0.88)
    }
}

private struct EventInvitationWeatherView: View {
    @Environment(\.colorScheme) private var colorScheme

    let phase: EventWeatherPhase
    let attribution: EventWeatherAttribution?
    let eventDate: Date?
    let retry: () -> Void

    var body: some View {
        EventInvitationFeatureCard {
            VStack(spacing: AppTheme.Spacing.standard) {
                VStack(spacing: 3) {
                    Text("Weather")
                        .font(.title3.bold())

                    if let eventDate {
                        Text(eventDate, format: .dateTime.month(.wide).day())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                weatherContent
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var weatherContent: some View {
        switch phase {
        case .idle, .loading:
            ProgressView("Checking the forecast…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(minHeight: 76)

        case .forecast(let forecast):
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 42))
                .accessibilityHidden(true)

            Text(
                "Expect \(forecast.conditionDescription.lowercased()), with a high of " +
                "\(forecast.highTemperatureText) and a low of \(forecast.lowTemperatureText)."
            )
            .font(.title3.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)

            Label(
                "\(forecast.precipitationChanceText) chance of precipitation",
                systemImage: "drop.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))

            if let attribution {
                weatherAttribution(attribution)
            }

        case .outsideForecastRange:
            weatherMessage(
                "A forecast will appear within 10 days of the event.",
                symbol: "calendar.badge.clock"
            )

        case .pastEvent:
            weatherMessage("This event has already taken place.", symbol: "clock.arrow.circlepath")

        case .missingLocation:
            weatherMessage("Add a mapped location to see weather here.", symbol: "mappin.slash")

        case .unavailable:
            weatherMessage("The forecast isn’t available right now.", symbol: "cloud.sun")
            Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    private func weatherMessage(_ message: String, symbol: String) -> some View {
        VStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: symbol)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityHidden(true)
            Text(message)
                .font(.body.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(minHeight: 88)
    }

    private func weatherAttribution(_ attribution: EventWeatherAttribution) -> some View {
        Link(destination: attribution.legalPageURL) {
            AsyncImage(
                url: colorScheme == .light
                    ? attribution.combinedMarkLightURL
                    : attribution.combinedMarkDarkURL
            ) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Text(attribution.serviceName)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .frame(width: 92, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Weather data attribution")
        .accessibilityHint("Opens Apple Weather data sources")
    }
}

private struct EventInvitationSection<Content: View>: View {
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
            let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            if reduceTransparency {
                shape.fill(.black.opacity(0.92))
            } else {
                shape.fill(.regularMaterial).overlay(shape.fill(.black.opacity(0.46)))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
    }
}

private struct EventInvitationLocationView: View {
    let location: EventLocation

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = location.latitude, let longitude = location.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var mapsURL: URL? {
        let query = location.formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let coordinate {
            return URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)")
        }
        return query.isEmpty ? nil : URL(string: "https://maps.apple.com/?q=\(query)")
    }

    var body: some View {
        EventInvitationFeatureCard(contentPadding: 0) {
            VStack(spacing: 0) {
                VStack(spacing: AppTheme.Spacing.standard) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.title3.bold())

                    Text(location.formatted)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                }
                .padding(AppTheme.Spacing.spacious)

                if let coordinate {
                    if let mapsURL {
                        Link(destination: mapsURL) {
                            staticMap(coordinate: coordinate)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(location.title) in Maps")
                        .accessibilityHint("Opens directions in Apple Maps")
                    } else {
                        staticMap(coordinate: coordinate)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func staticMap(coordinate: CLLocationCoordinate2D) -> some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            ),
            interactionModes: []
        ) {
            Marker(location.title, coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 260)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottomTrailing) {
            Label("Open in Maps", systemImage: "arrow.up.forward.app.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .background(.regularMaterial, in: Capsule())
                .padding(AppTheme.Spacing.compact)
        }
        .accessibilityHidden(true)
    }
}
