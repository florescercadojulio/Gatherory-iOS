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
            .padding(.horizontal, AppTheme.Spacing.standard)
            .padding(.bottom, AppTheme.Spacing.section)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("I Said Yes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add idea", systemImage: "plus") { }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("Opens the new wedding idea form")
            }
        }
    }

    private var weddingHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(workspace.title)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.8)

            Text(workspace.weddingDate, format: .dateTime.month(.wide).day().year())
                .font(.headline)
                .foregroundStyle(.secondary)

            Label("\(daysRemaining) days to go", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, AppTheme.Spacing.compact)
    }

    private var planningModeCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack(alignment: .top) {
                Image(systemName: workspace.planningMode.symbol)
                    .font(.title2)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Planning mode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(workspace.planningMode.title)
                        .font(.title3.bold())
                    Text(workspace.planningMode.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            }
            .buttonStyle(.bordered)
        }
        .appCard()
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.standard) {
            MetricCard(
                value: "\(workspace.decisionQueue.count)",
                label: "To decide",
                symbol: "rectangle.on.rectangle.angled",
                tint: .purple
            )
            MetricCard(
                value: "\(workspace.ideas.filter { $0.status == .shortlisted }.count)",
                label: "Shortlisted",
                symbol: "heart.fill",
                tint: .pink
            )
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            Text("Coming up")
                .font(.title2.bold())

            ForEach(workspace.upcomingTimeline.prefix(3)) { item in
                HStack(spacing: AppTheme.Spacing.standard) {
                    VStack(spacing: 2) {
                        Text(item.dueDate, format: .dateTime.month(.abbreviated))
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                        Text(item.dueDate, format: .dateTime.day())
                            .font(.title2.bold())
                    }
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.owner)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .appCard()
            }
        }
    }

    private var supportCircle: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack {
                Text("Your support circle")
                    .font(.title2.bold())
                Spacer()
                Button("Manage") { }
            }

            HStack(spacing: -8) {
                ForEach(workspace.members.prefix(5)) { member in
                    Text(member.initials)
                        .font(.subheadline.bold())
                        .frame(width: 44, height: 44)
                        .background(AppTheme.ColorToken.elevatedSurface, in: Circle())
                        .overlay(Circle().stroke(AppTheme.ColorToken.background, lineWidth: 3))
                        .accessibilityLabel("\(member.name), \(member.role)")
                }
            }
        }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value)
                .font(.title.bold())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environment(WeddingWorkspace.sample)
    }
}
