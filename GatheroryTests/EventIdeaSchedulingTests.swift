import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventIdeaSchedulingTests {
    @Test("Legacy event defaults can be scheduled while mismatched configuration cannot")
    func legacyAndMismatchedConfiguration() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let idea = PlanningIdea(
            title: "Legacy proposal", note: "", category: .event,
            submittedBy: "Host", status: .new
        )
        let workspace = makeWorkspace(members: [host], ideas: [idea])
        let proposal = try storedIdea(idea.id, in: workspace)

        #expect(proposal.eventConfiguration != nil)
        #expect(workspace.canScheduleEventIdea(proposal))
        #expect(workspace.makeScheduleRequest(for: proposal) != nil)
        #expect(workspace.timeline.isEmpty)

        var malformed = idea
        malformed.configuration = .standard
        let malformedWorkspace = makeWorkspace(members: [host], ideas: [malformed])
        let malformedProposal = try storedIdea(malformed.id, in: malformedWorkspace)
        #expect(!malformedWorkspace.canScheduleEventIdea(malformedProposal))
        #expect(malformedWorkspace.makeScheduleRequest(for: malformedProposal) == nil)
        #expect(malformedWorkspace.timeline.isEmpty)
    }

    @Test("Scheduling an undated idea publishes one dated Home child and preserves proposal content")
    func confirmsUndatedProposal() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let ideaID = UUID()
        let image = Data([0x01, 0x02, 0x03])
        let idea = makeIdea(id: ideaID, image: image)
        let response = IdeaResponse(ideaID: ideaID, userID: "host-account", choice: .maybe)
        let workspace = makeWorkspace(members: [host], ideas: [idea], ideaResponses: [response])
        let proposal = try storedIdea(ideaID, in: workspace)
        let request = try #require(workspace.makeScheduleRequest(for: proposal))
        let scheduledAt = Date.now.addingTimeInterval(86_400)
        let configuration = datedConfiguration(from: proposal, date: scheduledAt)

        let childID = try #require(workspace.confirmScheduleEventIdea(request, configuration: configuration))
        let child = try #require(workspace.timeline.first { $0.id == childID })
        let savedIdea = try #require(workspace.ideas.first { $0.id == ideaID })

        #expect(savedIdea.status == .chosen)
        #expect(savedIdea.eventConfiguration == configuration)
        #expect(child.linkedIdeaID == ideaID)
        #expect(child.parentEventID == workspace.mainEventID)
        #expect(child.title == idea.title)
        #expect(child.eventDescription == idea.note)
        #expect(child.scheduledAt == scheduledAt)
        #expect(child.imageData == image)
        #expect(child.mediaAssetID == idea.mediaAssetID)
        #expect(child.participantIDs == workspace.mainEventParticipantIDs)
        #expect(workspace.ideaResponses == [response])
        #expect(workspace.timeline.filter { $0.linkedIdeaID == ideaID }.count == 1)
    }

    @Test("Dated legacy proposal is reused and a retried confirmation returns the same child")
    func reusesDatedLegacyChild() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let date = Date.now.addingTimeInterval(86_400)
        let idea = makeIdea(id: UUID(), status: .chosen, date: date)
        let existing = TimelineItem(
            title: "Existing child", category: .other, scheduledAt: date,
            location: "", participantIDs: [host.id], parentEventID: nil,
            status: .draft, response: .notSure, linkedIdeaID: idea.id,
            imageData: idea.imageData, eventDescription: "Existing description",
            dressCode: "Existing attire", budgetCap: 125
        )
        let workspace = makeWorkspace(members: [host], ideas: [idea], timeline: [existing])
        let proposal = try storedIdea(idea.id, in: workspace)
        let request = try #require(workspace.makeScheduleRequest(for: proposal))

        let firstID = try #require(workspace.confirmScheduleEventIdea(
            request, configuration: proposal.eventConfiguration!
        ))
        let retryID = try #require(workspace.confirmScheduleEventIdea(
            request, configuration: proposal.eventConfiguration!
        ))
        let child = try #require(workspace.timeline.first { $0.id == existing.id })

        #expect(firstID == existing.id)
        #expect(retryID == existing.id)
        #expect(workspace.timeline.filter { $0.linkedIdeaID == idea.id }.count == 1)
        #expect(child.response == .notSure)
        #expect(child.budgetCap == 125)
        #expect(child.title == "Existing child")
        #expect(child.eventDescription == "Existing description")
        #expect(child.dressCode == "Existing attire")
    }

    @Test("A changed schedule request does not rebuild or overwrite an existing Home child")
    func changedRequestPreservesExistingChild() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let contributor = WorkspaceMember(name: "Member", participantRole: .collaborator, initials: "M")
        let date = Date.now.addingTimeInterval(86_400)
        let idea = makeIdea(id: UUID(), status: .chosen, date: date)
        let linkedEvent = TimelineItem(
            title: "Home edited title", category: .other, scheduledAt: date,
            location: "Home edited location", endsAt: date.addingTimeInterval(3_600),
            isAllDay: false, timeZoneIdentifier: "America/Detroit",
            participantIDs: [contributor.id], parentEventID: nil,
            status: .approved, completionStatus: .complete, response: .going,
            linkedIdeaID: idea.id, imageData: Data([0x77]), mediaAssetID: UUID(),
            eventDescription: "Home edited details", dressCode: "Home attire", budgetCap: 90
        )
        let workspace = makeWorkspace(
            members: [host, contributor], ideas: [idea], timeline: [linkedEvent]
        )
        let proposal = try storedIdea(idea.id, in: workspace)
        let request = try #require(workspace.makeScheduleRequest(for: proposal))
        let originalChild = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        let originalIdea = proposal
        var changedConfiguration = datedConfiguration(from: proposal, date: date.addingTimeInterval(86_400))
        changedConfiguration.location = EventLocation(address: "Changed proposal location")

        #expect(workspace.confirmScheduleEventIdea(request, configuration: changedConfiguration) == nil)
        #expect(workspace.timeline == [originalChild])
        #expect(workspace.ideas.first { $0.id == idea.id } == originalIdea)
        #expect(originalChild.participantIDs == [contributor.id])
        #expect(originalChild.imageData == Data([0x77]))
        #expect(originalChild.mediaAssetID == linkedEvent.mediaAssetID)
        #expect(originalChild.response == .going)
        #expect(originalChild.budgetCap == 90)
        #expect(originalChild.eventDescription == "Home edited details")
    }

    @Test("Schedule confirmation is denied to contributors and guests without changing votes or ideas")
    func permissionBoundary() throws {
        for (role, permission) in [
            (WorkspaceRole.collaborator, PlanningPermission.contribute),
            (.collaborator, .viewOnly),
            (.guest, .viewOnly),
            (.host, .viewOnly)
        ] {
            let actor = WorkspaceMember(
                name: "Actor", participantRole: role, initials: "A",
                planningPermission: permission
            )
            let idea = makeIdea(id: UUID())
            let response = IdeaResponse(ideaID: idea.id, userID: "actor", choice: .love)
            let workspace = makeWorkspace(members: [actor], ideas: [idea], ideaResponses: [response])
            let proposal = try storedIdea(idea.id, in: workspace)

            #expect(!workspace.canScheduleEventIdea(proposal))
            #expect(workspace.makeScheduleRequest(for: proposal) == nil)
            #expect(workspace.confirmScheduleEventIdea(
                EventIdeaScheduleRequest(
                    rootEventID: workspace.mainEventID,
                    ideaSnapshot: proposal,
                    viewerGeneration: 0,
                    viewerMemberID: actor.id,
                    viewerMemberSnapshot: actor
                ),
                configuration: datedConfiguration(from: proposal, date: .now)
            ) == nil)
            #expect(workspace.ideas == [proposal])
            #expect(workspace.ideaResponses == [response])
            #expect(workspace.timeline.isEmpty)
        }

        let contributor = WorkspaceMember(
            name: "Contributor", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let suggestedIdea = makeIdea(id: UUID())
        let suggestionWorkspace = makeWorkspace(members: [contributor], ideas: [suggestedIdea])
        let suggestionProposal = try storedIdea(suggestedIdea.id, in: suggestionWorkspace)
        var suggestion = suggestionProposal
        suggestion.configuration = .event(datedConfiguration(from: suggestionProposal, date: .now))
        suggestionWorkspace.updateIdea(suggestion)
        #expect(suggestionWorkspace.ideas.first?.eventConfiguration?.proposedDate != nil)
        #expect(suggestionWorkspace.ideas.first?.status == .new)
        #expect(suggestionWorkspace.timeline.isEmpty)
    }

    @Test("Confirmation rejects stale source, removed viewer, deleted root, and invalid undated submission")
    func staleAndInvalidBoundaries() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")

        let changedIdea = makeIdea(id: UUID())
        let changedWorkspace = makeWorkspace(members: [host], ideas: [changedIdea])
        let changedProposal = try storedIdea(changedIdea.id, in: changedWorkspace)
        let changedRequest = try #require(changedWorkspace.makeScheduleRequest(for: changedProposal))
        var edited = changedProposal
        edited.title = "Changed while sheet was open"
        changedWorkspace.updateIdea(edited)
        #expect(changedWorkspace.confirmScheduleEventIdea(
            changedRequest, configuration: datedConfiguration(from: changedProposal, date: .now)
        ) == nil)
        #expect(changedWorkspace.timeline.isEmpty)

        let removedIdea = makeIdea(id: UUID())
        let removedWorkspace = makeWorkspace(members: [host], ideas: [removedIdea])
        let removedProposal = try storedIdea(removedIdea.id, in: removedWorkspace)
        let removedRequest = try #require(removedWorkspace.makeScheduleRequest(for: removedProposal))
        removedWorkspace.members.removeAll { $0.id == host.id }
        #expect(removedWorkspace.confirmScheduleEventIdea(
            removedRequest, configuration: datedConfiguration(from: removedProposal, date: .now)
        ) == nil)
        #expect(removedWorkspace.ideas == [removedProposal])

        let retiredIdea = makeIdea(id: UUID())
        let retiredWorkspace = makeWorkspace(members: [host], ideas: [retiredIdea])
        let retiredProposal = try storedIdea(retiredIdea.id, in: retiredWorkspace)
        let retiredRequest = try #require(retiredWorkspace.makeScheduleRequest(for: retiredProposal))
        retiredWorkspace.updateIdea(retiredProposal, status: .archived)
        #expect(retiredWorkspace.confirmScheduleEventIdea(
            retiredRequest, configuration: datedConfiguration(from: retiredProposal, date: .now)
        ) == nil)
        #expect(retiredWorkspace.ideas.first?.status == .archived)
        #expect(retiredWorkspace.timeline.isEmpty)

        let actor = WorkspaceMember(
            userID: "manager", name: "Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        )
        var identityIdea = makeIdea(id: UUID())
        var identityConfiguration = identityIdea.eventConfiguration!
        identityConfiguration.audience = .inherited
        identityIdea.configuration = .event(identityConfiguration)
        let accountWorkspace = makeWorkspace(members: [actor, host], ideas: [identityIdea])
        let account = UserAccount(
            id: "manager", email: "manager@example.com", displayName: "Manager",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        accountWorkspace.configureViewer(account)
        let accountIdea = try #require(accountWorkspace.ideas.first)
        let accountRequest = try #require(accountWorkspace.makeScheduleRequest(for: accountIdea))
        accountWorkspace.configureViewer(account)
        #expect(accountWorkspace.confirmScheduleEventIdea(
            accountRequest, configuration: datedConfiguration(from: accountIdea, date: .now)
        ) != nil)

        let abaWorkspace = makeWorkspace(members: [actor, host], ideas: [makeIdea(id: UUID())])
        abaWorkspace.configureViewer(account)
        let abaIdea = try #require(abaWorkspace.ideas.first)
        let abaRequest = try #require(abaWorkspace.makeScheduleRequest(for: abaIdea))
        abaWorkspace.configureViewer(nil)
        abaWorkspace.configureViewer(account)
        #expect(abaWorkspace.confirmScheduleEventIdea(
            abaRequest, configuration: datedConfiguration(from: abaIdea, date: .now)
        ) == nil)
        #expect(abaWorkspace.timeline.isEmpty)

        let permissionWorkspace = makeWorkspace(members: [actor, host], ideas: [makeIdea(id: UUID())])
        permissionWorkspace.configureViewer(account)
        let permissionIdea = try #require(permissionWorkspace.ideas.first)
        let permissionRequest = try #require(permissionWorkspace.makeScheduleRequest(for: permissionIdea))
        #expect(permissionWorkspace.updateParticipant(
            actor.id, role: .collaborator, planningPermission: .contribute, in: .main
        ))
        #expect(permissionWorkspace.confirmScheduleEventIdea(
            permissionRequest, configuration: datedConfiguration(from: permissionIdea, date: .now)
        ) == nil)
        #expect(permissionWorkspace.timeline.isEmpty)

        let deletedIdea = makeIdea(id: UUID())
        let deletedWorkspace = makeWorkspace(members: [host], ideas: [deletedIdea])
        let deletedProposal = try storedIdea(deletedIdea.id, in: deletedWorkspace)
        let deletedRequest = try #require(deletedWorkspace.makeScheduleRequest(for: deletedProposal))
        deletedWorkspace.isMainEventDeleted = true
        #expect(deletedWorkspace.confirmScheduleEventIdea(
            deletedRequest, configuration: datedConfiguration(from: deletedProposal, date: .now)
        ) == nil)
        #expect(deletedWorkspace.timeline.isEmpty)

        let undatedIdea = makeIdea(id: UUID())
        let undatedWorkspace = makeWorkspace(members: [host], ideas: [undatedIdea])
        let undatedProposal = try storedIdea(undatedIdea.id, in: undatedWorkspace)
        let undatedRequest = try #require(undatedWorkspace.makeScheduleRequest(for: undatedProposal))
        var undated = datedConfiguration(from: undatedProposal, date: nil)
        undated.proposedDate = nil
        #expect(undatedWorkspace.confirmScheduleEventIdea(undatedRequest, configuration: undated) == nil)
        #expect(undatedWorkspace.ideas == [undatedProposal])
        #expect(undatedWorkspace.timeline.isEmpty)

        let invalidIdea = makeIdea(id: UUID())
        let invalidWorkspace = makeWorkspace(members: [host], ideas: [invalidIdea])
        let invalidProposal = try storedIdea(invalidIdea.id, in: invalidWorkspace)
        let invalidRequest = try #require(invalidWorkspace.makeScheduleRequest(for: invalidProposal))
        var invalid = datedConfiguration(from: invalidProposal, date: .now)
        invalid.proposedEndDate = invalid.proposedDate?.addingTimeInterval(-60)
        #expect(invalidWorkspace.confirmScheduleEventIdea(invalidRequest, configuration: invalid) == nil)
        #expect(invalidWorkspace.ideas == [invalidProposal])
        #expect(invalidWorkspace.timeline.isEmpty)

        var changedSettingsIdea = invalidProposal
        var changedConfiguration = invalidProposal.eventConfiguration!
        changedConfiguration.audience = .inherited
        changedSettingsIdea.configuration = .event(changedConfiguration)
        #expect(invalidWorkspace.confirmScheduleEventIdea(
            invalidRequest,
            configuration: datedConfiguration(from: changedSettingsIdea, date: .now)
        ) == nil)
        #expect(invalidWorkspace.ideas == [invalidProposal])
        #expect(invalidWorkspace.timeline.isEmpty)

        let allDayIdea = makeIdea(id: UUID())
        let allDayWorkspace = makeWorkspace(members: [host], ideas: [allDayIdea])
        let allDayProposal = try storedIdea(allDayIdea.id, in: allDayWorkspace)
        let allDayRequest = try #require(allDayWorkspace.makeScheduleRequest(for: allDayProposal))
        var oneDay = datedConfiguration(from: allDayProposal, date: Date.now)
        oneDay.isAllDay = true
        oneDay.proposedEndDate = oneDay.proposedDate
        let allDayEventID = try #require(allDayWorkspace.confirmScheduleEventIdea(
            allDayRequest, configuration: oneDay
        ))
        #expect(allDayWorkspace.timeline.first { $0.id == allDayEventID }?.isAllDay == true)
        #expect(allDayWorkspace.timeline.first { $0.id == allDayEventID }?.endsAt == oneDay.proposedDate)
    }

    @Test("Opening and cancelling the Schedule flow leaves a pending idea unchanged")
    func cancellationDoesNotMutate() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let idea = makeIdea(id: UUID())
        let workspace = makeWorkspace(members: [host], ideas: [idea])
        let proposal = try storedIdea(idea.id, in: workspace)
        _ = try #require(workspace.makeScheduleRequest(for: proposal))

        #expect(workspace.ideas == [proposal])
        #expect(workspace.ideaResponses.isEmpty)
        #expect(workspace.timeline.isEmpty)
    }

    @Test("A retry after a post-commit proposal edit is rejected as stale")
    func retryRejectsEditedCommit() throws {
        let host = WorkspaceMember(name: "Host", participantRole: .host, initials: "H")
        let idea = makeIdea(id: UUID())
        let workspace = makeWorkspace(members: [host], ideas: [idea])
        let proposal = try storedIdea(idea.id, in: workspace)
        let request = try #require(workspace.makeScheduleRequest(for: proposal))
        let configuration = datedConfiguration(from: proposal, date: .now)
        let eventID = try #require(workspace.confirmScheduleEventIdea(request, configuration: configuration))

        var edited = try #require(workspace.ideas.first)
        edited.title = "Edited after scheduling"
        workspace.updateIdea(edited)
        #expect(workspace.confirmScheduleEventIdea(request, configuration: configuration) == nil)
        #expect(workspace.timeline.filter { $0.linkedIdeaID == idea.id }.map(\.id) == [eventID])
        #expect(workspace.ideas.first?.title == "Edited after scheduling")
    }

    @Test("Contributors cannot revoke or unschedule a published idea but can edit unrelated proposal details")
    func contributorCannotRemoveScheduledEvent() throws {
        let host = WorkspaceMember(
            userID: "host", name: "Host", participantRole: .host,
            initials: "H", planningPermission: .manage
        )
        let contributor = WorkspaceMember(
            userID: "contributor", name: "Contributor", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let idea = makeIdea(id: UUID())
        let workspace = makeWorkspace(members: [host, contributor], ideas: [idea])
        let hostAccount = UserAccount(
            id: "host", email: "host@example.com", displayName: "Host",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        let contributorAccount = UserAccount(
            id: "contributor", email: "contributor@example.com", displayName: "Contributor",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        workspace.configureViewer(hostAccount)
        let proposal = try storedIdea(idea.id, in: workspace)
        let request = try #require(workspace.makeScheduleRequest(for: proposal))
        let configuration = datedConfiguration(from: proposal, date: .now.addingTimeInterval(86_400))
        let eventID = try #require(workspace.confirmScheduleEventIdea(request, configuration: configuration))

        workspace.configureViewer(contributorAccount)
        workspace.updateIdea(try #require(workspace.ideas.first), status: .archived)
        var unscheduled = try #require(workspace.ideas.first)
        var unscheduledConfiguration = unscheduled.eventConfiguration!
        unscheduledConfiguration.proposedDate = nil
        unscheduledConfiguration.proposedEndDate = nil
        unscheduled.configuration = .event(unscheduledConfiguration)
        workspace.updateIdea(unscheduled)

        #expect(workspace.ideas.first?.status == .chosen)
        #expect(workspace.ideas.first?.eventConfiguration?.proposedDate == configuration.proposedDate)
        #expect(workspace.timeline.contains { $0.id == eventID && $0.linkedIdeaID == idea.id })

        var unrelatedEdit = try #require(workspace.ideas.first)
        var unrelatedConfiguration = unrelatedEdit.eventConfiguration!
        unrelatedConfiguration.attireGuidance = "Smart casual"
        unrelatedEdit.configuration = .event(unrelatedConfiguration)
        workspace.updateIdea(unrelatedEdit)
        #expect(workspace.ideas.first?.eventConfiguration?.attireGuidance == "Smart casual")
        #expect(workspace.timeline.contains { $0.id == eventID })
    }

    private func makeWorkspace(
        members: [WorkspaceMember],
        ideas: [PlanningIdea],
        timeline: [TimelineItem] = [],
        ideaResponses: [IdeaResponse] = []
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            title: "Gathering", mainEventStartsAt: .now,
            venueName: "", location: "", planningMode: .openToIdeas,
            members: members, ideas: ideas, timeline: timeline,
            workspaceBudgetCap: 250, ideaResponses: ideaResponses, registry: []
        )
    }

    private func storedIdea(_ id: UUID, in workspace: PlanningWorkspace) throws -> PlanningIdea {
        try #require(workspace.ideas.first { $0.id == id })
    }

    private func makeIdea(
        id: UUID,
        status: IdeaStatus = .new,
        date: Date? = nil,
        image: Data? = Data([0xAB])
    ) -> PlanningIdea {
        PlanningIdea(
            id: id, title: "Dinner with friends", note: "Bring a warm layer",
            category: .event, submittedBy: "Guest", status: status,
            imageData: image, mediaAssetID: UUID(),
            configuration: .event(EventIdeaConfiguration(
                category: .reception, purpose: .planning,
                audience: .hostsOnly, requiresBudget: true,
                proposedBudget: 250, proposedDate: date,
                proposedEndDate: date?.addingTimeInterval(7_200),
                isAllDay: false, timeZoneIdentifier: "America/Detroit",
                location: EventLocation(address: "123 Main Street"),
                attireStyle: .formal, attireGuidance: "Garden formal"
            ))
        )
    }

    private func datedConfiguration(from idea: PlanningIdea, date: Date?) -> EventIdeaConfiguration {
        var configuration = idea.eventConfiguration!
        configuration.proposedDate = date
        configuration.proposedEndDate = date?.addingTimeInterval(7_200)
        return configuration
    }
}
