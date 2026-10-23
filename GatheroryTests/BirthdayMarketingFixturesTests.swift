import Testing
import UIKit
@testable import Gatherory

@MainActor
struct BirthdayMarketingFixturesTests {
    @Test("Marketing seed requires every isolation switch")
    func requiresIsolatedOptIn() {
        let flag = ["-UseBirthdayMarketingFixture"]
        #expect(BirthdayMarketingFixtures.isEnabled(arguments: flag, ephemeral: true,
            seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.isEnabled(arguments: [], ephemeral: true,
            seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.isEnabled(arguments: flag, ephemeral: false,
            seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.isEnabled(arguments: flag, ephemeral: true,
            seedsDevelopmentData: false, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.isEnabled(arguments: flag, ephemeral: true,
            seedsDevelopmentData: true, skipsAuthentication: false))
    }

    @Test("Manage preview launch option requires the fully isolated birthday fixture")
    func managePreviewRequiresIsolatedOptIn() {
        let arguments = ["-UseBirthdayMarketingFixture", "-BirthdayMarketingManagePreview"]
        #expect(BirthdayMarketingFixtures.startsOnManagePreview(arguments: arguments, ephemeral: true,
            seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.startsOnManagePreview(arguments: ["-BirthdayMarketingManagePreview"],
            ephemeral: true, seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.startsOnManagePreview(arguments: arguments, ephemeral: false,
            seedsDevelopmentData: true, skipsAuthentication: true))
        #expect(!BirthdayMarketingFixtures.startsOnManagePreview(arguments: arguments, ephemeral: true,
            seedsDevelopmentData: true, skipsAuthentication: false))
        #expect(!BirthdayMarketingFixtures.startsOnManagePreview(arguments: ["-UseBirthdayMarketingFixture"],
            ephemeral: true, seedsDevelopmentData: true, skipsAuthentication: true))
    }

    @Test("Birthday archive retains people photos, assignments, choices, and dinner costs")
    func archivePreservesPlanningGroup() throws {
        let workspace = BirthdayMarketingFixtures.makeWorkspace(locale: Locale(identifier: "en"))
        workspace.configureViewer(DevelopmentAccountFixtures.planner)
        let codec = WorkspaceArchiveCodec()
        let restored = try codec.decode(WorkspaceArchiveV1.self,
            from: codec.encode(WorkspaceArchiveV1(workspace: workspace))).makeWorkspace()
        restored.configureViewer(DevelopmentAccountFixtures.planner)

        #expect(restored.title == "Maya’s Birthday Dinner")
        #expect(restored.members.count == 11)
        for person in restored.members {
            let asset = try #require(person.profileImageAssetName)
            #expect(UIImage(named: asset) != nil)
        }
        #expect(Set(restored.members.compactMap(\.profileImageAssetName)).count == 11)
        #expect(!restored.members.contains { ["Casey Patel", "Taylor Brooks"].contains($0.name) })
        let attendance = ManageAttendanceSummary(participants: restored.participants(for: .main))
        #expect(attendance.going == 6)
        #expect(attendance.maybe == 2)
        #expect(attendance.declined == 1)
        #expect(attendance.awaiting == 2)
        #expect(restored.mainEventImageData?.isEmpty == false)
        #expect(restored.workspaceBudgetCap == 600)
        #expect(restored.eventExpenses.reduce(0, { $0 + $1.amount }) == 395)
        #expect(restored.notes.contains { $0.body.contains("playlist is ready") })
        #expect(restored.todos.allSatisfy { todo in
            restored.members.contains { $0.id == todo.assigneePersonID }
        })
        let card = try #require(restored.decisionQueue.first)
        #expect(card.title == "Candlelit birthday table")
        #expect(restored.teamResponseSummary(for: card) == .init(love: 2, maybe: 1, unanswered: 1))
        let playlist = try #require(restored.ideas.first { $0.category == .music })
        #expect(playlist.musicTracks.map(\.title) == ["With You Tonight", "Beneath the Stars", "One More Song"])
        #expect(restored.timeline.map(\.title).allSatisfy { !$0.localizedCaseInsensitiveContains("wedding") })
    }

    @Test("Birthday photos stay present and distinct through archive persistence")
    func archivePreservesDistinctMarketingPhotography() throws {
        let workspace = BirthdayMarketingFixtures.makeWorkspace(locale: Locale(identifier: "en"))
        let codec = WorkspaceArchiveCodec()
        let restored = try codec.decode(WorkspaceArchiveV1.self,
            from: codec.encode(WorkspaceArchiveV1(workspace: workspace))).makeWorkspace()

        let photos = [restored.mainEventImageData]
            + restored.ideas.map(\.imageData)
            + restored.timeline.map(\.imageData)
        let imageBytes = try photos.map { try #require($0) }

        #expect(imageBytes.count == 11)
        #expect(imageBytes.allSatisfy { !$0.isEmpty })
        #expect(Set(imageBytes).count == imageBytes.count)
    }

    @Test("Birthday fixture uses Spanish sample copy and local playlist metadata for Spanish previews")
    func spanishPreviewContentIsLocalized() throws {
        let workspace = BirthdayMarketingFixtures.makeWorkspace(locale: Locale(identifier: "es"))
        let playlist = try #require(workspace.ideas.first { $0.category == .music })

        #expect(workspace.title == "Cena de cumple de Maya")
        #expect(workspace.venueName == "Casa de Alex")
        #expect(workspace.location == "Detroit, Míchigan")
        #expect(workspace.dressCode == "Ven como eres")
        #expect(workspace.eventMessage.contains("Buena comida"))
        #expect(workspace.ideas.map(\.title).contains("Mesa de cumpleaños a la luz de las velas"))
        #expect(workspace.ideas.map(\.title).contains("Música para Maya"))
        #expect(playlist.note.contains("Clásicos"))
        #expect(playlist.musicTracks.map(\.title) == ["Aquí contigo", "Bajo las estrellas", "Una noche más"])
        #expect(playlist.musicTracks.allSatisfy {
            $0.providerID.rawValue == "local-fixture" && $0.externalURL == nil && $0.previewURL == nil
        })
        #expect(workspace.timeline.map(\.title).contains("Se sirve la cena"))
        #expect(workspace.eventExpenses.map(\.title).contains("Compras para la cena"))
        #expect(workspace.notes.first?.body.contains("La lista de reproducción está lista") == true)
        #expect(workspace.todos.map(\.title).contains("Recoger el pastel de cumpleaños"))
        #expect(workspace.members.first?.name == "Alex Morgan")
    }

    @Test("Pending requests include pictured requestors and remain transient and event scoped")
    func picturedPendingRequestsStayIsolated() async throws {
        let store = EventJoinRequestStore(client: BirthdayMarketingFixtures.joinRequestTransport)
        let accountID = "birthday-fixture-account"
        let unrelatedEventID = UUID()
        #expect(store.requestCount(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID) == nil)
        let fixtureArguments = ["-UseBirthdayMarketingFixture"]
        #expect(BirthdayMarketingFixtures.profileImageAssetName(forEmail: "pending-collaborator@gatherory.test",
            arguments: fixtureArguments, ephemeral: true, seedsDevelopmentData: true, skipsAuthentication: true) == "MarketingRequestCasey")
        #expect(BirthdayMarketingFixtures.profileImageAssetName(forEmail: "pending-collaborator@gatherory.test",
            arguments: fixtureArguments, ephemeral: false, seedsDevelopmentData: true, skipsAuthentication: true) == nil)
        #expect(BirthdayMarketingFixtures.profileImageAssetName(forEmail: "reception-planner@gatherory.test",
            arguments: fixtureArguments, ephemeral: true, seedsDevelopmentData: true, skipsAuthentication: true) == "MarketingRequestTaylor")
        #expect(UIImage(named: "MarketingRequestCasey") != nil)
        #expect(UIImage(named: "MarketingRequestTaylor") != nil)
        await store.refresh(eventID: unrelatedEventID, accountID: accountID)
        #expect(store.requestCount(eventID: unrelatedEventID, accountID: accountID) == 0)
        #expect(store.requests(eventID: unrelatedEventID, accountID: accountID).isEmpty)
        await store.refresh(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID)
        let requests = store.requests(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID)
        #expect(requests.map(\.name) == ["Casey Patel", "Taylor Brooks"])
        #expect(requests.allSatisfy { $0.profileImageURL != nil })
        #expect(requests.allSatisfy {
            BirthdayMarketingFixtures.profileImageAssetName(forEmail: $0.email, arguments: fixtureArguments,
                ephemeral: true, seedsDevelopmentData: true, skipsAuthentication: true) != nil
        })
        #expect(store.requestCount(eventID: BirthdayMarketingFixtures.eventID, accountID: "other-account") == nil)
        #expect(store.requests(eventID: BirthdayMarketingFixtures.eventID, accountID: "other-account").isEmpty)

        let approved = try #require(requests.first)
        #expect(await store.review(approved, eventID: BirthdayMarketingFixtures.eventID,
            accountID: accountID, action: .approve))
        #expect(store.requestCount(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID) == 1)
        #expect(store.requests(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID).first?.name == "Taylor Brooks")
        await store.refresh(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID, force: true)
        #expect(store.requestCount(eventID: BirthdayMarketingFixtures.eventID, accountID: accountID) == 1)
    }

    @Test("Older join-request API responses without profile image URLs still decode")
    func missingOptionalRequestPortraitDecodes() throws {
        let json = #"{"id":"0e808cf0-998b-46e6-8ec9-8a3e9cf31103","name":"Older response","email":"older@example.test","planningPermission":"contribute"}"#
        let request = try JSONDecoder().decode(EventJoinRequest.self, from: Data(json.utf8))
        #expect(request.name == "Older response")
        #expect(request.profileImageURL == nil)
    }
}
