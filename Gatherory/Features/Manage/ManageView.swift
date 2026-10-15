import SwiftUI

/// Read-only projections for navigation. Selecting a tool never changes Home's
/// event selection or writes an archive/outbox mutation.
@MainActor
struct ManageEventSummary: Identifiable {
    let reference: EventReference
    let eventID: UUID
    let title: String
    let spent: Decimal
    let budget: Decimal?
    let goingCount: Int
    let awaitingRSVPCount: Int
    let collaboratorCount: Int
    let attendance: ManageAttendanceSummary
    let canManageInvitations: Bool
    let canSendNote: Bool

    var id: UUID { eventID }

    static func references(in workspace: PlanningWorkspace) -> [EventReference] {
        guard workspace.showsPlanningInterface else { return [] }
        let main: [EventReference] = workspace.isMainEventDeleted ? [] : [.main]
        guard !workspace.isScopedEvent else { return main }
        return main + workspace.childEvents.map { .subevent($0.id) }
    }

    init?(workspace: PlanningWorkspace, reference: EventReference) {
        guard Self.references(in: workspace).contains(reference) else { return nil }
        self.reference = reference
        switch reference {
        case .main: eventID = workspace.mainEventID
        case .subevent(let id): eventID = id
        case .idea: return nil
        }
        title = workspace.eventTitle(for: eventID)
        spent = workspace.costTotal(for: reference)
        budget = workspace.budgetCap(for: reference)
        let people = workspace.participants(for: reference)
        attendance = ManageAttendanceSummary(participants: people)
        goingCount = people.filter { $0.attendance == .going }.count
        awaitingRSVPCount = people.filter { $0.attendance == .invited }.count
        collaboratorCount = people.filter { $0.participantRole != .guest }.count
        canManageInvitations = workspace.canManageInvitations(for: reference)
        canSendNote = workspace.canSendNote(to: reference)
    }
}

private enum ManageDestination: Hashable {
    case budget(EventReference)
}

struct ManageView: View {
    var isActive = true
    var onExitWorkspace: (() -> Void)?
    @Environment(PlanningWorkspace.self) private var workspace
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: EventReference = .main
    @State private var hasInitializedSelection = false

    private var references: [EventReference] { ManageEventSummary.references(in: workspace) }
    private var reference: EventReference { references.contains(selection) ? selection : references.first ?? .main }
    private var summary: ManageEventSummary? { ManageEventSummary(workspace: workspace, reference: reference) }
    private var approvalMetric: ManageMetric {
        guard let summary, summary.canManageInvitations else {
            return ManageMetric(value: "—", label: String(localized: "Manager only"))
        }
        let store = workspace.joinRequestStore
        if store.error(eventID: summary.eventID, accountID: authentication.currentUser?.id) != nil {
            return ManageMetric(value: "—", label: String(localized: "Requests unavailable"))
        }
        return ManageMetric(
            value: store.requestCount(eventID: summary.eventID, accountID: authentication.currentUser?.id)?.formatted() ?? "—",
            label: String(localized: "Awaiting approval")
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.spacious) {
                if let summary {
                    Group {
                        if references.count > 1 {
                            Picker("Event", selection: $selection) {
                                ForEach(references) { item in
                                    if let event = ManageEventSummary(workspace: workspace, reference: item) {
                                        Text(event.title).tag(item)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Text(summary.title).font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.Spacing.compact)

                    NavigationLink(value: ManageDestination.budget(reference)) {
                        ManageMetricPill(title: "Budget", symbol: "chart.bar.xaxis",
                            leading: ManageMetric(value: summary.spent.formatted(.currency(code: workspace.currencyCode)), label: String(localized: "Spent")),
                            trailing: .remaining(spent: summary.spent, budget: summary.budget, currencyCode: workspace.currencyCode))
                    }
                    ManagePeoplePill(summary: summary, approval: approvalMetric)
                    ManageNotesPreview(reference: reference)
                    if !workspace.visibleGuides(for: reference).isEmpty {
                        NavigationLink {
                            ExperienceGuidanceView(reference: reference)
                        } label: {
                            HStack {
                                Label("Planning Guide", systemImage: "book.closed")
                                Spacer()
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            .font(.headline)
                            .padding(AppTheme.Spacing.spacious)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                            .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                        }
                    }
                } else {
                    ContentUnavailableView("Manage", systemImage: "lock", description: Text("No planning event is available."))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.Layout.screenHorizontal)
            .padding(.top, AppTheme.Layout.screenTop)
            .padding(.bottom, AppTheme.Layout.screenBottom)
        }
        .background(AppTheme.ColorToken.background)
        .appSoftScrollEdges()
        .navigationTitle(AppCopy.Tab.manage)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onExitWorkspace {
                ToolbarItem(placement: .topBarLeading) { WorkspaceLibraryToolbarButton(action: onExitWorkspace) }
            }
            ToolbarItem(placement: .topBarTrailing) { AccountToolbarButton() }
        }
        .navigationDestination(for: ManageDestination.self) { destination in
            switch destination {
            case .budget(let reference): BudgetView(reference: reference)
            }
        }
        .onAppear {
            if !hasInitializedSelection {
                selection = references.contains(workspace.selectedEventReference) ? workspace.selectedEventReference : references.first ?? .main
                hasInitializedSelection = true
            }
        }
        .onChange(of: references) { _, values in
            if !values.contains(selection) { selection = values.first ?? .main }
        }
        .task(id: "\(summary?.eventID.uuidString ?? "")|\(authentication.currentUser?.id ?? "")|\(summary?.canManageInvitations == true)|\(scenePhase)|\(isActive)") {
            await refreshRequests()
        }
        .refreshable { await refreshRequests(force: true) }
    }

    private func refreshRequests(force: Bool = false) async {
        guard isActive, scenePhase == .active, let summary, summary.canManageInvitations,
              let accountID = authentication.currentUser?.id else { return }
        await workspace.joinRequestStore.refresh(eventID: summary.eventID, accountID: accountID, force: force)
    }
}

struct ManageMetric {
    let value: String
    let label: String
    var isWarning = false

    static func remaining(spent: Decimal, budget: Decimal?, currencyCode: String) -> Self {
        guard let budget else {
            return Self(value: "—", label: String(localized: "No budget set"))
        }
        let remaining = budget - spent
        return Self(
            value: abs(remaining).formatted(.currency(code: currencyCode)),
            label: remaining < .zero ? String(localized: "Over budget") : String(localized: "Remaining"),
            isWarning: remaining < .zero
        )
    }
}

/// Each entire pill remains one navigation target. Values lead visually, while
/// VoiceOver reads the title and both labeled metrics as one element.
private struct ManageMetricPill: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let symbol: String
    let leading: ManageMetric
    let trailing: ManageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                Spacer(minLength: AppTheme.Spacing.compact)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppTheme.Spacing.standard) {
                    metric(leading)
                    Divider().accessibilityHidden(true)
                    metric(trailing)
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.Spacing.standard) {
                    metric(leading)
                    Divider().accessibilityHidden(true)
                    metric(trailing)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, AppTheme.Spacing.spacious)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func metric(_ metric: ManageMetric) -> some View {
        VStack(spacing: 5) {
            Text(metric.value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(metric.isWarning ? AppTheme.ColorToken.destructive : AppTheme.ColorToken.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(metric.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
