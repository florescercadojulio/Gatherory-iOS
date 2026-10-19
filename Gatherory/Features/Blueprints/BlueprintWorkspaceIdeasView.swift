import SwiftUI

/// Read-only, workspace-style presentation of ideas supplied by a blueprint.
/// This view intentionally has no live workspace or account dependencies.
struct BlueprintWorkspaceIdeasView: View {
    let ideas: [BlueprintCatalogIdea]
    var responses: [String: DecisionChoice] = [:]
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
                        IdeaFilter.all.emptyTitle,
                        systemImage: "square.grid.2x2"
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
