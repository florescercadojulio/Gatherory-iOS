#if DEBUG
import Foundation

enum IdeaDiscoveryVisualFixture {
    static func pagingPage(cursor: String?, query: String?) -> IdeaDiscoveryResponse {
        let page = Int(cursor ?? "0") ?? 0
        let start = page * 20
        let records = (start..<(start + 20)).map { index in
            ("paging-idea-\(String(format: "%03d", index + 1))", "Paging idea \(index + 1)", index.isMultiple(of: 2) ? "food" : "other")
        }
        let ideas: [[String: Any]] = records.map { id, title, category in
            ["id": id, "sourceBlueprintId": "paging-fixture-blueprint", "sourceVersion": 1,
             "sourceTitle": "Paging fixture", "creator": ["displayName": "Gatherory"],
             "idea": ["key": id, "title": title, "category": category,
                      "notes": "Paging regression fixture idea.",
                      "target": ["kind": "main"], "configuration": ["version": 1]] as [String: Any]]
        }
        let nextCursor: Any = page < 3 ? String(page + 1) : NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: ["ideas": ideas, "nextCursor": nextCursor]),
              let response = try? JSONDecoder().decode(IdeaDiscoveryResponse.self, from: data) else {
            return IdeaDiscoveryResponse(ideas: [], nextCursor: nil)
        }
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedQuery.isEmpty else { return response }
        let matches = response.ideas.filter { "\($0.idea.title) \($0.idea.category)".localizedCaseInsensitiveContains(normalizedQuery) }
        return IdeaDiscoveryResponse(ideas: matches, nextCursor: response.nextCursor)
    }

    static func page(cursor: String?, query: String?) -> IdeaDiscoveryResponse {
        let page = cursor == nil ? 0 : 1
        let records = page == 0
            ? [("idea-fixture-1", "Garden brunch", "food"), ("idea-fixture-2", "Backyard games", "other"), ("idea-fixture-3", "Summer picnic", "event")]
            : [("idea-fixture-4", "Candlelit dinner", "food")]
        let ideas: [[String: Any]] = records.map { id, title, category in
            ["id": id, "sourceBlueprintId": "fixture-blueprint", "sourceVersion": 1,
             "sourceTitle": "A summer gathering", "creator": ["displayName": "Gatherory"],
             "idea": ["key": id, "title": title, "category": category,
                      "notes": "A bright, easy idea for your next get-together.",
                      "target": ["kind": "main"], "configuration": ["version": 1]] as [String: Any]]
        }
        let nextCursor: Any = page == 0 ? "fixture-next" : NSNull()
        guard let data = try? JSONSerialization.data(withJSONObject: ["ideas": ideas, "nextCursor": nextCursor]),
              let response = try? JSONDecoder().decode(IdeaDiscoveryResponse.self, from: data) else {
            return IdeaDiscoveryResponse(ideas: [], nextCursor: nil)
        }
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedQuery.isEmpty else { return response }
        let matches = response.ideas.filter { "\($0.idea.title) \($0.idea.category)".localizedCaseInsensitiveContains(normalizedQuery) }
        return IdeaDiscoveryResponse(ideas: matches, nextCursor: response.nextCursor)
    }
}
#endif
