import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AnnouncementSessionGenerationTests {
    @Test("Returning to the same account invalidates requests from its earlier session")
    func accountReturnAdvancesGeneration() async throws {
        let session = AuthenticationSession(environment: .development, skipsAuthentication: false,
            guestProfileStore: MemoryLocalGuestProfileStore(), guestCredentialStore: MemoryLocalGuestCredentialStore())
        try await session.signIn(using: .apple)
        let first = session.principalGeneration
        let identity = session.notificationPrincipal
        #expect(await session.signOut())
        try await session.signIn(using: .apple)
        #expect(session.notificationPrincipal == identity)
        #expect(session.principalGeneration > first)
    }

    @Test("Editing a guest display name preserves its existing request identity")
    func guestNamePreservesGeneration() throws {
        let profiles = MemoryLocalGuestProfileStore()
        let firstProfile = LocalGuestProfile(displayName: "First guest")
        try profiles.save(firstProfile)
        let session = AuthenticationSession(environment: .development, skipsAuthentication: false,
            guestProfileStore: profiles, guestCredentialStore: MemoryLocalGuestCredentialStore())
        let generation = session.principalGeneration
        // A name-only edit keeps the same guest ID and does not create another session.
        try session.continueAsGuest(displayName: "Changed name")
        #expect(session.localGuestProfile?.id == firstProfile.id)
        #expect(session.principalGeneration == generation)
    }
}
