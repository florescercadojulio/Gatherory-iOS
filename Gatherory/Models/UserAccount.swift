import Foundation

enum AccountRole: String, Codable, CaseIterable, Sendable {
    case planner
    case member

    var title: String {
        switch self {
        case .planner: "Planner"
        case .member: "Member"
        }
    }
}

enum AuthenticationProvider: String, Codable, CaseIterable, Sendable {
    case apple
    case google
    case password

    var title: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .password: "Email and password"
        }
    }
}

struct UserAccount: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var email: String
    var displayName: String
    var role: AccountRole
    var authenticationProvider: AuthenticationProvider
    var createdAt: Date
    var profileImageAssetName: String?

    init(
        id: UUID,
        email: String,
        displayName: String,
        role: AccountRole,
        authenticationProvider: AuthenticationProvider,
        createdAt: Date,
        profileImageAssetName: String? = nil
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.role = role
        self.authenticationProvider = authenticationProvider
        self.createdAt = createdAt
        self.profileImageAssetName = profileImageAssetName
    }
}

enum DevelopmentAccountFixtures {
    static let planner = UserAccount(
        id: UUID(uuidString: "47415448-4552-4F52-9950-4C414E4E4552")!,
        email: "planner@gatherory.test",
        displayName: "Gatherory Planner",
        role: .planner,
        authenticationProvider: .password,
        createdAt: Date(timeIntervalSince1970: 1_782_876_600),
        profileImageAssetName: "PlannerProfile"
    )

    static let plannerPassword = "password"
}
