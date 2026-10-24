import SwiftUI

struct BlueprintSetupView: View {
    // nil opens recovery only; it must never silently choose a different starter.
    let catalogKey: String?
    let sharedToken: String?
    let returnsToPreview: Bool
    /// Captured at explicit Install confirmation; nil retains the legacy setup/recovery entry.
    let installationOwnerID: String?
    let onInstallationCompleted: (() -> Void)?
    let onClose: (() -> Void)?
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(BlueprintSharedTemplateRouter.self) private var sharedBlueprintLinks
    @Environment(\.currentUserAccount) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isEventNameFocused: Bool

    @State private var coordinator: BlueprintInstallationCoordinator?
    @State private var catalogEntry: BlueprintCatalogEntry?
    @State private var tree: BlueprintExperienceTreeConfig?
    @State private var ideas: BlueprintIdeasConfig?
    @State private var loading = true
    @State private var busy = false
    @State private var installAttemptStarted = false
    @State private var errorMessage: String?
    @State private var pendingIntents: [BlueprintInstallationIntent] = []
    @State private var selectedChildren: Set<String> = []
    @State private var scheduleDraft = BlueprintScheduleDraft()
    @State private var scheduleRequest: ScheduleRequest?
    @State private var selectedIdeas: Set<String> = []
    @State private var eventName = ""
    @State private var dateContext = BlueprintSetupDateContext()
    @State private var dateSheetChild: BlueprintCatalogChild?
    @State private var showsMainDate = false
    @State private var dateDraft = Date.now
    @State private var dateEditorCapture: DateEditorCapture?
    @State private var requestForReview: BlueprintInstallInput?
    @State private var reviewedPlan: BlueprintExpandedPlan?
    @State private var showReview = false
    @State private var draftOwnerUserID: String?
    @State private var draftRequestID = UUID()
    @State private var draftCompleted = false
    @State private var draftSaveError: String?
    @State private var draftShareToken: String?
    @State private var setupGeneration = UUID()
    @State private var confirmsStartOver = false
    @State private var mainDateConfirmed = false
    @State private var lastPersistedEventName = ""
    @State private var customizations = BlueprintCustomization()
    @State private var previewDecisions: [String: DecisionChoice] = [:]

    private let draftStore: BlueprintSetupDraftStore
#if DEBUG
    private let installationCoordinatorFactory: (() -> BlueprintInstallationCoordinator?)?
#endif

    private init(catalogKey: String?, sharedToken: String?, returnsToPreview: Bool,
                 installationOwnerID: String?, onInstallationCompleted: (() -> Void)?,
                 onClose: (() -> Void)?, resolvedDraftStore: BlueprintSetupDraftStore?,
                 installationCoordinatorFactory: (() -> BlueprintInstallationCoordinator?)?) {
        self.catalogKey = catalogKey
        self.sharedToken = sharedToken
        self.returnsToPreview = returnsToPreview
        self.installationOwnerID = installationOwnerID
        self.onInstallationCompleted = onInstallationCompleted
        self.onClose = onClose
#if DEBUG
        let usesDateConfirmationFixture = ProcessInfo.processInfo.arguments.contains("-BlueprintSetupDateConfirmationFixture")
        self.draftStore = usesDateConfirmationFixture ? (resolvedDraftStore ?? BlueprintSetupDraftStore()) : BlueprintSetupDraftStore()
        self.installationCoordinatorFactory = usesDateConfirmationFixture ? installationCoordinatorFactory : nil
#else
        self.draftStore = BlueprintSetupDraftStore()
#endif
    }

    init(catalogKey: String?, sharedToken: String? = nil, returnsToPreview: Bool = false,
         installationOwnerID: String? = nil,
         onInstallationCompleted: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.init(catalogKey: catalogKey, sharedToken: sharedToken, returnsToPreview: returnsToPreview,
                  installationOwnerID: installationOwnerID, onInstallationCompleted: onInstallationCompleted,
                  onClose: onClose, resolvedDraftStore: nil, installationCoordinatorFactory: nil)
    }

#if DEBUG
    init(catalogKey: String?, sharedToken: String? = nil, returnsToPreview: Bool = false,
         installationOwnerID: String? = nil,
         onInstallationCompleted: (() -> Void)? = nil, onClose: (() -> Void)? = nil,
         setupDraftStore: BlueprintSetupDraftStore,
         installationCoordinatorFactory: @escaping () -> BlueprintInstallationCoordinator?) {
        self.init(catalogKey: catalogKey, sharedToken: sharedToken, returnsToPreview: returnsToPreview,
                  installationOwnerID: installationOwnerID, onInstallationCompleted: onInstallationCompleted,
                  onClose: onClose, resolvedDraftStore: setupDraftStore,
                  installationCoordinatorFactory: installationCoordinatorFactory)
    }
#endif

    private struct ScheduleRequest {
        let token: UUID
        let input: BlueprintScheduleInput
    }

    private struct DateEditorCapture: Equatable {
        let ownerID: String
        let requestID: UUID
        let setupGeneration: UUID
    }

