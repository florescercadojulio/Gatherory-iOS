import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct NotificationControllerTests {
    @Test("FCM disabled never asks for notification permission or registers")
    func disabledConfigurationDoesNotPrompt() async {
        let permission = TestNotificationPermissionCenter()
        let transport = TestNotificationTransport()
        let controller = makeController(configured: false, permission: permission, transport: transport)
        await controller.setEnabled(true, for: .guest(id: UUID()))
        #expect(await permission.requestCountSnapshot() == 0)
        let registrations = await transport.registrationSnapshot()
        #expect(registrations.isEmpty)
        #expect(!controller.isEnabled)
    }

    @Test("A tap is accepted only for the active principal and valid supported fields")
    func payloadAuthorization() {
        let guest = NotificationPrincipal.guest(id: UUID())
        let valid: [AnyHashable: Any] = [
            "type": "assignment_changed", "eventId": "event-1", "entityId": "todo-1",
            "recipientKind": "device_guest", "recipientId": guest.recipientID
        ]
        #expect(GatheroryNotificationPayload.route(from: valid, principal: guest) == .todo(eventID: "event-1", todoID: "todo-1"))
        var crossPrincipal = valid
        crossPrincipal["recipientKind"] = "user"
        #expect(GatheroryNotificationPayload.route(from: crossPrincipal, principal: guest) == nil)
        var malformed = valid
        malformed["eventId"] = "../account"
        #expect(GatheroryNotificationPayload.route(from: malformed, principal: guest) == nil)
        var unknown = valid
        unknown["type"] = "open_url"
        #expect(GatheroryNotificationPayload.route(from: unknown, principal: guest) == nil)
    }

    @Test("A cold-start tap waits for the root route handler")
    func coldStartTapWaitsForRoot() async {
        let guest = NotificationPrincipal.guest(id: UUID())
        let controller = makeController(configured: true)
        await controller.activate(identity: guest)
        await controller.setEnabled(true, for: guest)
        let payload: [AnyHashable: Any] = [
            "type": "assignment_changed", "eventId": "event-1", "entityId": "task-1",
            "recipientKind": "device_guest", "recipientId": guest.recipientID
        ]
        controller.receiveNotificationTap(payload)
        var received: NotificationRouteIntent?
        controller.onRouteIntent = { received = $0 }
        #expect(received == .todo(eventID: "event-1", todoID: "task-1"))
    }

    @Test("Announcement payloads bind to the active recipient and keep message text out of routing")
    func announcementPayloadAuthorization() {
        let account = NotificationPrincipal.account(id: "recipient-a")
        let eventID = UUID().uuidString
        let announcementID = UUID().uuidString
        var payload: [AnyHashable: Any] = [
            "type": "event_announcement", "eventId": eventID, "entityId": announcementID,
            "recipientKind": "user", "recipientId": "recipient-a", "message": "Untrusted text",
            "url": "https://example.test/private"
        ]
        #expect(GatheroryNotificationPayload.route(from: payload, principal: account) ==
            .announcement(eventID: eventID, announcementID: announcementID))
        #expect(GatheroryNotificationPayload.route(from: payload, principal: .account(id: "recipient-b")) == nil)
        #expect(GatheroryNotificationPayload.route(from: payload, principal: .guest(id: UUID())) == nil)
        payload["entityId"] = "../untrusted"
        #expect(GatheroryNotificationPayload.route(from: payload, principal: account) == nil)
    }

    @Test("Guest registration uses only guest proof and detach advances the installation revision")
    func guestRegistrationAndDetach() async throws {
        let guestID = UUID()
        let transport = TestNotificationTransport()
        let controller = makeController(configured: true, transport: transport, tokenProvider: FixedNotificationTokenProvider("fcm-token"))
        let guest = NotificationPrincipal.guest(id: guestID)
        await controller.activate(identity: guest)
        await controller.setEnabled(true, for: guest)
        let registrations = await transport.registrationSnapshot()
        #expect(registrations.count == 1)
        if case .guest(let id, let proof) = try #require(registrations.first?.auth) {
            #expect(id == guestID)
            #expect(LocalGuestCredentialToken.isValid(proof))
        } else { Issue.record("Expected device guest proof") }
        await controller.detachCurrentIdentity()
        let detachRevisions = await transport.detachRevisionSnapshot()
        #expect(detachRevisions.count == 1)
        #expect(detachRevisions[0] > registrations[0].revision)
    }

    @Test("A late A-B-A-era token lookup cannot register after identity changed")
    func staleIdentityRegistrationIsDiscarded() async {
        let accountA = NotificationPrincipal.account(id: "account-a")
        let accountB = NotificationPrincipal.account(id: "account-b")
        let defaults = UserDefaults(suiteName: "NotificationControllerTests-\(UUID())")!
        defaults.set(true, forKey: "notifications.enabled.user:account-a")
        defaults.set(true, forKey: "notifications.enabled.user:account-b")
        let provider = DelayedFirstNotificationTokenProvider()
        let transport = TestNotificationTransport()
        let controller = NotificationController(
            baseURL: URL(string: "https://notifications.test")!, configured: true,
            installationStore: TestInstallationStore(), guestCredentials: MemoryLocalGuestCredentialStore(),
            accountTokenStore: TestSessionTokenStore(), transport: transport,
            permissionCenter: TestNotificationPermissionCenter(), tokenProvider: provider, preferences: defaults
        )

        let staleActivation = Task { await controller.activate(identity: accountA) }
        await provider.waitForFirstCall()
        await controller.activate(identity: accountB)
        await controller.activate(identity: accountA)
        await provider.resumeFirstCall()
        await staleActivation.value

        let registrations = await transport.registrationSnapshot()
        #expect(registrations.count == 2)
        #expect(registrations.allSatisfy { $0.token == "current-token" })
    }

    @Test("A stale in-flight A POST cannot retry after A-B-A principal changes")
    func staleInFlightPostCannotRebindOldIdentity() async {
        let accountA = NotificationPrincipal.account(id: "account-a")
        let accountB = NotificationPrincipal.account(id: "account-b")
        let defaults = UserDefaults(suiteName: "NotificationControllerTests-\(UUID())")!
        defaults.set(true, forKey: "notifications.enabled.user:account-a")
        defaults.set(true, forKey: "notifications.enabled.user:account-b")
        let transport = DelayedFirstNotificationRegistrationTransport()
        let controller = NotificationController(
            baseURL: URL(string: "https://notifications.test")!, configured: true,
            installationStore: TestInstallationStore(), guestCredentials: MemoryLocalGuestCredentialStore(),
            accountTokenStore: TestSessionTokenStore(), transport: transport,
            permissionCenter: TestNotificationPermissionCenter(), tokenProvider: FixedNotificationTokenProvider("token"),
            preferences: defaults
        )

        let firstActivation = Task { await controller.activate(identity: accountA) }
        await transport.waitForFirstRegistration()
        await controller.activate(identity: accountB)
        await controller.activate(identity: accountA)
        await transport.resumeFirstRegistrationAsStale(serverRevision: 5)
        await firstActivation.value

        #expect(await transport.registrationCount() == 3)
        #expect(await transport.registrationRevisions() == [1, 3, 5])
    }

    private func makeController(
        configured: Bool,
        permission: TestNotificationPermissionCenter? = nil,
        transport: TestNotificationTransport? = nil,
        tokenProvider: (any NotificationTokenProviding)? = nil
    ) -> NotificationController {
        let defaults = UserDefaults(suiteName: "NotificationControllerTests-\(UUID())")!
        return NotificationController(
            baseURL: URL(string: "https://notifications.test")!,
            configured: configured,
            installationStore: TestInstallationStore(),
            guestCredentials: MemoryLocalGuestCredentialStore(),
            accountTokenStore: TestSessionTokenStore(),
            transport: transport ?? TestNotificationTransport(),
            permissionCenter: permission ?? TestNotificationPermissionCenter(),
            tokenProvider: tokenProvider ?? FixedNotificationTokenProvider("token"),
            preferences: defaults
        )
    }
}

