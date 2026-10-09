import MapKit
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
    @State private var weather = EventWeatherModel()
    @Namespace private var childTransition

    let reference: EventReference

    private var presentation: EventPresentation? {
        switch reference {
        case .main:
            let hosts = workspace.members
                .filter { $0.participantRole == .host }
                .map(\.name)
                .formatted()

            return EventPresentation(
                title: workspace.title,
                eyebrow: "Together with their families",
                categoryTitle: "Main Event",
                categorySymbol: "heart.fill",
                startsAt: workspace.weddingDate,
                endsAt: workspace.mainEventEndsAt,
                isAllDay: workspace.mainEventIsAllDay,
                location: workspace.mainEventLocation,
                imageData: workspace.mainEventImageData,
                fallbackAssetName: "WeddingVenueHero",
                colors: TimelineCategory.ceremony.artworkColors,
                accent: TimelineCategory.ceremony.artworkAccent,
                purpose: nil,
                statusTitle: workspace.currentMainEventStatus.title,
                statusSymbol: workspace.currentMainEventStatus.symbol,
                peopleLabel: "Hosted By",
                people: hosts.isEmpty ? "Your hosts" : hosts,
                response: workspace.mainEventResponse,
                permitsResponse: !workspace.currentMainEventStatus.isReadOnly,
                note: workspace.eventMessage,
                dressCode: workspace.dressCode,
                children: workspace.approvedChildEvents.filter { $0.purpose == .eventExperience },
                moments: workspace.mainEventMoments
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
                .formatted()

            return EventPresentation(
                title: item.title,
                eyebrow: item.purpose.title,
                categoryTitle: item.category.title,
                categorySymbol: item.category.symbol,
                startsAt: item.scheduledAt,
                endsAt: item.endsAt,
                isAllDay: item.isAllDay,
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
                    ? (item.purpose == .eventExperience ? "Your hosts" : "Planning team")
                    : participants,
                response: item.response,
                permitsResponse: item.status != .archived,
                note: item.eventDescription,
                dressCode: item.dressCode,
                children: [],
                moments: []
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
                endsAt: nil,
                isAllDay: false,
                location: configuration.location,
                imageData: idea.imageData,
                fallbackAssetName: configuration.category == .venue ? "WeddingVenueHero" : nil,
                colors: configuration.category.artworkColors,
                accent: configuration.category.artworkAccent,
                purpose: configuration.purpose,
                statusTitle: idea.status.title,
                statusSymbol: idea.status.symbol,
                peopleLabel: "Proposed By",
                people: idea.submittedBy,
                response: nil,
                permitsResponse: false,
                note: idea.note,
                dressCode: "",
                children: [],
                moments: []
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

                        if !location.detail.isEmpty {
                            Text(location.detail)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.84))
                        }
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
                .environment(\.colorScheme, .dark)
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
            if !event.moments.isEmpty {
                momentsCard(event.moments)
            }

            detailsCard(event)

            if reference.canHaveChildren, !event.children.isEmpty {
                scheduleCard(event.children)
            }

            if !event.dressCode.isEmpty {
                EventInvitationSection(title: "Dress Code", symbol: "tshirt.fill") {
                    Text(event.dressCode)
                        .font(.headline)
                }
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
        .environment(\.colorScheme, .dark)
    }

    private func detailsCard(_ event: EventPresentation) -> some View {
        EventInvitationSection(title: "Details", symbol: "calendar") {
            EventInvitationDetailRow(
                symbol: "calendar",
                title: "Date and Time",
                value: scheduleSummary(event)
            )

            if let purpose = event.purpose {
                EventInvitationDetailRow(
                    symbol: purpose.symbol,
                    title: "Purpose",
                    value: purpose.title
                )
            }

            if let location = event.location {
                EventInvitationLocationView(location: location)

                if event.startsAt != nil {
                    TimelineWeatherRow(phase: weather.phase, attribution: weather.attribution) {
                        Task {
                            guard let startsAt = event.startsAt else { return }
                            await weather.load(on: startsAt, location: event.location)
                        }
                    }
                }
            }

            EventInvitationDetailRow(
                symbol: "person.2.fill",
                title: event.peopleLabel,
                value: event.people
            )

            EventInvitationDetailRow(
                symbol: event.statusSymbol,
                title: reference == .main ? "Event Status" : "Planning Status",
                value: event.statusTitle
            )
        }
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
        EventInvitationSection(title: "Moments", symbol: "photo.on.rectangle.angled") {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppTheme.Spacing.compact
            ) {
                ForEach(moments) { moment in
                    if let image = UIImage(data: moment.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(0.82, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                    }
                }
            }
        }
    }

    private func scheduleSummary(_ event: EventPresentation) -> String {
        guard let startsAt = event.startsAt else { return "To be decided" }
        let start = startsAt.formatted(date: .long, time: event.isAllDay ? .omitted : .shortened)
        guard let endsAt = event.endsAt else {
            return event.isAllDay ? "\(start) · All-day" : start
        }
        return "\(start) – \(endsAt.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened))"
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
    let location: EventLocation?
    let imageData: Data?
    let fallbackAssetName: String?
    let colors: [Color]
    let accent: Color
    let purpose: EventPurpose?
    let statusTitle: String
    let statusSymbol: String
    let peopleLabel: String
    let people: String
    let response: EventResponse?
    let permitsResponse: Bool
    let note: String
    let dressCode: String
    let children: [TimelineItem]
    let moments: [EventMoment]
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

private struct EventInvitationDetailRow: View {
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
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.standard) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Location").font(.subheadline).foregroundStyle(.secondary)
                    Text(location.formatted).font(.body.weight(.semibold))
                }
                Spacer(minLength: 0)
                if let mapsURL {
                    Link(destination: mapsURL) {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }

            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ))) {
                    Marker(location.title, coordinate: coordinate)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            }
        }
    }
}
