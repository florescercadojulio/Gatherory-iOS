import SwiftUI

struct HomeView: View {
    @Environment(WeddingWorkspace.self) private var workspace

    private var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: .now, to: workspace.weddingDate).day ?? 0, 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                weddingHeader
                planningModeCard
                overviewGrid
                upcomingSection
                supportCircle
            }
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("I Said Yes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Opens the new wedding idea form")

                AccountToolbarButton()
            }
        }
    }

    private var weddingHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Together, on purpose")
                .editorialEyebrow()
                .foregroundStyle(.black.opacity(0.55))

            Text(workspace.title)
                .font(AppTheme.Typography.display)
                .tracking(-1)
                .minimumScaleFactor(0.8)

            Text(workspace.weddingDate, format: .dateTime.month(.wide).day().year())
                .font(.headline)
                .foregroundStyle(.black.opacity(0.62))

            Label("\(daysRemaining) days to go", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(
            background: AppTheme.ColorToken.lilac,
            foreground: AppTheme.ColorToken.onPastel,
            padding: AppTheme.Spacing.spacious,
            border: false
        )
    }

    private var planningModeCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .top) {
                Image(systemName: workspace.planningMode.symbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Planning mode")
                        .editorialEyebrow()
                        .foregroundStyle(.black.opacity(0.52))
                    Text(workspace.planningMode.title)
                        .font(AppTheme.Typography.cardTitle)
                    Text(workspace.planningMode.detail)
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.62))
                }

                Spacer(minLength: AppTheme.Spacing.compact)
            }

            Menu {
                ForEach(PlanningMode.allCases) { mode in
                    Button {
                        withAnimation {
                            workspace.planningMode = mode
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            } label: {
                Label("Change mode", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.black)
        }
        .appCard(
            background: AppTheme.ColorToken.cream,
            foreground: AppTheme.ColorToken.onPastel,
            padding: AppTheme.Spacing.spacious,
            border: false
        )
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.standard) {
            MetricCard(
                value: "\(workspace.decisionQueue.count)",
                label: "To decide",
                symbol: "rectangle.on.rectangle.angled",
                background: AppTheme.ColorToken.lime
            )
            MetricCard(
                value: "\(workspace.ideas.filter { $0.status == .shortlisted }.count)",
                label: "Shortlisted",
                symbol: "heart.fill",
                background: AppTheme.ColorToken.pink
            )
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("On the horizon")
                .editorialEyebrow()
                .foregroundStyle(.secondary)

            Text("Coming up")
                .font(AppTheme.Typography.sectionTitle)

            ForEach(workspace.upcomingTimeline.prefix(3)) { item in
                HStack(spacing: AppTheme.Spacing.standard) {
                    VStack(spacing: 2) {
                        Text(item.dueDate, format: .dateTime.month(.abbreviated))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                        Text(item.dueDate, format: .dateTime.day())
                            .font(.title2.bold())
                    }
                    .foregroundStyle(.black)
                    .frame(width: 48)
                    .padding(.vertical, AppTheme.Spacing.compact)
                    .background(AppTheme.ColorToken.lime, in: RoundedRectangle(cornerRadius: AppTheme.Radius.control))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.owner)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .appCard(background: AppTheme.ColorToken.surface)
            }
        }
    }

    private var supportCircle: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your people")
                        .editorialEyebrow()
                        .foregroundStyle(.black.opacity(0.52))
                    Text("Support circle")
                        .font(AppTheme.Typography.sectionTitle)
                }
                Spacer()
                Button("Manage") { }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.black)
            }

            HStack(spacing: -8) {
                ForEach(workspace.members.prefix(5)) { member in
                    Text(member.initials)
                        .font(.subheadline.bold())
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(AppTheme.ColorToken.pink, lineWidth: 3))
                        .accessibilityLabel("\(member.name), \(member.role)")
                }
            }
        }
        .appCard(
            background: AppTheme.ColorToken.pink,
            foreground: AppTheme.ColorToken.onPastel,
            padding: AppTheme.Spacing.spacious,
            border: false
        )
    }
}

private struct MetricCard: View {
    let value: String
    let label: String
    let symbol: String
    let background: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.black)
            Text(value)
                .font(.title.bold())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(background: background, foreground: .black, border: false)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(WeddingWorkspace.sample)
    }
}