@MainActor private final class TestInstallationStore: NotificationInstallationStoring {
    private var value = NotificationInstallation(secret: LocalGuestCredentialToken.make())
    func loadIfExists() throws -> NotificationInstallation? { value }
    func loadOrCreate() throws -> NotificationInstallation { value }
    func nextRevision(minimum: Int) throws -> NotificationInstallation {
        value.revision = max(value.revision + 1, minimum)
        return value
    }
    func markMayBeBound() throws { value.mayBeBound = true }
    func markDetached() throws { value.mayBeBound = false }
}

private struct TestSessionTokenStore: SessionTokenStore {
    func read() throws -> String? { "test-bearer" }
    func save(_ token: String) throws {}
    func delete() {}
}

@MainActor private final class TestNotificationTransport: NotificationRegistrationTransport {
    struct Registration: Sendable { let auth: NotificationAuth; let token: String; let revision: Int }
    private var registrations: [Registration] = []
    private var detachRevisions: [Int] = []
    @MainActor func register(installation: NotificationInstallation, token: String, enabled: Bool, auth: NotificationAuth) async throws -> Int {
        registrations.append(.init(auth: auth, token: token, revision: installation.revision))
        return installation.revision
    }
    @MainActor func detach(installation: NotificationInstallation) async throws -> Int {
        detachRevisions.append(installation.revision)
        return installation.revision
    }
    func registrationSnapshot() async -> [Registration] { registrations }
    func detachRevisionSnapshot() async -> [Int] { detachRevisions }
}

