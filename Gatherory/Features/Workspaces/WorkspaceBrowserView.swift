import SwiftUI

@MainActor
private enum WorkspaceBrowserSheet: Identifiable {
    case addWorkspace
    case blueprintCreateShare(PlanningWorkspace, publishesToSearch: Bool)
    case blueprintLinks(BlueprintLinkManagementRequest)

    var id: String {
        switch self {
        case .addWorkspace: "add-workspace"
        case .blueprintCreateShare(let workspace, let publish): "blueprint-create-share-\(workspace.mainEventID.uuidString)-\(publish)"
        case .blueprintLinks(let request): request.id.uuidString
        }
    }
}

struct WorkspaceBrowserView: View {
    @Environment(WorkspaceLibrary.self) private var library
    @Environment(GuestInvitationStore.self) private var guests
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(AuthenticationSession.self) private var authentication
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeSheet: WorkspaceBrowserSheet?
    var onExplore: () -> Void = {}

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: AppTheme.Spacing.standard)]
    }

    private var filteredWorkspaces: [PlanningWorkspace] {
        browsableWorkspaces
    }

    private var browsableWorkspaces: [PlanningWorkspace] {
        let planning = library.workspaces.filter { $0.showsPlanningInterface || guests.presentations[$0.mainEventID] == nil }
        let represented = Set(planning.flatMap { [$0.mainEventID] + $0.timeline.map(\.id) })
        return planning + guests.events.compactMap { represented.contains($0.id) ? nil : guests.presentations[$0.id] }
    }

    var body: some View {
        Group {
            if browsableWorkspaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppTheme.Spacing.standard) {
                        ForEach(filteredWorkspaces, id: \.mainEventID) { workspace in
                            Button {
                                if workspace.isInvitationProjection { guests.selectedEventID = workspace.mainEventID }
                                else { library.open(workspace) }
                            } label: {
                                WorkspacePreviewCard(workspace: workspace)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this workspace")
                            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: AppTheme.Radius.hero, style: .continuous))
                            .contextMenu {
                                if sharingURL(for: workspace) != nil {
                                    Button(BlueprintCopy.saveBlueprint, systemImage: "square.and.arrow.down") {
                                        activeSheet = .blueprintCreateShare(workspace, publishesToSearch: false)
                                    }
                                    Button {
                                        presentBlueprintCreateShare(for: workspace)
                                    } label: {
                                        Label(BlueprintCopy.shareTemplate, systemImage: "square.and.arrow.up")
                                    }

                                    Button {
                                        presentBlueprintLinks(for: workspace, mode: .manage)
                                    } label: {
                                        Label(BlueprintCopy.manageTemplateLinks, systemImage: "link")
                                    }
                                }
                            }
                            .accessibilityActions {
                                if sharingURL(for: workspace) != nil {
                                    Button(BlueprintCopy.saveBlueprint) {
                                        activeSheet = .blueprintCreateShare(workspace, publishesToSearch: false)
                                    }
                                    Button(BlueprintCopy.shareTemplate) {
                                        presentBlueprintCreateShare(for: workspace)
                                    }
                                    Button(BlueprintCopy.manageTemplateLinks) {
                                        presentBlueprintLinks(for: workspace, mode: .manage)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.top, AppTheme.Layout.screenTop)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                }
                .scrollIndicators(.hidden)
                .appSoftScrollEdges()
            }
        }
        .background(AppTheme.ColorToken.background)
        .refreshable {
            await guests.refresh(force: true)
            await cloudSync.synchronize(trigger: .manual)
        }
        .safeAreaInset(edge: .bottom) {
            if let message = guests.errorMessage {
                VStack(spacing: 8) {
                    Text(message).font(.footnote)
                    Button("Try Again") { Task { await guests.refresh(force: true) } }
                }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .navigationTitle("Workspaces")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add workspace", systemImage: "plus") {
                    activeSheet = .addWorkspace
                }
                .labelStyle(.iconOnly)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                AccountToolbarButton(avatarSize: 44)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: authentication.currentUser?.id) { _, _ in
            activeSheet = nil
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addWorkspace:
                NavigationStack {
                    NewWorkspaceView()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .blueprintCreateShare(let workspace, let publish):
                NavigationStack {
                    BlueprintCreateShareView(eventID: workspace.mainEventID, workspace: workspace, publishesToSearch: publish)
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
                .presentationDetents([.medium, .large])
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

    private func presentBlueprintCreateShare(for workspace: PlanningWorkspace) {
        guard sharingURL(for: workspace) != nil else { return }
        activeSheet = .blueprintCreateShare(workspace, publishesToSearch: true)
    }

    private func presentBlueprintLinks(for workspace: PlanningWorkspace, mode: BlueprintLinkManagementMode) {
        // The card always targets its root event, regardless of the selected child.
        guard mode == .manage, let captureURL = sharingURL(for: workspace) else { return }
        let request = BlueprintLinkManagementRequest(
            eventID: workspace.mainEventID,
            mode: mode,
            captureURL: captureURL,
            workspace: workspace
        )
        activeSheet = .blueprintLinks(request)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Workspaces", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Create a workspace to start shaping an event with your people.")
        } actions: {
            Button("Add Workspace", systemImage: "plus") {
                activeSheet = .addWorkspace
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.spacious)
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
        case .upcoming: "Upcoming"
        case .all: "All Workspaces"
        case .past: "Past Events"
        case .drafts: "Drafts"
        case .hosting: "Hosting"
        case .attending: "Attending"
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
        case .all: "No Workspaces"
        case .upcoming: "No Upcoming Workspaces"
        case .past: "No Past Events"
        case .drafts: "No Drafts"
        case .hosting: "No Hosted Workspaces"
        case .attending: "No Events You're Attending"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            "Create a workspace to start shaping an event with your people."
        case .upcoming:
            "Workspaces with a scheduled event will appear here."
        case .past:
            "Finished celebrations stay here as read-only memories."
        case .drafts:
            "Workspaces that are still being planned will appear here."
        case .hosting:
            "Workspaces where you're a host will appear here."
        case .attending:
            "Events you've been invited to or may attend will appear here."
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
                // Keep the library's first frame lightweight. Full-screen event
                // views can afford Glur; collection thumbnails already gain
                // legibility from the gradient below.
                progressiveBlurRadius: 0,
                blurStart: 0.5
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.12), .black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Label(
                    workspace.currentMainEventStatus.title,
                    systemImage: workspace.currentMainEventStatus.symbol
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(.ultraThinMaterial, in: Capsule())
                .appImageOverlayAppearance()

                Spacer(minLength: AppTheme.Spacing.section)

                Text(workspace.title)
                    .font(AppTheme.Typography.sectionTitle)
                    .lineLimit(2)

                Text(workspace.invitationDateIsUndecided || (workspace.isScopedEvent && !workspace.mainEventHasScheduledDate)
                    ? String(localized: "Date to be decided")
                    : workspace.mainEventStartsAt.formatted(date: .long, time: .omitted))
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
        .frame(height: dynamicCardHeight)
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

    private var dynamicCardHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 560 : 470
    }

    private var accessibilitySummary: String {
        let date = workspace.invitationDateIsUndecided || (workspace.isScopedEvent && !workspace.mainEventHasScheduledDate)
            ? String(localized: "Date to be decided")
            : workspace.mainEventStartsAt.formatted(date: .long, time: .omitted)
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
    @State private var startsAt = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
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
                        owner: authentication.currentUser
                    )

                    if let onWorkspaceCreated {
                        onWorkspaceCreated(workspace)
                    } else {
                        library.add(workspace)
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
