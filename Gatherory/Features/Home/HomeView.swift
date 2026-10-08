import Glur
import SwiftUI

struct HomeView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isInvitingCollaborators = false
    @State private var isComposingNote = false
    @State private var isShowingInvitationPreview = false
    @Namespace private var invitationTransition

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.weddingDate).day ?? 0, 0)
    }

    private var goingMembers: [WeddingMember] {
        workspace.members.filter { $0.attendance == .going }
    }

    private var eventHeroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 720 : 640
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                eventHero
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Send a note", systemImage: "megaphone") {
                    isComposingNote = true
                }
                .labelStyle(.iconOnly)

                Button("Invite collaborators", systemImage: "person.badge.plus") {
                    isInvitingCollaborators = true
                }
                .labelStyle(.iconOnly)

                AccountToolbarButton()
            }
        }
        .navigationDestination(isPresented: $isShowingInvitationPreview) {
            InvitationPreviewView(transitionNamespace: invitationTransition)
        }
        .fullScreenCover(isPresented: $isInvitingCollaborators) {
            CollaborationInviteView()
                .environment(workspace)
        }
        .sheet(isPresented: $isComposingNote) {
            NoteComposerView()
                .environment(workspace)
        }
    }

    private var eventHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Button {
                    isShowingInvitationPreview = true
                } label: {
                    ZStack(alignment: .bottom) {
                        venueArtwork
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

                    VStack {
                        HStack {
                            EventStatusBadge(status: workspace.mainEventStatus)

                            Spacer(minLength: 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(AppTheme.Spacing.spacious)
                }
                    .frame(width: proxy.size.width, height: eventHeroHeight)
                    .clipped()
                    .matchedTransitionSource(id: InvitationTransitionID.mainEvent, in: invitationTransition)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the guest invitation preview")
                .accessibilityLabel(
                    "\(workspace.title), \(workspace.weddingDate.formatted(date: .long, time: .omitted)), " +
                    "at \(workspace.venueName), \(workspace.location). \(goingMembers.count) going. " +
                    "\(daysRemaining) days to go."
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
                        Text("Share an update with everyone helping plan this event.")

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

private enum InvitationTransitionID: Hashable {
    case mainEvent
}

private struct InvitationPreviewView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedScheduleItem: TimelineItem?

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
                && Calendar.current.isDate($0.scheduledAt, inSameDayAs: workspace.weddingDate)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = max(
                proxy.size.height + proxy.safeAreaInsets.top,
                dynamicTypeSize.isAccessibilitySize ? 760 : 680
            )

            ZStack {
                InvitationFixedBackdrop(
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
        .navigationTransition(
            .zoom(sourceID: InvitationTransitionID.mainEvent, in: transitionNamespace)
        )
        .navigationDestination(item: $selectedScheduleItem) { item in
            TimelineEventReadOnlyView(
                item: item,
                transitionNamespace: scheduleTransition
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
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }

    private var invitationInformation: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.spacious) {
            rsvpCard
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

    private var rsvpCard: some View {
        InvitationSection(title: "Will You Join Us?", symbol: "envelope.open.fill") {
            Text("Kindly respond by \(responseDeadline.formatted(date: .long, time: .omitted)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            responseButtons

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

                Image("WeddingVenueHero")
                    .resizable()
                    .scaledToFill()
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
