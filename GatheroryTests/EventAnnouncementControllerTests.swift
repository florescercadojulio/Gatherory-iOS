import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized) @MainActor
struct EventAnnouncementControllerTests {
    let eventID = UUID()

    @Test("Only an acknowledged host capability exposes sending; guest is always read only")
    func serverCapabilityAndGuestBoundary() async {
        let transport = AnnouncementTestTransport()
        transport.feed = .init(announcements: [], canSend: true)
        let controller = EventAnnouncementController()
        activate(controller, transport: transport, principal: .guest(id: UUID()))
        await controller.refresh()
        controller.draft = "Welcome"
        #expect(!controller.canSend)
        #expect(!(await controller.send()))
        #expect(transport.sends.isEmpty)
        activate(controller, transport: transport)
        #expect(!controller.canSend)
        await controller.refresh()
        #expect(controller.canSend)
    }

    @Test("A failed send retains draft and retries the same ID only after Send")
    func explicitRetry() async {
        let transport = AnnouncementTestTransport()
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        controller.draft = "  Bring an umbrella.  \n"
        transport.failure = .unavailable
        #expect(!(await controller.send()))
        #expect(controller.draft == "  Bring an umbrella.  \n")
        #expect(controller.announcements.isEmpty)
        #expect(transport.sends.count == 1)
        transport.failure = nil
        await controller.refresh()
        #expect(transport.sends.count == 1)
        #expect(await controller.send())
        #expect(transport.sends.count == 2)
        #expect(transport.sends[0].id == transport.sends[1].id)
        #expect(transport.sends[0].message == "Bring an umbrella.")
        #expect(controller.draft.isEmpty)
        #expect(controller.announcements.count == 1)
    }

    @Test("Editing a failed draft creates a distinct explicit request")
    func editedDraftUsesFreshID() async {
        let transport = AnnouncementTestTransport()
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        transport.failure = .unavailable
        controller.draft = "First"
        _ = await controller.send()
        controller.draft = "Second"
        _ = await controller.send()
        #expect(transport.sends[0].id != transport.sends[1].id)
    }

    @Test("An idempotency conflict keeps the draft and requires an edit before another send")
    func conflictRequiresExplicitEdit() async {
        let transport = AnnouncementTestTransport()
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        controller.draft = "First"
        transport.failure = .requestConflict
        #expect(!(await controller.send()))
        #expect(controller.draft == "First")
        #expect(!controller.canSubmit)
        #expect(!(await controller.send()))
        #expect(transport.sends.count == 1)
        controller.draft = "Revised"
        transport.failure = nil
        #expect(controller.canSubmit)
        #expect(await controller.send())
        #expect(transport.sends[0].id != transport.sends[1].id)
    }

    @Test("Audience choices come from server capabilities and default to Planning when available")
    func audienceCapabilities() async {
        let transport = AnnouncementTestTransport()
        let controller = EventAnnouncementController()
        transport.feed = .init(announcements: [], canSend: true, allowedAudiences: [.all, .planning, .guests])
        activate(controller, transport: transport)
        await controller.refresh()
        #expect(controller.audience == .planning)
        #expect(controller.allowedAudiences == [.all, .planning, .guests])
        transport.feed = .init(announcements: [], canSend: true, allowedAudiences: [.planning])
        await controller.refresh()
        controller.audience = .guests
        controller.draft = "Private"
        #expect(!controller.canSubmit)
        #expect(!(await controller.send()))
        #expect(transport.sends.isEmpty)
        controller.audience = .planning
        #expect(await controller.send())
        #expect(transport.sends.first?.audience == .planning)
        #expect(controller.announcements.first?.audience == .planning)
    }

    @Test("Changing the audience after a failed request uses a fresh request ID")
    func audienceRetryIsolation() async {
        let transport = AnnouncementTestTransport()
        transport.feed = .init(announcements: [], canSend: true, allowedAudiences: [.all, .planning, .guests])
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        controller.draft = "Same message"
        transport.failure = .unavailable
        _ = await controller.send()
        _ = await controller.send()
        #expect(transport.sends[0].id == transport.sends[1].id)
        controller.audience = .guests
        transport.failure = nil
        #expect(await controller.send())
        #expect(transport.sends[0].id != transport.sends[2].id)
        #expect(transport.sends[0].audience == .planning)
        #expect(transport.sends[2].audience == .guests)
    }

    @Test("A missing audience capability on an old feed fails closed")
    func missingWireCapability() async throws {
        let feed = try JSONDecoder().decode(EventAnnouncementFeed.self, from: Data("{\"announcements\":[],\"canSend\":true}".utf8))
        #expect(feed.allowedAudiences.isEmpty)
        #expect(!feed.canSend)
        let transport = AnnouncementTestTransport()
        transport.feed = feed
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        #expect(!controller.canSend)
    }

    @Test("Validation uses trimmed Unicode scalars and rejects empty or oversized messages")
    func unicodeValidation() {
        #expect(!EventAnnouncementMessage.isValid(" \n\t"))
        #expect(EventAnnouncementMessage.isValid("  " + String(repeating: "é", count: 750) + "\n"))
        #expect(!EventAnnouncementMessage.isValid(String(repeating: "é", count: 751)))
        #expect(!EventAnnouncementMessage.isValid(String(repeating: "👨‍👩‍👧‍👦", count: 108)))
    }

