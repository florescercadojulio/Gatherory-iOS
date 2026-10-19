import SwiftUI

struct BlueprintPreviewEventArtwork: Equatable {
    let category: TimelineCategory
    let symbol: String

    var colors: [Color] { category.artworkColors }
    var accent: Color { category.artworkAccent }

    static func resolve(
        id: BlueprintPreviewEventID,
        rawCategory: String,
        browseCategory: BlueprintBrowseCategory
    ) -> Self {
        guard case .child = id else {
            return Self(category: browseCategory.artworkCategory, symbol: browseCategory.symbol)
        }

        if rawCategory == "event" {
            return Self(category: browseCategory.artworkCategory, symbol: browseCategory.symbol)
        }
        let category = timelineCategory(for: rawCategory) ?? .other
        return Self(category: category, symbol: category.symbol)
    }

    private static func timelineCategory(for rawValue: String) -> TimelineCategory? {
        switch rawValue.lowercased().filter({ $0.isLetter || $0.isNumber }) {
        case "venue", "venuevisit": .venue
        case "foodtasting": .foodTasting
        case "photography", "photoshoot": .photography
        case "honeymoon": .honeymoon
        case "attirefitting": .attireFitting
        case "weddingshower": .weddingShower
        case "bachelorbachelorette", "bachelorparty", "bacheloretteparty": .bachelorBachelorette
        case "rehearsal": .rehearsal
        case "ceremony": .ceremony
        case "reception": .reception
        case "other": .other
        default: nil
        }
    }
}

struct BlueprintPreviewEventRailItem: Identifiable, Equatable {
    let id: BlueprintPreviewEventID
    let title: String
    let annotation: String?

    static func items(from content: BlueprintPreviewContent) -> [Self] {
        content.eventIDs.compactMap { id in
            guard let event = content.event(for: id) else { return nil }
            let annotation = event.scheduleProposal.map {
                String.localizedStringWithFormat(
                    BlueprintCopy.scheduleProposalExplanation,
                    $0.localTime,
                    Int64($0.dayOffset)
                )
            }
            return Self(id: id, title: event.title, annotation: annotation)
        }
    }
}
