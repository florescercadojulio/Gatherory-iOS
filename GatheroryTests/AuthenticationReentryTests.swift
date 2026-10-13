import Foundation
import Testing
@testable import Gatherory

struct AuthenticationReentryTests {
    @Test("Apple account deletion permits fresh sign-in without recreating the client")
    @MainActor
    func signInAfterDeletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationReentryProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let tokens = ReentryTokenStore()
        let client = BetterAuthClient(
            baseURL: URL(string: "https://auth-reentry.invalid")!,
            urlSession: session,
            tokenStore: tokens
        )
        let auth = AuthenticationSession(environment: .production, skipsAuthentication: false, client: client)
        func identity(_ value: String) -> AppleIdentity {
            AppleIdentity(identityToken: value, authorizationCode: value, nonce: "nonce",
                          email: nil, givenName: nil, familyName: nil)
        }
        try await auth.signInWithApple(identity("before"), requestingSignUp: false)
        #expect(auth.currentUser?.id == "before")
        try await auth.deleteAccount()
        #expect(auth.currentUser == nil)
        #expect(tokens.read() == nil)
        try await auth.signInWithApple(identity("after"), requestingSignUp: false)
        #expect(auth.currentUser?.id == "after")
        #expect(tokens.read() == "after")
    }
}

@MainActor
private final class ReentryTokenStore: SessionTokenStore {
    private var token: String?
    func read() -> String? { token }
    func save(_ token: String) { self.token = token }
    func delete() { token = nil }
}

private final class AuthenticationReentryProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // A reused client must never consult cookies or a cached auth response.
        guard !request.httpShouldHandleCookies,
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store" else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        var body: [String: Any] = [:]
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } else if let data = request.httpBody {
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let payload: [String: Any]
        var status = 200
        switch request.url!.lastPathComponent {
        case "social":
            let value = (body["idToken"] as? [String: Any])?["token"] as? String ?? "missing"
            payload = ["token": value, "user": ["id": value, "email": "test@example.com", "name": "Tester"]]
        case "apple-token":
            let code = body["authorizationCode"] as? String ?? "missing"
            if request.value(forHTTPHeaderField: "Authorization") != "Bearer \(code)" { status = 401 }
            payload = ["saved": true]
        case "delete-user":
            if request.value(forHTTPHeaderField: "Authorization") != "Bearer before" { status = 401 }
            payload = ["success": true, "message": "User deleted"]
        default:
            status = 404
            payload = [:]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
