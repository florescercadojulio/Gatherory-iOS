//
//  GatheroryTests.swift
//  GatheroryTests
//
//  Created by Julio C on 10/7/26.
//

import Foundation
import Testing
@testable import Gatherory

struct GatheroryTests {

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
        let item = try #require(workspace.timeline.first { $0.completionStatus == .upcoming })

        workspace.toggleTimelineItem(item)

        let completedItem = try #require(workspace.timeline.first { $0.id == item.id })
        #expect(completedItem.completionStatus == .complete)
    }

    @Test("The event tree is limited to a root and direct subevents")
    func eventTreeHasOnlyTwoLevels() {
        let workspace = WeddingWorkspace.sample
        let tree = workspace.eventTree

        #expect(tree.id == workspace.mainEventID)
        #expect(tree.parentID == nil)
        #expect(tree.canHaveChildren)
        #expect(tree.children.count == workspace.childEvents.count)
        #expect(tree.children.allSatisfy { child in
            child.parentID == workspace.mainEventID
                && !child.canHaveChildren
                && child.children.isEmpty
        })
    }

    @Test("A subevent cannot become the parent of another event")
    func subeventsCannotHaveChildren() throws {
        let workspace = WeddingWorkspace.sample
        let proposedParent = try #require(workspace.timeline.first)
        let originalCount = workspace.timeline.count
        let nestedEvent = TimelineItem(
            title: "Nested event",
            category: .other,
            scheduledAt: .now,
            eventLocation: nil,
            participantIDs: [],
            parentEventID: proposedParent.id
        )

        workspace.addTimelineItem(nestedEvent)

        #expect(workspace.timeline.count == originalCount)
    }

    @Test("A new subevent starts with a snapshot of the main event participants")
    func newSubeventCopiesMainEventParticipants() throws {
        let workspace = WeddingWorkspace.sample
        let newEvent = TimelineItem(
            title: "Welcome drinks",
            category: .reception,
            scheduledAt: .now,
            eventLocation: nil,
            participantIDs: [],
            parentEventID: workspace.mainEventID
        )

        workspace.addTimelineItem(newEvent)

        let storedEvent = try #require(workspace.timeline.first { $0.id == newEvent.id })
        #expect(Set(storedEvent.participantIDs) == Set(workspace.mainEventParticipantIDs))
    }

    @Test("Ideas and decisions follow the selected event context")
    func ideasFollowSelectedEventContext() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)

        workspace.selectEventContext(.subevent(child.id))
        #expect(workspace.contextualIdeas.isEmpty)
        #expect(workspace.decisionQueue.isEmpty)

        workspace.addIdea(
            WeddingIdea(
                title: "Welcome table for this event",
                note: "Keep it specific to the selected subevent.",
                category: .decor,
                submittedBy: "Alex"
            )
        )

        let scopedIdea = try #require(workspace.contextualIdeas.first)
        #expect(scopedIdea.eventID == child.id)
        #expect(workspace.decisionQueue.first?.id == scopedIdea.id)

        workspace.selectEventContext(.main)
        #expect(workspace.contextualIdeas.contains { $0.id == scopedIdea.id } == false)
    }

    @Test("Removing the active subevent returns planning to the main event")
    func deletingActiveSubeventRestoresMainContext() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)

        workspace.selectEventContext(.subevent(child.id))
        workspace.deleteTimelineItem(child)

        #expect(workspace.selectedEventReference == .main)
    }

    @Test("Event contexts are ordered chronologically")
    func eventContextsAreChronological() {
        let workspace = WeddingWorkspace.sample
        let dates = workspace.availableEventContexts.map(workspace.eventDate(for:))

        #expect(dates == dates.sorted())
    }

    @Test("Notes are scoped to the selected event")
    func notesFollowSelectedEventContext() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)

        workspace.selectEventContext(.subevent(child.id))
        workspace.sendNote("Meet at the side entrance.")

        let note = try #require(workspace.contextualNotes.first)
        #expect(note.eventID == child.id)

        workspace.selectEventContext(.main)
        #expect(workspace.contextualNotes.contains { $0.id == note.id } == false)
    }

    @Test("Timeline events can be deleted from their details")
    func deleteTimelineItem() throws {
        let workspace = WeddingWorkspace.sample
        let item = try #require(workspace.timeline.first)

        workspace.deleteTimelineItem(item)

        #expect(workspace.timeline.contains { $0.id == item.id } == false)
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

    @Test("A guest invitation preserves role and contact details")
    func inviteCollaborator() throws {
        let workspace = WeddingWorkspace.sample

        workspace.inviteParticipant(
            name: "Taylor Reed",
            email: "taylor@example.com",
            initials: "TR",
            role: .guest
        )

        let collaborator = try #require(workspace.members.first { $0.name == "Taylor Reed" })
        #expect(collaborator.email == "taylor@example.com")
        #expect(collaborator.participantRole == .guest)
        #expect(collaborator.planningPermission == .viewOnly)
        #expect(collaborator.invitationStatus == .invited)
    }

    @Test("The same collaborator is not invited twice")
    func collaboratorInvitationsAreUnique() {
        let workspace = WeddingWorkspace.sample
        let originalCount = workspace.members.count

        workspace.inviteParticipant(
            name: "Sarah",
            initials: "S",
            role: .collaborator
        )

        #expect(workspace.members.count == originalCount)
    }

    @Test("Guests are excluded from timeline assignments")
    func timelineAssignmentsOnlyIncludePlanners() {
        let workspace = WeddingWorkspace.sample

        #expect(workspace.planningMembers.allSatisfy { $0.participantRole != .guest })
        #expect(workspace.members.contains { $0.participantRole == .guest })
    }

    @Test("A custom event location name remains separate from its address")
    func eventLocationFormatting() {
        let location = EventLocation(
            address: "5070 East North Avenue, Kalamazoo, Michigan 49048",
            shortAddress: "5070 E North Ave",
            placeName: "5070 E North Ave",
            locationName: "Jordan’s Parents’ House",
            addressLine2: "Garden entrance"
        )

        #expect(location.title == "Jordan’s Parents’ House")
        #expect(location.detail == "Garden entrance, 5070 East North Avenue, Kalamazoo, Michigan 49048")
    }

    @Test("Legacy timeline locations migrate into the structured location model")
    func legacyTimelineLocation() throws {
        let item = TimelineItem(
            title: "Venue visit",
            category: .venue,
            scheduledAt: .now,
            location: "Willow & Stone Estate",
            participantIDs: []
        )

        let location = try #require(item.eventLocation)
        #expect(location.address == "Willow & Stone Estate")
        #expect(item.location == "Willow & Stone Estate")
    }

    @Test("Timeline events can be created without a location")
    func optionalTimelineLocation() {
        let item = TimelineItem(
            title: "Choose readings",
            category: .ceremony,
            scheduledAt: .now,
            eventLocation: nil,
            participantIDs: []
        )

        #expect(item.eventLocation == nil)
        #expect(item.location == nil)
    }

    @Test("Timeline events preserve their full schedule")
    func timelineScheduleMetadata() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Detroit"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startsAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 18))
        )
        let endsAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 22))
        )

        let item = TimelineItem(
            title: "Rehearsal dinner",
            category: .rehearsal,
            scheduledAt: startsAt,
            eventLocation: nil,
            endsAt: endsAt,
            isAllDay: false,
            timeZoneIdentifier: timeZone.identifier,
            participantIDs: []
        )

        #expect(item.scheduledAt == startsAt)
        #expect(item.endsAt == endsAt)
        #expect(item.isAllDay == false)
        #expect(item.timeZoneIdentifier == "America/Detroit")
    }

    @Test("Weather forecasts match the event calendar day")
    func eventWeatherDateMatching() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let eventDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 18)))
        let matchingDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 6)))
        let otherDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 6)))
        let matchingForecast = EventWeatherForecast(
            date: matchingDate,
            conditionDescription: "Partly Cloudy",
            symbolName: "cloud.sun.fill",
            highTemperature: Measurement(value: 22, unit: .celsius),
            lowTemperature: Measurement(value: 12, unit: .celsius),
            precipitationChance: 0.2
        )
        let otherForecast = EventWeatherForecast(
            date: otherDate,
            conditionDescription: "Rain",
            symbolName: "cloud.rain.fill",
            highTemperature: Measurement(value: 18, unit: .celsius),
            lowTemperature: Measurement(value: 10, unit: .celsius),
            precipitationChance: 0.7
        )

        let result = EventWeatherModel.forecast(
            on: eventDate,
            from: [otherForecast, matchingForecast],
            calendar: calendar
        )

        #expect(result == matchingForecast)
    }

}
