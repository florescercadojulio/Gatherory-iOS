#if DEBUG
import UIKit

/// Opt-in prototype content. It can only enter an isolated, in-memory store;
/// ordinary development fixtures and signed-in account databases are untouched.
enum BirthdayMarketingFixtures {
    static let eventID = UUID(uuidString: "F2A6F730-79BB-4D9D-9AB8-27F79A347B10")!

    static func profileImageAssetName(forEmail email: String) -> String? {
        guard isEnabled else { return nil }
        return requestProfileImageAssetName(forEmail: email)
    }

    static func profileImageAssetName(forEmail email: String, arguments: [String], ephemeral: Bool,
                                      seedsDevelopmentData: Bool, skipsAuthentication: Bool) -> String? {
        guard isEnabled(arguments: arguments, ephemeral: ephemeral,
            seedsDevelopmentData: seedsDevelopmentData, skipsAuthentication: skipsAuthentication) else { return nil }
        return requestProfileImageAssetName(forEmail: email)
    }

    private static func requestProfileImageAssetName(forEmail email: String) -> String? {
        return switch email.lowercased() {
        case "pending-collaborator@gatherory.test": "MarketingRequestCasey"
        case "reception-planner@gatherory.test": "MarketingRequestTaylor"
        default: nil
        }
    }

    @MainActor
    static let joinRequestTransport: any EventJoinRequestTransport = BirthdayMarketingJoinRequestTransport()

    static var isEnabled: Bool {
        isEnabled(arguments: ProcessInfo.processInfo.arguments,
            ephemeral: AppRuntimeConfiguration.usesEphemeralDataStore,
            seedsDevelopmentData: AppRuntimeConfiguration.seedsDevelopmentData,
            skipsAuthentication: AppRuntimeConfiguration.skipsAuthentication)
    }

    static var startsOnManagePreview: Bool {
        startsOnManagePreview(arguments: ProcessInfo.processInfo.arguments,
            ephemeral: AppRuntimeConfiguration.usesEphemeralDataStore,
            seedsDevelopmentData: AppRuntimeConfiguration.seedsDevelopmentData,
            skipsAuthentication: AppRuntimeConfiguration.skipsAuthentication)
    }

    static func startsOnManagePreview(arguments: [String], ephemeral: Bool,
                                      seedsDevelopmentData: Bool, skipsAuthentication: Bool) -> Bool {
        isEnabled(arguments: arguments, ephemeral: ephemeral,
            seedsDevelopmentData: seedsDevelopmentData, skipsAuthentication: skipsAuthentication)
            && arguments.contains("-BirthdayMarketingManagePreview")
    }

    static func isEnabled(arguments: [String], ephemeral: Bool,
                          seedsDevelopmentData: Bool, skipsAuthentication: Bool) -> Bool {
        arguments.contains("-UseBirthdayMarketingFixture") && ephemeral
            && seedsDevelopmentData && skipsAuthentication
    }