    @Test("An offline refresh keeps current-scope messages; revoked access clears them")
    func offlineAndRevocation() async {
        let transport = AnnouncementTestTransport()
        transport.feed = .init(announcements: [announcement()], canSend: true)
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        transport.failure = .unavailable
        await controller.refresh()
        #expect(controller.announcements.count == 1)
        #expect(controller.loadFailure == .unavailable)
        transport.failure = .accessDenied
        await controller.refresh()
        #expect(controller.announcements.isEmpty)
        #expect(!controller.canSend)
    }

    @Test("New identity clears memory, draft, and capabilities")
    func scopeReset() async {
        let transport = AnnouncementTestTransport()
        transport.feed = .init(announcements: [announcement()], canSend: true)
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        controller.draft = "Private draft"
        activate(controller, transport: transport, principal: .account(id: "account-b"))
        #expect(controller.announcements.isEmpty)
        #expect(controller.draft.isEmpty)
        #expect(!controller.canSend)
        #expect(!controller.hasLoaded)
    }

    @Test("A late load cannot repopulate an A-B-A account generation")
    func lateLoadGeneration() async {
        let transport = AnnouncementTestTransport()
        transport.delayLoad = true
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        let task = Task { await controller.refresh() }
        while transport.loadContinuation == nil { await Task.yield() }
        activate(controller, transport: AnnouncementTestTransport(), principal: .account(id: "account-b"), generation: 1)
        activate(controller, transport: AnnouncementTestTransport(), generation: 2)
        transport.loadContinuation?.resume(returning: .init(announcements: [announcement()], canSend: true))
        await task.value
        #expect(controller.announcements.isEmpty)
        #expect(!controller.canSend)
    }

    @Test("A late send never clears the next identity’s draft or publishes success")
    func lateSendGeneration() async {
        let transport = AnnouncementTestTransport()
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        transport.delaySend = true
        controller.draft = "A’s message"
        let task = Task { await controller.send() }
        while transport.sendContinuation == nil { await Task.yield() }
        activate(controller, transport: AnnouncementTestTransport(), generation: 2)
        controller.draft = "New draft"
        transport.sendContinuation?.resume(returning: announcement())
        #expect(!(await task.value))
        #expect(controller.draft == "New draft")
        #expect(controller.announcements.isEmpty)
    }

    @Test("Live session invalidation rejects late callbacks before the view reactivates")
    func currentSessionGuard() async {
        let transport = AnnouncementTestTransport()
        transport.delayLoad = true
        var current = true
        let controller = EventAnnouncementController()
        controller.activate(scope: .init(principal: .account(id: "a"), generation: 0, eventID: eventID), transport: transport, isCurrent: { current })
        let task = Task { await controller.refresh() }
        while transport.loadContinuation == nil { await Task.yield() }
        current = false
        transport.loadContinuation?.resume(returning: .init(announcements: [announcement()], canSend: true))
        await task.value
        #expect(controller.announcements.isEmpty)
        #expect(!controller.canSend)
    }

    @Test("A response for another exact event is never displayed")
    func exactEventBoundary() async {
        let transport = AnnouncementTestTransport()
        transport.feed = .init(announcements: [announcement(event: UUID())], canSend: true)
        let controller = EventAnnouncementController()
        activate(controller, transport: transport)
        await controller.refresh()
        #expect(controller.loadFailure == .invalidResponse)
        #expect(controller.announcements.isEmpty)
        #expect(!controller.canSend)
    }

    private func announcement(event: UUID? = nil) -> EventAnnouncement {
        .init(id: UUID(), eventId: event ?? eventID, message: "Update", authorName: "Host", createdAt: .now)
    }
    private func activate(_ controller: EventAnnouncementController, transport: any EventAnnouncementTransport,
                          principal: NotificationPrincipal = .account(id: "account-a"), generation: UInt64 = 0) {
        controller.activate(scope: .init(principal: principal, generation: generation, eventID: eventID), transport: transport, isCurrent: { true })
    }
}

@MainActor private final class AnnouncementTestTransport: EventAnnouncementTransport {
    var feed = EventAnnouncementFeed(announcements: [], canSend: true)
    var failure: EventAnnouncementFailure?
    var sends: [(id: UUID, message: String, audience: EventAnnouncementAudience)] = []
    var delayLoad = false
    var delaySend = false
    var loadContinuation: CheckedContinuation<EventAnnouncementFeed, any Error>?
    var sendContinuation: CheckedContinuation<EventAnnouncement, any Error>?
    func load(eventID: UUID) async throws -> EventAnnouncementFeed {
        if delayLoad { return try await withCheckedThrowingContinuation { loadContinuation = $0 } }
        if let failure { throw failure }
        return feed
    }
    func send(eventID: UUID, requestID: UUID, message: String, audience: EventAnnouncementAudience) async throws -> EventAnnouncement {
        sends.append((requestID, message, audience))
        if delaySend { return try await withCheckedThrowingContinuation { sendContinuation = $0 } }
        if let failure { throw failure }
        return .init(id: requestID, eventId: eventID, message: message, authorName: "Host", createdAt: .now, audience: audience)
    }
}