@MainActor private final class DelayedFirstNotificationRegistrationTransport: NotificationRegistrationTransport {
    private var count = 0
    private var revisions: [Int] = []
    private var firstRegistration: CheckedContinuation<Int, Error>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    @MainActor func register(installation: NotificationInstallation, token: String, enabled: Bool, auth: NotificationAuth) async throws -> Int {
        count += 1
        revisions.append(installation.revision)
        guard count == 1 else { return installation.revision }
        return try await withCheckedThrowingContinuation { continuation in
            firstRegistration = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    @MainActor func detach(installation: NotificationInstallation) async throws -> Int { installation.revision }

    func waitForFirstRegistration() async {
        if count > 0 { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeFirstRegistrationAsStale(serverRevision: Int) {
        firstRegistration?.resume(throwing: NotificationRegistrationFailure.staleRevision(serverRevision))
        firstRegistration = nil
    }

    func registrationCount() async -> Int { count }
    func registrationRevisions() async -> [Int] { revisions }
}

@MainActor private final class TestNotificationPermissionCenter: NotificationPermissionCenter {
    private var requests = 0
    func requestAuthorization() async throws -> Bool {
        requests += 1
        return true
    }
    func isAuthorized() async -> Bool { true }
    func registerForRemoteNotifications() async {}
    func requestCountSnapshot() async -> Int { requests }
}

@MainActor private struct FixedNotificationTokenProvider: NotificationTokenProviding {
    let token: String?
    init(_ token: String?) { self.token = token }
    func currentToken() async throws -> String? { token }
    func setAutoInitEnabled(_ enabled: Bool) {}
}

@MainActor private final class DelayedFirstNotificationTokenProvider: NotificationTokenProviding {
    private var calls = 0
    private var firstCallContinuation: CheckedContinuation<String?, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func currentToken() async throws -> String? {
        calls += 1
        guard calls == 1 else { return "current-token" }
        return await withCheckedContinuation { continuation in
            firstCallContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }
    func setAutoInitEnabled(_ enabled: Bool) {}

    func waitForFirstCall() async {
        if calls > 0 { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeFirstCall() { firstCallContinuation?.resume(returning: "late-token"); firstCallContinuation = nil }
}
