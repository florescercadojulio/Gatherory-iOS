//
//  isaidyesTests.swift
//  isaidyesTests
//
//  Created by Julio C on 10/7/26.
//

import Testing
@testable import isaidyes

struct isaidyesTests {

    @Test("Loving an idea adds it to the shortlist")
    func loveIdea() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.love, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .shortlisted)
        #expect(workspace.decisionQueue.contains { $0.id == idea.id } == false)
    }

    @Test("Maybe saves an idea for later")
    func saveIdeaForLater() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.maybe, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .maybe)
    }

    @Test("Passing an idea archives it")
    func passIdea() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.pass, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .passed)
    }

    @Test("The latest decision can be undone")
    func undoDecision() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.love, on: idea)
        workspace.undoLastDecision()

        let restoredIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(restoredIdea.status == .new)
        #expect(workspace.decisionQueue.contains { $0.id == idea.id })
    }

    @Test("Timeline items toggle between upcoming and complete")
    func toggleTimelineItem() throws {
        let workspace = WeddingWorkspace.sample
        let item = try #require(workspace.timeline.first { $0.status == .upcoming })

        workspace.toggleTimelineItem(item)

        let completedItem = try #require(workspace.timeline.first { $0.id == item.id })
        #expect(completedItem.status == .complete)
    }

    @Test("Ideas can be archived from the list")
    func archiveIdea() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.ideas.first)

        workspace.updateIdea(idea, status: .archived)

        let archivedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(archivedIdea.status == .archived)
    }

    @Test("Guests can reserve an available registry item")
    func reserveRegistryItem() throws {
        let workspace = WeddingWorkspace.sample
        let item = try #require(workspace.registry.first { !$0.isFulfilled })

        workspace.commitToRegistryItem(item)

        let reservedItem = try #require(workspace.registry.first { $0.id == item.id })
        #expect(reservedItem.committedCount == item.committedCount + 1)
    }

    @Test("A private registry does not accept reservations")
    func privateRegistryCannotBeReserved() throws {
        let workspace = WeddingWorkspace.sample
        workspace.isRegistryShared = false
        let item = try #require(workspace.registry.first { !$0.isFulfilled })

        workspace.commitToRegistryItem(item)

        let unchangedItem = try #require(workspace.registry.first { $0.id == item.id })
        #expect(unchangedItem.committedCount == item.committedCount)
    }

}
