import SwiftUI

struct BlueprintSetupView: View {
    // nil opens recovery only; it must never silently choose a different starter.
    let catalogKey: String?
    @Environment(WorkspaceCloudSyncController.self) private var cloudSync
    @Environment(\.currentUserAccount) private var account
    @Environment(\.dismiss) private var dismiss

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
    @State private var datesKept = false
    @State private var selectedIdeas: Set<String> = []
    @State private var eventName = ""
    @State private var dateContext = BlueprintSetupDateContext()
    @State private var dateSheetChild: BlueprintCatalogChild?
    @State private var dateDraft = Date.now
    @State private var requestForReview: BlueprintInstallInput?
    @State private var reviewedPlan: BlueprintExpandedPlan?
    @State private var showReview = false

    private struct ScheduleRequest {
        let token: UUID
        let input: BlueprintScheduleInput
    }

    private var coordinatorForView: BlueprintInstallationCoordinator? {
        if let coordinator { return coordinator }
        return cloudSync.makeBlueprintInstallationCoordinator()
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
                Section {
                    TextField(BlueprintCopy.eventName, text: $eventName)
                        .textInputAutocapitalization(.words)
                    DatePicker(BlueprintCopy.dateTime, selection: Binding(
                        get: { startsAt },
                        set: { dateContext.startsAt = $0; scheduleAnchorChanged() }
                    ))
                        .environment(\.timeZone, selectedTimeZone)
                    Picker(BlueprintCopy.timeZone, selection: Binding(
                        get: { timeZoneIdentifier },
                        set: { if dateContext.selectTimeZone($0) { scheduleAnchorChanged() } }
                    )) {
                        ForEach(dateContext.timeZoneOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    Button(BlueprintCopy.useDeviceTimeZone, systemImage: "clock") {
                        if dateContext.useDeviceTimeZone() { scheduleAnchorChanged() }
                    }
                } header: {
                    Text(BlueprintCopy.mainEvent)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(catalogEntry?.discovery?.summary ?? BlueprintCopy.description)
                        Text(BlueprintCopy.deviceTimeZoneHint)
                    }
                }

                Section(BlueprintCopy.children) {
                    Text(BlueprintCopy.suggestionConfirmation)
                        .font(.footnote).foregroundStyle(.secondary)
                    if datesKept {
                        Text(BlueprintCopy.datesKept)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
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
                    }
                }

                Section(BlueprintCopy.ideas) {
                    ForEach(ideas.ideas) { idea in
                        Toggle(isOn: ideaSelection(idea)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(idea.title)
                                if let notes = idea.notes, !notes.isEmpty {
                                    Text(notes).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text(BlueprintCopy.nothingCreatedYet)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await requestPlanReview() }
                    } label: {
                        if busy {
                            ProgressView { Text(BlueprintCopy.reviewing) }
                        } else {
                            Text(BlueprintCopy.review)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(busy || trimmedEventName.isEmpty || !selectedChildrenHaveDates)
                    .buttonStyle(.borderedProminent)
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
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle(catalogEntry?.definition.blueprint.name ?? BlueprintCopy.starter)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppCopy.Common.close) { dismiss() }
            }
        }
        .task(id: loadTaskID) { await load() }
        .task(id: scheduleRequest?.token) {
            if let request = scheduleRequest { await fetchSuggestions(request) }
        }
        .onChange(of: eventName) { _, _ in invalidateReview() }
        .onChange(of: scheduleDraft.confirmedDates) { _, _ in invalidateReview() }
        .navigationDestination(isPresented: Binding(
            get: { dateSheetChild != nil },
            set: { if !$0 { dateSheetChild = nil } }
        )) {
            if let child = dateSheetChild {
                Form {
                    DatePicker(BlueprintCopy.dateTime, selection: $dateDraft)
                        .environment(\.timeZone, selectedTimeZone)
                    Text(formattedChildDate(dateDraft))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .navigationTitle(child.title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppCopy.Common.cancel) { dateSheetChild = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(BlueprintCopy.confirmDate) {
                            scheduleDraft.confirm(key: child.key, date: dateDraft)
                            dateSheetChild = nil
                        }
                    }
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

    private func openManualDatePicker(for child: BlueprintCatalogChild) {
        // Capture once on opening. A suggestion arriving while the editor is
        // open must not replace the person's in-progress changes.
        dateDraft = scheduleDraft.initialManualDate(for: child.key, fallback: startsAt)
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
            }
        )
    }

    private func ideaSelection(_ idea: BlueprintCatalogIdea) -> Binding<Bool> {
        Binding(
            get: { selectedIdeas.contains(idea.key) },
            set: { isSelected in
                if isSelected { selectedIdeas.insert(idea.key) }
                else { selectedIdeas.remove(idea.key) }
                invalidateReview()
            }
        )
    }

    private func invalidateReview() {
        requestForReview = nil
        reviewedPlan = nil
        errorMessage = nil
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
                        _ = scheduleDraft.confirmSuggestion(key: child.key, candidateIndex: index, token: token)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BlueprintCopy.useSuggestedDate)
                            Text(formattedChildDate(suggestion.candidates[index])).font(.footnote)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            } else if suggestion.status == "nonexistent" {
                Text(BlueprintCopy.nonexistentTime).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleAnchorChanged() {
        invalidateReview()
        datesKept = !scheduleDraft.confirmedDates.isEmpty
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard let entry = catalogEntry, !installAttemptStarted, pendingIntents.isEmpty else { return }
        // Expire old buttons synchronously, before the asynchronous task starts.
        let token = scheduleDraft.beginRefresh()
        scheduleRequest = ScheduleRequest(token: token, input: BlueprintScheduleInput(
            catalogKey: entry.catalogKey, revision: entry.revision, contentHash: entry.contentHash,
            mainEvent: .init(startsAt: startsAt, timeZone: timeZoneIdentifier)
        ))
    }

    @MainActor
    private func fetchSuggestions(_ request: ScheduleRequest) async {
        guard let coordinator else { return }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let response = try await coordinator.schedule(request.input)
            try Task.checkCancellation()
            scheduleDraft.apply(response.suggestions, token: request.token)
        } catch {
            guard !Task.isCancelled else { return }
            scheduleDraft.failRefresh(token: request.token)
        }
    }

    private func formattedChildDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.timeZone = selectedTimeZone
        let localizedDate = formatter.string(from: date)
        formatter.dateFormat = "ZZZZ"
        return "\(localizedDate) · \(formatter.string(from: date)) · \(timeZoneIdentifier)"
    }

    @MainActor
    private func load() async {
        guard let account else {
            loading = false
            errorMessage = BlueprintCopy.signInRequired
            return
        }
        guard let coordinator = coordinatorForView else {
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
            guard let catalogKey else { throw BlueprintStarterViewError.invalidCatalog }
            let catalog = try await coordinator.catalog()
            guard let entry = catalog.entries.filter({ $0.catalogKey == catalogKey }).max(by: { $0.revision < $1.revision }),
                  let treeModule = entry.definition.modules.first(where: { $0.type == "experience_tree" }),
                  let decodedTree = treeModule.decodeConfiguration(BlueprintExperienceTreeConfig.self),
                  let ideasModule = entry.definition.modules.first(where: { $0.type == "ideas" }),
                  let decodedIdeas = ideasModule.decodeConfiguration(BlueprintIdeasConfig.self) else {
                throw BlueprintStarterViewError.invalidCatalog
            }
            let isInitialLoad = catalogEntry == nil
            catalogEntry = entry
            tree = decodedTree
            ideas = decodedIdeas
            if isInitialLoad {
                selectedIdeas = Set(decodedIdeas.ideas.map(\.key))
                eventName = entry.definition.experienceDefaults.type == "wedding"
                    ? BlueprintCopy.defaultEventName(for: account.displayName)
                    : entry.definition.blueprint.name
            }
            refreshSuggestions()
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func requestPlanReview() async {
        guard let entry = catalogEntry, let coordinator, selectedChildrenHaveDates else { return }
        busy = true
        errorMessage = nil
        let input: BlueprintInstallInput
        if let existing = requestForReview {
            input = existing
        } else {
            input = BlueprintInstallInput(
                requestID: UUID(),
                catalogKey: entry.catalogKey,
                revision: entry.revision,
                contentHash: entry.contentHash,
                mainEvent: .init(name: trimmedEventName, startsAt: startsAt, timeZone: timeZoneIdentifier),
                selectedChildren: selectedChildren.sorted().compactMap { key in
                    scheduleDraft.confirmedDates[key].map { .init(key: key, startsAt: $0) }
                },
                selectedIdeaKeys: selectedIdeas.sorted(),
                capabilities: SyncClientCapabilities.blueprintFeatures
            )
            requestForReview = input
        }
        do {
            let response = try await coordinator.preview(input)
            reviewedPlan = response.plan
            showReview = true
        } catch {
            errorMessage = error.localizedDescription
        }
        busy = false
    }

    @MainActor
    private func install(_ input: BlueprintInstallInput) async {
        guard let coordinator else { return }
        installAttemptStarted = true
        busy = true
        errorMessage = nil
        do {
            _ = try await coordinator.install(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            pendingIntents = (try? coordinator.pendingIntentsForActiveAccount()) ?? []
        }
        busy = false
    }

    @MainActor
    private func resume(_ intent: BlueprintInstallationIntent) async {
        guard let account, let coordinator, account.id == intent.ownerUserID else { return }
        busy = true
        errorMessage = nil
        do {
            _ = try await coordinator.resume(intent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            pendingIntents = (try? coordinator.pendingIntentsForActiveAccount()) ?? []
        }
        busy = false
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

            Section(BlueprintCopy.planningSetup) {
                LabeledContent(BlueprintCopy.experienceType, value: plan.experienceType)
                LabeledContent(BlueprintCopy.categoryOrder, value: plan.categoryOrder.joined(separator: ", "))
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
                            LabeledContent(BlueprintCopy.category, value: idea.category)
                            LabeledContent(BlueprintCopy.status, value: idea.status)
                            LabeledContent(BlueprintCopy.target, value: targetName(for: idea.targetSourceKey))
                            if let configuration = configurationText(idea.configuration) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(BlueprintCopy.configuration)
                                    Text(configuration).font(.caption.monospaced())
                                }
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            }
                            if let notes = idea.notes, !notes.isEmpty {
                                Text(notes).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
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
                            Text(targetName(for: guide.targetSourceKey))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Planning Guide")
                }
            }

            if !plan.omissions.isEmpty {
                Section(BlueprintCopy.omitted) {
                    ForEach(plan.omissions) { omission in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(omission.sourceKey)
                            Text(BlueprintCopy.omissionReason)
                            Text(omission.reason)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text(isInstalling || !pendingIntents.isEmpty
                     ? BlueprintCopy.pendingInstall
                     : BlueprintCopy.nothingCreatedYet)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let pending = pendingIntents.first(where: { $0.requestID == requestID }) {
                    Button(BlueprintCopy.retryInstall, systemImage: "arrow.clockwise") {
                        onResume(pending)
                    }
                    .disabled(isInstalling)
                } else {
                    Button(action: onInstall) {
                        if isInstalling { ProgressView { Text(BlueprintCopy.installing) } }
                        else { Text(BlueprintCopy.install).frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle(BlueprintCopy.review)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventRow(_ event: BlueprintPlannedEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.name).font(.headline)
            Text(formattedDate(event.startsAt, timeZone: event.timeZone))
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent(BlueprintCopy.eventType, value: event.eventType)
            if let parentSourceKey = event.parentSourceKey {
                LabeledContent(BlueprintCopy.parentEvent, value: targetName(for: parentSourceKey))
            }
            if let purpose = event.purpose {
                LabeledContent(BlueprintCopy.eventPurpose, value: purpose)
            }
            if let category = event.category {
                LabeledContent(BlueprintCopy.category, value: category)
            }
            if let status = event.planningStatus {
                LabeledContent(BlueprintCopy.status, value: status)
            }
        }
        .padding(.vertical, 3)
    }

    private func formattedDate(_ date: Date, timeZone identifier: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: identifier)
        return "\(formatter.string(from: date)) · \(identifier)"
    }

    private func targetName(for sourceKey: String) -> String {
        if plan.main.sourceKey == sourceKey { return plan.main.name }
        return plan.children.first(where: { $0.sourceKey == sourceKey })?.name ?? sourceKey
    }

    private func configurationText(_ configuration: [String: ExperienceJSONValue]) -> String? {
        guard let data = try? JSONEncoder().encode(configuration),
              let json = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: formatted, encoding: .utf8)
    }
}

private enum BlueprintStarterViewError: LocalizedError {
    case invalidCatalog

    var errorDescription: String? {
        String(localized: "blueprint.catalogInvalid", defaultValue: "This blueprint returned an unsupported plan.")
    }
}
