import Foundation
import Observation

enum AuthenticationFailure: LocalizedError, Equatable {
    case invalidCredentials
    case invalidRegistration
    case accountAlreadyExists
    case providerUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password doesn’t match the development account."
        case .invalidRegistration:
            "Enter a name, a valid email address, and a password with at least eight characters."
        case .accountAlreadyExists:
            "An account with this email address already exists."
        case .providerUnavailable:
            "This sign-in provider will become available when the authentication backend is connected."
        }
    }
}

@Observable
final class AuthenticationSession {
    private(set) var currentUser: UserAccount?
    private(set) var developmentAccounts: [UserAccount]

    let environment: AppRuntimeConfiguration.Environment

    private var developmentPasswords: [String: String]

    var isAuthenticated: Bool {
        currentUser != nil
    }

    init(
        environment: AppRuntimeConfiguration.Environment,
        skipsAuthentication: Bool
    ) {
        self.environment = environment

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
    }

    static func bootstrap() -> AuthenticationSession {
        AuthenticationSession(
            environment: AppRuntimeConfiguration.environment,
            skipsAuthentication: AppRuntimeConfiguration.skipsAuthentication
        )
    }

    func signIn(email: String, password: String) throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard
            let account = developmentAccounts.first(where: { $0.email.lowercased() == normalizedEmail }),
            developmentPasswords[normalizedEmail] == password
        else {
            throw AuthenticationFailure.invalidCredentials
        }

        currentUser = account
    }

    func register(displayName: String, email: String, password: String) throws {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard
            environment == .development,
            !normalizedName.isEmpty,
            normalizedEmail.contains("@"),
            password.count >= 8
        else {
            throw AuthenticationFailure.invalidRegistration
        }

        guard !developmentAccounts.contains(where: { $0.email.lowercased() == normalizedEmail }) else {
            throw AuthenticationFailure.accountAlreadyExists
        }

        let account = UserAccount(
            id: UUID(),
            email: normalizedEmail,
            displayName: normalizedName,
            role: .member,
            authenticationProvider: .password,
            createdAt: .now
        )
        developmentAccounts.append(account)
        developmentPasswords[normalizedEmail] = password
        currentUser = account
    }

    func signIn(using provider: AuthenticationProvider) throws {
        guard environment == .development else {
            throw AuthenticationFailure.providerUnavailable
        }

        var planner = DevelopmentAccountFixtures.planner
        planner.authenticationProvider = provider
        currentUser = planner
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
        currentUser = nil
    }
}
