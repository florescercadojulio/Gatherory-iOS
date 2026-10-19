import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintDecideContextTests {
    @Test("Context title follows the current idea target and falls back to the selected scope")
    func contextTitleMapping() throws {
        let content = try #require(BlueprintPreviewContent(entry: fixture()))
        let child = try #require(content.children.first)

        #expect(BlueprintDecideContext.title(content: content, scope: .all, ideaTarget: .main) == content.title)
        #expect(BlueprintDecideContext.title(content: content, scope: .all, ideaTarget: .child(key: child.key)) == child.title)
        #expect(BlueprintDecideContext.title(content: content, scope: .all, ideaTarget: nil) == BlueprintCopy.allIdeas)
        #expect(BlueprintDecideContext.title(content: content, scope: .main, ideaTarget: nil) == content.title)
        #expect(BlueprintDecideContext.title(content: content, scope: .main, ideaTarget: .child(key: "unknown")) == content.title)
    }

    private func fixture() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintDecideContextFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: data).entries.first)
    }
}

private final class BlueprintDecideContextFixtureBundle: NSObject {}
