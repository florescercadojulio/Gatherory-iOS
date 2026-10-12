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

    @Test("Music previews survive persistence and older tracks remain decodable")
    @MainActor
    func musicPreviewPersistenceIsBackwardCompatible() throws {
        let previewURL = try #require(URL(string: "https://example.com/song-preview.m4a"))
        let track = MusicTrack(
            providerID: .appleMusic,
            catalogID: "song-1",
            title: "First Dance",
            artistName: "The Band",
            albumTitle: "Together",
            artworkURL: URL(string: "https://example.com/artwork.jpg"),
            previewURL: previewURL,
            externalURL: URL(string: "https://music.apple.com/song-1"),
            isrc: "TEST123",
            duration: 180
        )

        let encoded = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(MusicTrack.self, from: encoded)
        #expect(decoded.previewURL == previewURL)

        let legacyTrack = LegacyMusicTrack(
            providerID: .appleMusic,
            catalogID: "legacy-song",
            title: "Legacy Song",
            artistName: "The Band",
            albumTitle: nil,
            artworkURL: nil,
            externalURL: nil,
            isrc: nil,
            duration: nil
        )
        let legacyData = try JSONEncoder().encode(legacyTrack)
        let migratedTrack = try JSONDecoder().decode(MusicTrack.self, from: legacyData)
        #expect(migratedTrack.previewURL == nil)
    }

    @Test("A shared playlist uses its first song as the automatic cover source")
    func musicPlaylistUsesFirstSongArtwork() throws {
        let firstArtworkURL = try #require(URL(string: "https://example.com/first-song.jpg"))
        let firstTrack = MusicTrack(
            providerID: .appleMusic,
            catalogID: "first-song",
            title: "First Song",
            artistName: "Artist One",
            albumTitle: "Album One",
            artworkURL: firstArtworkURL,
            externalURL: nil,
            isrc: nil,
            duration: nil
        )
        let secondTrack = MusicTrack(
            providerID: .appleMusic,
            catalogID: "second-song",
            title: "Second Song",
            artistName: "Artist Two",
            albumTitle: "Album Two",
            artworkURL: URL(string: "https://example.com/second-song.jpg"),
            externalURL: nil,
            isrc: nil,
            duration: nil
        )
        let playlist = PlanningIdea(
            title: "Reception Playlist",
            note: "",
            category: .music,
            submittedBy: "You",
            configuration: .music(MusicIdeaConfiguration(tracks: [firstTrack, secondTrack]))
        )

        #expect(playlist.musicTrack?.artworkURL == firstArtworkURL)
    }

    @Test("Library-only MusicKit artwork falls back to catalog recovery")
    func musicKitArtworkRequiresRecovery() throws {
        let libraryArtworkURL = try #require(
            URL(string: "musicKit://artwork/library/track/600x600")
        )
        let track = MusicTrack(
            providerID: .appleMusic,
            catalogID: "i.4YBN1YWf2a62bq9",
            title: "BABYDOLL (Speed)",
            artistName: "Ari Abdul",
            albumTitle: "BABYDOLL (Speed) - Single",
            artworkURL: libraryArtworkURL,
            externalURL: nil,
            isrc: nil,
            duration: 156.651
        )

        #expect(track.displayArtworkURL == nil)
    }

    @Test("Money entry groups large values while preserving their numeric value")
    func moneyEntryFormatting() {
        let locale = Locale(identifier: "en_US")

        #expect(
            MoneyInputFormatter.editingText(
                from: "1234567",
                allowsFraction: false,
                locale: locale
            ) == "1,234,567"
        )
        #expect(
            MoneyInputFormatter.editingText(
                from: "1234567.89",
                locale: locale
            ) == "1,234,567.89"
        )
        #expect(
            MoneyInputFormatter.decimal(from: "1,234,567.89", locale: locale)
                == Decimal(string: "1234567.89")
        )
    }

    @Test("The active color theme covers every visual category")
    func activeColorThemeIsComplete() {
        #expect(!AppTheme.active.name.isEmpty)

        for category in IdeaCategory.allCases {
            #expect(category.artworkColors.count >= 3)
        }
        for category in RegistryCategory.allCases {
            #expect(category.artworkColors.count >= 3)
        }
        for category in TimelineCategory.allCases {
            #expect(category.artworkColors.count >= 3)
        }
    }

    @Test("Account privacy links use Gatherory's public legal destinations")
    func accountPrivacyLinksUsePublicLegalDestinations() {
        #expect(
            GatheroryLegalDestination.privacyPolicy.absoluteString
                == "https://gatherory.com/privacy"
        )
        #expect(
            GatheroryLegalDestination.termsOfUse.absoluteString
                == "https://gatherory.com/terms"
        )
        #expect(
            GatheroryLegalDestination.privacyQuestions.absoluteString
                == "mailto:privacy@gatherory.com"
        )
    }

    @Test("The Decide primer waits until the Decide tab is active")
    func decidePrimerPresentationRequiresActiveTab() {
        #expect(
            !DecidePrimerPresentationPolicy.shouldPresent(
                hasSeenPrimer: false,
                isDecideTabActive: false
            )
        )
        #expect(
            DecidePrimerPresentationPolicy.shouldPresent(
                hasSeenPrimer: false,
                isDecideTabActive: true
            )
        )
        #expect(
            !DecidePrimerPresentationPolicy.shouldPresent(
                hasSeenPrimer: true,
                isDecideTabActive: true
            )
        )
    }

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

    @Test("Workspace filters separate lifecycle and participation scopes")
    func workspaceFiltersMatchTheSignedInPersonAndEventLifecycle() {
        let now = Date.now
        let account = UserAccount(
            id: "jordan-user",
            email: "jordan@example.com",
            displayName: "Jordan Lee",
            role: .member,
            authenticationProvider: .password,
            createdAt: now
        )
        let host = WorkspaceMember(
            userID: account.id,
            name: account.displayName,
            participantRole: .host,
            initials: "JL",
            email: account.email,
            planningPermission: .manage
        )
        let attendee = WorkspaceMember(
            userID: account.id,
            name: account.displayName,
            participantRole: .guest,
            initials: "JL",
            attendance: .going,
            email: account.email,
            planningPermission: .viewOnly
        )

        let hostedUpcoming = workspaceFilterFixture(
            title: "Hosted upcoming",
            date: now.addingTimeInterval(86_400),
            status: .ongoing,
            member: host
        )
        let attendedUpcoming = workspaceFilterFixture(
            title: "Attended upcoming",
            date: now.addingTimeInterval(172_800),
            status: .ongoing,
            member: attendee
        )
        let draft = workspaceFilterFixture(
            title: "Draft",
            date: now.addingTimeInterval(259_200),
            status: .draft,
            member: host
        )
        let past = workspaceFilterFixture(
            title: "Past",
            date: now.addingTimeInterval(-86_400),
            status: .finished,
            member: host
        )
        let workspaces = [hostedUpcoming, attendedUpcoming, draft, past]

        #expect(
            WorkspaceFilter.upcoming.workspaces(from: workspaces, for: account, now: now)
                .map(\.title)
                == ["Hosted upcoming", "Attended upcoming"]
        )
        #expect(
            WorkspaceFilter.drafts.workspaces(from: workspaces, for: account, now: now)
                .map(\.title)
                == ["Draft"]
        )
        #expect(
            WorkspaceFilter.past.workspaces(from: workspaces, for: account, now: now)
                .map(\.title)
                == ["Past"]
        )
        #expect(
            WorkspaceFilter.hosting.workspaces(from: workspaces, for: account, now: now)
                .map(\.title)
                == ["Hosted upcoming", "Draft", "Past"]
        )
        #expect(
            WorkspaceFilter.attending.workspaces(from: workspaces, for: account, now: now)
                .map(\.title)
                == ["Attended upcoming"]
        )
    }

    @Test("Collaborators receive the complete planning interface")
    func collaboratorViewerReceivesHostControls() throws {
        let workspace = PlanningWorkspace.sample
        let collaboratorIndex = try #require(
            workspace.members.firstIndex { $0.participantRole == .collaborator }
        )
        workspace.members[collaboratorIndex].userID = "collaborator-user"
        workspace.members[collaboratorIndex].email = "collaborator@gatherory.test"

        workspace.configureViewer(
            UserAccount(
                id: "collaborator-user",
                email: "collaborator@gatherory.test",
                displayName: "Sarah",
                role: .member,
                authenticationProvider: .password,
                createdAt: .now
            )
        )

        #expect(workspace.showsPlanningInterface)
        #expect(workspace.canManageMainEvent)
        #expect(workspace.canDeleteMainEvent)
        #expect(workspace.visibleEventContexts == workspace.availableEventContexts)
    }

    @Test("Guests only receive Home events in their invitation scope")
    func guestViewerReceivesInvitationOnlyScope() throws {
        let workspace = PlanningWorkspace.sample
        let guestIndex = try #require(
            workspace.members.firstIndex { $0.participantRole == .guest }
        )
        workspace.members[guestIndex].userID = "guest-user"
        workspace.members[guestIndex].email = "guest@gatherory.test"

        workspace.configureViewer(
            UserAccount(
                id: "guest-user",
                email: "guest@gatherory.test",
                displayName: "Chris",
                role: .member,
                authenticationProvider: .password,
                createdAt: .now
            )
        )

        #expect(!workspace.showsPlanningInterface)
        #expect(workspace.isGuestViewer)
        #expect(!workspace.canManageMainEvent)
        #expect(!workspace.canDeleteMainEvent)
        #expect(workspace.visibleEventContexts == [.main])
    }

    private func workspaceFilterFixture(
        title: String,
        date: Date,
        status: MainEventStatus,
        member: WorkspaceMember
    ) -> PlanningWorkspace {
        PlanningWorkspace(
            title: title,
            mainEventStartsAt: date,
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member],
            ideas: [],
            timeline: [],
            mainEventStatus: status,
            registry: []
        )
    }

    @Test("Development authentication always includes the planner account")
    @MainActor
    func developmentAuthenticationIncludesPlanner() async throws {
        let authentication = AuthenticationSession(
            environment: .development,
            skipsAuthentication: false
        )

        #expect(authentication.currentUser == nil)
        #expect(authentication.developmentAccounts == [DevelopmentAccountFixtures.planner])

        try await authentication.signIn(
            email: "planner@gatherory.test",
            password: "password"
        )

        #expect(authentication.currentUser == DevelopmentAccountFixtures.planner)
    }

    @Test("Development authentication can bypass the login view")
    @MainActor
    func developmentAuthenticationCanSkipLogin() {
        let authentication = AuthenticationSession(
            environment: .development,
            skipsAuthentication: true
        )

        #expect(authentication.currentUser == DevelopmentAccountFixtures.planner)
    }

    @Test("Editing a profile updates the active account")
    @MainActor
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
    @MainActor
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
        let workspace = PlanningWorkspace.newWorkspace(
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
        let workspace = PlanningWorkspace.newWorkspace(
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
        #expect(workspace.mainEventStartsAt == calendar.startOfDay(for: startsAt))
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
        let attendableIdeas = PlanningWorkspace.sample.ideas.filter {
            guard let eventType = $0.eventConfiguration?.category else { return false }
            return attendableTypes.contains(eventType)
        }

        #expect(attendableIdeas.contains { $0.eventConfiguration?.category == .venue })
        #expect(attendableIdeas.contains { $0.eventConfiguration?.category == .photography })
        #expect(attendableIdeas.allSatisfy { $0.category == .event })
    }

    @Test("A dated approved event idea can enter the timeline once")
    func approvedEventIdeaCanBeScheduled() throws {
        let workspace = PlanningWorkspace.sample
        let hosts = Set(workspace.members.filter { $0.participantRole == .host }.map(\.id))
        let idea = PlanningIdea(
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
        let workspace = PlanningWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.love, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .chosen)
        #expect(workspace.decisionQueue.contains { $0.id == idea.id } == false)
    }

    @Test("Loving a dated event idea creates its linked event")
    func loveEventIdeaCreatesEvent() throws {
        let workspace = PlanningWorkspace.sample
        let idea = PlanningIdea(
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

    @Test("Loving an undated event idea keeps the proposal in Ideas")
    func loveUndatedEventIdeaNeedsDate() throws {
        let workspace = PlanningWorkspace.sample
        let idea = PlanningIdea(
            title: "Choose a rehearsal venue",
            note: "We like the space but have not picked a date.",
            category: .event,
            submittedBy: "Alex",
            configuration: .event(
                EventIdeaConfiguration(
                    category: .rehearsal,
                    purpose: .planning,
                    proposedDate: nil,
                    location: nil
                )
            )
        )
        workspace.addIdea(idea)

        workspace.decide(.love, on: idea)

        let approvedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(approvedIdea.status == .chosen)
        #expect(workspace.timeline.contains { $0.linkedIdeaID == idea.id } == false)
        #expect(workspace.contextualIdeas.contains { $0.id == idea.id })
    }

    @Test("Adding a date to an approved event idea promotes it to Home once")
    func datingApprovedEventIdeaPromotesItToHome() throws {
        let workspace = PlanningWorkspace.sample
        let idea = PlanningIdea(
            title: "Welcome dinner",
            note: "A relaxed dinner before the celebration.",
            category: .event,
            submittedBy: "Alex",
            status: .chosen,
            configuration: .event(
                EventIdeaConfiguration(
                    category: .rehearsal,
                    purpose: .eventExperience,
                    proposedDate: nil,
                    location: nil
                )
            )
        )
        workspace.addIdea(idea)

        var datedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        var configuration = try #require(datedIdea.eventConfiguration)
        configuration.proposedDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
        datedIdea.configuration = .event(configuration)
        workspace.updateIdea(datedIdea)

        let linkedEvent = try #require(workspace.timeline.first { $0.linkedIdeaID == idea.id })
        #expect(linkedEvent.hasScheduledDate)
        #expect(workspace.availableEventContexts.contains(.subevent(linkedEvent.id)))

        workspace.updateIdea(datedIdea)
        #expect(workspace.timeline.filter { $0.linkedIdeaID == idea.id }.count == 1)
    }

    @Test("Maybe saves an idea for later")
    func saveIdeaForLater() throws {
        let workspace = PlanningWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.maybe, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .maybe)
    }

    @Test("Passing an idea archives it")
    func passIdea() throws {
        let workspace = PlanningWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.pass, on: idea)

        let updatedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(updatedIdea.status == .passed)
    }

    @Test("The latest decision can be undone")
    func undoDecision() throws {
        let workspace = PlanningWorkspace.sample
        let idea = try #require(workspace.decisionQueue.first)

        workspace.decide(.love, on: idea)
        workspace.undoLastDecision()

        let restoredIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(restoredIdea.status == .new)
        #expect(workspace.decisionQueue.contains { $0.id == idea.id })
    }

    @Test("Timeline items toggle between upcoming and complete")
    func toggleTimelineItem() throws {
        let workspace = PlanningWorkspace.sample
        let item = try #require(workspace.timeline.first { $0.completionStatus == .upcoming })

        workspace.toggleTimelineItem(item)

        let completedItem = try #require(workspace.timeline.first { $0.id == item.id })
        #expect(completedItem.completionStatus == .complete)
    }

    @Test("Event costs roll up across the workspace")
    func eventCostsRollUp() {
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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

    @Test("Ideas follow context while decisions stay workspace-wide")
    func ideasFollowSelectedEventContextWhileDecisionsStayWorkspaceWide() throws {
        let workspace = PlanningWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        let initialDecisionIDs = Set(workspace.decisionQueue.map(\.id))

        workspace.selectEventContext(.subevent(child.id))
        #expect(workspace.contextualIdeas.isEmpty)
        #expect(Set(workspace.decisionQueue.map(\.id)) == initialDecisionIDs)

        workspace.addIdea(
            PlanningIdea(
                title: "Welcome table for this event",
                note: "Keep it specific to the selected subevent.",
                category: .decor,
                submittedBy: "Alex"
            )
        )

        let scopedIdea = try #require(workspace.contextualIdeas.first)
        #expect(scopedIdea.eventID == child.id)
        #expect(workspace.decisionQueue.contains { $0.id == scopedIdea.id })
        #expect(workspace.decisionQueue(for: child.id).contains { $0.id == scopedIdea.id })

        workspace.selectEventContext(.main)
        #expect(workspace.contextualIdeas.contains { $0.id == scopedIdea.id } == false)
    }

    @Test("Event ideas from a child context remain first-level subevents")
    func eventIdeasCreatedFromChildContextUseMainEvent() throws {
        let workspace = PlanningWorkspace.sample
        let child = try #require(workspace.childEvents.first)
        workspace.selectEventContext(.subevent(child.id))

        let proposal = PlanningIdea(
            title: "After party",
            note: "Keep it as a first-level event.",
            category: .event,
            submittedBy: "Alex"
        )
        workspace.addIdea(proposal)

        let storedProposal = try #require(workspace.ideas.first { $0.id == proposal.id })
        #expect(storedProposal.eventID == workspace.mainEventID)
    }

    @Test("Removing the active subevent returns planning to the main event")
    func deletingActiveSubeventRestoresMainContext() throws {
        let workspace = PlanningWorkspace.sample
        let child = try #require(workspace.childEvents.first)

        workspace.selectEventContext(.subevent(child.id))
        workspace.deleteTimelineItem(child)

        #expect(workspace.selectedEventReference == .main)
    }

    @Test("Event contexts are ordered chronologically")
    func eventContextsAreChronological() {
        let workspace = PlanningWorkspace.sample
        let dates = workspace.availableEventContexts.map(workspace.eventDate(for:))

        #expect(dates == dates.sorted())
    }

    @Test("Home shortcut prefers the current event, then the next event")
    func homeShortcutFindsCurrentOrNextEvent() throws {
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
        let child = try #require(workspace.childEvents.first)

        workspace.selectEventContext(.subevent(child.id))
        workspace.sendNote("Meet at the side entrance.")

        let note = try #require(workspace.contextualNotes.first)
        #expect(note.eventID == child.id)

        workspace.selectEventContext(.main)
        #expect(workspace.contextualNotes.contains { $0.id == note.id } == false)
    }

    @Test("Shared album photos stay scoped to their event")
    func sharedAlbumPhotosAreEventScoped() throws {
        let workspace = PlanningWorkspace.sample
        let child = try #require(
            workspace.childEvents.first(where: { $0.status != .archived })
        )

        workspace.addEventMoment(Data([0x01]), to: .main)
        workspace.addEventMoment(Data([0x02]), to: .subevent(child.id))

        #expect(workspace.moments(for: .main).count == 1)
        #expect(workspace.moments(for: .subevent(child.id)).count == 1)
        #expect(workspace.moments(for: .main).first?.imageData == Data([0x01]))
        #expect(workspace.moments(for: .subevent(child.id)).first?.imageData == Data([0x02]))

        workspace.deleteTimelineItem(child)

        #expect(workspace.moments(for: .main).count == 1)
        #expect(workspace.moments(for: .subevent(child.id)).isEmpty)
    }

    @Test("Approved event ideas share their scheduled event album")
    func approvedEventIdeaUsesScheduledAlbum() throws {
        let workspace = PlanningWorkspace.sample
        let idea = try #require(
            workspace.ideas.first {
                $0.category == .event && $0.status == .chosen
            }
        )
        var scheduledIdea = idea
        var configuration = try #require(scheduledIdea.eventConfiguration)
        configuration.proposedDate = Date(timeIntervalSinceReferenceDate: 900_000_000)
        scheduledIdea.configuration = .event(configuration)
        workspace.updateIdea(scheduledIdea)
        let linkedEvent = try #require(
            workspace.timeline.first { $0.linkedIdeaID == idea.id }
        )

        workspace.addEventMoment(Data([0x03]), to: .idea(idea.id))

        #expect(workspace.moments(for: .idea(idea.id)).count == 1)
        #expect(workspace.moments(for: .subevent(linkedEvent.id)).count == 1)
    }

    @Test("Timeline events can be deleted from their details")
    func deleteTimelineItem() throws {
        let workspace = PlanningWorkspace.sample
        let item = try #require(workspace.timeline.first)

        workspace.deleteTimelineItem(item)

        #expect(workspace.timeline.contains { $0.id == item.id } == false)
    }

    @Test("Ideas can be archived from the list")
    func archiveIdea() throws {
        let workspace = PlanningWorkspace.sample
        let idea = try #require(workspace.ideas.first)

        workspace.updateIdea(idea, status: .archived)

        let archivedIdea = try #require(workspace.ideas.first { $0.id == idea.id })
        #expect(archivedIdea.status == .archived)
    }

    @Test("Idea edits replace content without changing identity or status")
    func editIdea() throws {
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
        let item = try #require(workspace.registry.first { !$0.isFulfilled })

        workspace.commitToRegistryItem(item)

        let reservedItem = try #require(workspace.registry.first { $0.id == item.id })
        #expect(reservedItem.committedCount == item.committedCount + 1)
    }

    @Test("A private registry does not accept reservations")
    func privateRegistryCannotBeReserved() throws {
        let workspace = PlanningWorkspace.sample
        workspace.isRegistryShared = false
        let item = try #require(workspace.registry.first { !$0.isFulfilled })

        workspace.commitToRegistryItem(item)

        let unchangedItem = try #require(workspace.registry.first { $0.id == item.id })
        #expect(unchangedItem.committedCount == item.committedCount)
    }

    @Test("A guest invitation preserves role and contact details")
    func inviteCollaborator() throws {
        let workspace = PlanningWorkspace.sample

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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample
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
        let workspace = PlanningWorkspace.sample

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

    @Test("Attire defaults to guest-facing while planning details stay private")
    func ideaInvitationVisibilityDefaultsByCategory() {
        let attire = PlanningIdea(
            title: "Black Tie",
            note: "",
            category: .attire,
            submittedBy: "Alex"
        )
        let flowers = PlanningIdea(
            title: "White lilies",
            note: "",
            category: .flowers,
            submittedBy: "Alex"
        )

        #expect(attire.isShownOnInvitation)
        #expect(!flowers.isShownOnInvitation)
    }

    @Test("Invitation ideas require approval, visibility, and the matching event")
    func invitationIdeasFollowCentralGuestPresentationPolicy() {
        let workspace = PlanningWorkspace.sample
        let firstAttire = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Black Tie",
            note: "",
            category: .attire,
            submittedBy: "Alex",
            status: .chosen,
            configuration: .attire(AttireIdeaConfiguration(style: .blackTie, restrictions: ""))
        )
        let secondAttire = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Formal",
            note: "Jewel tones welcome",
            category: .attire,
            submittedBy: "Jordan",
            status: .chosen,
            configuration: .attire(AttireIdeaConfiguration(style: .formal, restrictions: ""))
        )
        let privateFlowers = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "White lilies",
            note: "",
            category: .flowers,
            submittedBy: "Alex",
            status: .chosen
        )
        let sharedFlowers = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Flower-free ceremony",
            note: "For allergy awareness",
            category: .flowers,
            submittedBy: "Jordan",
            status: .chosen,
            invitationVisibility: .shownToGuests
        )
        let pendingAttire = PlanningIdea(
            eventID: workspace.mainEventID,
            title: "Cocktail",
            note: "",
            category: .attire,
            submittedBy: "Alex",
            status: .new
        )
        let otherEventAttire = PlanningIdea(
            eventID: UUID(),
            title: "Garden",
            note: "",
            category: .attire,
            submittedBy: "Alex",
            status: .chosen
        )

        [firstAttire, secondAttire, privateFlowers, sharedFlowers, pendingAttire, otherEventAttire]
            .forEach { workspace.addIdea($0) }

        let visibleIDs = Set(workspace.invitationIdeas(for: .main).map(\.id))
        #expect(visibleIDs.contains(firstAttire.id))
        #expect(visibleIDs.contains(secondAttire.id))
        #expect(visibleIDs.contains(sharedFlowers.id))
        #expect(!visibleIDs.contains(privateFlowers.id))
        #expect(!visibleIDs.contains(pendingAttire.id))
        #expect(!visibleIDs.contains(otherEventAttire.id))
    }

    @Test("Link ideas normalize and persist website addresses")
    func linkIdeasNormalizeAndPersistWebsiteAddresses() throws {
        let normalizedURL = try #require(
            LinkIdeaConfiguration.normalizedURL(from: "  gatherory.com/inspiration  ")
        )
        #expect(normalizedURL.absoluteString == "https://gatherory.com/inspiration")
        #expect(LinkIdeaConfiguration.normalizedURL(from: "ftp://gatherory.com") == nil)

        let idea = PlanningIdea(
            title: "Venue inspiration",
            note: "A useful reference for the ceremony look.",
            category: .link,
            submittedBy: "Julio",
            configuration: .link(LinkIdeaConfiguration(url: normalizedURL))
        )
        let data = try JSONEncoder().encode(idea)
        let restored = try JSONDecoder().decode(PlanningIdea.self, from: data)

        #expect(restored.linkConfiguration?.url == normalizedURL)
        #expect(restored.title == idea.title)
        #expect(restored.note == idea.note)
    }

}

private struct LegacyMusicTrack: Encodable {
    let providerID: MusicProviderID
    let catalogID: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let externalURL: URL?
    let isrc: String?
    let duration: TimeInterval?
}
