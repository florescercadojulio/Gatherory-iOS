import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewContentTests {
    @Test("Preview reads actual authored content without changing the catalog or choosing dates")
    func authoredContent() throws {
        let entry = try fixture()
        let original = entry.definition
        let content = try #require(BlueprintPreviewContent(entry: entry))
        #expect(content.children.map(\.key) == ["venue_visit", "rehearsal", "ceremony", "reception"])
        #expect(content.ideas().contains { $0.title == "Flowers" && $0.notes == "Collect floral styles and seasonal ideas." })
        #expect(content.guidance().map(\.key) == ["planning_priorities"])
        #expect(content.guidance().first?.audience == .planningOnly)
        #expect(content.children.first?.scheduleProposal?.dayOffset == -30)
        #expect(entry.definition == original)
    }

    @Test("Activity previews isolate their own ideas and guidance, preserving order and audience")
    func targetIsolation() throws {
        let content = try #require(BlueprintPreviewContent(entry: fixture()))
        #expect(content.guidance(for: "ceremony").map(\.key) == ["ceremony_guidance"])
        #expect(content.guidance(for: "ceremony").first?.audience == .eventParticipants)
        #expect(content.guidance(for: "reception").map(\.key) == ["reception_guidance"])
        #expect(content.guidance(for: "missing").isEmpty)
        #expect(content.ideas(for: "ceremony").isEmpty)
        #expect(content.ideas(for: "missing").isEmpty)
    }

    @Test("Child-targeted ideas retain complete notes and never leak into the main preview")
    func childIdeas() throws {
        let entry = try fixture { document in
            var modules = document["modules"] as! [[String: Any]]
            let index = modules.firstIndex { $0["type"] as? String == "ideas" }!
            var config = modules[index]["config"] as! [String: Any]
            var ideas = config["ideas"] as! [[String: Any]]
            ideas[0]["target"] = ["kind": "child", "key": "ceremony"]
            ideas[0]["notes"] = String(repeating: "Full authored notes. ", count: 100)
            config["ideas"] = ideas
            modules[index]["config"] = config
            document["modules"] = modules
        }
        let content = try #require(BlueprintPreviewContent(entry: entry))
        let childIdea = try #require(content.ideas(for: "ceremony").first)
        #expect(childIdea.notes == String(repeating: "Full authored notes. ", count: 100))
        #expect(!content.ideas().contains { $0.key == childIdea.key })
        #expect(content.ideas(for: "reception").isEmpty)
    }

    @Test("Missing required content and future schema versions do not expose a misleading usable preview")
    func invalidContent() throws {
        let missing = try fixture { $0["modules"] = [] }
        #expect(BlueprintPreviewContent(entry: missing) == nil)
        let future = try fixture { $0["schemaVersion"] = 999 }
        #expect(BlueprintPreviewContent(entry: future) == nil)
    }

    @Test("The shared event presentation gives only the main preview the event carousel")
    func eventPresentationScopes() throws {
        let entry = try fixture()
        let original = entry.definition
        let content = try #require(BlueprintPreviewContent(entry: entry))
        let main = try #require(content.event())
        #expect(main.title == entry.definition.blueprint.name)
        #expect(main.children.map(\.key) == content.children.map(\.key))
        #expect(main.ideas.map(\.key) == content.ideas().map(\.key))
        #expect(main.guidance.map(\.key) == ["planning_priorities"])
        #expect(main.scheduleProposal == nil)

        for child in content.children {
            let preview = try #require(content.event(for: child.key))
            #expect(preview.title == child.title)
            #expect(preview.category == child.category)
            #expect(preview.children.isEmpty)
            #expect(preview.summary == nil)
            #expect(preview.scheduleProposal?.dayOffset == child.scheduleProposal?.dayOffset)
            #expect(preview.scheduleProposal?.localTime == child.scheduleProposal?.localTime)
        }
        #expect(content.event(for: "missing") == nil)
        #expect(entry.definition == original)
    }

    @Test("A leaf event's shared presentation retains only its authored ideas and guidance")
    func leafEventContent() throws {
        let entry = try fixture { document in
            var modules = document["modules"] as! [[String: Any]]
            let index = modules.firstIndex { $0["type"] as? String == "ideas" }!
            var config = modules[index]["config"] as! [String: Any]
            var ideas = config["ideas"] as! [[String: Any]]
            ideas[0]["target"] = ["kind": "child", "key": "ceremony"]
            ideas[0]["notes"] = String(repeating: "Unabridged template notes. ", count: 100)
            config["ideas"] = ideas
            modules[index]["config"] = config
            document["modules"] = modules
        }
        let content = try #require(BlueprintPreviewContent(entry: entry))
        let ceremony = try #require(content.event(for: "ceremony"))
        let idea = try #require(ceremony.ideas.first)
        #expect(ceremony.children.isEmpty)
        #expect(ceremony.ideas.count == 1)
        #expect(idea.notes == String(repeating: "Unabridged template notes. ", count: 100))
        #expect(ceremony.guidance.map(\.key) == ["ceremony_guidance"])
        #expect(ceremony.guidance.first?.audience == .eventParticipants)
        #expect(content.event(for: "reception")?.ideas.isEmpty == true)
        #expect(content.event()?.ideas.contains { $0.key == idea.key } == false)
    }

    private func fixture(edit: ((inout [String: Any]) -> Void)? = nil) throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintPreviewFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var entries = try #require(root["entries"] as? [[String: Any]])
        var document = try #require(entries[0]["definition"] as? [String: Any])
        edit?(&document)
        entries[0]["definition"] = document
        root["entries"] = entries
        return try JSONDecoder().decode(BlueprintCatalogResponse.self, from: JSONSerialization.data(withJSONObject: root)).entries[0]
    }
}

private final class BlueprintPreviewFixtureBundle: NSObject {}
