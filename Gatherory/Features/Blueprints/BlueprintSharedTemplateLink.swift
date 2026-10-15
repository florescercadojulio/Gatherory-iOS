import Foundation
import Observation

nonisolated enum BlueprintSharedTemplateLink {
    static func token(from url: URL, baseURL: URL?) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        let token: String
        if components.scheme?.lowercased() == "gatherory" {
            guard components.host?.lowercased() == "template", components.port == nil else { return nil }
            let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].isEmpty else { return nil }
            token = String(parts[1])
        } else {
            guard let baseURL,
                  let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
                  base.scheme?.lowercased() == "https",
                  components.scheme?.lowercased() == base.scheme?.lowercased(),
                  components.host?.lowercased() == base.host?.lowercased(),
                  components.port == base.port else { return nil }
            let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 4,
                  parts[0].isEmpty,
                  parts[1] == "templates",
                  parts[2] == "shared" else { return nil }
            token = String(parts[3])
        }
        return isValidToken(token) ? token : nil
    }

    static func isValidToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
}

/// Holds an incoming unlisted link while sign-in and account activation finish.
/// The bearer token stays in memory and is never added to Explore history.
@MainActor @Observable
final class BlueprintSharedTemplateRouter {
    private(set) var pendingToken: String?
    private let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let token = BlueprintSharedTemplateLink.token(from: url, baseURL: baseURL) else { return false }
        pendingToken = token
        return true
    }

    func dismiss() {
        pendingToken = nil
    }
}
