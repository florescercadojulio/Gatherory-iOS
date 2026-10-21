import SwiftUI

/// Row-local anchor prevents presenting from an offscreen navigation/form root.
/// Scrolling the calendar leaves the explicit confirmation controls reachable.
private struct BlueprintDatePopup: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var date: Date
    let title: String
    let timeZone: TimeZone
    let onConfirm: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.headline)
                        DatePicker(BlueprintCopy.dateTime, selection: $date)
                            .datePickerStyle(.graphical)
                            .environment(\.timeZone, timeZone)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                HStack {
                    Button(AppCopy.Common.cancel) { isPresented = false }
                    Spacer()
                    Button(BlueprintCopy.confirmDate) {
                        onConfirm()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .frame(idealWidth: 340, idealHeight: verticalSizeClass == .compact ? 220 : 460,
                   maxHeight: verticalSizeClass == .compact ? 260 : 500)
            .presentationCompactAdaptation(.popover)
        }
    }
}

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
    @State private var customizations = BlueprintCustomization()
    @State private var previewDecisions: [String: DecisionChoice] = [:]
    @State private var contentEditor: ContentEditor?

    private let draftStore = BlueprintSetupDraftStore()

    init(catalogKey: String?, sharedToken: String? = nil, returnsToPreview: Bool = false,
         installationOwnerID: String? = nil,
         onInstallationCompleted: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.catalogKey = catalogKey
        self.sharedToken = sharedToken
        self.returnsToPreview = returnsToPreview
        self.installationOwnerID = installationOwnerID
        self.onInstallationCompleted = onInstallationCompleted
        self.onClose = onClose
    }

    private struct ScheduleRequest {
        let token: UUID
        let input: BlueprintScheduleInput
    }

    private struct ContentEditor {
        enum Item {
            case idea(BlueprintCatalogIdea?)
            case child(BlueprintCatalogChild?)
        }
        let item: Item
        let ownerID: String
        let generation: UUID
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
            && catalogEntry != nil && draftSaveError == nil && errorMessage == nil
            && BlueprintInstallReadiness.isReady(mainDateConfirmed: mainDateConfirmed,
                                                selected: selectedChildren, confirmed: scheduleDraft.confirmedDates)
    }

    var body: some View {
        Form {
            if !pendingIntents.isEmpty {
                Section {
                    ForEach(pendingIntents, id: \.requestID) { intent in
                        Button {
                            Task { await resume(intent) }
                        } label: {
                            Label(BlueprintCopy.retryInstall, systemImage: "arrow.clockwise")
                        }
                        .disabled(busy || account?.id != intent.ownerUserID)
                    }
                    Text(BlueprintCopy.pendingInstall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(BlueprintCopy.finishPreviousInstall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            } else if installAttemptStarted {
                Section {
                    Text(BlueprintCopy.finishPreviousInstall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    if let input = requestForReview {
                        Button(BlueprintCopy.retrySameRequest, systemImage: "arrow.clockwise") {
                            Task { await install(input) }
                        }
                        .disabled(busy)
                    }
                }
            } else if loading {
                Section { ProgressView() }
            } else if let tree, let ideas {
                if let draftSaveError {
                    Section {
                        Text(draftSaveError).foregroundStyle(.red)
                        Button(AppCopy.Common.retry) { persistDraft() }
                    }
                }
                if installationOwnerID != nil {
                    missingDateSections(tree: tree)
                } else {
                Section {
                    TextField(BlueprintCopy.eventName, text: $eventName)
                        .textInputAutocapitalization(.words)
                    mainDateRow
                } header: {
                    Text(BlueprintCopy.mainEvent)
                } footer: {
                    Text(catalogEntry?.discovery?.summary ?? BlueprintCopy.description)
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
                            Button(AppCopy.Common.edit, systemImage: "pencil") {
                                openEditor(.child(child))
                            }
                            .font(.subheadline)
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
                                } else {
                                    suggestionChoices(for: child)
                                    Button(BlueprintCopy.chooseDate, systemImage: "calendar.badge.plus") {
                                        openManualDatePicker(for: child)
                                    }
                                    .font(.subheadline)
                                    Text(BlueprintCopy.childDateRequired)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .modifier(datePopup(for: child))
                    }
                    Button("Add Sub-event", systemImage: "plus") { openEditor(.child(nil)) }
                        .disabled(tree.children.count >= 50)
                }

                Section(BlueprintCopy.ideas) {
                    ForEach(ideas.ideas) { idea in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: ideaSelection(idea)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(idea.title)
                                    if let notes = idea.notes, !notes.isEmpty {
                                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Text(targetTitle(idea.target))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(AppCopy.Common.edit, systemImage: "pencil") {
                                openEditor(.idea(idea))
                            }
                            .font(.subheadline)
                        }
                    }
                    Button("Add Idea", systemImage: "plus") { openEditor(.idea(nil)) }
                        .disabled(ideas.ideas.count >= 100)
                }

                Section {
                    Button {
                        Task { await requestPlanReview() }
                    } label: {
                        if busy {
                            ProgressView { Text(BlueprintCopy.reviewing) }
                        } else {
                            Text(AppCopy.Common.continueAction)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(busy || !mainDateConfirmed || trimmedEventName.isEmpty || trimmedEventName.unicodeScalars.count > 120 || !selectedChildrenHaveDates || draftSaveError != nil)
                    .buttonStyle(.borderedProminent)
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

            if let errorMessage, !loading, catalogEntry != nil {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .navigationTitle(catalogEntry?.definition.blueprint.name ?? BlueprintCopy.starter)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        }
        .confirmationDialog(BlueprintCopy.startOverConfirmation, isPresented: $confirmsStartOver, titleVisibility: .visible) {
            Button(BlueprintCopy.startOver, role: .destructive) { Task { await startOver() } }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .task(id: loadTaskID) { await load() }
        .task(id: scheduleRequest?.token) {
            if let request = scheduleRequest { await fetchSuggestions(request) }
        }
        .onChange(of: eventName) { _, _ in invalidateReview(); persistDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistDraft() }
        }
        .onDisappear { persistDraft() }
        .navigationDestination(isPresented: Binding(
            get: { contentEditor != nil },
            set: { if !$0 { contentEditor = nil } }
        )) {
            if let editor = contentEditor {
                switch editor.item {
                case .idea(let idea):
                    BlueprintIdeaDraftEditor(idea: idea, children: tree?.children ?? []) {
                        saveIdea($0, editor: editor)
                    }
                case .child(let child):
                    BlueprintChildDraftEditor(child: child) { saveChild($0, editor: editor) }
                }
            }
        }
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

    private func targetTitle(_ target: BlueprintTarget) -> String {
        switch target {
        case .main: trimmedEventName.isEmpty ? BlueprintCopy.mainEvent : trimmedEventName
        case .child(let key): tree?.children.first { $0.key == key }?.title ?? BlueprintCopy.children
        }
    }

    @ViewBuilder
    private func missingDateSections(tree: BlueprintExperienceTreeConfig) -> some View {
        Section(BlueprintCopy.mainEvent) {
            mainDateRow
        }
        if !selectedChildren.isEmpty {
            Section {
                if scheduleDraft.refreshFailed {
                    Text(BlueprintCopy.datesUnavailable).font(.footnote).foregroundStyle(.secondary)
                    Button(AppCopy.Common.retry) { refreshSuggestions() }
                }
                ForEach(tree.children.filter { selectedChildren.contains($0.key) }) { child in
                    dateConfirmationRow(child)
                }
            } header: {
                HStack {
                    Text(BlueprintCopy.dateTime)
                    Spacer()
                    ProgressView().opacity(scheduleDraft.isRefreshing ? 1 : 0)
                        .accessibilityHidden(!scheduleDraft.isRefreshing)
                }
            } footer: {
                Text(String(localized: "blueprint.dates.rowHint", defaultValue: "Tap to edit. Swipe to confirm."))
            }
        }
        Section {
            Button { Task { await requestPlanReview() } } label: {
                HStack {
                    Text("Create Workspace")
                    Spacer()
                    ProgressView().opacity(busy ? 1 : 0).accessibilityHidden(!busy)
                }
            }
            .disabled(!readyForDirectInstallation)
        }
        if errorMessage != nil {
            Section {
                Button(AppCopy.Common.retry) { Task { await requestPlanReview() } }
                    .disabled(!mainDateConfirmed || !selectedChildrenHaveDates)
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
            Button { openManualDatePicker(for: child) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(child.title).font(.headline)
                        if let date = confirmed ?? candidate {
                            Text(formattedChildDate(date)).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(2, reservesSpace: true)
                        } else {
                            Text(BlueprintCopy.chooseDate).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(2, reservesSpace: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .opacity(confirmed != nil ? 1 : 0)
                        .accessibilityHidden(confirmed == nil)
                        .accessibilityLabel(BlueprintCopy.confirmedDate)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(BlueprintCopy.chooseDate)
            if confirmed == nil && suggestion?.status == "ambiguous" { suggestionChoices(for: child) }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(AppCopy.Common.edit, systemImage: "pencil") { openManualDatePicker(for: child) }
            if canConfirm {
                Button(BlueprintCopy.confirmDate, systemImage: "checkmark") {
                    if scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: 0, token: token) {
                        invalidateReview()
                        persistDraft()
                    }
                }.tint(.green)
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
        .modifier(datePopup(for: child))
    }

    private var mainDateRow: some View {
        Button {
            dateDraft = startsAt
            dateSheetChild = nil
            showsMainDate = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(BlueprintCopy.dateTime).font(.headline)
                    Text(formattedChildDate(startsAt)).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                    Text(mainDateConfirmed ? BlueprintCopy.confirmedDate : BlueprintCopy.confirmDate)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .opacity(mainDateConfirmed ? 1 : 0)
                    .accessibilityHidden(!mainDateConfirmed)
                    .accessibilityLabel(BlueprintCopy.confirmedDate)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(BlueprintDatePopup(isPresented: $showsMainDate, date: $dateDraft,
            title: BlueprintCopy.mainEvent, timeZone: selectedTimeZone) {
                guard !busy, !installAttemptStarted, pendingIntents.isEmpty,
                      let ownerID = draftOwnerUserID, ownerID == account?.id else { return }
                dateContext.startsAt = dateDraft
                mainDateConfirmed = true
                scheduleAnchorChanged()
            })
    }

    private func datePopup(for child: BlueprintCatalogChild) -> BlueprintDatePopup {
        BlueprintDatePopup(isPresented: Binding(
            get: { dateSheetChild?.key == child.key },
            set: { if !$0 && dateSheetChild?.key == child.key { dateSheetChild = nil } }
        ), date: $dateDraft, title: child.title, timeZone: selectedTimeZone) {
            guard !busy, !installAttemptStarted, pendingIntents.isEmpty,
                  let ownerID = draftOwnerUserID, ownerID == account?.id else { return }
            scheduleDraft.confirm(key: child.key, date: dateDraft)
            invalidateReview()
            persistDraft()
        }
    }

    private func openEditor(_ item: ContentEditor.Item) {
        guard !busy, !installAttemptStarted, pendingIntents.isEmpty,
              let ownerID = draftOwnerUserID, ownerID == account?.id else { return }
        contentEditor = ContentEditor(item: item, ownerID: ownerID, generation: setupGeneration)
    }

    private func canSaveContent(_ editor: ContentEditor) -> Bool {
        !busy && !installAttemptStarted && pendingIntents.isEmpty
            && editor.ownerID == account?.id && editor.ownerID == draftOwnerUserID
            && editor.generation == setupGeneration
    }

    private func saveChild(_ child: BlueprintCatalogChild, editor: ContentEditor) {
        guard canSaveContent(editor), let entry = catalogEntry else { return }
        var candidate = customizations
        do {
            try candidate.upsert(child)
            let effective = try candidate.applying(to: entry)
            let isNew = !(tree?.children.contains { $0.key == child.key } ?? false)
            customizations = candidate
            tree = effective.tree
            ideas = effective.ideas
            if isNew { selectedChildren.insert(child.key) }
            // Content edits never confirm or replace a date. New children must
            // use the existing explicit date-confirmation step before review.
            invalidateReview()
            persistDraft()
        } catch { errorMessage = BlueprintCopy.customizationInvalid }
    }

    private func saveIdea(_ idea: BlueprintCatalogIdea, editor: ContentEditor) {
        guard canSaveContent(editor), let entry = catalogEntry else { return }
        var candidate = customizations
        do {
            try candidate.upsert(idea)
            let effective = try candidate.applying(to: entry)
            let isNew = !(ideas?.ideas.contains { $0.key == idea.key } ?? false)
            customizations = candidate
            previewDecisions.removeValue(forKey: idea.key)
            tree = effective.tree
            ideas = effective.ideas
            if isNew { selectedIdeas.insert(idea.key) }
            invalidateReview()
            persistDraft()
        } catch { errorMessage = BlueprintCopy.customizationInvalid }
    }

    private func openManualDatePicker(for child: BlueprintCatalogChild) {
        // Capture once on opening. A suggestion arriving while the editor is
        // open must not replace the person's in-progress changes.
        dateDraft = scheduleDraft.initialManualDate(for: child.key, fallback: startsAt)
        showsMainDate = false
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

    private func ideaSelection(_ idea: BlueprintCatalogIdea) -> Binding<Bool> {
        Binding(
            get: { selectedIdeas.contains(idea.key) },
            set: { isSelected in
                if isSelected { selectedIdeas.insert(idea.key) }
                else { selectedIdeas.remove(idea.key) }
                previewDecisions.removeValue(forKey: idea.key)
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
        guard let coordinator = cloudSync.makeBlueprintInstallationCoordinator() else {
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
        guard !busy, mainDateConfirmed,
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
        guard let coordinator, let ownerID = draftOwnerUserID, account?.id == ownerID else { return }
        let generation = setupGeneration
        installAttemptStarted = true
        busy = true
        errorMessage = nil
        do {
            _ = try await coordinator.install(input)
            guard account?.id == ownerID, setupGeneration == generation else { return }
            draftCompleted = true
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
        contentEditor = nil
        selectedChildren = []
        selectedIdeas = []
        scheduleDraft = BlueprintScheduleDraft()
        scheduleRequest = nil
        dateContext = BlueprintSetupDateContext()
        mainDateConfirmed = false
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
        dateContext = BlueprintSetupDateContext(startsAt: saved.startsAt, timeZone: zone)
        mainDateConfirmed = saved.mainDateConfirmed == true
        selectedChildren = saved.selectedChildren
        selectedIdeas = saved.selectedIdeas
        // Preview installation must also normalize older drafts whose stored
        // selections predate the Love-only Home plan. Pending retries keep their
        // already-frozen request rather than rebuilding an installation.
        if installationOwnerID != nil {
            let plan = BlueprintPreviewContent(entry: saved.entry, customizations: overlay)?
                .homeContent(responses: previewDecisions)
            selectedChildren = Set(plan?.children.map(\.key) ?? [])
            selectedIdeas = Set(plan?.ideas.map(\.key) ?? [])
        }
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
    }

    @discardableResult
    private func persistDraft() -> Bool {
        guard !draftCompleted, !installAttemptStarted, pendingIntents.isEmpty,
              let ownerID = draftOwnerUserID, ownerID == account?.id,
              let entry = catalogEntry else { return false }
        do {
            var saved = BlueprintSetupDraft(
                ownerUserID: ownerID, entry: entry, requestID: draftRequestID,
                eventName: eventName, startsAt: startsAt, timeZoneIdentifier: timeZoneIdentifier,
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

            Section {
                if let pending = pendingIntents.first(where: { $0.requestID == requestID }) {
                    Button(BlueprintCopy.retryInstall, systemImage: "arrow.clockwise") {
                        onResume(pending)
                    }
                    .disabled(isInstalling)
                } else {
                    Button(action: onInstall) {
                        if isInstalling { ProgressView { Text(BlueprintCopy.installing) } }
                        else { Text("Create Workspace").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
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
