import Foundation
import Observation
import PostHog

enum AuthenticationFailure: LocalizedError, Equatable {
    case invalidCredentials
    case invalidRegistration
    case accountAlreadyExists
    case providerUnavailable
    case emailNotVerified
    case invalidSession
    case reauthenticationRequired
    case networkUnavailable
    case serviceUnavailable
    case invalidServerResponse
    case server(message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect."
        case .invalidRegistration:
            "Enter a name, a valid email address, and a password with at least eight characters."
        case .accountAlreadyExists:
            "An account with this email address already exists."
        case .providerUnavailable:
            "This sign-in provider isn’t available right now."
        case .emailNotVerified:
            "Verify your email address, then try signing in again."
        case .invalidSession:
            "Your session has expired. Sign in again to continue."
        case .reauthenticationRequired:
            "For security, sign out and sign in again before deleting your account."
        case .networkUnavailable:
            "Gatherory couldn’t reach the sign-in service. Check your connection and try again."
        case .serviceUnavailable:
            "The sign-in service is temporarily unavailable. Try again in a moment."
        case .invalidServerResponse:
            "Gatherory received an unexpected response from the sign-in service."
        case .server(let message):
            message ?? "Gatherory couldn’t complete the sign-in request."
        }
    }
}

@Observable
@MainActor
final class AuthenticationSession {
    private(set) var currentUser: UserAccount?
    private(set) var developmentAccounts: [UserAccount]
    private(set) var isProcessing = false
    private(set) var registrationNotice: String?

    let environment: AppRuntimeConfiguration.Environment

    private var developmentPasswords: [String: String]
    private let client: (any AuthenticationClient)?

    var isAuthenticated: Bool {
        currentUser != nil
    }

    init(
        environment: AppRuntimeConfiguration.Environment,
        skipsAuthentication: Bool,
        client: (any AuthenticationClient)? = nil
    ) {
        self.environment = environment
        self.client = client

        if environment == .development {
            let planner = DevelopmentAccountFixtures.planner
            developmentAccounts = [planner]
            developmentPasswords = [
                planner.email.lowercased(): DevelopmentAccountFixtures.plannerPassword
            ]
            currentUser = skipsAuthentication ? planner : nil
        } else {
            developmentAccounts = []
            developmentPasswords = [:]
            currentUser = nil
        }

        if let currentUser {
            identify(currentUser)
        }
    }

    static func bootstrap() -> AuthenticationSession {
        let client = AppRuntimeConfiguration.authenticationBaseURL.map {
            BetterAuthClient(baseURL: $0)
        }
        return AuthenticationSession(
            environment: AppRuntimeConfiguration.environment,
            skipsAuthentication: AppRuntimeConfiguration.skipsAuthentication,
            client: client
        )
    }

    func restoreSession() async {
        guard currentUser == nil, let client else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            currentUser = try await client.restoreSession()
            if let currentUser {
                identify(currentUser)
            } else {
                PostHogSDK.shared.reset()
            }
        } catch {
            // A failed refresh must never manufacture an authenticated state.
            // The login screen will surface errors when the user actively retries.
            currentUser = nil
            PostHogSDK.shared.reset()
        }
    }

    func signIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        registrationNotice = nil

        if let client {
            isProcessing = true
            defer { isProcessing = false }
            let account = try await client.signIn(email: normalizedEmail, password: password)
            currentUser = account
            identify(account)
            return
        }

        guard
            let account = developmentAccounts.first(where: { $0.email.lowercased() == normalizedEmail }),
            developmentPasswords[normalizedEmail] == password
        else {
            throw AuthenticationFailure.invalidCredentials
        }

        currentUser = account
        identify(account)
    }

    func clearRegistrationNotice() {
        registrationNotice = nil
    }

    func register(displayName: String, email: String, password: String) async throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard
            !normalizedName.isEmpty,
            normalizedEmail.contains("@"),
            password.count >= 8
        else {
            throw AuthenticationFailure.invalidRegistration
        }

        registrationNotice = nil

        if let client {
            isProcessing = true
            defer { isProcessing = false }

            switch try await client.register(
                displayName: normalizedName,
                email: normalizedEmail,
                password: password
            ) {
            case .authenticated(let account):
                currentUser = account
                identify(account)
            case .verificationRequired(let email):
                currentUser = nil
                registrationNotice = "Check \(email) for a verification link, then sign in."
            }
            return
        }

        guard environment == .development else {
            throw AuthenticationFailure.serviceUnavailable
        }

        guard !developmentAccounts.contains(where: { $0.email.lowercased() == normalizedEmail }) else {
            throw AuthenticationFailure.accountAlreadyExists
        }

        let account = UserAccount(
            id: UUID().uuidString,
            email: normalizedEmail,
            displayName: normalizedName,
            role: .member,
            authenticationProvider: .password,
            createdAt: .now
        )
        developmentAccounts.append(account)
        developmentPasswords[normalizedEmail] = password
        currentUser = account
        identify(account)
    }

    func signIn(using provider: AuthenticationProvider) async throws {
        registrationNotice = nil
        guard environment == .development, client == nil else {
            throw AuthenticationFailure.providerUnavailable
        }

        var planner = DevelopmentAccountFixtures.planner
        planner.authenticationProvider = provider
        currentUser = planner
        identify(planner)
    }

    func signInWithApple(
        _ identity: AppleIdentity,
        requestingSignUp: Bool
    ) async throws {
        registrationNotice = nil

        guard let client else {
            try await signIn(using: .apple)
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        let account = try await client.signInWithApple(
            identity,
            requestingSignUp: requestingSignUp
        )
        currentUser = account
        identify(account)
    }

    func signInWithGoogle(
        identityToken: String,
        nonce: String,
        requestingSignUp: Bool
    ) async throws {
        registrationNotice = nil

        guard let client else {
            try await signIn(using: .google)
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        let account = try await client.signInWithGoogle(
            identityToken: identityToken,
            nonce: nonce,
            requestingSignUp: requestingSignUp
        )
        currentUser = account
        identify(account)
    }

    @discardableResult
    func updateProfile(displayName: String) -> Bool {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, var account = currentUser else { return false }

        account.displayName = normalizedName
        currentUser = account

        if let index = developmentAccounts.firstIndex(where: { $0.id == account.id }) {
            developmentAccounts[index] = account
        }
        return true
    }

    func signOut() {
        PostHogSDK.shared.reset()
        currentUser = nil
        registrationNotice = nil

        guard let client else { return }
        Task {
            await client.signOut()
        }
    }

    func deleteAccount() async throws {
        guard let account = currentUser else {
            throw AuthenticationFailure.invalidSession
        }

        isProcessing = true
        defer { isProcessing = false }

        if let client {
            try await client.deleteAccount()
        } else {
            developmentAccounts.removeAll { $0.id == account.id }
            developmentPasswords.removeValue(forKey: account.email.lowercased())
        }

        PostHogSDK.shared.reset()
        currentUser = nil
        registrationNotice = nil
    }

    private func identify(_ account: UserAccount) {
        PostHogSDK.shared.identify(
            account.id,
            userProperties: [
                "role": account.role.rawValue,
                "authentication_provider": account.authenticationProvider.rawValue
            ]
        )
    }
}
