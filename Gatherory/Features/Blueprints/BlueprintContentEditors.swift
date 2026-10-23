import SwiftUI

/// Stages the main event's editable values until the user saves the whole form.
struct BlueprintMainEventDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueprintCoverSource) private var coverSource
    @State private var values: BlueprintPreviewSession.MainEventValues
    @State private var coverAssetID: UUID?
    @State private var coverWasRemoved = false
    private let publicCoverImageURL: String?
    @State private var isUploadingCover = false
    @State private var showsDateEditor = false
    @State private var confirmsDate = false
    let onSave: (BlueprintPreviewSession.MainEventValues, UUID?, Bool, Bool) -> Void

    init(values: BlueprintPreviewSession.MainEventValues, coverAssetID: UUID?, publicCoverImageURL: String? = nil,
         onSave: @escaping (BlueprintPreviewSession.MainEventValues, UUID?, Bool, Bool) -> Void) {
        _values = State(initialValue: values)
        _coverAssetID = State(initialValue: coverAssetID)
        self.publicCoverImageURL = publicCoverImageURL
        self.onSave = onSave
    }

    private var trimmedName: String { values.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedTimeZone: TimeZone {
        TimeZone(identifier: values.timeZoneIdentifier) ?? .autoupdatingCurrent
    }
    private var formattedStart: String {
        values.startsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: selectedTimeZone))
    }
    private var isValid: Bool {
        !isUploadingCover && !trimmedName.isEmpty && trimmedName.unicodeScalars.count <= 120
            && values.startsAt.timeIntervalSince1970.isFinite
            && TimeZone(identifier: values.timeZoneIdentifier) != nil
    }

    var body: some View {
        Form {
            Section {
                BasicEditorNameField(label: Text("Title"), prompt: Text("Event name"), text: $values.name)
                if trimmedName.unicodeScalars.count > 120 {
                    Text("Titles can be up to 120 characters.").foregroundStyle(AppTheme.ColorToken.destructive)
                }
            } header: {
                Text(BlueprintCopy.eventName)
            }

            Section {
                Button { showsDateEditor = true } label: {
                    HStack(spacing: AppTheme.Spacing.standard) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                            Text(BlueprintCopy.dateTime)
                                .foregroundStyle(.primary)
                            Text("\(formattedStart) · \(selectedTimeZone.abbreviation(for: values.startsAt) ?? values.timeZoneIdentifier)")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                BlueprintCoverField(assetID: $coverAssetID, source: coverSource, isUploading: $isUploadingCover,
                                    publicImageURL: coverWasRemoved ? nil : publicCoverImageURL,
                                    onCoverRemoved: { coverWasRemoved = true })
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardDismissal()
        .interactiveDismissDisabled(isUploadingCover)
        .sheet(isPresented: $showsDateEditor) {
            EventDateTimeEditorView(startsAt: values.startsAt, endsAt: nil, isAllDay: false,
                                    timeZoneIdentifier: values.timeZoneIdentifier,
                                    supportsExtendedSchedule: false) { date, _, _, zone in
                values.startsAt = date
                values.timeZoneIdentifier = zone
                confirmsDate = true
            }
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    values.name = trimmedName
                    onSave(values, coverAssetID, confirmsDate, coverWasRemoved)
                    dismiss()
                }
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct BlueprintPreviewEditorRoute: Identifiable {
    enum Item {
        case mainEvent
        case child(BlueprintCatalogChild?)
        case idea(BlueprintCatalogIdea?)
    }
    let id = UUID()
    let item: Item
    let ownerID: String
    let generation: UUID
}

struct BlueprintIdeaDraftEditor: View {
    private struct TargetOption: Identifiable {
        let key: String
        let title: String
        var id: String { key }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueprintCoverSource) private var coverSource

    let idea: BlueprintCatalogIdea?
    let children: [BlueprintCatalogChild]
    let onSave: (BlueprintCatalogIdea) -> Void

    @State private var title: String
    @State private var category: IdeaCategory?
    @State private var notes: String
    @State private var targetKey: String
    @State private var coverAssetID: UUID?
    @State private var coverWasRemoved = false
    @State private var isUploadingCover = false
    @State private var categoryPage = 0
    @State private var isChoosingCategory: Bool
    private let publicCoverImageURL: String?

    init(
        idea: BlueprintCatalogIdea?,
        children: [BlueprintCatalogChild],
        publicCoverImageURL: String? = nil,
        initialTarget: BlueprintTarget = .main,
        onSave: @escaping (BlueprintCatalogIdea) -> Void
    ) {
        self.idea = idea
        self.children = children
        self.publicCoverImageURL = publicCoverImageURL
        self.onSave = onSave
        _title = State(initialValue: idea?.title ?? "")
        _coverAssetID = State(initialValue: idea?.coverAssetId)
        _category = State(initialValue: idea.map { IdeaCategory(rawValue: $0.category) ?? .other })
        _notes = State(initialValue: idea?.notes ?? "")
        _targetKey = State(initialValue: Self.targetKey(for: idea?.target ?? initialTarget))
        _isChoosingCategory = State(initialValue: idea == nil)
    }

    private static let categoryPages: [[IdeaCategory]] = [
        [.link, .event, .registry, .attire, .food, .flowers, .music, .decor, .invitations, .other],
        [.venue, .photography, .honeymoon]
    ]

    private var supportedCategories: [IdeaCategory] {
        IdeaCategory.allCases.filter { $0 != .music }
    }

    private var visibleCategoryPages: [[IdeaCategory]] {
        Self.categoryPages.map { page in page.filter { supportedCategories.contains($0) } }
            .filter { !$0.isEmpty }
    }

    private var targetOptions: [TargetOption] {
        [TargetOption(key: "main", title: BlueprintCopy.mainEvent)]
            + children.map { TargetOption(key: "child:\($0.key)", title: $0.title) }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !isUploadingCover && !trimmedTitle.isEmpty
            && trimmedTitle.unicodeScalars.count <= 120
            && notes.unicodeScalars.count <= 2_000
            && category.map { supportedCategories.contains($0) } == true
            && targetOptions.contains(where: { $0.key == targetKey })
    }

    var body: some View {
        Group {
            if isChoosingCategory {
                ScrollView {
                    BasicIdeaCategoryChooser(
                        pageIndex: $categoryPage,
                        selectedCategory: category,
                        pages: visibleCategoryPages,
                        onSelect: chooseCategory
                    )
                    .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                    .padding(.top, AppTheme.Spacing.compact)
                    .padding(.bottom, AppTheme.Layout.screenBottom)
                }
                .scrollIndicators(.hidden)
                .background(AppTheme.ColorToken.background)
            } else {
                detailsForm
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle(idea == nil ? Text(String(localized: "Add Template Idea", defaultValue: "Add Idea")) : Text(String(localized: "Edit Template Idea", defaultValue: "Edit Idea")))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .appKeyboardDismissal()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            if !isChoosingCategory {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var detailsForm: some View {
        Form {
            Section {
                BasicEditorNameField(label: Text("Title"), prompt: Text("Idea name"), text: $title)
                BasicEditorNotesField(
                    label: Text("Notes"),
                    prompt: Text("Add context or guidance (optional)"),
                    text: $notes
                )
                validationHint
            } header: {
                Text("Idea Details")
            }

            Section {
                BlueprintCoverField(assetID: $coverAssetID, source: coverSource, isUploading: $isUploadingCover,
                                    publicImageURL: coverWasRemoved ? nil : publicCoverImageURL,
                                    onCoverRemoved: { coverWasRemoved = true })
            }

            Section("Category") {
                if let category {
                    BasicIdeaCategoryButton(category: category) {
                        withAnimation(.snappy) {
                            isChoosingCategory = true
                        }
                    }
                }
            }

            Section {
                Picker(BlueprintCopy.target, selection: $targetKey) {
                    ForEach(targetOptions) { option in
                        Text(option.title).tag(option.key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var validationHint: some View {
        if trimmedTitle.unicodeScalars.count > 120 {
            Text("Titles can be up to 120 characters.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ColorToken.destructive)
        } else if notes.unicodeScalars.count > 2_000 {
            Text("Notes can be up to 2,000 characters.")
                .font(.footnote)
                .foregroundStyle(AppTheme.ColorToken.destructive)
        }
    }

    private func save() {
        guard isValid, let category else { return }
        let updatedIdea = BlueprintCatalogIdea(
            key: idea?.key ?? Self.newKey(),
            title: trimmedTitle,
            category: category.rawValue,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            target: Self.target(from: targetKey),
            configuration: idea?.configuration ?? ["version": .integer(1)],
            coverAssetId: coverAssetID,
            coverAssetIdWasProvided: coverWasRemoved || coverAssetID != idea?.coverAssetId || idea?.coverAssetIdWasProvided == true
        )
        onSave(updatedIdea)
        dismiss()
    }

    private func chooseCategory(_ category: IdeaCategory) {
        withAnimation(.snappy) {
            self.category = category
            isChoosingCategory = false
        }
    }

    private static func newKey() -> String {
        "custom_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_"))"
    }

    private static func targetKey(for target: BlueprintTarget) -> String {
        switch target {
        case .main: "main"
        case .child(let key): "child:\(key)"
        }
    }

    private static func target(from key: String) -> BlueprintTarget {
        guard key.hasPrefix("child:") else { return .main }
        return .child(key: String(key.dropFirst("child:".count)))
    }
}

struct BlueprintChildDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueprintCoverSource) private var coverSource

    let child: BlueprintCatalogChild?
    let publicCoverImageURL: String?
    let onSave: (BlueprintCatalogChild) -> Void

    @State private var title: String
    @State private var category: TimelineCategory
    @State private var purpose: EventPurpose
    @State private var coverAssetID: UUID?
    @State private var coverWasRemoved = false
    @State private var isUploadingCover = false

    init(child: BlueprintCatalogChild?, publicCoverImageURL: String? = nil, onSave: @escaping (BlueprintCatalogChild) -> Void) {
        self.child = child
        self.publicCoverImageURL = publicCoverImageURL
        self.onSave = onSave
        _title = State(initialValue: child?.title ?? "")
        _coverAssetID = State(initialValue: child?.coverAssetId)
        _category = State(initialValue: child.flatMap { Self.timelineCategory(from: $0.category) } ?? .other)
        _purpose = State(initialValue: child?.purpose == "part_of_event" ? .eventExperience : .planning)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !isUploadingCover && !trimmedTitle.isEmpty && trimmedTitle.unicodeScalars.count <= 120
    }

    var body: some View {
        Form {
            Section {
                BasicEditorNameField(label: Text("Title"), prompt: Text("Event name"), text: $title)
                if trimmedTitle.unicodeScalars.count > 120 {
                    Text("Titles can be up to 120 characters.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ColorToken.destructive)
                }
            } header: {
                Text(BlueprintCopy.eventName)
            }

            Section {
                BlueprintCoverField(assetID: $coverAssetID, source: coverSource, isUploading: $isUploadingCover,
                                    publicImageURL: coverWasRemoved ? nil : publicCoverImageURL,
                                    onCoverRemoved: { coverWasRemoved = true })
            }

            Section("Category") {
                EventCategoryStrip(selection: $category)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                BasicEventPurposePicker(selection: $purpose)
                Text(purpose.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Purpose")
            }
        }
        .background(AppTheme.ColorToken.background)
        .navigationTitle(child == nil ? Text(String(localized: "Add Template Sub-event", defaultValue: "Add Event")) : Text(String(localized: "Edit Template Sub-event", defaultValue: "Edit Event")))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .appKeyboardDismissal()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let updatedChild = BlueprintCatalogChild(
            key: child?.key ?? "custom_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "_"))",
            title: trimmedTitle,
            purpose: purpose == .eventExperience ? "part_of_event" : "planning_scouting",
            category: Self.blueprintCategory(from: category),
            scheduleProposal: child?.scheduleProposal,
            coverAssetId: coverAssetID,
            coverAssetIdWasProvided: coverWasRemoved || coverAssetID != child?.coverAssetId || child?.coverAssetIdWasProvided == true
        )
        onSave(updatedChild)
        dismiss()
    }

    private static func timelineCategory(from rawValue: String) -> TimelineCategory? {
        switch rawValue {
        case "food_tasting": .foodTasting
        case "attire_fitting": .attireFitting
        case "wedding_shower": .weddingShower
        case "bachelor_bachelorette": .bachelorBachelorette
        default: TimelineCategory(rawValue: rawValue)
        }
    }

    private static func blueprintCategory(from category: TimelineCategory) -> String {
        switch category {
        case .foodTasting: "food_tasting"
        case .attireFitting: "attire_fitting"
        case .weddingShower: "wedding_shower"
        case .bachelorBachelorette: "bachelor_bachelorette"
        default: category.rawValue
        }
    }
}

#Preview("Edit Blueprint Event · Light") {
    NavigationStack {
        BlueprintMainEventDraftEditor(
            values: .init(name: "Garden celebration", startsAt: .now, timeZoneIdentifier: TimeZone.current.identifier),
            coverAssetID: nil
            ) { _, _, _, _ in }
    }
    .preferredColorScheme(.light)
}

#Preview("Edit Blueprint Event · Dark") {
    NavigationStack {
        BlueprintMainEventDraftEditor(
            values: .init(name: "Garden celebration", startsAt: .now, timeZoneIdentifier: TimeZone.current.identifier),
            coverAssetID: nil
        ) { _, _, _, _ in }
    }
    .preferredColorScheme(.dark)
}