    private var trimmedEventName: String {
        eventName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedChildrenHaveDates: Bool {
        selectedChildren.allSatisfy { scheduleDraft.confirmedDates[$0] != nil }
    }

    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
    }

    private var startsAt: Date { dateContext.startsAt }
    private var timeZoneIdentifier: String { dateContext.timeZoneIdentifier }

    private var loadTaskID: String {
        "\(account?.id ?? "signed-out")-\(String(describing: cloudSync.accountOnboardingState))"
    }

    private var readyForDirectInstallation: Bool {
        installationOwnerID != nil && installationOwnerID == account?.id
            && draftOwnerUserID == installationOwnerID && !loading && !busy
            && !installAttemptStarted && pendingIntents.isEmpty && dateSheetChild == nil && !showsMainDate
            && catalogEntry != nil && draftSaveError == nil
            && BlueprintInstallReadiness.isValidEventName(eventName)
            && BlueprintInstallReadiness.isReady(mainDateConfirmed: mainDateConfirmed,
                                                selected: selectedChildren, confirmed: scheduleDraft.confirmedDates)
    }

    private var showsSetupAction: Bool {
        !loading && catalogEntry != nil && tree != nil && ideas != nil
            && pendingIntents.isEmpty && !installAttemptStarted
    }

    private var setupActionEnabled: Bool {
        if installationOwnerID != nil { return readyForDirectInstallation }
        return !busy && mainDateConfirmed && BlueprintInstallReadiness.isValidEventName(eventName)
            && selectedChildrenHaveDates && draftSaveError == nil
    }

    private var setupGuidance: String? {
        if !mainDateConfirmed { return BlueprintCopy.confirmMainDateToContinue }
        if !selectedChildrenHaveDates { return BlueprintCopy.confirmEventDatesToContinue }
        return nil
    }

