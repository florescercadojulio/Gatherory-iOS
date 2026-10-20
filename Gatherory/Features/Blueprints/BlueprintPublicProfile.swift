import SwiftUI

nonisolated enum BlueprintCreatorNameValidation {
    static func normalized(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 80 else { return nil }
        return name
    }
}

nonisolated enum BlueprintSharingStatus: String, CaseIterable, Sendable {
    case linkActive
    case inSearch
    case privateBlueprint

    static func badges(activeShareLinkCount: Int?, listedRevision: Int?) -> [Self] {
        var result: [Self] = []
        if let activeShareLinkCount, activeShareLinkCount > 0 { result.append(.linkActive) }
        if listedRevision != nil { result.append(.inSearch) }
        if activeShareLinkCount == 0, listedRevision == nil { result.append(.privateBlueprint) }
        return result
    }

    @MainActor var title: String {
        switch self {
        case .linkActive: BlueprintCopy.statusLinkActive
        case .inSearch: BlueprintCopy.statusInSearch
        case .privateBlueprint: BlueprintCopy.statusPrivate
        }
    }

    var symbol: String {
        switch self {
        case .linkActive: "link"
        case .inSearch: "magnifyingglass"
        case .privateBlueprint: "lock"
        }
    }
}

struct BlueprintSharingStatusBadges: View {
    let activeShareLinkCount: Int?
    let listedRevision: Int?
    var isRetired = false

    var body: some View {
        let statuses = BlueprintSharingStatus.badges(
            activeShareLinkCount: activeShareLinkCount,
            listedRevision: listedRevision
        )
        if !isRetired && !statuses.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { badges(statuses) }
                VStack(alignment: .leading, spacing: 6) { badges(statuses) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func badges(_ statuses: [BlueprintSharingStatus]) -> some View {
        ForEach(statuses, id: \.self) { status in
            Label(status.title, systemImage: status.symbol)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.black.opacity(0.58), in: Capsule())
        }
    }
}

struct BlueprintCreatorNameSheet: View {
    let initialName: String
    let isSubmitting: Bool
    let onPublish: (String) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var didEditName = false

    init(initialName: String = "", isSubmitting: Bool = false,
         onPublish: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialName = initialName
        self.isSubmitting = isSubmitting
        self.onPublish = onPublish
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
    }

    private var normalizedName: String? { BlueprintCreatorNameValidation.normalized(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(BlueprintCopy.creatorNameLabel, text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: name) { _, _ in didEditName = true }
                    Text(BlueprintCopy.creatorNameExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if didEditName && normalizedName == nil {
                        Text(BlueprintCopy.creatorNameInvalid)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(BlueprintCopy.listInSearch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, action: onCancel)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let normalizedName else { return }
                        onPublish(normalizedName)
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(BlueprintCopy.listInSearch)
                        }
                    }
                    .disabled(normalizedName == nil || isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }
}
