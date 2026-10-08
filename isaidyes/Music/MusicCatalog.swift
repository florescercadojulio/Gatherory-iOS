import Foundation
import MusicKit
import Observation

struct MusicProviderID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let appleMusic = MusicProviderID(rawValue: "apple-music")
    static let spotify = MusicProviderID(rawValue: "spotify")

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        default: rawValue
        }
    }
}

struct MusicTrack: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(providerID.rawValue):\(catalogID)" }

    let providerID: MusicProviderID
    let catalogID: String
    let title: String
    let artistName: String
    let albumTitle: String?
    let artworkURL: URL?
    let externalURL: URL?
    let isrc: String?
    let duration: TimeInterval?
}

enum MusicAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

protocol MusicCatalogProviding: Sendable {
    var id: MusicProviderID { get }
    var displayName: String { get }

    func authorizationState() -> MusicAuthorizationState
    func requestAuthorization() async -> MusicAuthorizationState
    func searchSongs(matching term: String, limit: Int) async throws -> [MusicTrack]
}

struct AppleMusicCatalogProvider: MusicCatalogProviding {
    let id = MusicProviderID.appleMusic
    let displayName = "Apple Music"

    func authorizationState() -> MusicAuthorizationState {
        MusicAuthorization.currentStatus.catalogState
    }

    func requestAuthorization() async -> MusicAuthorizationState {
        await MusicAuthorization.request().catalogState
    }

    func searchSongs(matching term: String, limit: Int) async throws -> [MusicTrack] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit

        let response = try await request.response()
        return response.songs.map { song in
            MusicTrack(
                providerID: id,
                catalogID: song.id.rawValue,
                title: song.title,
                artistName: song.artistName,
                albumTitle: song.albumTitle,
                artworkURL: song.artwork?.url(width: 600, height: 600),
                externalURL: song.url,
                isrc: song.isrc,
                duration: song.duration
            )
        }
    }
}

@MainActor
@Observable
final class MusicCatalog {
    private let providers: [any MusicCatalogProviding]

    init(providers: [any MusicCatalogProviding]? = nil) {
        self.providers = providers ?? [AppleMusicCatalogProvider()]
    }

    func providerName(for id: MusicProviderID) -> String {
        provider(for: id)?.displayName ?? id.displayName
    }

    func authorizationState(for id: MusicProviderID) -> MusicAuthorizationState {
        provider(for: id)?.authorizationState() ?? .restricted
    }

    func requestAuthorization(for id: MusicProviderID) async -> MusicAuthorizationState {
        guard let provider = provider(for: id) else { return .restricted }
        return await provider.requestAuthorization()
    }

    func searchSongs(
        matching term: String,
        with id: MusicProviderID,
        limit: Int = 25
    ) async throws -> [MusicTrack] {
        guard let provider = provider(for: id) else {
            throw MusicCatalogError.providerUnavailable(id)
        }
        return try await provider.searchSongs(matching: term, limit: limit)
    }

    private func provider(for id: MusicProviderID) -> (any MusicCatalogProviding)? {
        providers.first { $0.id == id }
    }
}

enum MusicCatalogError: LocalizedError {
    case providerUnavailable(MusicProviderID)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let id):
            "\(id.displayName) isn’t available right now."
        }
    }
}

private extension MusicAuthorization.Status {
    var catalogState: MusicAuthorizationState {
        switch self {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}
