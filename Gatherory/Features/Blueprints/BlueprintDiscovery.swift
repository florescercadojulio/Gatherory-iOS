import Foundation
import Observation

enum BlueprintBrowseCategory: String, CaseIterable, Identifiable {
    case weddings, birthdays, holidays, events
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weddings: String(localized: "explore.weddings", defaultValue: "Weddings")
        case .birthdays: String(localized: "explore.birthdays", defaultValue: "Birthdays")
        case .holidays: String(localized: "explore.holidays", defaultValue: "Holidays")
        case .events: String(localized: "explore.events", defaultValue: "Other Events")
        }
    }

    var symbol: String {
        switch self {
        case .weddings: "heart.circle.fill"
        case .birthdays: "birthday.cake.fill"
        case .holidays: "gift.fill"
        case .events: "party.popper.fill"
        }
    }
}

enum BlueprintSearchMode: Equatable {
    case browse, recent, results

    static func resolve(isFocused: Bool, query: String) -> Self {
        guard isFocused else { return .browse }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .recent : .results
    }
}

extension BlueprintCatalogEntry {
    var browseCategories: [BlueprintBrowseCategory] {
        if let discovery {
            let known = discovery.categories.compactMap(BlueprintBrowseCategory.init(rawValue:))
            return known.isEmpty ? [.events] : known
        }
        // Older servers have no discovery metadata. Preserve a usable catalog.
        switch definition.experienceDefaults.type {
        case "wedding": return [.weddings]
        case "birthday": return [.birthdays]
        case "holiday": return [.holidays]
        default: return [.events]
        }
    }

    func matches(query: String) -> Bool {
        let fields = [definition.blueprint.name, catalogKey, discovery?.summary ?? ""]
            + (discovery?.tags ?? []) + browseCategories.flatMap { [$0.rawValue, $0.title] }
        let searchable = fields.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            searchable.contains(String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        }
    }
}

/// Device-local browsing history, never a workspace mutation or sync operation.
struct BlueprintRecentHistory {
    let defaults: UserDefaults
    private let limit = 12

    private func key(_ ownerID: String) -> String {
        "blueprint.recents.v1." + Data(ownerID.utf8).base64EncodedString()
    }

    func keys(ownerID: String) -> [String] {
        guard !ownerID.isEmpty else { return [] }
        var seen = Set<String>()
        return Array((defaults.stringArray(forKey: key(ownerID)) ?? [])
            .filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(limit))
    }

    func record(_ catalogKey: String, ownerID: String) {
        guard !ownerID.isEmpty, !catalogKey.isEmpty else { return }
        defaults.set(Array(([catalogKey] + keys(ownerID: ownerID).filter { $0 != catalogKey }).prefix(limit)), forKey: key(ownerID))
    }

    func clear(ownerID: String) { defaults.removeObject(forKey: key(ownerID)) }
}

@MainActor @Observable
final class BlueprintDiscoveryModel {
    private(set) var entries: [BlueprintCatalogEntry] = []
    private(set) var recentKeys: [String] = []
    private(set) var loading = false
    private(set) var loadFailed = false
    private let ownerID: String
    private let history: BlueprintRecentHistory
    private var generation = UUID()

    init(ownerID: String, defaults: UserDefaults = .standard) {
        self.ownerID = ownerID
        self.history = BlueprintRecentHistory(defaults: defaults)
        recentKeys = history.keys(ownerID: ownerID)
    }

    var recentEntries: [BlueprintCatalogEntry] {
        // Removed/retired entries cannot be resurrected from history.
        recentKeys.compactMap { key in entries.first { $0.catalogKey == key } }
    }

    func recordAccess(_ entry: BlueprintCatalogEntry) {
        history.record(entry.catalogKey, ownerID: ownerID)
        recentKeys = history.keys(ownerID: ownerID)
    }

    func clearRecents() {
        history.clear(ownerID: ownerID)
        recentKeys = []
    }

    func load(fetch: () async throws -> BlueprintCatalogResponse) async {
        let token = UUID()
        generation = token
        loading = true
        loadFailed = false
        defer { if generation == token { loading = false } }
        do {
            let response = try await fetch()
            guard generation == token, !Task.isCancelled else { return }
            var latest: [String: BlueprintCatalogEntry] = [:]
            for entry in response.entries where entry.definition.supportsCurrentSchema {
                if entry.revision > (latest[entry.catalogKey]?.revision ?? 0) { latest[entry.catalogKey] = entry }
            }
            entries = latest.values.sorted {
                let order = $0.definition.blueprint.name.localizedStandardCompare($1.definition.blueprint.name)
                return order == .orderedSame ? $0.catalogKey < $1.catalogKey : order == .orderedAscending
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            loadFailed = true
        }
    }
}
