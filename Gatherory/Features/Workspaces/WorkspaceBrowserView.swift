import SwiftUI

@MainActor
private enum WorkspaceBrowserSheet: Identifiable {
    case addWorkspace
    case duplicateEvent(PlanningWorkspace, principalGeneration: UInt64)
    case blueprintCreateShare(PlanningWorkspace, createsShareLink: Bool)
    case blueprintLinks(BlueprintLinkManagementRequest)

    var id: String {
        switch self {
        case .addWorkspace: "add-workspace"
        case .duplicateEvent(let workspace, let generation): "duplicate-event-\(workspace.mainEventID.uuidString)-\(generation)"
        case .blueprintCreateShare(let workspace, let createsShareLink): "blueprint-create-share-\(workspace.mainEventID.uuidString)-\(createsShareLink)"
        case .blueprintLinks(let request): request.id.uuidString
        }
    }
}

@MainActor
enum WorkspaceBrowserRequestIdentity {
    static func isCurrent(
        workspace: PlanningWorkspace,
        principalGeneration: UInt64,
        expectedPrincipalGeneration: UInt64,
        isSigningOut: Bool,
        workspaces: [PlanningWorkspace]
    ) -> Bool {
        expectedPrincipalGeneration == principalGeneration
            && !isSigningOut
            && workspaces.contains(where: { $0 === workspace })
    }
}

@MainActor
struct WorkspaceBrowserEventActionRequest {
    let workspace: PlanningWorkspace
    let action: EventRemovalAction
    let title: String
    let principalGeneration: UInt64

    func isCurrent(
        principalGeneration: UInt64,
        isSigningOut: Bool,
        workspaces: [PlanningWorkspace]
    ) -> Bool {
        WorkspaceBrowserRequestIdentity.isCurrent(
            workspace: workspace,
            principalGeneration: self.principalGeneration,
            expectedPrincipalGeneration: principalGeneration,
            isSigningOut: isSigningOut,
            workspaces: workspaces
        )
    }
}

@MainActor
private struct WorkspaceBrowserEventActionConfirmation: ViewModifier {
    @Binding var request: WorkspaceBrowserEventActionRequest?
    @Binding var isUnavailable: Bool
    var onConfirm: (WorkspaceBrowserEventActionRequest) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                request?.title ?? AppCopy.EventRemoval.actions,
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                presenting: request
            ) { request in
                Button(request.action.title, role: .destructive) { onConfirm(request) }
                Button(AppCopy.Common.cancel, role: .cancel) {}
            } message: { request in
                Text(request.action.confirmationMessage)
            }
            .alert(
                AppCopy.EventRemoval.unavailableTitle,
                isPresented: $isUnavailable
            ) {
                Button(AppCopy.Common.done, role: .cancel) {}
            } message: {
                Text(AppCopy.EventRemoval.unavailableMessage)
            }
    }
}

struct WorkspaceBrowserView: View {
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(GuestInvitationStore.self) private var guests
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(AuthenticationSession.self) private var authentication
    @State private var activeSheet: WorkspaceBrowserSheet?
    @State private var pendingMainEventAction: WorkspaceBrowserEventActionRequest?
    @State private var isMainEventActionUnavailable = false
    @State private var selectedFilter: WorkspaceFilter = .all
    @State private var focusedEventID: UUID?
    var onExplore: () -> Void = {}

    private var filteredWorkspaces: [PlanningWorkspace] {
        selectedFilter.workspaces(from: browsableWorkspaces, for: authentication.currentUser)
    }

    private var browsableWorkspaces: [PlanningWorkspace] {
        let planning = library.workspaces.filter { $0.showsPlanningInterface || guests.presentations[$0.mainEventID] == nil }
        let represented = Set(planning.flatMap { [$0.mainEventID] + $0.timeline.map(\.id) })
        return planning + guests.events.compactMap { represented.contains($0.id) ? nil : guests.presentations[$0.id] }
    }

