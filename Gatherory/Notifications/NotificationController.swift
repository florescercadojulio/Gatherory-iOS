import Foundation
import FirebaseMessaging
import Observation
import UIKit
import UserNotifications

@MainActor protocol NotificationPermissionCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func isAuthorized() async -> Bool
    func registerForRemoteNotifications() async
}

@MainActor protocol NotificationTokenProviding: Sendable {
    func currentToken() async throws -> String?
    func setAutoInitEnabled(_ enabled: Bool)
}

@Observable @MainActor
final class NotificationController {
    private(set) var isConfigured = false
    private(set) var isEnabled = false
    private(set) var lastError: Error?
    @ObservationIgnored private let installationStore: any NotificationInstallationStoring
    @ObservationIgnored private let guestCredentials: any LocalGuestCredentialStore
    @ObservationIgnored private let accountTokenStore: any SessionTokenStore
    @ObservationIgnored private let transport: any NotificationRegistrationTransport
    @ObservationIgnored private let permissionCenter: any NotificationPermissionCenter
    @ObservationIgnored private let tokenProvider: any NotificationTokenProviding
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private var principal: NotificationPrincipal?
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var fcmToken: String?
    @ObservationIgnored private var pendingTap: [AnyHashable: Any]?
    var activePrincipal: NotificationPrincipal? { principal }
    var onRouteIntent: ((NotificationRouteIntent) -> Void)? {
        didSet { dispatchPendingTapIfReady() }
    }
    var onRefreshRequested: (() -> Void)?

    init(baseURL: URL?, configured: Bool? = nil,
         installationStore: (any NotificationInstallationStoring)? = nil,
         guestCredentials: (any LocalGuestCredentialStore)? = nil,
         accountTokenStore: (any SessionTokenStore)? = nil,
         transport: (any NotificationRegistrationTransport)? = nil,
         permissionCenter: (any NotificationPermissionCenter)? = nil,
         tokenProvider: (any NotificationTokenProviding)? = nil,
         preferences: UserDefaults = .standard) {
        self.isConfigured = (configured ?? FCMRuntimeConfiguration.isConfigured) && baseURL != nil
        self.installationStore = installationStore ?? KeychainNotificationInstallationStore()
        self.guestCredentials = guestCredentials ?? KeychainLocalGuestCredentialStore()
        self.accountTokenStore = accountTokenStore ?? KeychainSessionTokenStore()
        if let transport { self.transport = transport }
        else if let baseURL { self.transport = URLSessionNotificationRegistrationTransport(baseURL: baseURL) }
        else { self.transport = UnavailableNotificationRegistrationTransport() }
        self.permissionCenter = permissionCenter ?? SystemNotificationPermissionCenter()
        self.tokenProvider = tokenProvider ?? FirebaseNotificationTokenProvider()
        self.preferences = preferences
    }

    func isEnabled(for principal: NotificationPrincipal) -> Bool {
        isConfigured && (self.principal == principal ? isEnabled : preferences.bool(forKey: preferenceKey(principal)))
    }

    func activate(identity: NotificationPrincipal?) async {
        let previous = principal
        generation &+= 1
        let expected = generation
        principal = identity
        isEnabled = identity.map { isConfigured && preferences.bool(forKey: preferenceKey($0)) } ?? false
        if identity == nil { tokenProvider.setAutoInitEnabled(false) }
        let mayBeBound = (try? installationStore.loadIfExists()?.mayBeBound) ?? false
        if isConfigured, mayBeBound, (previous != identity || identity == nil) {
            do { try await detachWithRevision(expectedGeneration: expected) }
            catch { lastError = error }
            guard generation == expected, principal == identity else { return }
        }
        dispatchPendingTapIfReady()
        guard let identity, isEnabled, isConfigured else { return }
        let authorized = await permissionCenter.isAuthorized()
        guard generation == expected, principal == identity else { return }
        guard authorized else {
            tokenProvider.setAutoInitEnabled(false)
            preferences.set(false, forKey: preferenceKey(identity))
            isEnabled = false
            if mayBeBound {
                do { try await detachWithRevision(expectedGeneration: expected) }
                catch { if generation == expected, principal == identity { lastError = error } }
            }
            return
        }
        tokenProvider.setAutoInitEnabled(true)
        await permissionCenter.registerForRemoteNotifications()
        guard generation == expected, principal == identity else { return }
        await register(identity: identity, generation: generation)
    }

