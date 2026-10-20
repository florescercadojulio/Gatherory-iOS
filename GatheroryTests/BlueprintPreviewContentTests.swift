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

    @Test("Preview event IDs distinguish the main event from a child named main")
    func eventIdentifiersAndScopedIdeas() throws {
        let entry = try fixture { document in
            var modules = document["modules"] as! [[String: Any]]
            let treeIndex = modules.firstIndex { $0["type"] as? String == "experience_tree" }!
            var treeConfig = modules[treeIndex]["config"] as! [String: Any]
            var children = treeConfig["children"] as! [[String: Any]]
            children[0]["key"] = "main"
            treeConfig["children"] = children
            modules[treeIndex]["config"] = treeConfig

            let ideasIndex = modules.firstIndex { $0["type"] as? String == "ideas" }!
            var ideasConfig = modules[ideasIndex]["config"] as! [String: Any]
            var ideas = ideasConfig["ideas"] as! [[String: Any]]
            ideas[1]["target"] = ["kind": "child", "key": "main"]
            ideas[2]["target"] = ["kind": "child", "key": "ceremony"]
            ideas[3]["target"] = ["kind": "child", "key": "main"]
            ideas[4]["target"] = ["kind": "child", "key": "reception"]
            ideasConfig["ideas"] = ideas
            modules[ideasIndex]["config"] = ideasConfig
            document["modules"] = modules
        }
        let original = entry.definition
        let content = try #require(BlueprintPreviewContent(entry: entry))

        #expect(content.eventIDs == [
            .main, .child("main"), .child("rehearsal"), .child("ceremony"), .child("reception")
        ])
        #expect(Set(content.eventIDs).count == content.eventIDs.count)

        #expect(content.ideas(in: .all).map(\.key) == ["venue", "attire", "food", "flowers", "photography"])
        #expect(content.ideas(in: .main).map(\.key) == ["venue"])
        #expect(content.ideas(in: .child("main")).map(\.key) == ["attire", "flowers"])
        #expect(content.ideas(in: .child("ceremony")).map(\.key) == ["food"])
        #expect(content.ideas(in: .child("missing")).isEmpty)

        let rootEvent = try #require(content.event(for: .main))
        let childNamedMain = try #require(content.event(for: .child("main")))
        #expect(rootEvent.title == content.title)
        #expect(rootEvent.ideas.map(\.key) == ["venue"])
        #expect(childNamedMain.title == "Venue visit")
        #expect(childNamedMain.ideas.map(\.key) == ["attire", "flowers"])
        #expect(content.event(for: .child("missing")) == nil)

        #expect(content.ideas.map(\.key) == ["venue", "attire", "food", "flowers", "photography"])
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

    @Test("Home browsing cannot narrow Decide and every main/child idea is visited once")
    func homeDoesNotFilterDecide() throws {
        let content = try mixedTargetContent()
        var navigation = BlueprintPreviewNavigation()
        var responses: [String: DecisionChoice] = [:]
        var visited: [String] = []
        for event in content.eventIDs {
            navigation.homeEvent = event
            #expect(navigation.decisionScope == .all)
        }
        while let idea = BlueprintDecisionQueue.nextIdea(
            in: content.ideas(in: navigation.decisionScope), responses: responses,
            filter: .unanswered, reviewedKeys: []) {
            visited.append(idea.key)
            responses[idea.key] = .love
            navigation.homeEvent = content.homeContent(responses: responses).eventIDs.last ?? .main
            #expect(visited.count <= content.ideas.count)
            if visited.count > content.ideas.count { break }
        }
        #expect(visited == content.ideas.map(\.key))
        #expect(Set(visited).count == content.ideas.count)
        // Explicit event filters still work and are not changed by Home.
        navigation.decisionScope = .child("ceremony")
        navigation.homeEvent = .main
        #expect(navigation.decisionScope == .child("ceremony"))
        #expect(content.ideas(in: navigation.decisionScope).map(\.key) == ["venue", "attire"])
    }

    @Test("Home starts at the main event and Love reveals only its target activity")
    func decisionDrivenHome() throws {
        let content = try mixedTargetContent()
        let initial = content.homeContent(responses: [:])
        #expect(initial.eventIDs == [.main])
        #expect(initial.ideas.isEmpty)
        #expect(initial.guidance().map(\.key) == content.guidance().map(\.key))
        let home = content.homeContent(responses: ["venue": .love, "attire": .maybe,
                                                  "food": .pass, "flowers": .love,
                                                  "unknown": .love])
        #expect(home.eventIDs == [.main, .child("ceremony")])
        #expect(home.ideas().map(\.key) == ["flowers"])
        #expect(home.ideas(for: "ceremony").map(\.key) == ["venue"])
        #expect(home.event(for: "reception") == nil)
        #expect(home.event()?.children.map(\.key) == ["ceremony"])
        // The full catalog remains available to Ideas and Decide.
        #expect(content.ideas.count == 5)
        #expect(content.children.count == 4)
    }

    @Test("Changing the last Love removes its activity; other Loves keep it visible in authored order")
    func revisingHomeDecisions() throws {
        let content = try mixedTargetContent()
        let both = content.homeContent(responses: ["food": .love, "venue": .love])
        #expect(both.eventIDs == [.main, .child("ceremony"), .child("reception")])
        let one = content.homeContent(responses: ["venue": .pass, "attire": .love, "food": .maybe])
        #expect(one.eventIDs == [.main, .child("ceremony")])
        let none = content.homeContent(responses: ["venue": .pass, "attire": .maybe, "food": .pass])
        #expect(none.eventIDs == [.main])
    }

    @Test("A child with an authored to-do remains available in Home even without loved ideas")
    func todoOnlyChildRemainsInHome() throws {
        let entry = try fixture { document in
            var modules = document["modules"] as! [[String: Any]]
            modules.append([
                "key": "starter_todos", "type": "todos", "version": 1, "required": false,
                "config": ["todos": [[
                    "key": "book-transport", "title": "Book transport", "target": ["kind": "child", "key": "ceremony"]
                ]]]
            ])
            document["modules"] = modules
        }
        let content = try #require(BlueprintPreviewContent(entry: entry))
        #expect(content.event(for: "ceremony")?.todos.map(\.key) == ["book-transport"])

        let home = content.homeContent(responses: [:])
        #expect(home.eventIDs == [.main, .child("ceremony")])
        #expect(home.event(for: "ceremony")?.todos.map(\.key) == ["book-transport"])
        #expect(home.ideas().isEmpty)
    }

    private func mixedTargetContent() throws -> BlueprintPreviewContent {
        let entry = try fixture { document in
            var modules = document["modules"] as! [[String: Any]]
            let index = modules.firstIndex { $0["type"] as? String == "ideas" }!
            var config = modules[index]["config"] as! [String: Any]
            var ideas = config["ideas"] as! [[String: Any]]
            ideas[0]["target"] = ["kind": "child", "key": "ceremony"]
            ideas[1]["target"] = ["kind": "child", "key": "ceremony"]
            ideas[2]["target"] = ["kind": "child", "key": "reception"]
            ideas[4]["target"] = ["kind": "child", "key": "rehearsal"]
            config["ideas"] = ideas
            modules[index]["config"] = config
            document["modules"] = modules
        }
        return try #require(BlueprintPreviewContent(entry: entry))
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
