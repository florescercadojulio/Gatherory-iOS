import SwiftUI

/// Read-only, workspace-style presentation of ideas supplied by a blueprint.
/// This view intentionally has no live workspace or account dependencies.
struct BlueprintWorkspaceIdeasView: View {
    let ideas: [BlueprintCatalogIdea]
    var responses: [String: DecisionChoice] = [:]
    var emptyStateTitle: String = IdeaFilter.all.emptyTitle
    var emptyStateSymbol: String = "square.grid.2x2"
    var onEdit: ((BlueprintCatalogIdea) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIdeaKey: String?
    @Namespace private var ideaTransition

    var body: some View {
        ScrollView {
            Group {
                if ideas.isEmpty {
                    ContentUnavailableView(
                        emptyStateTitle,
                        systemImage: emptyStateSymbol
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.section)
                } else {
                    MasonryLayout(
                        columnCount: dynamicTypeSize.isAccessibilitySize ? 1 : 2,
                        spacing: 12,
                        layoutDirection: layoutDirection
                    ) {
                        ForEach(ideas) { idea in
                            Button {
                                selectedIdeaKey = idea.key
                            } label: {
                                ideaCard(idea)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(ExploreCopy.openHint)
                            .contextMenu {
                                if let onEdit {
                                    Button(AppCopy.Common.edit, systemImage: "pencil") { onEdit(idea) }
                                }
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
        .background(AppTheme.ColorToken.background)
        .navigationTitle(AppCopy.Tab.ideas)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedIdeaKey) { key in
            if let idea = ideas.first(where: { $0.key == key }) {
                Group {
                    if reduceMotion {
                        BlueprintIdeaPreview(idea: idea, onEdit: onEdit.map { edit in { edit(idea) } })
                    } else {
                        BlueprintIdeaPreview(idea: idea, onEdit: onEdit.map { edit in { edit(idea) } })
                            .navigationTransition(.zoom(sourceID: idea.key, in: ideaTransition))
                    }
                }
            }
        }
    }

    private func ideaCard(_ idea: BlueprintCatalogIdea) -> some View {
        let category = IdeaCategory(rawValue: idea.category) ?? .other

        return IdeaCollectionPresentation(
            title: idea.title,
            category: category,
            aspectRatio: category.collectionAspectRatio
        ) {
            MediaArtwork(
                imageData: nil,
                symbol: category.symbol,
                colors: category.artworkColors,
                accent: category.artworkAccent,
                ambientBlurRadius: 12,
                progressiveBlurRadius: 22,
                blurStart: 0.30
            )
        } supporting: {
            if let notes = idea.notes, !notes.isEmpty {
                Text(notes)
                    .lineLimit(1)
            }
        }
        .matchedTransitionSource(id: idea.key, in: ideaTransition)
        .overlay(alignment: .bottom) {
            TeamResponseBar(summary: BlueprintIdeaResponsePresentation.summary(responses[idea.key]),
                            showsTitle: false, showsSymbols: false, barHeight: 6)
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                .offset(y: 4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(BlueprintIdeaResponsePresentation.title(responses[idea.key]))
    }
}

enum BlueprintIdeasFilter: String, CaseIterable, Identifiable {
    case all
    case unanswered
    case love
    case maybe
    case passed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All Ideas")
        case .unanswered: String(localized: "Unanswered")
        case .love: String(localized: "Love It")
        case .maybe: String(localized: "Maybe")
        case .passed: String(localized: "Pass")
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .unanswered: "circle.dashed"
        case .love: "heart.fill"
        case .maybe: "questionmark.circle"
        case .passed: "hand.thumbsdown.fill"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: IdeaFilter.all.emptyTitle
        case .unanswered: String(localized: "No unanswered ideas")
        case .love: String(localized: "No ideas marked Love It")
        case .maybe: String(localized: "No ideas marked Maybe")
        case .passed: String(localized: "No passed ideas")
        }
    }

    func includes(_ response: DecisionChoice?) -> Bool {
        switch self {
        case .all: true
        case .unanswered: response == nil
        case .love: response == .love
        case .maybe: response == .maybe
        case .passed: response == .pass
        }
    }
}

struct BlueprintIdeasEventScopeAccessory: View {
    @Binding var scope: BlueprintPreviewScope
    let content: BlueprintPreviewContent

    private var title: String {
        switch scope {
        case .all: String(localized: "All Ideas")
        case .main: content.title
        case .child(let key): content.children.first { $0.key == key }?.title ?? content.title
        }
    }

    var body: some View {
        Menu {
            Button {
                withAnimation(.snappy) { scope = .all }
            } label: {
                Label("All Ideas", systemImage: scope == .all ? "checkmark" : "square.grid.2x2")
            }

            Button {
                withAnimation(.snappy) { scope = .main }
            } label: {
                Label(content.title, systemImage: scope == .main ? "checkmark" : "calendar")
            }

            if !content.children.isEmpty {
                Divider()
                ForEach(content.children) { child in
                    Button {
                        withAnimation(.snappy) { scope = .child(child.key) }
                    } label: {
                        Label(child.title, systemImage: scope == .child(child.key) ? "checkmark" : "calendar")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityLabel("Ideas event filter")
        .accessibilityValue(title)
        .accessibilityHint("Choose which blueprint event’s ideas to show")
    }
}

/// Personal preview choices, never collaborator votes or shared approval states.
enum BlueprintIdeaResponsePresentation {
    static func summary(_ choice: DecisionChoice?) -> TeamResponseSummary {
        switch choice {
        case .love: .init(love: 1)
        case .maybe: .init(maybe: 1)
        case .pass: .init(pass: 1)
        case nil: .init(unanswered: 1)
        }
    }

    static func title(_ choice: DecisionChoice?) -> String {
        switch choice {
        case .love: String(localized: "Love It")
        case .maybe: String(localized: "Maybe")
        case .pass: String(localized: "Pass")
        case nil: String(localized: "Unanswered")
        }
    }
}
