import Foundation
import Security

enum RegistrationOutcome: Equatable, Sendable {
    case authenticated(UserAccount)
    case verificationRequired(email: String)
}

struct AppleIdentity: Sendable {
    let identityToken: String
    let authorizationCode: String
    let nonce: String
    let email: String?
    let givenName: String?
    let familyName: String?
}

protocol AuthenticationClient: Sendable {
    func restoreSession() async throws -> UserAccount?
    func signIn(email: String, password: String) async throws -> UserAccount
    func register(displayName: String, email: String, password: String) async throws -> RegistrationOutcome
    func signInWithApple(_ identity: AppleIdentity, requestingSignUp: Bool) async throws -> UserAccount
    func signInWithGoogle(identityToken: String, nonce: String, requestingSignUp: Bool) async throws -> UserAccount
    func deleteAccount() async throws
    func signOut() async
}

enum SecureSessionTokenError: LocalizedError {
    case unreadable(OSStatus)
    case unwritable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Gatherory couldn’t read the secure sign-in session."
        case .unwritable:
            "Gatherory couldn’t save the secure sign-in session."
        }
    }
}

protocol SessionTokenStore: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete()
}

struct KeychainSessionTokenStore: SessionTokenStore {
    private let service: String
    private let account = "better-auth-session"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.guide-systems.gatherory") {
        service = "\(bundleIdentifier).authentication"
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureSessionTokenError.unreadable(status)
        }

        return String(data: data, encoding: .utf8)
    }

    func save(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw SecureSessionTokenError.unwritable(errSecParam)
        }

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(baseQuery as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureSessionTokenError.unwritable(status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct BetterAuthClient: AuthenticationClient {
    private let baseURL: URL
    private let urlSession: URLSession
    private let tokenStore: any SessionTokenStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        urlSession: URLSession? = nil,
        tokenStore: any SessionTokenStore = KeychainSessionTokenStore()
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore

        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    func restoreSession() async throws -> UserAccount? {
        guard let token = try tokenStore.read() else { return nil }

        do {
            let result: SessionResponse? = try await request(
                path: ["get-session"],
                method: "GET",
                token: token
            )

            guard let result else {
                tokenStore.delete()
                return nil
            }
            return result.user.account(provider: .password)
        } catch AuthenticationFailure.invalidSession {
            tokenStore.delete()
            return nil
        }
    }

    func signIn(email: String, password: String) async throws -> UserAccount {
        tokenStore.delete()
        let response: AuthResponse = try await request(
            path: ["sign-in", "email"],
            body: EmailSignInRequest(email: email, password: password, rememberMe: true)
        )
        try saveToken(from: response)
        return response.user.account(provider: .password)
    }

    func register(
        displayName: String,
        email: String,
        password: String
    ) async throws -> RegistrationOutcome {
        tokenStore.delete()
        let response: AuthResponse = try await request(
            path: ["sign-up", "email"],
            body: EmailRegistrationRequest(
                name: displayName,
                email: email,
                password: password,
                rememberMe: true
            )
        )

        let bearerToken = try tokenStore.read()
        guard response.token != nil || bearerToken?.isEmpty == false else {
            return .verificationRequired(email: response.user.email)
        }

        try saveToken(from: response)
        return .authenticated(response.user.account(provider: .password))
    }

    func signInWithApple(
        _ identity: AppleIdentity,
        requestingSignUp: Bool
    ) async throws -> UserAccount {
        tokenStore.delete()
        let response: AuthResponse = try await request(
            path: ["sign-in", "social"],
            body: SocialSignInRequest(
                provider: "apple",
                idToken: .init(
                    token: identity.identityToken,
                    nonce: identity.nonce,
                    user: .init(
                        name: .init(
                            firstName: identity.givenName,
                            lastName: identity.familyName
                        ),
                        email: identity.email
                    )
                ),
                requestSignUp: requestingSignUp
            )
        )
        try saveToken(from: response)
        do {
            guard let token = try tokenStore.read() else {
                throw AuthenticationFailure.invalidSession
            }
            let receipt: AppleRevocationTokenResponse = try await request(
                path: ["apple-token"],
                body: AppleAuthorizationCodeRequest(authorizationCode: identity.authorizationCode),
                token: token
            )
            guard receipt.saved else { throw AuthenticationFailure.invalidServerResponse }
        } catch {
            // Do not leave an Apple session active without the token needed
            // to disconnect it if the user later deletes the account.
            await signOut()
            throw error
        }
        return response.user.account(provider: .apple)
    }

    func signInWithGoogle(
        identityToken: String,
        nonce: String,
        requestingSignUp: Bool
    ) async throws -> UserAccount {
        tokenStore.delete()
        let response: AuthResponse = try await request(
            path: ["sign-in", "social"],
            body: SocialSignInRequest(
                provider: "google",
                idToken: .init(token: identityToken, nonce: nonce, user: nil),
                requestSignUp: requestingSignUp
            )
        )
        try saveToken(from: response)
        return response.user.account(provider: .google)
    }

    func deleteAccount() async throws {
        guard let token = try tokenStore.read() else {
            throw AuthenticationFailure.invalidSession
        }

        let response: DeleteUserResponse = try await request(
            path: ["delete-user"],
            body: EmptyRequest(),
            token: token
        )

        guard response.success, response.message == "User deleted" else {
            throw AuthenticationFailure.invalidServerResponse
        }
        tokenStore.delete()
        await resetNetworkSession()
    }

    func signOut() async {
        let token = try? tokenStore.read()
        tokenStore.delete()
        guard let token else {
            await resetNetworkSession()
            return
        }

        let _: SignOutResponse? = try? await request(
            path: ["sign-out"],
            body: EmptyRequest(),
            token: token
        )
        await resetNetworkSession()
    }

    private func resetNetworkSession() async {
        // Keep the client reusable after deletion while discarding the
        // cookies, credentials and cached responses of the former account.
        await withCheckedContinuation { continuation in
            urlSession.reset { continuation.resume() }
        }
    }

    private func saveToken(from response: AuthResponse) throws {
        if let token = response.token, !token.isEmpty {
            try tokenStore.save(token)
            return
        }

        // Better Auth's bearer plugin can return the native session through
        // `set-auth-token` instead of duplicating it in the JSON response.
        guard let token = try tokenStore.read(), !token.isEmpty else {
            throw AuthenticationFailure.invalidSession
        }
    }

    private func request<Response: Decodable>(
        path: [String],
        method: String,
        token: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(path))
        request.httpMethod = method
        return try await perform(request, token: token)
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: [String],
        body: Body,
        token: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: endpointURL(path))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request, token: token)
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        token: String?
    ) async throws -> Response {
        var request = request
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, rawResponse) = try await urlSession.data(for: request)
            guard let response = rawResponse as? HTTPURLResponse else {
                throw AuthenticationFailure.serviceUnavailable
            }

            guard (200..<300).contains(response.statusCode) else {
                throw authenticationFailure(statusCode: response.statusCode, data: data)
            }

            if let token = response.value(forHTTPHeaderField: "set-auth-token"), !token.isEmpty {
                try tokenStore.save(token)
            }

            return try decoder.decode(Response.self, from: data)
        } catch let failure as AuthenticationFailure {
            throw failure
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .timedOut:
                throw AuthenticationFailure.networkUnavailable
            default:
                throw AuthenticationFailure.serviceUnavailable
            }
        } catch is DecodingError {
            throw AuthenticationFailure.invalidServerResponse
        }
    }

    private func authenticationFailure(statusCode: Int, data: Data) -> AuthenticationFailure {
        let response = try? decoder.decode(APIErrorResponse.self, from: data)
        switch response?.code {
        case "INVALID_EMAIL_OR_PASSWORD":
            return .invalidCredentials
        case "EMAIL_NOT_VERIFIED":
            return .emailNotVerified
        case "USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL":
            return .accountAlreadyExists
        case "INVALID_TOKEN":
            return .invalidSession
        case "SESSION_EXPIRED", "SESSION_NOT_FRESH":
            return .reauthenticationRequired
        case "PROVIDER_NOT_FOUND":
            return .providerUnavailable
        default:
            if statusCode == 401 {
                return .invalidSession
            }
            return .server(message: response?.userMessage ?? response?.message)
        }
    }

    private func endpointURL(_ path: [String]) -> URL {
        var url = baseURL
        for component in ["api", "auth"] + path {
            url.appendPathComponent(component)
        }
        return url
    }
}