    static func makeWorkspace() -> PlanningWorkspace {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Detroit")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 18, minute: 30))!
        let owner = DevelopmentAccountFixtures.planner
        let alex = WorkspaceMember(userID: owner.id, name: "Alex Morgan", participantRole: .host,
            initials: "AM", email: owner.email, profileImageAssetName: "MarketingAlex", planningPermission: .manage)
        let jordan = WorkspaceMember(userID: "birthday-demo-jordan", name: "Jordan Lee",
            participantRole: .collaborator, initials: "JL", email: "jordan@gatherory.test",
            profileImageAssetName: "MarketingJordan", planningPermission: .manage)
        let maya = WorkspaceMember(userID: "birthday-demo-maya", name: "Maya Chen",
            participantRole: .collaborator, initials: "MC", email: "coordinator@gatherory.test",
            profileImageAssetName: "MarketingMaya", planningPermission: .manage)
        let riley = WorkspaceMember(userID: "birthday-demo-riley", name: "Riley Kim",
            participantRole: .collaborator, initials: "RK", email: "latest-collaborator@gatherory.test",
            profileImageAssetName: "MarketingRiley", planningPermission: .manage)
        let guestContacts = [
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C001")!, name: "Sam Rivera",
                participantRole: .guest, initials: "SR", attendance: .going,
                email: "sam.rivera@gatherory.test", profileImageAssetName: "MarketingGuestSam",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C002")!, name: "Noah Williams",
                participantRole: .guest, initials: "NW", attendance: .going,
                email: "noah.williams@gatherory.test", profileImageAssetName: "MarketingGuestNoah",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C003")!, name: "Priya Shah",
                participantRole: .guest, initials: "PS", attendance: .maybe,
                email: "priya.shah@gatherory.test", profileImageAssetName: "MarketingGuestPriya",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C004")!, name: "Grace Kim",
                participantRole: .guest, initials: "GK", attendance: .maybe,
                email: "grace.kim@gatherory.test", profileImageAssetName: "MarketingGuestGrace",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C005")!, name: "Miguel Santos",
                participantRole: .guest, initials: "MS", attendance: .declined,
                email: "miguel.santos@gatherory.test", profileImageAssetName: "MarketingGuestMiguel",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C006")!, name: "Olivia Reed",
                participantRole: .guest, initials: "OR", attendance: .invited,
                email: "olivia.reed@gatherory.test", profileImageAssetName: "MarketingGuestOlivia",
                planningPermission: .viewOnly),
            WorkspaceMember(id: UUID(uuidString: "2B1AB2EA-76A9-4A63-9372-7216F753C007")!, name: "Theo Bennett",
                participantRole: .guest, initials: "TB", attendance: .invited,
                email: "theo.bennett@gatherory.test", profileImageAssetName: "MarketingGuestTheo",
                planningPermission: .viewOnly)
        ]
        let members = [alex, jordan, maya, riley] + guestContacts
        let eventCoverImage = imageData(named: "MarketingBirthdayCover")
        let submittedAt = calendar.date(byAdding: .day, value: -14, to: date)!
        let ideas = [
            PlanningIdea(title: "Candlelit birthday table",
                note: "A long table, little candles, and everyone’s favorite people. Keep it warm and relaxed.",
                category: .decor, submittedBy: "Riley Kim", submittedByUserID: riley.userID,
                estimatedCost: 45, submittedAt: submittedAt.addingTimeInterval(300),
                imageData: imageData(named: "MarketingBirthdayTable")),
            PlanningIdea(title: "Family-style pasta dinner",
                note: "Big bowls to share, a seasonal salad, and a vegetarian option for the table.",
                category: .food, submittedBy: "Jordan Lee", submittedByUserID: jordan.userID,
                estimatedCost: 180, status: .chosen, submittedAt: submittedAt.addingTimeInterval(240),
                imageData: imageData(named: "MarketingBirthdayPasta")),
            PlanningIdea(title: "Maya’s birthday playlist",
                note: "Old favorites and songs that make us think of Maya. Add your picks before Saturday.",
                category: .music, submittedBy: "Alex Morgan", submittedByUserID: alex.userID,
                status: .chosen, submittedAt: submittedAt.addingTimeInterval(180),
                imageData: imageData(named: "MarketingBirthdayPlaylist")),
            PlanningIdea(title: "Chocolate birthday cake",
                note: "Chocolate layers, fresh berries, and a few extra candles. Enough for twelve.",
                category: .food, submittedBy: "Maya Chen", submittedByUserID: maya.userID,
                estimatedCost: 65, submittedAt: submittedAt.addingTimeInterval(120),
                imageData: imageData(named: "MarketingBirthdayCake")),
            PlanningIdea(title: "Flowers from the market",
                note: "A few colorful stems in small bud vases, so everyone can still see across the table.",
                category: .flowers, submittedBy: "Riley Kim", submittedByUserID: riley.userID,
                estimatedCost: 35, submittedAt: submittedAt.addingTimeInterval(60),
                imageData: imageData(named: "MarketingBirthdayFlowers")),
            PlanningIdea(title: "A photo of all of us",
                note: "Set up a phone tripod before dessert so everyone makes it into the picture.",
                category: .photography, submittedBy: "Jordan Lee", submittedByUserID: jordan.userID,
                estimatedCost: 0, submittedAt: submittedAt,
                imageData: imageData(named: "MarketingBirthdayPhoto"))
        ]
        func time(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
        }
        return PlanningWorkspace(mainEventID: eventID, title: "Maya’s Birthday Dinner",
            mainEventStartsAt: date, mainEventEndsAt: time(22, 0),
            mainEventTimeZoneIdentifier: "America/Detroit", mainEventImageData: eventCoverImage,
            venueName: "Alex’s place", location: "Detroit, Michigan", dressCode: "Come as you are",
            eventMessage: "Good food, old friends, and a birthday worth celebrating. Dinner for twelve at Alex’s.",
            planningMode: .openToIdeas, members: members, ideas: ideas,
            timeline: [
                TimelineItem(title: "Set the birthday table", category: .other, scheduledAt: time(17, 30),
                    location: "Alex’s place", participantIDs: [alex.id, riley.id],
                    imageData: imageData(named: "MarketingBirthdaySetup")),
                TimelineItem(title: "Drinks & catch-ups", category: .other, purpose: .eventExperience,
                    scheduledAt: time(18, 30), location: "Alex’s place", participantIDs: members.map(\.id),
                    imageData: imageData(named: "MarketingBirthdayDrinks")),
                TimelineItem(title: "Dinner is served", category: .other, purpose: .eventExperience,
                    scheduledAt: time(19, 0), location: "Alex’s place", participantIDs: members.map(\.id),
                    imageData: imageData(named: "MarketingBirthdayServed")),
                TimelineItem(title: "Cake, candles & a group photo", category: .other, purpose: .eventExperience,
                    scheduledAt: time(20, 30), location: "Alex’s place", participantIDs: members.map(\.id),
                    imageData: imageData(named: "MarketingBirthdayCandles"))
            ], eventExpenses: [
                EventExpense(eventID: eventID, title: "Dinner groceries", amount: 180, category: .foodAndDrink, status: .paid),
                EventExpense(eventID: eventID, title: "Birthday cake", amount: 65, category: .foodAndDrink, status: .committed),
                EventExpense(eventID: eventID, title: "Drinks for the table", amount: 70, category: .foodAndDrink, status: .paid),
                EventExpense(eventID: eventID, title: "Candles & flowers", amount: 80, category: .other, status: .estimated)
            ], workspaceBudgetCap: 600, currencyCode: "USD", notes: [
                EventNote(eventID: eventID, authorUserID: maya.userID,
                    body: "The playlist is ready, and I set the bud vases aside. See everyone Saturday!",
                    sentAt: calendar.date(byAdding: .day, value: -2, to: date)!)
            ], todos: [
                EventTodo(eventID: eventID, title: "Pick up the birthday cake", dueDate: "2026-11-14", assigneePersonID: jordan.id),
                EventTodo(eventID: eventID, title: "Bring candles and bud vases", dueDate: "2026-11-14", assigneePersonID: alex.id),
                EventTodo(eventID: eventID, title: "Check dietary preferences", dueDate: "2026-11-07", assigneePersonID: alex.id, isCompleted: true)
            ], ideaResponses: [
                IdeaResponse(ideaID: ideas[0].id, userID: jordan.userID!, choice: .love),
                IdeaResponse(ideaID: ideas[0].id, userID: maya.userID!, choice: .love),
                IdeaResponse(ideaID: ideas[0].id, userID: riley.userID!, choice: .maybe)
            ], registry: [])
    }

    private static func imageData(named name: String) -> Data? {
        UIImage(named: name)?.jpegData(compressionQuality: 0.9)
    }
}

