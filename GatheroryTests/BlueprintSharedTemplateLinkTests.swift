import Foundation
import Testing
@testable import Gatherory

struct BlueprintSharedTemplateLinkTests {
    private let token = String(repeating: "a1", count: 32)

    @Test("Configured HTTPS shared-template URLs resolve only on the configured origin and exact path")
    func httpsRouteValidation() throws {
        let base = try #require(URL(string: "https://dev.gatherory.com"))
        let valid = try #require(URL(string: "https://dev.gatherory.com/templates/shared/\(token)"))
        #expect(BlueprintSharedTemplateLink.token(from: valid, baseURL: base) == token)

        for string in [
            "https://other.gatherory.com/templates/shared/\(token)",
            "http://dev.gatherory.com/templates/shared/\(token)",
            "https://dev.gatherory.com/templates/shared/\(token)?from=email",
            "https://dev.gatherory.com/templates/shared/\(token)#fragment",
            "https://dev.gatherory.com/templates/shared/\(token)/extra",
            "https://dev.gatherory.com/other/shared/\(token)",
            "https://user:secret@dev.gatherory.com/templates/shared/\(token)"
        ] {
            let url = try #require(URL(string: string))
            #expect(BlueprintSharedTemplateLink.token(from: url, baseURL: base) == nil)
        }
    }

    @Test("The Gatherory custom URL scheme is accepted with the same bearer-token format")
    func customSchemeRouteValidation() throws {
        let url = try #require(URL(string: "gatherory://template/\(token)"))
        #expect(BlueprintSharedTemplateLink.token(from: url, baseURL: nil) == token)
        #expect(BlueprintSharedTemplateLink.token(
            from: try #require(URL(string: "gatherory://other/\(token)")), baseURL: nil
        ) == nil)
    }

    @Test("Tokens require exactly 64 lowercase hexadecimal characters")
    func strictTokenFormat() throws {
        #expect(BlueprintSharedTemplateLink.isValidToken(token))
        #expect(!BlueprintSharedTemplateLink.isValidToken(String(repeating: "A", count: 64)))
        #expect(!BlueprintSharedTemplateLink.isValidToken(String(repeating: "a", count: 63)))
        #expect(!BlueprintSharedTemplateLink.isValidToken(String(repeating: "g", count: 64)))
        let uppercaseToken = String(repeating: "A", count: 64)
        #expect(BlueprintSharedTemplateLink.token(
            from: try #require(URL(string: "https://dev.gatherory.com/templates/shared/\(uppercaseToken)")),
            baseURL: URL(string: "https://dev.gatherory.com")
        ) == nil)
    }

    @Test("Incoming links stay in memory and clear when dismissed")
    @MainActor
    func routerKeepsTokenOnlyForCurrentHandoff() throws {
        let base = URL(string: "https://dev.gatherory.com")
        let router = BlueprintSharedTemplateRouter(baseURL: base)
        let url = try #require(URL(string: "https://dev.gatherory.com/templates/shared/\(token)"))

        #expect(router.receive(url))
        #expect(router.pendingToken == token)
        router.dismiss()
        #expect(router.pendingToken == nil)
    }
}
