import SwiftUI

/// A focused wrapper around the same name field used by workspace editors.
struct BlueprintPreviewNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let onSave: (String) -> Void

    init(name: String, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.onSave = onSave
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            BasicEditorNameField(label: Text("Title"), prompt: Text("Event name"), text: $name)
            if trimmed.unicodeScalars.count > 120 {
                Text("Titles can be up to 120 characters.").foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .navigationTitle("Event name")
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardDismissal()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(trimmed); dismiss() }
                    .disabled(trimmed.isEmpty || trimmed.unicodeScalars.count > 120)
            }
        }
    }
}

struct BlueprintPreviewEditorRoute: Identifiable {
    enum Item {
        case name
        case dateTime
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

    let idea: BlueprintCatalogIdea?
    let children: [BlueprintCatalogChild]
    let onSave: (BlueprintCatalogIdea) -> Void

    @State private var title: String
    @State private var category: IdeaCategory?
    @State private var notes: String
    @State private var targetKey: String
    @State private var categoryPage = 0
    @State private var isChoosingCategory: Bool

    init(
        idea: BlueprintCatalogIdea?,
        children: [BlueprintCatalogChild],
        initialTarget: BlueprintTarget = .main,
        onSave: @escaping (BlueprintCatalogIdea) -> Void
    ) {
        self.idea = idea
        self.children = children
        self.onSave = onSave
        _title = State(initialValue: idea?.title ?? "")
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
        !trimmedTitle.isEmpty
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
        .scrollContentBackground(.hidden)
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
            configuration: idea?.configuration ?? ["version": .integer(1)]
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

    let child: BlueprintCatalogChild?
    let onSave: (BlueprintCatalogChild) -> Void

    @State private var title: String
    @State private var category: TimelineCategory
    @State private var purpose: EventPurpose

    init(child: BlueprintCatalogChild?, onSave: @escaping (BlueprintCatalogChild) -> Void) {
        self.child = child
        self.onSave = onSave
        _title = State(initialValue: child?.title ?? "")
        _category = State(initialValue: child.flatMap { Self.timelineCategory(from: $0.category) } ?? .other)
        _purpose = State(initialValue: child?.purpose == "part_of_event" ? .eventExperience : .planning)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedTitle.isEmpty && trimmedTitle.unicodeScalars.count <= 120
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
        .scrollContentBackground(.hidden)
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
            scheduleProposal: child?.scheduleProposal
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
