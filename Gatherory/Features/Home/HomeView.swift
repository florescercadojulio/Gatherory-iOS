import Glur
import SwiftUI

struct HomeView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedIdeaID: UUID?
    @State private var isInvitingCollaborators = false
    @State private var isShowingInvitationPreview = false
    @Namespace private var ideaTransition
    @Namespace private var invitationTransition

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.weddingDate).day ?? 0, 0)
    }

    private var goingMembers: [WeddingMember] {
        workspace.members.filter { $0.attendance == .going }
    }

    private var chosenIdeas: [WeddingIdea] {
        workspace.ideas.filter { $0.status == .chosen }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                Button {
                    isShowingInvitationPreview = true
                } label: {
                    eventHero
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the guest invitation preview")

                eventActions
                confirmedPlans
                nextMoment
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Our wedding")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton()
            }
        }
        .navigationDestination(item: $selectedIdeaID) { ideaID in
            IdeaDetailView(
                ideaID: ideaID,
                transitionNamespace: ideaTransition
            )
        }
        .navigationDestination(isPresented: $isShowingInvitationPreview) {
            InvitationPreviewView(transitionNamespace: invitationTransition)
        }
        .fullScreenCover(isPresented: $isInvitingCollaborators) {
            CollaborationInviteView()
                .environment(workspace)
        }
    }

    private var eventHero: some View {
        ZStack(alignment: .bottom) {
            venueArtwork

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

                attendeeSummary

                VStack(spacing: 8) {
                    Text(workspace.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(workspace.weddingDate, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Label("\(workspace.venueName) · \(workspace.location)", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(daysRemaining) days away")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, AppTheme.Spacing.compact)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }
            .foregroundStyle(.white)
            .padding(AppTheme.Spacing.spacious)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 650 : 570)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
        .matchedTransitionSource(id: InvitationTransitionID.mainEvent, in: invitationTransition)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(workspace.title), \(workspace.weddingDate.formatted(date: .long, time: .omitted)), " +
            "at \(workspace.venueName), \(workspace.location). \(goingMembers.count) going. " +
            "\(daysRemaining) days to go."
        )
    }

    @ViewBuilder
    private var venueArtwork: some View {
        let artwork = Image("WeddingVenueHero")
            .resizable()
            .scaledToFill()

        if reduceTransparency {
            artwork
        } else {
            artwork.glur(
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

    private var eventActions: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            Button("Send a note", systemImage: "megaphone.fill") { }
                .frame(maxWidth: .infinity)

            Button("Invite", systemImage: "person.badge.plus") {
                isInvitingCollaborators = true
            }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    private var confirmedPlans: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("The wedding so far")
                .font(AppTheme.Typography.sectionTitle)

            ForEach(chosenIdeas) { idea in
                ConfirmedPlanRow(
                    idea: idea,
                    venueImageName: idea.category == .venue ? "WeddingVenueHero" : nil,
                    transitionNamespace: ideaTransition,
                    open: {
                        selectedIdeaID = idea.id
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var nextMoment: some View {
        if let item = workspace.upcomingTimeline.first {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                Text("Next up")
                    .font(AppTheme.Typography.sectionTitle)

                HStack(spacing: AppTheme.Spacing.standard) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.ColorToken.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.scheduledAt, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .appCard(background: AppTheme.ColorToken.surface)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private enum InvitationTransitionID: Hashable {
    case mainEvent
}

private enum InvitationResponse: String, CaseIterable, Identifiable {
    case going
    case notSure
    case notGoing

    var id: Self { self }

    var title: String {
        switch self {
        case .going: "Going"
        case .notSure: "Not Sure"
        case .notGoing: "Can't Go"
        }
    }

    var symbol: String {
        switch self {
        case .going: "checkmark.circle.fill"
        case .notSure: "questionmark.circle.fill"
        case .notGoing: "xmark.circle.fill"
        }
    }
}

private struct InvitationMoment: Identifiable {
    let id = UUID()
    let title: String
    let time: Date
    let detail: String
    let symbol: String
}

private struct InvitationPreviewView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var response: InvitationResponse?

    let transitionNamespace: Namespace.ID

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

    private var schedule: [InvitationMoment] {
        [
            InvitationMoment(
                title: "Ceremony",
                time: eventTime(hour: 16),
                detail: "The garden at \(workspace.venueName)",
                symbol: "heart.fill"
            ),
            InvitationMoment(
                title: "Cocktail Hour",
                time: eventTime(hour: 17),
                detail: "Drinks and small bites on the terrace",
                symbol: "wineglass.fill"
            ),
            InvitationMoment(
                title: "Dinner & Dancing",
                time: eventTime(hour: 18),
                detail: "Dinner under the trees, followed by dancing",
                symbol: "music.note"
            )
        ]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
                invitationHero
                rsvpCard
                eventDetails
                scheduleCard
                musicCard
                dressCodeCard
                notesCard
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollIndicators(.hidden)
        .appSoftScrollEdges()
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .appClearNavigationBar()
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTransition(
            .zoom(sourceID: InvitationTransitionID.mainEvent, in: transitionNamespace)
        )
    }

    private var invitationHero: some View {
        ZStack(alignment: .bottom) {
            heroArtwork

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.30),
                    .init(color: .black.opacity(reduceTransparency ? 0.28 : 0.10), location: 0.50),
                    .init(color: .black.opacity(reduceTransparency ? 0.78 : 0.50), location: 0.74),
                    .init(color: .black.opacity(reduceTransparency ? 0.92 : 0.74), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

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

                    Text(workspace.venueName)
                        .font(.subheadline.weight(.semibold))

                    Text(workspace.location)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.34), radius: 10, y: 4)
            .padding(AppTheme.Spacing.spacious)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 690 : 610)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var heroArtwork: some View {
        let artwork = Image("WeddingVenueHero")
            .resizable()
            .scaledToFill()

        if reduceTransparency {
            artwork
        } else {
            artwork.glur(
                radius: 26,
                mask: .linear(
                    stops: [
                        .init(intensity: 0, location: 0),
                        .init(intensity: 0, location: 0.46),
                        .init(intensity: 0.18, location: 0.60),
                        .init(intensity: 0.74, location: 0.79),
                        .init(intensity: 1, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                noise: 0.025
            )
        }
    }

    private var rsvpCard: some View {
        InvitationSection(title: "Will You Join Us?", symbol: "envelope.open.fill") {
            Text("Kindly respond by \(responseDeadline.formatted(date: .long, time: .omitted)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppTheme.Spacing.compact) {
                    responseButtons
                }

                VStack(spacing: AppTheme.Spacing.compact) {
                    responseButtons
                }
            }

            if let response {
                Label(
                    response == .going ? "We can't wait to celebrate with you." : "Response saved for this preview.",
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
        ForEach(InvitationResponse.allCases) { option in
            Button {
                withAnimation(.snappy) {
                    response = option
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: option.symbol)
                        .font(.title3)

                    Text(option.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(response == option ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 62)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: AppTheme.Radius.control))
            .tint(
                response == option
                    ? AppTheme.ColorToken.accent
                    : Color(uiColor: .tertiarySystemFill)
            )
            .accessibilityValue(response == option ? "Selected" : "Not selected")
        }
    }

    private var eventDetails: some View {
        InvitationSection(title: "Details", symbol: "calendar") {
            InvitationDetailRow(
                symbol: "calendar",
                title: "Date",
                value: workspace.weddingDate.formatted(date: .long, time: .omitted)
            )

            InvitationDetailRow(
                symbol: "mappin.and.ellipse",
                title: "Location",
                value: "\(workspace.venueName)\n\(workspace.location)"
            )

            InvitationDetailRow(
                symbol: "person.2.fill",
                title: "Hosted By",
                value: hosts.map(\.name).formatted()
            )
        }
    }

    private var scheduleCard: some View {
        InvitationSection(title: "Schedule", symbol: "clock.fill") {
            ForEach(schedule) { moment in
                InvitationDetailRow(
                    symbol: moment.symbol,
                    title: moment.time.formatted(date: .omitted, time: .shortened),
                    value: "\(moment.title)\n\(moment.detail)"
                )
            }
        }
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
            Text("Garden formal")
                .font(.headline)

            Text("Dress for an outdoor ceremony and an evening of dinner and dancing.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var notesCard: some View {
        InvitationSection(title: "A Note From Us", symbol: "heart.text.square.fill") {
            Text(
                "Your presence means the world to us. The ceremony and reception will be outdoors, " +
                "so please plan for the evening weather."
            )
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

    private func eventTime(hour: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: 0,
            second: 0,
            of: workspace.weddingDate
        ) ?? workspace.weddingDate
    }
}

private struct InvitationSection<Content: View>: View {
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
        .background(
            AppTheme.ColorToken.surface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.ColorToken.hairline, lineWidth: 0.5)
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

private struct ConfirmedPlanRow: View {
    let idea: WeddingIdea
    let venueImageName: String?
    let transitionNamespace: Namespace.ID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: AppTheme.Spacing.standard) {
                artwork

                VStack(alignment: .leading, spacing: 5) {
                    Label(idea.category.title, systemImage: idea.category.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(idea.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(idea.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens idea details")
        .padding(AppTheme.Spacing.standard)
        .background(
            AppTheme.ColorToken.surface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let venueImageName {
            Image(venueImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                .matchedTransitionSource(id: idea.id, in: transitionNamespace)
                .accessibilityHidden(true)
        } else {
            MediaArtwork(
                imageData: idea.imageData,
                symbol: idea.category.symbol,
                colors: idea.category.artworkColors,
                accent: idea.category.artworkAccent,
                ambientBlurRadius: 4,
                progressiveBlurRadius: 0,
                blurStart: 1
            )
            .frame(width: 72, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
            .matchedTransitionSource(id: idea.id, in: transitionNamespace)
            .accessibilityHidden(true)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(WeddingWorkspace.sample)
    }
}
