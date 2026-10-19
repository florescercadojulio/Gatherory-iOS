import SwiftUI

struct BasicEditorNameField: View {
    let label: Text?
    let prompt: Text
    @Binding var text: String
    var capitalization: TextInputAutocapitalization = .words
    var fieldAccessibilityLabel: Text? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                label
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField(text: $text, prompt: prompt) {
                fieldAccessibilityLabel ?? label ?? prompt
            }
                .textInputAutocapitalization(capitalization)
        }
    }
}

struct BasicEditorNotesField: View {
    let label: Text?
    let prompt: Text
    @Binding var text: String
    var lineLimit: ClosedRange<Int> = 3...6

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                label
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField(text: $text, prompt: prompt, axis: .vertical) {
                label ?? prompt
            }
                .textInputAutocapitalization(.sentences)
                .lineLimit(lineLimit)
        }
    }
}

struct BasicIdeaCategoryChooser: View {
    @Binding var pageIndex: Int
    let selectedCategory: IdeaCategory?
    let pages: [[IdeaCategory]]
    let onSelect: (IdeaCategory) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TabView(selection: $pageIndex) {
            ForEach(pages.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.compact),
                            count: 3
                        ),
                        spacing: AppTheme.Spacing.compact
                    ) {
                        ForEach(pages[index]) { option in
                            categoryTile(option)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 500 : 390)
        .accessibilityLabel("Idea categories")
    }

    private func categoryTile(_ option: IdeaCategory) -> some View {
        let isSelected = selectedCategory == option

        return Button {
            onSelect(option)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    CategoryGlassIcon(category: option, size: 42)
                        .scaleEffect(isSelected ? 1.06 : 1)
                        .opacity(isSelected ? 1 : 0.9)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.ColorToken.onAccent, AppTheme.ColorToken.accent)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(option.title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 112 : 76)
            .padding(4)
            .background(
                isSelected
                    ? option.artworkAccent.opacity(0.14)
                    : AppTheme.ColorToken.elevatedSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                    .stroke(
                        isSelected ? option.artworkAccent : AppTheme.ColorToken.cardBorder,
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects the \(option.title.lowercased()) idea form")
    }
}

struct BasicIdeaCategoryButton: View {
    let category: IdeaCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.standard) {
                CategoryGlassIcon(category: category, size: 48)

                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ColorToken.textPrimary)

                Spacer(minLength: AppTheme.Spacing.compact)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.minimumTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Idea type, \(category.title)")
        .accessibilityHint("Choose a different idea type")
    }
}

/// Shared by event creation and event ideas so choosing an event type feels
/// identical regardless of where the flow starts.
struct EventCategoryStrip: View {
    @Binding var selection: TimelineCategory

    private var orderedCategories: [TimelineCategory] {
        [.other] + TimelineCategory.allCases.filter { $0 != .other }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ForEach(orderedCategories) { option in
                    let isSelected = selection == option

                    Button {
                        withAnimation(.snappy) {
                            selection = option
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option == .other ? "circle.slash" : option.symbol)
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)

                            Text(option == .other ? "None" : option.title)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .foregroundStyle(isSelected ? AppTheme.ColorToken.onAccent : .primary)
                        .frame(width: 98, height: 76)
                        .background(
                            isSelected ? option.artworkAccent : AppTheme.ColorToken.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .strokeBorder(
                                    isSelected ? option.artworkAccent : AppTheme.ColorToken.cardBorder,
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option == .other ? "No category" : option.title)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Event categories")
    }
}

struct EventPurposeSelector: View {
    @Binding var selection: EventPurpose
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppTheme.Spacing.compact) { purposeTiles }
            } else {
                HStack(spacing: AppTheme.Spacing.compact) { purposeTiles }
            }
        }
        .padding(2)
        .accessibilityLabel("Event purpose")
    }

    private var purposeTiles: some View {
        ForEach(EventPurpose.allCases) { option in
            let isSelected = selection == option

            Button {
                withAnimation(.snappy) {
                    selection = option
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Label(option.title, systemImage: option.symbol)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    Text(option.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                .padding(8)
                .background(
                    isSelected ? AppTheme.ColorToken.accent.opacity(0.14) : AppTheme.ColorToken.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                        .strokeBorder(
                            isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.cardBorder,
                            lineWidth: isSelected ? 2 : 0.5
                        )
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }
}

struct BasicEventPurposePicker: View {
    @Binding var selection: EventPurpose

    var body: some View {
        Picker("Purpose", selection: $selection) {
            ForEach(EventPurpose.allCases) { option in
                Text(option.shortTitle).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
