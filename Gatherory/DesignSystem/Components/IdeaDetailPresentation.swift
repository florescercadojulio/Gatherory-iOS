import Glur
import SwiftUI

/// Authored display content only: no identity, votes, permissions or mutations.
struct IdeaDetailContent {
    let title: String
    let note: String
    let category: IdeaCategory
    let configuration: IdeaConfiguration?
    let currencyCode: String?

    init(title: String, note: String, category: IdeaCategory,
         configuration: IdeaConfiguration? = nil, currencyCode: String? = nil) {
        self.title = title
        self.note = note
        self.category = category
        self.configuration = configuration
        self.currencyCode = currencyCode
    }

    init(idea: PlanningIdea, currencyCode: String) {
        self.init(title: idea.title, note: idea.note, category: idea.category,
                  configuration: idea.configuration, currencyCode: currencyCode)
    }

    var musicTracks: [MusicTrack] {
        guard case let .music(configuration)? = configuration else { return [] }
        return configuration.tracks
    }
}

extension IdeaDetailContent {
    init(preview idea: BlueprintCatalogIdea) {
        self.init(title: idea.title, note: idea.notes ?? "", category: IdeaCategory(rawValue: idea.category) ?? .other)
    }
}

/// The actual idea reading screen, used by both the workspace and templates.
/// Only workspace callers supply live controls, provenance and category tools.
struct IdeaDetailScreen<Accessory: View, Footer: View, Details: View, Artwork: View>: View {
    let content: IdeaDetailContent
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var details: () -> Details
    @ViewBuilder var artwork: () -> Artwork
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        IdeaDetailPresentation {
            IdeaSummaryContent(title: content.title, note: content.note, category: content.category,
                               accessory: accessory, footer: footer)
        } details: {
            details()
        } backdrop: { progress in
            ZStack {
                artwork()
                    .scaleEffect(1 + (0.06 * progress))
                    .blur(radius: reduceTransparency ? 0 : 38 * progress, opaque: true)
                    .clipped()
                // The same reading contrast as the workspace idea screen.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.18 + 0.18 * progress), location: 0.55),
                        .init(color: .black.opacity(reduceTransparency ? 0.88 : 0.64), location: 1)
                    ], startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
    }
}

/// Static full-strength Glur, including the top edge. Reduce Motion need not
/// disable a static effect; Reduce Transparency retains the unblurred artwork.
struct GlurredArtwork<Artwork: View>: View {
    @ViewBuilder var artwork: () -> Artwork
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            artwork()
        } else {
            artwork().glur(radius: 40, mask: .linear(stops: [
                .init(intensity: 1, location: 0),
                .init(intensity: 1, location: 1)
            ]), noise: 0.035)
        }
    }
}

/// The same non-interactive notes card used by workspace category details.
struct IdeaNotesCard: View {
    let note: String
    let category: IdeaCategory

    var body: some View {
        if !note.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("About This Idea", systemImage: category.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(note)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ideaContentSurface()
        }
    }
}

/// The artwork-led reading layout shared by workspace ideas and catalog ideas.
/// Callers supply content and actions; this view never owns a workspace or sync.
struct IdeaDetailPresentation<Summary: View, Details: View, Backdrop: View>: View {
    @ViewBuilder var summary: () -> Summary
    @ViewBuilder var details: () -> Details
    @ViewBuilder var backdrop: (CGFloat) -> Backdrop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(proxy.size.height * 0.42, 260) + 16)
                        summary()
                    }
                    .padding(.bottom, AppTheme.Spacing.standard)
                    .frame(minHeight: proxy.size.height, alignment: .bottom)
                    details()
                }
                .padding(.horizontal, AppTheme.Layout.screenHorizontal)
                .padding(.bottom, AppTheme.Layout.screenBottom)
                .frame(minHeight: proxy.size.height, alignment: .bottom)
            }
            .scrollIndicators(.hidden)
            .appSoftScrollEdges()
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
            } action: { _, newOffset in
                scrollOffset = newOffset
            }
            .background {
                backdrop(reduceMotion ? 0 : min(max(scrollOffset / 220, 0), 1))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Shared summary surface, with live-only metadata/actions supplied separately.
struct IdeaSummaryContent<Accessory: View, Footer: View>: View {
    let title: String
    let note: String
    let category: IdeaCategory
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: AppTheme.Spacing.compact) {
                Label(category.title, systemImage: category.symbol)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: AppTheme.Spacing.compact)
                accessory()
            }
            Text(title)
                .font(.largeTitle.bold())
                .tracking(-0.7)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !note.isEmpty {
                Text(note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer()
        }
        .padding(AppTheme.Spacing.standard)
        .ideaContentSurface()
    }
}
