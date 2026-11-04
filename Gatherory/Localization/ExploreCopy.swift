import Foundation

enum ExploreCopy {
    static var exploreBlueprints: String { String(localized: "explore.create.exploreBlueprints", defaultValue: "Explore Blueprints") }
    static var startFromScratch: String { String(localized: "explore.create.startFromScratch", defaultValue: "Start from Scratch") }
    static var title: String { String(localized: "explore.title", defaultValue: "Explore") }
    static var searchTitle: String { String(localized: "explore.searchTitle", defaultValue: "Search") }
    static var search: String { String(localized: "explore.search", defaultValue: "Search blueprints and ideas") }
    static var recent: String { String(localized: "explore.recent", defaultValue: "Recently Viewed") }
    static var clear: String { String(localized: "explore.clear", defaultValue: "Clear") }
    static var loading: String { String(localized: "explore.loading", defaultValue: "Loading blueprints…") }
    static var refresh: String { String(localized: "explore.refresh", defaultValue: "Refresh") }
    static var filter: String { String(localized: "explore.filter", defaultValue: "Filter") }
    static var unavailable: String { String(localized: "explore.unavailable", defaultValue: "Can’t Load Blueprints") }
    static var connection: String { String(localized: "explore.connection", defaultValue: "Connect to the internet and sign in to browse blueprints. Your events are still available offline.") }
    static var refreshFailed: String { String(localized: "explore.refreshFailed", defaultValue: "Couldn’t refresh. Showing the last loaded blueprints.") }
    static var noResults: String { String(localized: "explore.noResults", defaultValue: "No Blueprints Found") }
    static var tryAnotherSearch: String { String(localized: "explore.tryAnotherSearch", defaultValue: "Try another name or description.") }
    static var emptyCategory: String { String(localized: "explore.emptyCategory", defaultValue: "No Blueprints Yet") }
    static var checkBack: String { String(localized: "explore.checkBack", defaultValue: "There aren’t any blueprints in this category yet. Explore another category or start a blank event.") }
    static var noRecents: String { String(localized: "explore.noRecents", defaultValue: "No Recently Viewed Blueprints") }
    static var recentsHint: String { String(localized: "explore.recentsHint", defaultValue: "Blueprints you open will appear here. Search to find your first one.") }
    static var openHint: String { String(localized: "explore.openHint", defaultValue: "Explore the blueprint’s activities, ideas, and guidance. Nothing is created until you confirm.") }
}