    func setEnabled(_ enabled: Bool, for identity: NotificationPrincipal) async {
        guard isConfigured else { isEnabled = false; return }
        // A delayed view task must never switch principals or reuse a newer identity's bearer.
        guard principal == identity else { return }
        let expected = generation &+ 1
        generation = expected
        guard enabled else {
            preferences.set(false, forKey: preferenceKey(identity))
            isEnabled = false
            tokenProvider.setAutoInitEnabled(false)
            do {
                try await detachWithRevision(expectedGeneration: expected)
            } catch { if generation == expected { lastError = error } }
            return
        }
        do {
            guard try await permissionCenter.requestAuthorization() else {
                guard generation == expected, principal == identity else { return }
                preferences.set(false, forKey: preferenceKey(identity))
                isEnabled = false
                return
            }
            guard generation == expected, principal == identity else { return }
            preferences.set(true, forKey: preferenceKey(identity))
            isEnabled = true
            tokenProvider.setAutoInitEnabled(true)
            await permissionCenter.registerForRemoteNotifications()
            if let token = try await tokenProvider.currentToken() {
                guard generation == expected, principal == identity else { return }
                fcmToken = token
                await register(identity: identity, generation: expected)
            }
        } catch { if generation == expected, principal == identity { lastError = error } }
    }

    /// Call before changing principal or removing a guest identity.
    func detachCurrentIdentity() async {
        generation &+= 1
        let old = principal
        principal = nil
        isEnabled = false
        tokenProvider.setAutoInitEnabled(false)
        let mayBeBound = (try? installationStore.loadIfExists()?.mayBeBound) ?? false
        guard isConfigured, old != nil || mayBeBound else { return }
        do { try await detachWithRevision(explicitBarrier: true) }
        catch { lastError = error }
    }

    func receiveFCMToken(_ token: String) async {
        guard !token.isEmpty else { return }
        fcmToken = token
        guard let principal, isEnabled, isConfigured else { return }
        await register(identity: principal, generation: generation)
    }

    func forgetDeletedAccount(_ accountID: String) async {
        let deleted = NotificationPrincipal.account(id: accountID)
        if principal == deleted { await detachCurrentIdentity() }
        preferences.removeObject(forKey: preferenceKey(deleted))
    }

    func receiveNotificationTap(_ userInfo: [AnyHashable: Any]) {
        guard let principal else { pendingTap = userInfo; return }
        guard isEnabled, let intent = GatheroryNotificationPayload.route(from: userInfo, principal: principal) else { return }
        guard let onRouteIntent else { pendingTap = userInfo; return }
        onRouteIntent(intent)
    }