    var body: some View {
        Group {
            if filteredWorkspaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.standard) {
                        ForEach(filteredWorkspaces, id: \.mainEventID) { workspace in
                            Button {
                                if workspace.isInvitationProjection { guests.selectedEventID = workspace.mainEventID }
                                else { library.open(workspace) }
                                AppHaptics.play(.impact)
                            } label: {
                                WorkspacePreviewCard(workspace: workspace)
                            }
                            .buttonStyle(.plain)
                            .adaptiveReadingWidth(760)
                            .accessibilityIdentifier("events.event.\(workspace.mainEventID)")
                            .accessibilityHint("Opens this workspace")
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
                            .contextMenu {
                                mainEventDuplicateAction(for: workspace)
                                if sharingURL(for: workspace) != nil {
                                    Button(BlueprintCopy.saveBlueprint, systemImage: "square.and.arrow.down") {
                                        activeSheet = .blueprintCreateShare(workspace, createsShareLink: false)
                                    }
                                    Button {
                                        presentBlueprintLinks(for: workspace, mode: .share)
                                    } label: {
                                        Label(BlueprintCopy.shareTemplate, systemImage: "square.and.arrow.up")
                                    }
                                }
                                mainEventLifecycleActions(for: workspace)
                            }
                            .accessibilityActions {
                                if PlanningWorkspaceDuplicateFactory.canDuplicate(
                                    from: workspace,
                                    owner: authentication.currentUser,
                                    localGuest: authentication.isGuestMode ? authentication.localGuestProfile : nil
                                ) {
                                    Button(AppCopy.DuplicateEvent.title) {
                                        requestDuplicateEvent(for: workspace)
                                    }
                                }
                                if sharingURL(for: workspace) != nil {
                                    Button(BlueprintCopy.saveBlueprint) {
                                        activeSheet = .blueprintCreateShare(workspace, createsShareLink: false)
                                    }
                                    Button(BlueprintCopy.shareTemplate) {
                                        presentBlueprintLinks(for: workspace, mode: .share)
                                    }
                                }
                                if workspace.canCancelEvent(.main) {
                                    Button(AppCopy.Lifecycle.cancelEvent) {
                                        requestMainEventAction(.cancelEvent, for: workspace)
                                    }
                                }
                                if let action = workspace.eventRemovalAction(for: .main) {
                                    Button(action.title) {
                                        requestMainEventAction(action, for: workspace)
                                    }
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                }
                .accessibilityIdentifier("events.list")
                .contentMargins(.vertical, AppTheme.Spacing.compact, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $focusedEventID, anchor: .top)
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
            }
        }
        .background(AppTheme.ColorToken.background)
        .refreshable {
            await guests.refresh(force: true)
            await cloudSync.synchronize(trigger: .manual)
        }
        .modifier(WorkspaceBrowserEventActionConfirmation(
            request: $pendingMainEventAction,
            isUnavailable: $isMainEventActionUnavailable,
            onConfirm: confirmMainEventAction
        ))
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                workspaceFilterMenu
            }
            AdaptiveToolbarActions {
                Menu("Add workspace", systemImage: "plus") {
                    Button(ExploreCopy.exploreBlueprints, systemImage: "magnifyingglass") {
                        onExplore()
                    }
                    Button(ExploreCopy.startFromScratch, systemImage: "square.and.pencil") {
                        activeSheet = .addWorkspace
                    }
                    .accessibilityIdentifier("workspace.startFromScratch")
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("workspace.add")

                AccountToolbarButton(avatarSize: 28)
                    .frame(width: 44, height: 44)
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            focusedEventID = filteredWorkspaces.first?.mainEventID
        }
        .onChange(of: authentication.currentUser?.id) { _, _ in
            activeSheet = nil
            focusedEventID = nil
        }
        .onChange(of: authentication.principalGeneration) { _, _ in
            activeSheet = nil
            pendingMainEventAction = nil
            isMainEventActionUnavailable = false
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addWorkspace:
                NavigationStack {
                    NewWorkspaceView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .duplicateEvent(let workspace, let principalGeneration):
                WorkspaceBrowserDuplicateEventSheet(workspace: workspace) { title in
                    duplicateEvent(
                        workspace,
                        principalGeneration: principalGeneration,
                        title: title
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .blueprintCreateShare(let workspace, let createsShareLink):
                NavigationStack {
                    BlueprintCreateShareView(
                        eventID: workspace.mainEventID,
                        workspace: workspace,
                        publishesToSearch: false,
                        createsShareLink: createsShareLink,
                        startsWithReview: true
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .blueprintLinks(let request):
                NavigationStack {
                    BlueprintLinkManagementView(
                        eventID: request.eventID,
                        workspace: request.workspace,
                        mode: request.mode,
                        captureURL: request.captureURL
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private func sharingURL(for workspace: PlanningWorkspace) -> URL? {
        BlueprintCaptureLink.sharingURL(
            baseURL: AppRuntimeConfiguration.authenticationBaseURL,
            workspace: workspace
        )
    }

    private func presentBlueprintLinks(for workspace: PlanningWorkspace, mode: BlueprintLinkManagementMode) {
        // The card always targets its root event, regardless of the selected child.
        guard let captureURL = sharingURL(for: workspace) else { return }
        let request = BlueprintLinkManagementRequest(
            eventID: workspace.mainEventID,
            mode: mode,
            captureURL: captureURL,
            workspace: workspace
        )
        activeSheet = .blueprintLinks(request)
    }

    @ViewBuilder
    private func mainEventDuplicateAction(for workspace: PlanningWorkspace) -> some View {
        if PlanningWorkspaceDuplicateFactory.canDuplicate(
            from: workspace,
            owner: authentication.currentUser,
            localGuest: authentication.isGuestMode ? authentication.localGuestProfile : nil
        ) {
            Button(AppCopy.DuplicateEvent.title, systemImage: "plus.square.on.square") {
                requestDuplicateEvent(for: workspace)
            }
            .accessibilityIdentifier("workspace.duplicateEvent")
        }
    }

    private func requestDuplicateEvent(for workspace: PlanningWorkspace) {
        activeSheet = .duplicateEvent(workspace, principalGeneration: authentication.principalGeneration)
    }

    private func duplicateEvent(
        _ source: PlanningWorkspace,
        principalGeneration: UInt64,
        title: String
    ) -> Bool {
        guard WorkspaceBrowserRequestIdentity.isCurrent(
                  workspace: source,
                  principalGeneration: authentication.principalGeneration,
                  expectedPrincipalGeneration: principalGeneration,
                  isSigningOut: authentication.isSigningOut,
                  workspaces: library.workspaces
              ),
              let duplicate = PlanningWorkspaceDuplicateFactory.makeDuplicate(
                from: source,
                title: title,
                owner: authentication.currentUser,
                localGuest: authentication.isGuestMode ? authentication.localGuestProfile : nil
              ) else {
            return false
        }
        library.add(duplicate)
        guard library.workspaces.contains(where: { $0 === duplicate }) else { return false }
        AppHaptics.play(.success)
        return true
    }

    @ViewBuilder
    private func mainEventLifecycleActions(for workspace: PlanningWorkspace) -> some View {
        if workspace.canCancelEvent(.main) {
            Button(AppCopy.Lifecycle.cancelEvent, systemImage: "calendar.badge.minus", role: .destructive) {
                requestMainEventAction(.cancelEvent, for: workspace)
            }
        }
        if let action = workspace.eventRemovalAction(for: .main) {
            Button(action.title, systemImage: action.symbol, role: .destructive) {
                requestMainEventAction(action, for: workspace)
            }
        }
    }

    private func requestMainEventAction(_ action: EventRemovalAction, for workspace: PlanningWorkspace) {
        pendingMainEventAction = WorkspaceBrowserEventActionRequest(
            workspace: workspace,
            action: action,
            title: workspace.title,
            principalGeneration: authentication.principalGeneration
        )
    }

    private func confirmMainEventAction(_ request: WorkspaceBrowserEventActionRequest) {
        pendingMainEventAction = nil
        guard request.isCurrent(
            principalGeneration: authentication.principalGeneration,
            isSigningOut: authentication.isSigningOut,
            workspaces: library.workspaces
        ) else {
            isMainEventActionUnavailable = true
            return
        }
        let changed = request.action == .cancelEvent
            ? request.workspace.cancelEvent(.main)
            : request.workspace.removeEventFromHome(.main, expecting: request.action)
        guard changed else {
            isMainEventActionUnavailable = true
            return
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(selectedFilter.emptyTitle, systemImage: selectedFilter.symbol)
        } description: {
            VStack(spacing: AppTheme.Spacing.compact) {
                Text(selectedFilter.emptyDescription)
                if browsableWorkspaces.isEmpty, let message = guests.errorMessage {
                    Text(message)
                        .font(.footnote)
                    Button("Try Again") { Task { await guests.refresh(force: true) } }
                        .font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("workspace-library.retry")
                }
            }
        } actions: {
            if selectedFilter == .all, browsableWorkspaces.isEmpty {
                VStack(spacing: AppTheme.Spacing.compact) {
                    Button(ExploreCopy.exploreBlueprints, systemImage: "magnifyingglass") {
                        onExplore()
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(AppTheme.ColorToken.onAccent)

                    Button(ExploreCopy.startFromScratch, systemImage: "square.and.pencil") {
                        activeSheet = .addWorkspace
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.spacious)
    }

    private var workspaceFilterMenu: some View {
        Menu {
            Picker("Filter workspaces", selection: Binding(
                get: { selectedFilter },
                set: { filter in
                    withAnimation(.snappy) { selectedFilter = filter }
                }
            )) {
                Section {
                    ForEach(WorkspaceFilter.primaryFilters) { filter in
                        filterOption(filter)
                    }
                }
                Section {
                    ForEach(WorkspaceFilter.participationFilters) { filter in
                        filterOption(filter)
                    }
                }
            }
        } label: {
            Text(selectedFilter.title)
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Filter workspaces")
        .accessibilityValue(selectedFilter.title)
    }

    private func filterOption(_ filter: WorkspaceFilter) -> some View {
        Label("\(filter.title) (\(filterCount(for: filter)))", systemImage: filter.symbol)
            .tag(filter)
    }

    private func filterCount(for filter: WorkspaceFilter) -> Int {
        filter.workspaces(from: browsableWorkspaces, for: authentication.currentUser).count
    }
}

/// The high-level ways someone can browse their workspaces. These scopes are
/// intentionally derived rather than persisted: a workspace's role and date
/// can change as people RSVP or the event moves through its lifecycle.
enum WorkspaceFilter: String, CaseIterable, Identifiable {
    case upcoming
    case all
    case past
    case drafts
    case hosting
    case attending

    static let primaryFilters: [WorkspaceFilter] = [.upcoming, .all, .past, .drafts]
    static let participationFilters: [WorkspaceFilter] = [.hosting, .attending]

    var id: Self { self }

    var title: String {
        switch self {
        case .upcoming: String(localized: "Upcoming")
        case .all: String(localized: "All Workspaces")
        case .past: String(localized: "Past Events")
        case .drafts: String(localized: "Drafts")
        case .hosting: String(localized: "Hosting")
        case .attending: String(localized: "Attending")
        }
    }

    var symbol: String {
        switch self {
        case .upcoming: "calendar"
        case .all: "square.grid.2x2"
        case .past: "arrow.counterclockwise"
        case .drafts: "pencil"
        case .hosting: "crown.fill"
        case .attending: "checkmark.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: String(localized: "No Workspaces")
        case .upcoming: String(localized: "No Upcoming Workspaces")
        case .past: String(localized: "No Past Events")
        case .drafts: String(localized: "No Drafts")
        case .hosting: String(localized: "No Hosted Workspaces")
        case .attending: String(localized: "No Events You're Attending")
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            String(localized: "Create a workspace to start shaping an event with your people.")
        case .upcoming:
            String(localized: "Workspaces with a scheduled event will appear here.")
        case .past:
            String(localized: "Finished celebrations stay here as read-only memories.")
        case .drafts:
            String(localized: "Workspaces that are still being planned will appear here.")
        case .hosting:
            String(localized: "Workspaces where you're a host will appear here.")
        case .attending:
            String(localized: "Events you've been invited to or may attend will appear here.")
        }
    }

    func workspaces(
        from workspaces: [PlanningWorkspace],
        for account: UserAccount?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [PlanningWorkspace] {
        workspaces.filter { workspace in
            includes(workspace, account: account, now: now, calendar: calendar)
        }.sorted {
            EventDateOrdering.key(for: $0, now: now) < EventDateOrdering.key(for: $1, now: now)
        }
    }

    func includes(
        _ workspace: PlanningWorkspace,
        account: UserAccount?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .drafts:
            return workspace.currentMainEventStatus == .draft
        case .upcoming:
            return workspace.currentMainEventStatus != .draft
                && workspace.currentMainEventStatus != .finished
                && calendar.startOfDay(for: workspace.mainEventStartsAt)
                    >= calendar.startOfDay(for: now)
        case .past:
            return workspace.currentMainEventStatus == .finished
                || (
                    workspace.currentMainEventStatus != .draft
                        && calendar.startOfDay(for: workspace.mainEventStartsAt)
                            < calendar.startOfDay(for: now)
                )
        case .hosting:
            return member(in: workspace, matching: account)?.participantRole == .host
        case .attending:
            guard let member = member(in: workspace, matching: account) else { return false }
            return member.participantRole != .host
                && member.attendance != .declined
        }
    }

    private func member(
        in workspace: PlanningWorkspace,
        matching account: UserAccount?
    ) -> WorkspaceMember? {
        guard let account else { return nil }

        return workspace.participants(for: .main).first { member in
            member.userID == account.id
                || (
                    member.email?.caseInsensitiveCompare(account.email)
                        == .orderedSame
                )
        }
    }
}

private struct WorkspacePreviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let workspace: PlanningWorkspace

    private var locationText: String? {
        let value = workspace.mainEventLocation?.formatted
            ?? [workspace.venueName, workspace.location]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        return value.isEmpty ? nil : value
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaArtwork(
                imageData: workspace.mainEventImageData,
                symbol: IdeaCategory.event.symbol,
                colors: IdeaCategory.event.artworkColors,
                accent: IdeaCategory.event.artworkAccent,
                progressiveBlurRadius: 22,
                blurStart: 0.5
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.12), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Spacer(minLength: AppTheme.Spacing.section)

                Text(workspace.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .lineLimit(2)

                Text(workspace.invitationDateIsUndecided || (workspace.isScopedEvent && !workspace.mainEventHasScheduledDate)
                    ? String(localized: "Date to be decided")
                    : EventScheduleFormatter.string(
                        from: workspace.mainEventStartsAt,
                        includesTime: false,
                        timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
                        dateStyle: .long
                    ))
                    .font(.headline)

                if let locationText {
                    Label(locationText, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                }

                Label(
                    "\(workspace.participants(for: .main).count) people",
                    systemImage: "person.2.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(AppTheme.Spacing.spacious)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { height, _ in
            max(height - AppTheme.Spacing.spacious,
                dynamicTypeSize.isAccessibilitySize ? 620 : 360)
        }
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let date = workspace.invitationDateIsUndecided || (workspace.isScopedEvent && !workspace.mainEventHasScheduledDate)
            ? String(localized: "Date to be decided")
            : EventScheduleFormatter.string(
                from: workspace.mainEventStartsAt,
                includesTime: false,
                timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier,
                dateStyle: .long
            )
        let location = locationText.map { ", \($0)" } ?? ""
        return "\(workspace.title), \(date)\(location), \(workspace.currentMainEventStatus.title)"
    }
}

struct NewWorkspaceView: View {
    private enum FocusedField: Hashable {
        case eventName
        case budget
    }

    @Environment(WorkspaceLibrary.self) private var library
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dismiss) private var dismiss
    var onWorkspaceCreated: ((PlanningWorkspace) -> Void)?
    @State private var title = ""
    @State private var startsAt = Date.now
    @State private var endsAt: Date?
    @State private var isAllDay = false
    @State private var timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
    @State private var eventLocation: EventLocation?
    @State private var imageData: Data?
    @State private var budgetAmount = ""
    @State private var isEditingDateAndTime = false
    @State private var isEditingLocation = false
    @FocusState private var focusedField: FocusedField?

    init(onWorkspaceCreated: ((PlanningWorkspace) -> Void)? = nil) {
        self.onWorkspaceCreated = onWorkspaceCreated
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedBudget: Decimal? {
        guard !budgetAmount.isEmpty else { return nil }
        return MoneyInputFormatter.decimal(from: budgetAmount)
    }

    private var budgetIsValid: Bool {
        budgetAmount.isEmpty || (parsedBudget.map { $0 > .zero } ?? false)
    }

    var body: some View {
        Form {
            Section("Event Name") {
                TextField("Event name", text: $title)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .eventName)
                    .onSubmit { focusedField = nil }
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Location (Optional)") {
                Button {
                    isEditingLocation = true
                } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(eventLocation?.title ?? "Add Location")
                                .foregroundStyle(
                                    eventLocation == nil
                                        ? AppTheme.ColorToken.accent
                                        : AppTheme.ColorToken.textPrimary
                                )

                            if let detail = eventLocation?.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Date & Time") {
                Button {
                    isEditingDateAndTime = true
                } label: {
                    EventScheduleRow(
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace.new.dateTime")
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section {
                MoneyAmountField(
                    amount: $budgetAmount,
                    title: "Budget Cap",
                    placeholder: "Optional"
                )
                    .focused($focusedField, equals: .budget)
            } header: {
                Text("Budget (Optional)")
            } footer: {
                Text("The main event starts with the full budget. You can allocate part of it to sub-events later.")
            }
            .listRowBackground(AppTheme.ColorToken.surface)

            Section("Cover") {
                PhotoAttachmentPicker(
                    imageData: $imageData,
                    emptySymbol: IdeaCategory.event.symbol,
                    fallbackColors: IdeaCategory.event.artworkColors,
                    fallbackAccent: IdeaCategory.event.artworkAccent,
                    suggestedConcept: "Artwork for \(trimmedTitle.isEmpty ? "our event" : trimmedTitle)"
                )
            }
            .listRowBackground(AppTheme.ColorToken.surface)
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("New Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let workspace = PlanningWorkspace.newWorkspace(
                        title: trimmedTitle,
                        startsAt: startsAt,
                        endsAt: endsAt,
                        isAllDay: isAllDay,
                        timeZoneIdentifier: timeZoneIdentifier,
                        eventLocation: eventLocation,
                        imageData: imageData,
                        budgetCap: parsedBudget,
                        owner: authentication.currentUser,
                        localGuest: authentication.isGuestMode ? authentication.localGuestProfile : nil
                    )

                    if let onWorkspaceCreated {
                        onWorkspaceCreated(workspace)
                    } else {
                        library.add(workspace)
                        if library.workspaces.contains(where: { $0 === workspace }) {
                            AppHaptics.play(.success)
                        }
                    }
                    dismiss()
                }
                .disabled(trimmedTitle.isEmpty || !budgetIsValid)
                .keyboardShortcut(.defaultAction)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .sheet(isPresented: $isEditingDateAndTime) {
            EventDateTimeEditorView(
                startsAt: startsAt,
                endsAt: endsAt,
                isAllDay: isAllDay,
                timeZoneIdentifier: timeZoneIdentifier
            ) { updatedStart, updatedEnd, updatedAllDay, updatedTimeZone in
                startsAt = updatedStart
                endsAt = updatedEnd
                isAllDay = updatedAllDay
                timeZoneIdentifier = updatedTimeZone
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isEditingLocation) {
            EventLocationEditorView(location: eventLocation) { updatedLocation in
                eventLocation = updatedLocation
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

struct WorkspaceLibraryToolbarButton: View {
    let action: () -> Void
    var title: String = String(localized: "Workspaces")
    var hint: String = String(localized: "Returns to all workspaces")

    var body: some View {
        Button(title, systemImage: "rectangle.grid.2x2.fill", action: action)
            .labelStyle(.iconOnly)
            .accessibilityHint(hint)
    }
}

#Preview("Events · Large Cards") {
    @Previewable @State var library = WorkspaceLibrary.sample
    TabView {
        Tab("Workspaces", systemImage: "rectangle.stack.fill") {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.standard) {
                        ForEach(library.workspaces, id: \.mainEventID) { workspace in
                            WorkspacePreviewCard(workspace: workspace)
                                .adaptiveReadingWidth(760)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                }
                .contentMargins(.vertical, AppTheme.Spacing.compact, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
            }
        }
    }
}