    var body: some View {
        Form {
            if !pendingIntents.isEmpty {
                Section {
                    if busy {
                        ProgressView(BlueprintCopy.installing)
                    }
                    ForEach(pendingIntents, id: \.requestID) { intent in
                        Button {
                            Task { await resume(intent) }
                        } label: {
                            Label(BlueprintCopy.retryInstall, systemImage: "arrow.clockwise")
                        }
                        .disabled(busy || account?.id != intent.ownerUserID)
                        .accessibilityIdentifier("blueprint.setup.retryInstallation")
                    }
                    Text(BlueprintCopy.pendingInstall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(BlueprintCopy.finishPreviousInstall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(AppTheme.ColorToken.destructive)
                    }
                }
            } else if installAttemptStarted {
                Section {
                    if busy {
                        ProgressView(BlueprintCopy.installing)
                            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget)
                    } else {
                        Text(BlueprintCopy.finishPreviousInstall)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(AppTheme.ColorToken.destructive) }
                        if let input = requestForReview {
                            Button(installationOwnerID != nil ? BlueprintCopy.retryCreateEvents : BlueprintCopy.retrySameRequest,
                                   systemImage: "arrow.clockwise") {
                                Task { await install(input) }
                            }
                        }
                    }
                }
            } else if loading {
                Section { ProgressView() }
            } else if let tree, ideas != nil {
                if let draftSaveError {
                    Section {
                        Text(draftSaveError).foregroundStyle(AppTheme.ColorToken.destructive)
                        Button(AppCopy.Common.retry) { persistDraft() }
                    }
                }
                if installationOwnerID != nil {
                    missingDateSections(tree: tree)
                } else {
                Section {
                    eventNameField
                    mainDateRow
                } header: {
                    Text(BlueprintCopy.mainEvent)
                }

                Section(BlueprintCopy.children) {
                    if scheduleDraft.isRefreshing {
                        ProgressView(BlueprintCopy.loadingDates)
                    } else if scheduleDraft.refreshFailed {
                        Text(BlueprintCopy.datesUnavailable)
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(AppCopy.Common.retry) { refreshSuggestions() }
                    }
                    ForEach(tree.children) { child in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(child.title, isOn: childSelection(child))
                            if selectedChildren.contains(child.key) {
                                if let date = scheduleDraft.confirmedDates[child.key] {
                                    Text(BlueprintCopy.confirmedDate)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button {
                                        openManualDatePicker(for: child)
                                    } label: {
                                        Label(formattedChildDate(date), systemImage: "calendar")
                                    }
                                    .font(.subheadline)
                                    .accessibilityIdentifier("blueprint.setup.childDate.\(child.key)")
                                } else {
                                    suggestionChoices(for: child)
                                    Button(BlueprintCopy.chooseDate, systemImage: "calendar.badge.plus") {
                                        openManualDatePicker(for: child)
                                    }
                                    .font(.subheadline)
                                    .accessibilityIdentifier("blueprint.setup.childDate.\(child.key)")
                                    Text(BlueprintCopy.childDateRequired)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                }
            } else {
                Section {
                    Text(errorMessage ?? BlueprintCopy.loadFailed)
                        .foregroundStyle(.secondary)
                    Button(AppCopy.Common.retry) { Task { await load() } }
                        .disabled(busy)
                }
            }

            if let errorMessage, !loading, catalogEntry != nil,
               !showsSetupAction, !installAttemptStarted, pendingIntents.isEmpty {
                Section { Text(errorMessage).foregroundStyle(AppTheme.ColorToken.destructive) }
            }
            if let setupGuidance, showsSetupAction, pendingIntents.isEmpty, !installAttemptStarted {
                Section { Label(setupGuidance, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            }
            if let errorMessage, showsSetupAction, pendingIntents.isEmpty, !installAttemptStarted {
                Section {
                    Text(errorMessage).foregroundStyle(AppTheme.ColorToken.destructive)
                    Button(installationOwnerID == nil ? BlueprintCopy.retrySameRequest : BlueprintCopy.retryCreateEvents,
                           systemImage: "arrow.clockwise") {
                        Task { await requestPlanReview() }
                    }
                    .disabled(busy || !setupActionEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .listSectionSpacing(.custom(20))
        .scrollDismissesKeyboard(.interactively)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .navigationTitle(installationOwnerID != nil ? BlueprintCopy.createEvents
            : catalogEntry?.definition.blueprint.name ?? BlueprintCopy.starter)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppCopy.Common.done) { isEventNameFocused = false }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button(AppCopy.Common.close) { closeSetup() }
                    .disabled(busy)
            }
            if installationOwnerID == nil, catalogEntry != nil, !installAttemptStarted, pendingIntents.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(BlueprintCopy.startOver, systemImage: "arrow.counterclockwise") {
                        confirmsStartOver = true
                    }
                    .disabled(busy)
                }
            }
            if showsSetupAction {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await requestPlanReview() }
                    } label: {
                        HStack(spacing: AppTheme.Spacing.compact) {
                            if busy { ProgressView() }
                            Text(busy ? (installationOwnerID != nil ? BlueprintCopy.installing : BlueprintCopy.reviewing)
                                : installationOwnerID == nil ? AppCopy.Common.continueAction
                                : errorMessage == nil ? BlueprintCopy.createEvents : BlueprintCopy.retryCreateEvents)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!setupActionEnabled || busy)
                    .accessibilityIdentifier("blueprint.setup.primaryAction")
                }
            }
        }
        .confirmationDialog(BlueprintCopy.startOverConfirmation, isPresented: $confirmsStartOver, titleVisibility: .visible) {
            Button(BlueprintCopy.startOver, role: .destructive) { Task { await startOver() } }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .task(id: loadTaskID) { await load() }
        .task(id: scheduleRequest?.token) {
            if let request = scheduleRequest { await fetchSuggestions(request) }
        }
        .sheet(isPresented: $showsMainDate, onDismiss: { dateEditorCapture = nil }) {
            mainDateEditor
        }
        .sheet(item: $dateSheetChild, onDismiss: { dateEditorCapture = nil }) { child in
            childDateEditor(for: child)
        }
        .onChange(of: eventName) { _, _ in invalidateReview(); persistDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistDraft() }
        }
        .onDisappear { persistDraft() }
        .navigationDestination(isPresented: $showReview) {
            if let plan = reviewedPlan, let input = requestForReview {
                BlueprintPlanReviewView(
                    plan: plan,
                    requestID: input.requestID,
                    onInstall: { Task { await install(input) } },
                    isInstalling: busy,
                    errorMessage: errorMessage,
                    pendingIntents: pendingIntents,
                    onResume: { intent in Task { await resume(intent) } }
                )
            }
        }
    }

    @ViewBuilder
    private func missingDateSections(tree: BlueprintExperienceTreeConfig) -> some View {
        Section {
            eventNameField
            mainDateRow
        } header: {
            Text(BlueprintCopy.mainEvent)
        }
        if !selectedChildren.isEmpty {
            Section {
                ForEach(tree.children.filter { selectedChildren.contains($0.key) }) { child in
                    dateConfirmationRow(child)
                }
            } header: {
                HStack {
                    Text(BlueprintCopy.children)
                    Spacer()
                    if scheduleDraft.isRefreshing {
                        ProgressView()
                            .accessibilityLabel(BlueprintCopy.loadingDates)
                    }
                }
            } footer: {
                if scheduleDraft.refreshFailed {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text(BlueprintCopy.datesUnavailable)
                        Button(AppCopy.Common.retry) { refreshSuggestions() }
                            .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                    }
                }
            }
        }
    }

    private func dateConfirmationRow(_ child: BlueprintCatalogChild) -> some View {
        let confirmed = scheduleDraft.confirmedDates[child.key]
        let suggestion = scheduleDraft.suggestions[child.key]
        let candidate = suggestion?.status == "suggested" && suggestion?.candidates.count == 1
            ? suggestion?.candidates.first : nil
        let token = scheduleDraft.refreshToken
        let canConfirm = mainDateConfirmed && confirmed == nil && candidate != nil && !scheduleDraft.isRefreshing && !scheduleDraft.refreshFailed
        return VStack(alignment: .leading, spacing: 8) {
            BlueprintSetupDateRow(
                title: child.title,
                dateLabel: (confirmed ?? candidate).map { formattedChildDate($0) } ?? BlueprintCopy.chooseDate,
                isConfirmed: confirmed != nil
            ) {
                openManualDatePicker(for: child)
            }
            .accessibilityIdentifier("blueprint.setup.childDate.\(child.key)")
            if confirmed == nil && suggestion?.status == "ambiguous" { suggestionChoices(for: child) }
            if canConfirm {
                Button(BlueprintCopy.confirmDate, systemImage: "checkmark") {
                    if scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: 0, token: token) {
                        invalidateReview()
                        persistDraft()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: AppTheme.Layout.minimumTouchTarget)
                .accessibilityIdentifier("blueprint.setup.childDate.\(child.key).confirm")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(AppCopy.Common.edit, systemImage: "pencil") { openManualDatePicker(for: child) }
            if canConfirm {
                Button(BlueprintCopy.confirmDate, systemImage: "checkmark") {
                    if scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: 0, token: token) {
                        invalidateReview()
                        persistDraft()
                    }
                }.tint(AppTheme.ColorToken.success)
            }
        }
        .contextMenu {
            Button(AppCopy.Common.edit, systemImage: "pencil") { openManualDatePicker(for: child) }
            if canConfirm {
                Button(BlueprintCopy.confirmDate, systemImage: "checkmark") {
                    if scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: 0, token: token) {
                        invalidateReview()
                        persistDraft()
                    }
                }
            }
        }
    }

