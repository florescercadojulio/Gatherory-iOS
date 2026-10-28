import Foundation

enum HomeEventLayout: String, CaseIterable, Identifiable {
    case cards
    case overview

    static let preferenceKey = "home.layout"

    init(persistedValue: String) {
        self = HomeEventLayout(rawValue: persistedValue) ?? .cards
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: String(localized: "Cards")
        case .overview: String(localized: "Overview")
        }
    }
}
