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

    @Test("The app uses the Gatherory launch screen")
    func appDeclaresLaunchScreen() {
        let launchScreen = Bundle.main.object(
            forInfoDictionaryKey: "UILaunchStoryboardName"
        ) as? String

        #expect(launchScreen == "LaunchScreen")
    }

    @Test("The branded launch animation stays brief and shortens for Reduce Motion")
    func launchExperienceTimingIsBrief() {
        #expect(LaunchExperienceTiming.standardMilliseconds <= 1_500)
        #expect(
            LaunchExperienceTiming.reducedMotionMilliseconds
                < LaunchExperienceTiming.standardMilliseconds
        )
    }

    @Test("The sample library opens on the workspace collection")
    func sampleLibraryStartsAtWorkspaceCollection() {
        let library = WorkspaceLibrary.sample

        #expect(library.workspaces.count == 2)
        #expect(library.selectedWorkspace == nil)
    }

    @Test("Workspace bootstrap honors the development seed setting")
    func workspaceBootstrapHonorsSeedSetting() {
        let seededLibrary = WorkspaceLibrary.bootstrap(seedData: true)
        let emptyLibrary = WorkspaceLibrary.bootstrap(seedData: false)

        #expect(seededLibrary.workspaces.count == 2)
        #expect(emptyLibrary.workspaces.isEmpty)
        #expect(seededLibrary.selectedWorkspace == nil)
        #expect(emptyLibrary.selectedWorkspace == nil)
    }

    @Test("Development authentication always includes the planner account")
    func developmentAuthenticationIncludesPlanner() throws {
        let authentication = AuthenticationSession(
            environment: .development,
            skipsAuthentication: false
        )

        #expect(authentication.currentUser == nil)
        #expect(authentication.developmentAccounts == [DevelopmentAccountFixtures.planner])

        try authentication.signIn(
            email: "planner@gatherory.test",
            password: "password"
        )

        #expect(authentication.currentUser == DevelopmentAccountFixtures.planner)
    }

    @Test("Development authentication can bypass the login view")
    func developmentAuthenticationCanSkipLogin() {
        let authentication = AuthenticationSession(
            environment: .development,
            skipsAuthentication: true
        )

        #expect(authentication.currentUser == DevelopmentAccountFixtures.planner)
    }

    @Test("Editing a profile updates the active account")
    func editingProfileUpdatesCurrentAccount() throws {
        let authentication = AuthenticationSession(
            environment: .development,
            skipsAuthentication: true
        )

        #expect(authentication.updateProfile(displayName: "  Jordan Lee  "))

        let account = try #require(authentication.currentUser)
        #expect(account.displayName == "Jordan Lee")
        #expect(authentication.developmentAccounts.first?.displayName == "Jordan Lee")
    }

    @Test("Production never installs the simulated planner account")
    func productionDoesNotInstallDevelopmentAccount() {
        let authentication = AuthenticationSession(
            environment: .production,
            skipsAuthentication: true
        )

        #expect(authentication.currentUser == nil)
        #expect(authentication.developmentAccounts.isEmpty)
    }

    @Test("Opening and closing a workspace updates the active context")
    func workspaceSelectionRoundTrip() throws {
        let library = WorkspaceLibrary.sample
        let workspace = try #require(library.workspaces.first)

        library.open(workspace)
        #expect(library.selectedWorkspace === workspace)

        library.closeWorkspace()
        #expect(library.selectedWorkspace == nil)

        library.closeWorkspace()
        #expect(library.selectedWorkspace == nil)
    }

    @Test("Creating a workspace adds it and opens it")
    func creatingWorkspaceSelectsIt() {
        let library = WorkspaceLibrary()
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Neighborhood dinner",
            startsAt: .now,
            eventLocation: nil,
            imageData: nil,
            budgetCap: 5_000
        )

        library.add(workspace)

        #expect(library.workspaces.count == 1)
        #expect(library.selectedWorkspace === workspace)
        #expect(workspace.workspaceBudgetCap == 5_000)
        #expect(workspace.mainEventBudgetCap == 5_000)
    }

    @Test("Creating an all-day workspace preserves all-day scheduling")
    func creatingAllDayWorkspace() {
        let startsAt = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let endsAt = Date(timeIntervalSinceReferenceDate: 900_086_400)
        let workspace = WeddingWorkspace.newWorkspace(
            title: "Neighborhood festival",
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: true,
            timeZoneIdentifier: "America/Detroit",
            eventLocation: nil,
            imageData: nil
        )
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: "America/Detroit") ?? .autoupdatingCurrent

        #expect(workspace.mainEventIsAllDay)
        #expect(workspace.weddingDate == calendar.startOfDay(for: startsAt))
        #expect(workspace.mainEventEndsAt == calendar.startOfDay(for: endsAt))
        #expect(workspace.mainEventTimeZoneIdentifier == "America/Detroit")
    }

    @Test("All-day schedules normalize dates in their selected time zone")
    func allDayScheduleNormalization() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Detroit"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startsAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 15, minute: 30))
        )
        let endsAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 18))
        )

        let schedule = EventSchedule(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: true,
            timeZoneIdentifier: timeZone.identifier
        ).normalized

        #expect(schedule.startsAt == calendar.startOfDay(for: startsAt))
        #expect(schedule.endsAt == calendar.startOfDay(for: endsAt))
        #expect(schedule.isAllDay)
    }

    @Test("Event ideas preserve an optional full schedule")
    func eventIdeaScheduleMetadata() {
        let startsAt = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let endsAt = Date(timeIntervalSinceReferenceDate: 900_007_200)
        let configuration = EventIdeaConfiguration(
            category: .reception,
            purpose: .eventExperience,
            proposedDate: startsAt,
            proposedEndDate: endsAt,
            isAllDay: false,
            timeZoneIdentifier: "America/Detroit",
            location: nil
        )

        #expect(configuration.proposedDate == startsAt)
        #expect(configuration.proposedEndDate == endsAt)
        #expect(configuration.isAllDay == false)
        #expect(configuration.timeZoneIdentifier == "America/Detroit")
        #expect(configuration.audience == .inherited)
    }

    @Test("Legacy event ideas default to the inherited audience")
    func legacyEventIdeaAudience() throws {
        let configuration = EventIdeaConfiguration(
            category: .photography,
            purpose: .planning,
            proposedDate: nil,
            location: nil
        )
        let encoded = try JSONEncoder().encode(configuration)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "audience")
        object.removeValue(forKey: "requiresBudget")
        object.removeValue(forKey: "proposedBudget")
        object.removeValue(forKey: "attireStyle")
        object.removeValue(forKey: "attireGuidance")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(EventIdeaConfiguration.self, from: legacyData)

        #expect(decoded.audience == .inherited)
        #expect(decoded.requiresBudget == false)
        #expect(decoded.proposedBudget == nil)
        #expect(decoded.attireStyle == .any)
        #expect(decoded.attireGuidance.isEmpty)
        #expect(decoded.category == .photography)
    }

    @Test("Honeymoon event ideas can be scoped to hosts")
    func honeymoonEventAudience() {
        let configuration = EventIdeaConfiguration(
            category: .honeymoon,
            purpose: .eventExperience,
            audience: .hostsOnly,
            proposedDate: nil,
            location: nil
        )

        #expect(configuration.audience == .hostsOnly)
        #expect(configuration.category.title == "Honeymoon")
    }

    @Test("Attendable sample ideas use the event model")
    func attendableIdeasUseEventModel() {
        let attendableTypes: Set<TimelineCategory> = [.venue, .photography, .honeymoon]
        let attendableIdeas = WeddingWorkspace.sample.ideas.filter {
            guard let eventType = $0.eventConfiguration?.category else { return false }
            return attendableTypes.contains(eventType)
        }

        #expect(attendableIdeas.contains { $0.eventConfiguration?.category == .venue })
        #expect(attendableIdeas.contains { $0.eventConfiguration?.category == .photography })
        #expect(attendableIdeas.allSatisfy { $0.category == .event })
    }

    @Test("A dated approved event idea can enter the timeline once")
    func approvedEventIdeaCanBeScheduled() throws {
        let workspace = WeddingWorkspace.sample
        let hosts = Set(workspace.members.filter { $0.participantRole == .host }.map(\.id))
        let idea = WeddingIdea(
            title: "Honeymoon",
            note: "A quiet trip after the celebration.",
            category: .event,
            submittedBy: "Alex & Jordan",
            status: .chosen,
            configuration: .event(
                EventIdeaConfiguration(
                    category: .honeymoon,
                    purpose: .eventExperience,
                    audience: .hostsOnly,
                    proposedDate: Date(timeIntervalSinceReferenceDate: 900_000_000),
                    location: nil
                )
            )
        )
        workspace.addIdea(idea)

        let automaticallyScheduled = try #require(
            workspace.timeline.first { $0.linkedIdeaID == idea.id }
        )
        let firstID = try #require(workspace.scheduleEventIdea(idea))
        let secondID = try #require(workspace.scheduleEventIdea(idea))
        let scheduled = try #require(workspace.timeline.first { $0.id == firstID })

        #expect(automaticallyScheduled.id == firstID)
        #expect(firstID == secondID)
        #expect(Set(scheduled.participantIDs) == hosts)
        #expect(workspace.timeline.filter { $0.linkedIdeaID == idea.id }.count == 1)
    }

    @Test("Loving an idea approves it")
    func loveIdea() throws {
        let workspace = WeddingWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.love, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .chosen)
        #expect(workspace.decisionQueue.contains { $0.id == idea.id } == false)
    }

    @Test("Loving a dated event idea creates its linked event")
    func loveEventIdeaCreatesEvent() throws {
        let workspace = WeddingWorkspace.sample
        let idea = WeddingIdea(
            title: "Venue",
            note: "Tour the venue together.",
            category: .event,
            submittedBy: "Alex",
            configuration: .event(
                EventIdeaConfiguration(
                    category: .venue,
                    purpose: .planning,
                    proposedDate: Date(timeIntervalSinceReferenceDate: 900_000_000),
                    location: nil
                )
            )
        )
        workspace.addIdea(idea)

        workspace.decide(.love, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .chosen)
        #expect(workspace.timeline.contains { $0.linkedIdeaID == idea.id })
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

    @Test("Event costs roll up across the workspace")
    func eventCostsRollUp() {
        let workspace = WeddingWorkspace.sample
        let expectedTotal = workspace.eventExpenses.reduce(Decimal.zero) { $0 + $1.amount }

        #expect(workspace.workspaceCostTotal == expectedTotal)
        #expect(
            EventExpenseStatus.allCases.reduce(Decimal.zero) {
                $0 + workspace.costTotal(status: $1)
            } == expectedTotal
        )
    }

    @Test("Budget transfers preserve the workspace cap")
    func budgetTransfersPreserveWorkspaceCap() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let totalBefore = workspace.allocatedBudgetTotal

        #expect(workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(workspace.transferBudget(500, from: .main, to: .subevent(child.id)))

        #expect(workspace.budgetCap(for: .subevent(child.id)) == 500)
        #expect(workspace.allocatedBudgetTotal == totalBefore)
        #expect(
            workspace.allocatedBudgetTotal + workspace.freeBudgetPool
                == workspace.workspaceBudgetCap
        )
    }

    @Test("An event cannot take more budget than its source owns")
    func budgetTransferCannotOverdrawSource() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let mainBudget = try #require(workspace.mainEventBudgetCap)

        #expect(workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(
            workspace.transferBudget(
                mainBudget + 1,
                from: .main,
                to: .subevent(child.id)
            ) == false
        )
        #expect(workspace.mainEventBudgetCap == mainBudget)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == .zero)
    }

    @Test("Removing an event budget returns its allocation to the free pool")
    func removingEventBudgetReturnsAllocationToPool() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let mainBudget = try #require(workspace.mainEventBudgetCap)
        let freePool = workspace.freeBudgetPool

        #expect(workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(workspace.transferBudget(750, from: .main, to: .subevent(child.id)))
        #expect(workspace.setEventRequiresBudget(false, eventID: child.id))

        #expect(workspace.mainEventBudgetCap == mainBudget - 750)
        #expect(workspace.freeBudgetPool == freePool + 750)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == nil)
    }

    @Test("Budget can move through the free pool")
    func budgetCanMoveThroughFreePool() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let initialPool = workspace.freeBudgetPool

        #expect(workspace.setEventRequiresBudget(true, eventID: child.id))
        #expect(
            workspace.transferBudget(
                500,
                from: .event(.main),
                to: .freePool
            )
        )
        #expect(workspace.freeBudgetPool == initialPool + 500)

        #expect(
            workspace.transferBudget(
                300,
                from: .freePool,
                to: .event(.subevent(child.id))
            )
        )
        #expect(workspace.freeBudgetPool == initialPool + 200)
        #expect(workspace.budgetCap(for: .subevent(child.id)) == 300)
    }

    @Test("Replacing costs only changes the selected event")
    func replacingEventCostsIsScoped() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let mainCosts = workspace.expenses(for: .main)
        let replacement = EventExpense(
            eventID: child.id,
            title: "Transportation",
            amount: 350,
            category: .travel,
            status: .committed
        )

        workspace.replaceExpenses([replacement], forEventID: child.id)

        #expect(workspace.expenses(for: .subevent(child.id)) == [replacement])
        #expect(workspace.expenses(for: .main) == mainCosts)
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

    @Test("Changing a participant role applies its appropriate access")
    func participantRoleUpdatesAccess() throws {
        let workspace = WeddingWorkspace.sample
        let collaborator = try #require(
            workspace.members.first { $0.participantRole == .collaborator }
        )

        let didUpdate = workspace.updateParticipant(
            collaborator.id,
            role: .guest,
            planningPermission: .contribute
        )

        let updated = try #require(workspace.members.first { $0.id == collaborator.id })
        #expect(didUpdate)
        #expect(updated.participantRole == .guest)
        #expect(updated.planningPermission == .viewOnly)
    }

    @Test("Removing a participant only changes the selected event")
    func participantRemovalIsEventScoped() throws {
        let workspace = WeddingWorkspace.sample
        let event = try #require(workspace.childEvents.first { !$0.participantIDs.isEmpty })
        let participantID = try #require(
            event.participantIDs.first { workspace.mainEventParticipantIDs.contains($0) }
        )

        let didRemove = workspace.removeParticipant(
            participantID,
            from: .subevent(event.id)
        )

        let updatedEvent = try #require(workspace.timeline.first { $0.id == event.id })
        #expect(didRemove)
        #expect(!updatedEvent.participantIDs.contains(participantID))
        #expect(workspace.mainEventParticipantIDs.contains(participantID))
        #expect(workspace.members.contains { $0.id == participantID })
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

    @Test("Home shortcut prefers the current event, then the next event")
    func homeShortcutFindsCurrentOrNextEvent() throws {
        let workspace = WeddingWorkspace.sample
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let currentID = UUID()
        let nextID = UUID()

        workspace.timeline = [
            TimelineItem(
                id: currentID,
                title: "Current event",
                category: .other,
                scheduledAt: now.addingTimeInterval(-900),
                eventLocation: nil,
                endsAt: now.addingTimeInterval(900),
                participantIDs: [],
                parentEventID: workspace.mainEventID
            ),
            TimelineItem(
                id: nextID,
                title: "Next event",
                category: .other,
                scheduledAt: now.addingTimeInterval(3_600),
                eventLocation: nil,
                participantIDs: [],
                parentEventID: workspace.mainEventID
            )
        ]

        #expect(workspace.currentOrNextChildEventReference(at: now) == .subevent(currentID))

        workspace.timeline[0].completionStatus = .complete
        #expect(workspace.currentOrNextChildEventReference(at: now) == .subevent(nextID))
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

    @Test("Idea edits replace content without changing identity or status")
    func editIdea() throws {
        let workspace = WeddingWorkspace.sample
        let original = try #require(workspace.ideas.first)
        var edited = original
        edited.title = "Updated idea"
        edited.note = "Updated details"
        edited.estimatedCost = 425

        workspace.updateIdea(edited)

        let saved = try #require(workspace.ideas.first { $0.id == original.id })
        #expect(saved.title == "Updated idea")
        #expect(saved.note == "Updated details")
        #expect(saved.estimatedCost == 425)
        #expect(saved.status == original.status)
        #expect(saved.eventID == original.eventID)
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

    @Test("Adding a participant follows the selected event context")
    func participantInvitationsFollowSelectedEvent() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let originalDirectoryCount = workspace.members.count
        let originalMainEventParticipantIDs = workspace.mainEventParticipantIDs
        workspace.selectEventContext(.subevent(child.id))

        workspace.inviteParticipant(
            name: "Taylor Event",
            email: "taylor.event@example.com",
            initials: "TE",
            role: .collaborator
        )

        let participant = try #require(workspace.members.first { $0.name == "Taylor Event" })
        let updatedChild = try #require(workspace.timeline.first { $0.id == child.id })
        #expect(workspace.members.count == originalDirectoryCount + 1)
        #expect(workspace.mainEventParticipantIDs == originalMainEventParticipantIDs)
        #expect(updatedChild.participantIDs.contains(participant.id))
        #expect(workspace.selectedEventParticipants.contains { $0.id == participant.id })
    }

    @Test("An existing main-event participant can join a selected subevent")
    func existingParticipantCanJoinSelectedSubevent() throws {
        let workspace = WeddingWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let originalIDs = Set(child.participantIDs)
        let participant = try #require(workspace.members.first { !originalIDs.contains($0.id) })
        let originalMemberCount = workspace.members.count
        workspace.selectEventContext(.subevent(child.id))

        workspace.inviteParticipant(
            name: participant.name,
            email: participant.email,
            initials: participant.initials,
            role: participant.participantRole
        )

        let updatedChild = try #require(workspace.timeline.first { $0.id == child.id })
        #expect(workspace.members.count == originalMemberCount)
        #expect(updatedChild.participantIDs.contains(participant.id))
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