@MainActor
private final class BirthdayMarketingJoinRequestTransport: EventJoinRequestTransport {
    private var requests = [
        EventJoinRequest(id: UUID(uuidString: "0E808CF0-998B-46E6-8EC9-8A3E9CF31101")!,
            name: "Casey Patel", email: "pending-collaborator@gatherory.test", planningPermission: "contribute",
            profileImageURL: URL(string: "https://images.unsplash.com/photo-1517841905240-472988babdf9?w=240&h=240&fit=crop&crop=faces&auto=format")),
        EventJoinRequest(id: UUID(uuidString: "0E808CF0-998B-46E6-8EC9-8A3E9CF31102")!,
            name: "Taylor Brooks", email: "reception-planner@gatherory.test", planningPermission: "contribute",
            profileImageURL: URL(string: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=240&h=240&fit=crop&crop=faces&auto=format"))
    ]

    func joinRequests(eventID: UUID) async throws -> [EventJoinRequest] {
        eventID == BirthdayMarketingFixtures.eventID ? requests : []
    }

    func reviewJoinRequest(eventID: UUID, requestID: UUID, action: JoinRequestReviewAction) async throws {
        guard eventID == BirthdayMarketingFixtures.eventID,
              requests.contains(where: { $0.id == requestID }) else { return }
        requests.removeAll { $0.id == requestID }
    }
}
#endif
