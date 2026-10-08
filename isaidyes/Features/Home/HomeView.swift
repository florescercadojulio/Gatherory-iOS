import Glur
import SwiftUI

struct HomeView: View {
    @Environment(WeddingWorkspace.self) private var workspace
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedIdeaID: UUID?
    @State private var isInvitingCollaborators = false
    @Namespace private var ideaTransition

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
                eventHero
                eventActions
                confirmedPlans
                nextMoment
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Our wedding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