    func receiveForegroundNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard isEnabled, let principal,
              GatheroryNotificationPayload.route(from: userInfo, principal: principal) != nil else { return false }
        let expected = generation
        guard await permissionCenter.isAuthorized(), generation == expected, self.principal == principal else { return false }
        onRefreshRequested?()
        return true
    }

    private func register(identity: NotificationPrincipal, generation expected: UInt64) async {
        guard isConfigured, principal == identity, generation == expected, isEnabled else { return }
        do {
            let token: String
            if let fcmToken { token = fcmToken }
            else {
                guard let resolved = try await tokenProvider.currentToken() else { return }
                token = resolved
            }
            guard principal == identity, generation == expected, isEnabled else { return }
            guard let auth = try auth(for: identity) else { return }
            guard principal == identity, generation == expected, isEnabled else { return }
            try await registerWithRevision(token: token, enabled: true, auth: auth, identity: identity, generation: expected)
            guard generation == expected, principal == identity else { return }
            lastError = nil
        } catch { if generation == expected { lastError = error } }
    }

    private func registerWithRevision(token: String, enabled: Bool, auth: NotificationAuth,
                                      identity: NotificationPrincipal, generation expected: UInt64) async throws {
        var minimum = 0
        for attempt in 0..<3 {
            guard generation == expected, principal == identity, isEnabled else { throw NotificationRegistrationFailure.superseded }
            try installationStore.markMayBeBound()
            let installation = try installationStore.nextRevision(minimum: minimum)
            do { _ = try await transport.register(installation: installation, token: token, enabled: enabled, auth: auth); return }
            catch NotificationRegistrationFailure.staleRevision(let serverRevision) where attempt < 2 {
                guard generation == expected, principal == identity, isEnabled else { throw NotificationRegistrationFailure.superseded }
                minimum = serverRevision + 1
            }
        }
        throw NotificationRegistrationFailure.invalidResponse
    }

    private func detachWithRevision(expectedGeneration: UInt64? = nil, explicitBarrier: Bool = false) async throws {
        var minimum = 0
        for attempt in 0..<3 {
            if !explicitBarrier, let expectedGeneration, generation != expectedGeneration {
                throw NotificationRegistrationFailure.superseded
            }
            try installationStore.markMayBeBound()
            let installation = try installationStore.nextRevision(minimum: minimum)
            do {
                _ = try await transport.detach(installation: installation)
                if !explicitBarrier, let expectedGeneration, generation != expectedGeneration {
                    throw NotificationRegistrationFailure.superseded
                }
                try installationStore.markDetached()
                return
            }
            catch NotificationRegistrationFailure.staleRevision(let serverRevision) where attempt < 2 {
                if !explicitBarrier, let expectedGeneration, generation != expectedGeneration {
                    throw NotificationRegistrationFailure.superseded
                }
                minimum = serverRevision + 1
            }
        }
        throw NotificationRegistrationFailure.invalidResponse
    }

    private func auth(for identity: NotificationPrincipal) throws -> NotificationAuth? {
        switch identity {
        case .account:
            guard let token = try accountTokenStore.read(), !token.isEmpty else { return nil }
            return .accountBearer(token)
        case .guest(let id):
            return .guest(id: id, proof: try guestCredentials.loadOrCreateToken(profileID: id))
        }
    }

    private func preferenceKey(_ principal: NotificationPrincipal) -> String { "notifications.enabled.\(principal.storageKey)" }

    private func dispatchPendingTapIfReady() {
        guard let pendingTap, let principal, isEnabled, let onRouteIntent else { return }
        self.pendingTap = nil
        guard let intent = GatheroryNotificationPayload.route(from: pendingTap, principal: principal) else { return }
        onRouteIntent(intent)
    }
}

@MainActor struct SystemNotificationPermissionCenter: NotificationPermissionCenter {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func registerForRemoteNotifications() async { UIApplication.shared.registerForRemoteNotifications() }
}

private nonisolated struct UnavailableNotificationRegistrationTransport: NotificationRegistrationTransport {
    func register(installation: NotificationInstallation, token: String, enabled: Bool, auth: NotificationAuth) async throws -> Int {
        throw NotificationRegistrationFailure.insecureEndpoint
    }
    func detach(installation: NotificationInstallation) async throws -> Int {
        throw NotificationRegistrationFailure.insecureEndpoint
    }
}

nonisolated enum FCMRuntimeConfiguration {
    static var isConfigured: Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "FCM_NOTIFICATIONS_ENABLED") as? String == "YES",
              let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url) as? [String: Any] else { return false }
        return ["GOOGLE_APP_ID", "GCM_SENDER_ID", "API_KEY", "PROJECT_ID", "BUNDLE_ID"]
            .allSatisfy { (values[$0] as? String)?.isEmpty == false }
            && (values["BUNDLE_ID"] as? String) == Bundle.main.bundleIdentifier
    }
}

@MainActor struct FirebaseNotificationTokenProvider: NotificationTokenProviding {
    func currentToken() async throws -> String? {
        guard FCMRuntimeConfiguration.isConfigured else { return nil }
        return try await MessagingTokenAccess.current()
    }
    func setAutoInitEnabled(_ enabled: Bool) {
        guard FCMRuntimeConfiguration.isConfigured else { return }
        Messaging.messaging().isAutoInitEnabled = enabled
    }
}

private enum MessagingTokenAccess {
    static func current() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            GatheroryFCMTokenCompatibility.fetch(messaging: Messaging.messaging()) { token, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: token) }
            }
        }
    }
}