    private var mainDateRow: some View {
        Button(action: openMainDateEditor) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                HStack(spacing: AppTheme.Spacing.compact) {
                    EventScheduleRow(startsAt: startsAt, endsAt: nil, isAllDay: false,
                                     timeZoneIdentifier: timeZoneIdentifier)
                    if mainDateConfirmed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.ColorToken.success)
                            .accessibilityHidden(true)
                    }
                }
                if !mainDateConfirmed {
                    Text(BlueprintCopy.confirmMainDateToContinue)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("blueprint.setup.mainDate")
        .accessibilityValue(mainDateConfirmed ? BlueprintCopy.confirmedDate : BlueprintCopy.confirmDate)
    }

    private var eventNameField: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            TextField(BlueprintCopy.eventName, text: $eventName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isEventNameFocused)
                .onSubmit { isEventNameFocused = false }
                .accessibilityIdentifier("blueprint.setup.eventName")
            if trimmedEventName.unicodeScalars.count > 120 {
                Text("Titles can be up to 120 characters.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ColorToken.destructive)
            }
        }
    }

    private var canOpenDateEditor: Bool {
        !busy && !loading && !installAttemptStarted && pendingIntents.isEmpty
            && draftOwnerUserID == account?.id
    }

    private func openMainDateEditor() {
        guard canOpenDateEditor, let ownerID = draftOwnerUserID else { return }
        isEventNameFocused = false
        dateSheetChild = nil
        dateEditorCapture = DateEditorCapture(ownerID: ownerID, requestID: draftRequestID,
                                              setupGeneration: setupGeneration)
        showsMainDate = true
    }

    private var mainDateEditor: some View {
        let captureAtPresentation = dateEditorCapture
        return EventDateTimeEditorView(
            startsAt: startsAt,
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: timeZoneIdentifier,
            supportsExtendedSchedule: false
        ) { updatedStart, _, _, updatedTimeZone in
            guard let capture = captureAtPresentation, dateEditorIsCurrent(capture, mainDate: true) else {
                errorMessage = BlueprintCopy.draftLoadFailed
                return
            }
            dateContext.startsAt = updatedStart
            _ = dateContext.selectTimeZone(updatedTimeZone)
            mainDateConfirmed = true
            scheduleAnchorChanged()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func childDateEditor(for child: BlueprintCatalogChild) -> some View {
        let captureAtPresentation = dateEditorCapture
        return EventDateTimeEditorView(
            startsAt: dateDraft,
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: timeZoneIdentifier,
            supportsExtendedSchedule: false
        ) { updatedStart, _, _, updatedTimeZone in
            guard let capture = captureAtPresentation,
                  dateEditorIsCurrent(capture, childKey: child.key),
                  updatedTimeZone == timeZoneIdentifier else {
                errorMessage = BlueprintCopy.draftLoadFailed
                return
            }
            scheduleDraft.confirm(key: child.key, date: updatedStart)
            invalidateReview()
            persistDraft()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func dateEditorIsCurrent(_ capture: DateEditorCapture, mainDate: Bool) -> Bool {
        dateEditorCapture == capture && showsMainDate && dateSheetChild == nil
            && dateEditorIsCurrent(capture)
    }

    private func dateEditorIsCurrent(_ capture: DateEditorCapture, childKey: String) -> Bool {
        dateEditorCapture == capture && dateSheetChild?.key == childKey && !showsMainDate
            && dateEditorIsCurrent(capture)
    }

    private func dateEditorIsCurrent(_ capture: DateEditorCapture) -> Bool {
        account?.id == capture.ownerID && draftOwnerUserID == capture.ownerID
            && draftRequestID == capture.requestID && setupGeneration == capture.setupGeneration
            && !busy && !loading && !installAttemptStarted && pendingIntents.isEmpty
    }

    private func openManualDatePicker(for child: BlueprintCatalogChild) {
        guard canOpenDateEditor, let ownerID = draftOwnerUserID else { return }
        isEventNameFocused = false
        dateDraft = scheduleDraft.initialManualDate(for: child.key, fallback: startsAt)
        showsMainDate = false
        dateEditorCapture = DateEditorCapture(ownerID: ownerID, requestID: draftRequestID,
                                              setupGeneration: setupGeneration)
        dateSheetChild = child
    }

    private func childSelection(_ child: BlueprintCatalogChild) -> Binding<Bool> {
        Binding(
            get: { selectedChildren.contains(child.key) },
            set: { isSelected in
                if isSelected {
                    selectedChildren.insert(child.key)
                } else {
                    selectedChildren.remove(child.key)
                    scheduleDraft.remove(key: child.key)
                }
                invalidateReview()
                persistDraft()
            }
        )
    }

    private func invalidateReview() {
        requestForReview = nil
        reviewedPlan = nil
        errorMessage = nil
    }

    private func closeSetup() {
        if let onClose {
            onClose()
            return
        }
        if BlueprintSetupExitPolicy.dismissesSharedLink(
            hasSharedToken: sharedToken != nil,
            returnsToPreview: returnsToPreview,
            didComplete: draftCompleted
        ) {
            sharedBlueprintLinks.dismiss()
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    private func suggestionChoices(for child: BlueprintCatalogChild) -> some View {
        if let suggestion = scheduleDraft.suggestions[child.key], !scheduleDraft.isRefreshing {
            let token = scheduleDraft.refreshToken
            if suggestion.status == "suggested" || suggestion.status == "ambiguous" {
                if suggestion.status == "ambiguous" {
                    Text(BlueprintCopy.repeatedTime).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(suggestion.candidates.indices, id: \.self) { index in
                    Button {
                        if scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: index, token: token) {
                            invalidateReview()
                            persistDraft()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BlueprintCopy.confirmDate).font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                Text(BlueprintSetupDateLabel.text(suggestion.candidates[index], timeZone: selectedTimeZone,
                                     includesOffset: suggestion.status == "ambiguous"))
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "checkmark.circle")
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(BlueprintCopy.useSuggestedDate))
                    .accessibilityValue(BlueprintSetupDateLabel.text(suggestion.candidates[index], timeZone: selectedTimeZone,
                                        includesOffset: suggestion.status == "ambiguous"))
                }
            } else if suggestion.status == "nonexistent" {
                Text(BlueprintCopy.nonexistentTime).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleAnchorChanged() {
        invalidateReview()
        persistDraft()
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard let entry = catalogEntry, !installAttemptStarted, pendingIntents.isEmpty else { return }
        // Expire old buttons synchronously, before the asynchronous task starts.
        let token = scheduleDraft.beginRefresh()
        scheduleRequest = ScheduleRequest(token: token, input: BlueprintScheduleInput(
            catalogKey: entry.catalogKey, revision: entry.revision, contentHash: entry.contentHash,
            mainEvent: .init(startsAt: startsAt, timeZone: timeZoneIdentifier),
            shareToken: draftShareToken
        ))
    }

    @MainActor
    private func fetchSuggestions(_ request: ScheduleRequest) async {
        guard let coordinator else { return }
        do {
            try await Task.sleep(for: .milliseconds(250))
            guard let ownerID = draftOwnerUserID, ownerID == account?.id,
                  let entry = catalogEntry,
                  let draft = try draftStore.load(ownerUserID: ownerID, catalogKey: entry.catalogKey, shareToken: draftShareToken)
            else { throw BlueprintStarterViewError.invalidCatalog }
            let copied = try await coordinator.prepareDraftCopy(draft)
            try Task.checkCancellation()
            guard account?.id == ownerID, draftRequestID == copied.requestID else { return }
            let pin = copied.installationEntry
            let input = BlueprintScheduleInput(catalogKey: pin.catalogKey, revision: pin.revision,
                contentHash: pin.contentHash, mainEvent: request.input.mainEvent, shareToken: copied.installationShareToken)
            let response = try await coordinator.schedule(input)
            try Task.checkCancellation()
            scheduleDraft.apply(response.suggestions, token: request.token)
        } catch {
            guard !Task.isCancelled else { return }
            scheduleDraft.failRefresh(token: request.token)
        }
    }

    private func formattedChildDate(_ date: Date) -> String {
        BlueprintSetupDateLabel.text(date, timeZone: selectedTimeZone)
    }

    @MainActor
    private func load() async {
        guard let account else {
            resetSetup()
            loading = false
            errorMessage = BlueprintCopy.signInRequired
            return
        }
        guard installationOwnerID == nil || installationOwnerID == account.id else {
            resetSetup()
            loading = false
            errorMessage = BlueprintCopy.signInRequired
            return
        }
        if draftOwnerUserID != account.id { resetSetup() }
        let generation = setupGeneration
        let coordinator: BlueprintInstallationCoordinator?
#if DEBUG
        if let installationCoordinatorFactory {
            coordinator = installationCoordinatorFactory()
        } else {
            coordinator = cloudSync.makeBlueprintInstallationCoordinator()
        }
#else
        coordinator = cloudSync.makeBlueprintInstallationCoordinator()
#endif
        guard let coordinator else {
            loading = false
            errorMessage = BlueprintCopy.loadFailed
            return
        }
        self.coordinator = coordinator
        loading = true
        errorMessage = nil
        do {
            pendingIntents = try coordinator.pendingIntentsForActiveAccount()
            if !pendingIntents.isEmpty {
                loading = false
                return
            }
            if installationOwnerID != nil {
                let saved: BlueprintSetupDraft?
                if let sharedToken { saved = try draftStore.load(ownerUserID: account.id, shareToken: sharedToken) }
                else if let catalogKey { saved = try draftStore.load(ownerUserID: account.id, catalogKey: catalogKey) }
                else { saved = nil }
                guard let saved else { throw BlueprintStarterViewError.invalidCatalog }
                try restore(saved)
                loading = false
                if !selectedChildrenHaveDates { refreshSuggestions() }
                return
            }
            if let sharedToken {
                if let saved = try draftStore.load(ownerUserID: account.id, shareToken: sharedToken) {
                    // A previously resolved entry is safe to keep locally. Restoring
                    // first preserves offline setup. Server requests use a private
                    // copy of this saved snapshot, not the original link's authority.
                    try restore(saved)
                    guard self.account?.id == account.id, setupGeneration == generation else { return }
                    loading = false
                    refreshSuggestions()
                } else {
                    let entry = try await coordinator.sharedBlueprint(token: sharedToken)
                    try Task.checkCancellation()
                    guard self.account?.id == account.id, setupGeneration == generation else { return }
                    try configure(entry, ownerID: account.id, shareToken: sharedToken)
                    persistDraft()
                    loading = false
                    refreshSuggestions()
                }
                return
            }
            guard let catalogKey else { throw BlueprintStarterViewError.invalidCatalog }
            // A saved source is pinned to the reviewed revision. Restore locally
            // even offline. A private snapshot copy supplies server setup/install.
            if catalogEntry == nil,
               let saved = try draftStore.load(ownerUserID: account.id, catalogKey: catalogKey) {
                try restore(saved)
            }
            if catalogEntry != nil {
                loading = false
                refreshSuggestions()
                return
            }
            let catalog = try await coordinator.catalog()
            try Task.checkCancellation()
            guard self.account?.id == account.id, setupGeneration == generation else { return }
            guard let entry = catalog.entries.filter({ $0.catalogKey == catalogKey }).max(by: { $0.revision < $1.revision }) else {
                throw BlueprintStarterViewError.invalidCatalog
            }
            let isInitialLoad = catalogEntry == nil
            try configure(entry, ownerID: account.id, shareToken: nil, isInitialLoad: isInitialLoad)
            persistDraft()
            refreshSuggestions()
        } catch {
            guard !Task.isCancelled, self.account?.id == account.id, setupGeneration == generation else { return }
            errorMessage = setupErrorMessage(error)
        }
        loading = false
    }

    @MainActor
    private func requestPlanReview() async {
        guard !busy, mainDateConfirmed, BlueprintInstallReadiness.isValidEventName(eventName),
              installationOwnerID == nil || installationOwnerID == account?.id,
              let entry = catalogEntry, let coordinator, selectedChildrenHaveDates,
              draftOwnerUserID == account?.id, persistDraft() else { return }
        let ownerID = draftOwnerUserID
        let generation = setupGeneration
        busy = true
        errorMessage = nil
        defer {
            if account?.id == ownerID, setupGeneration == generation { busy = false }
        }
        do {
            let input: BlueprintInstallInput
            if let existing = requestForReview {
                input = existing
            } else {
                guard let ownerID,
                      let saved = try draftStore.load(ownerUserID: ownerID, catalogKey: entry.catalogKey, shareToken: draftShareToken)
                else { throw BlueprintStarterViewError.invalidCatalog }
                let copied = try await coordinator.prepareDraftCopy(saved)
                guard !Task.isCancelled, account?.id == ownerID, setupGeneration == generation else { return }
                let pin = copied.installationEntry
                input = BlueprintInstallInput(
                    requestID: draftRequestID,
                    catalogKey: pin.catalogKey,
                    revision: pin.revision,
                    contentHash: pin.contentHash,
                    mainEvent: .init(name: trimmedEventName, startsAt: startsAt, timeZone: timeZoneIdentifier),
                    selectedChildren: selectedChildren.sorted().compactMap { key in
                        scheduleDraft.confirmedDates[key].map { .init(key: key, startsAt: $0) }
                    },
                    selectedIdeaKeys: selectedIdeas.sorted(),
                    capabilities: SyncClientCapabilities.blueprintFeatures,
                    shareToken: copied.installationShareToken,
                    customizations: customizations.isEmpty ? nil : customizations
                )
                requestForReview = input
            }
            let response = try await coordinator.preview(input)
            guard !Task.isCancelled, account?.id == ownerID, setupGeneration == generation else { return }
            reviewedPlan = response.plan
            if installationOwnerID != nil {
                await install(input)
            } else {
                showReview = true
            }
        } catch {
            guard !Task.isCancelled, account?.id == ownerID, setupGeneration == generation else { return }
            errorMessage = setupErrorMessage(error)
        }
        busy = false
    }

    @MainActor
    private func install(_ input: BlueprintInstallInput) async {
        guard let coordinator, let ownerID = draftOwnerUserID,
              account?.id == ownerID, input.requestID == draftRequestID else { return }
        let generation = setupGeneration
        installAttemptStarted = true
        busy = true
        errorMessage = nil
        do {
            _ = try await coordinator.install(input)
            guard account?.id == ownerID, setupGeneration == generation else { return }
            draftCompleted = true
            AppHaptics.play(.success)
            onInstallationCompleted?()
            closeSetup()
        } catch {
            guard self.account?.id == ownerID, setupGeneration == generation else { return }
            errorMessage = setupErrorMessage(error)
            pendingIntents = (try? coordinator.pendingIntentsForActiveAccount()) ?? []
        }
        busy = false
    }

    @MainActor
    private func resume(_ intent: BlueprintInstallationIntent) async {
        guard let account, let coordinator, account.id == intent.ownerUserID else { return }
        let generation = setupGeneration
        busy = true
        errorMessage = nil
        do {
            _ = try await coordinator.resume(intent)
            guard self.account?.id == account.id, setupGeneration == generation else { return }
            draftCompleted = true
            AppHaptics.play(.success)
            onInstallationCompleted?()
            closeSetup()
        } catch {
            guard self.account?.id == account.id, setupGeneration == generation else { return }
            errorMessage = setupErrorMessage(error)
            pendingIntents = (try? coordinator.pendingIntentsForActiveAccount()) ?? []
        }
        busy = false
    }

    private func resetSetup() {
        setupGeneration = UUID()
        coordinator = nil
        catalogEntry = nil
        tree = nil
        ideas = nil
        customizations = BlueprintCustomization()
        previewDecisions = [:]
        selectedChildren = []
        selectedIdeas = []
        scheduleDraft = BlueprintScheduleDraft()
        scheduleRequest = nil
        dateContext = BlueprintSetupDateContext()
        mainDateConfirmed = false
        lastPersistedEventName = ""
        dateEditorCapture = nil
        eventName = ""
        draftOwnerUserID = nil
        draftShareToken = nil
        draftRequestID = UUID()
        draftCompleted = false
        draftSaveError = nil
        pendingIntents = []
        installAttemptStarted = false
        busy = false
        dateSheetChild = nil
        showsMainDate = false
        showReview = false
        invalidateReview()
    }

    private func setupErrorMessage(_ error: Error) -> String {
        if sharedToken != nil || draftShareToken != nil,
           case CloudSyncFailure.server(let code) = error,
           code == "BLUEPRINT_NOT_FOUND" || code == "BLUEPRINT_LINK_UNAVAILABLE" {
            return BlueprintCopy.sharedLinkUnavailable
        }
        return error.localizedDescription
    }

    private func startOver() async {
        guard !busy, !installAttemptStarted, pendingIntents.isEmpty,
              let ownerID = draftOwnerUserID, ownerID == account?.id,
              let catalogKey = catalogEntry?.catalogKey else { return }
        do {
            try draftStore.remove(
                ownerUserID: ownerID,
                catalogKey: catalogKey,
                requestID: draftRequestID,
                shareToken: draftShareToken
            )
            resetSetup()
            await load()
        } catch {
            draftSaveError = BlueprintCopy.draftSaveFailed
        }
    }

    private func restore(_ saved: BlueprintSetupDraft) throws {
        guard let zone = TimeZone(identifier: saved.timeZoneIdentifier) else {
            throw BlueprintStarterViewError.invalidCatalog
        }
        let overlay = saved.customizations ?? BlueprintCustomization()
        let effective = try overlay.applying(to: saved.entry)
        catalogEntry = saved.entry
        customizations = overlay
        previewDecisions = saved.previewDecisions ?? [:]
        tree = effective.tree
        ideas = effective.ideas
        draftOwnerUserID = saved.ownerUserID
        draftShareToken = saved.shareToken
        draftRequestID = saved.requestID
        eventName = saved.eventName
        lastPersistedEventName = saved.eventName
        dateContext = BlueprintSetupDateContext(startsAt: saved.startsAt, timeZone: zone)
        mainDateConfirmed = saved.mainDateConfirmed == true
        selectedChildren = saved.selectedChildren
        selectedIdeas = saved.selectedIdeas
        scheduleDraft = BlueprintScheduleDraft(confirmedDates: saved.confirmedDates)
    }

    private func configure(
        _ entry: BlueprintCatalogEntry,
        ownerID: String,
        shareToken: String?,
        isInitialLoad: Bool = true
    ) throws {
        let effective = try customizations.applying(to: entry)
        catalogEntry = entry
        tree = effective.tree
        ideas = effective.ideas
        draftOwnerUserID = ownerID
        draftShareToken = shareToken
        if isInitialLoad {
            selectedIdeas = Set(effective.ideas.ideas.map(\.key))
            eventName = entry.definition.experienceDefaults.type == "wedding"
                ? BlueprintCopy.defaultEventName(for: account?.displayName ?? "")
                : entry.definition.blueprint.name
        }
        if BlueprintInstallReadiness.isValidEventName(eventName) {
            lastPersistedEventName = trimmedEventName
        }
    }

    @discardableResult
    private func persistDraft() -> Bool {
        guard !draftCompleted, !installAttemptStarted, pendingIntents.isEmpty,
              let ownerID = draftOwnerUserID, ownerID == account?.id,
              let entry = catalogEntry else { return false }
        let nameToPersist = BlueprintInstallReadiness.isValidEventName(eventName)
            ? trimmedEventName : lastPersistedEventName
        guard BlueprintInstallReadiness.isValidEventName(nameToPersist) else { return false }
        do {
            var saved = BlueprintSetupDraft(
                ownerUserID: ownerID, entry: entry, requestID: draftRequestID,
                eventName: nameToPersist, startsAt: startsAt, timeZoneIdentifier: timeZoneIdentifier,
                selectedChildren: selectedChildren, selectedIdeas: selectedIdeas,
                confirmedDates: scheduleDraft.confirmedDates,
                shareToken: draftShareToken,
                customizations: customizations.isEmpty ? nil : customizations,
                previewDecisions: previewDecisions.isEmpty ? nil : previewDecisions,
                mainDateConfirmed: mainDateConfirmed
            )
            if let existing = try draftStore.load(ownerUserID: ownerID, catalogKey: entry.catalogKey, shareToken: draftShareToken),
               existing.requestID == saved.requestID, existing.entry.contentHash == entry.contentHash,
               existing.entry.revision == entry.revision {
                saved.copyRequestID = existing.copyRequestID
                saved.copyEntry = existing.copyEntry
            }
            try draftStore.save(saved)
            if BlueprintInstallReadiness.isValidEventName(eventName) {
                lastPersistedEventName = trimmedEventName
            }
            draftSaveError = nil
            return true
        } catch {
            draftSaveError = BlueprintCopy.draftSaveFailed
            return false
        }
    }
}

private struct BlueprintPlanReviewView: View {
    let plan: BlueprintExpandedPlan
    let requestID: UUID
    let onInstall: () -> Void
    let isInstalling: Bool
    let errorMessage: String?
    let pendingIntents: [BlueprintInstallationIntent]
    let onResume: (BlueprintInstallationIntent) -> Void

    var body: some View {
        Form {
            Section(BlueprintCopy.mainEvent) {
                eventRow(plan.main)
            }

            if !plan.children.isEmpty {
                Section(BlueprintCopy.children) {
                    ForEach(plan.children) { eventRow($0) }
                }
            }

            if !plan.ideas.isEmpty {
                Section(BlueprintCopy.ideas) {
                    ForEach(plan.ideas) { idea in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(idea.title)
                            if let notes = idea.notes, !notes.isEmpty {
                                Text(notes).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !plan.todos.isEmpty {
                Section {
                    ForEach(plan.todos) { todo in
                        BlueprintTodoDefinitionRow(title: todo.title, websiteURL: todo.websiteURL)
                    }
                } header: {
                    Text(TodoCopy.title)
                } footer: {
                    Text(BlueprintCopy.todoCopyExplanation)
                }
            }

            if !plan.instructions.isEmpty {
                Section {
                    ForEach(plan.instructions) { guide in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(guide.title).font(.headline)
                            Text(guide.body)
                            Text(guide.audience == .planningOnly ? "Planning team only" : "Shared with event guests")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Planning Guide")
                }
            }

            if !plan.omissions.isEmpty {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(BlueprintCopy.omitted).font(.headline)
                        ForEach(Array(Set(plan.omissions.map { omission in
                            omission.reason == "child_not_selected"
                                ? BlueprintCopy.omittedUnselectedContent
                                : BlueprintCopy.omittedUnsupportedContent
                        })).sorted(), id: \.self) { explanation in
                            Text(explanation)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }

        }
        .formStyle(.grouped)
        .listSectionSpacing(.custom(20))
        .safeAreaBar(edge: .bottom, spacing: 0) {
            BlueprintSetupActionBar(
                title: isInstalling ? BlueprintCopy.installing
                    : pendingIntents.contains(where: { $0.requestID == requestID })
                        ? BlueprintCopy.retryInstall : BlueprintCopy.install,
                isWorking: isInstalling,
                isEnabled: !isInstalling,
                errorMessage: errorMessage
            ) {
                if let pending = pendingIntents.first(where: { $0.requestID == requestID }) {
                    onResume(pending)
                } else {
                    onInstall()
                }
            }
        }
        .navigationTitle(BlueprintCopy.review)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventRow(_ event: BlueprintPlannedEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name).font(.headline)
            Text(formattedDate(event.startsAt, timeZone: event.timeZone))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func formattedDate(_ date: Date, timeZone identifier: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: identifier)
        let zone = formatter.timeZone.abbreviation(for: date) ?? identifier
        return "\(formatter.string(from: date)) · \(zone)"
    }
}

private enum BlueprintStarterViewError: LocalizedError {
    case invalidCatalog

    var errorDescription: String? {
        String(localized: "blueprint.catalogInvalid", defaultValue: "This blueprint returned an unsupported plan.")
    }
}