private struct EmailSignInRequest: Encodable {
    let email: String
    let password: String
    let rememberMe: Bool
}

private struct EmailRegistrationRequest: Encodable {
    let name: String
    let email: String
    let password: String
    let rememberMe: Bool
}

private struct SocialSignInRequest: Encodable {
    struct IdentityToken: Encodable {
        struct User: Encodable {
            struct Name: Encodable {
                let firstName: String?
                let lastName: String?
            }

            let name: Name
            let email: String?
        }

        let token: String
        let nonce: String?
        let user: User?
    }

    let provider: String
    let idToken: IdentityToken
    let requestSignUp: Bool
}

private struct AppleAuthorizationCodeRequest: Encodable {
    let authorizationCode: String
}

private struct AppleRevocationTokenResponse: Decodable {
    let saved: Bool
}

private struct EmptyRequest: Encodable {}

private struct SignOutResponse: Decodable {
    let success: Bool
}

private struct DeleteUserResponse: Decodable {
    let success: Bool
    let message: String
}

private struct SessionResponse: Decodable {
    let user: BetterAuthUser
}

private struct AuthResponse: Decodable {
    let token: String?
    let user: BetterAuthUser
}

private struct BetterAuthUser: Decodable {
    let id: String
    let email: String
    let name: String
    let image: String?
    let createdAt: String?

    func account(provider: AuthenticationProvider) -> UserAccount {
        UserAccount(
            id: id,
            email: email,
            displayName: name,
            role: .member,
            authenticationProvider: provider,
            createdAt: createdAt.flatMap { try? Date($0, strategy: .iso8601) } ?? .now,
            profileImageURL: image.flatMap(URL.init(string:))
        )
    }
}

private struct APIErrorResponse: Decodable {
    let code: String?
    let message: String?
    let userMessage: String?
}
