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
    let previewURL: URL?
    let externalURL: URL?
    let isrc: String?
    let duration: TimeInterval?

    init(
        providerID: MusicProviderID,
        catalogID: String,
        title: String,
        artistName: String,
        albumTitle: String?,
        artworkURL: URL?,
        previewURL: URL? = nil,
        externalURL: URL?,
        isrc: String?,
        duration: TimeInterval?
    ) {
        self.providerID = providerID
        self.catalogID = catalogID
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.artworkURL = artworkURL
        self.previewURL = previewURL
        self.externalURL = externalURL
        self.isrc = isrc
        self.duration = duration
    }
}

extension MusicTrack {
    init(appleMusicSong song: Song) {
        self.init(
            providerID: .appleMusic,
            catalogID: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            artworkURL: song.artwork?.url(width: 600, height: 600),
            previewURL: song.previewAssets?.compactMap(\.url).first,
            externalURL: song.url,
            isrc: song.isrc,
            duration: song.duration
        )
    }
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
    /// Looks up fresh artwork from the provider using the durable catalog ID
    /// we store with a shared song. Artwork URLs are deliberately treated as
    /// cacheable display data, not the source of truth for a track.
    func artworkURL(for track: MusicTrack) async -> URL?
}

extension MusicCatalogProviding {
    func artworkURL(for track: MusicTrack) async -> URL? {
        nil
    }
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
        return response.songs.map(MusicTrack.init(appleMusicSong:))
    }

    func artworkURL(for track: MusicTrack) async -> URL? {
        guard track.providerID == id else { return nil }
        return await AppleMusicArtworkLookup.shared.artworkURL(for: track.catalogID)
    }
}

/// A failed or omitted artwork URL must not make a shared playlist look
/// incomplete. Apple Music catalog IDs survive local persistence and cloud
/// sync, so use them to recover artwork on the device that is rendering it.
private actor AppleMusicArtworkLookup {
    static let shared = AppleMusicArtworkLookup()

    private var cachedURLs: [String: URL?] = [:]

    func artworkURL(for catalogID: String) async -> URL? {
        if let cachedURL = cachedURLs[catalogID] {
            return cachedURL
        }

        let artworkURL: URL?
        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(catalogID)
            )
            let response = try await request.response()
            artworkURL = response.items.first?.artwork?.url(width: 900, height: 900)
        } catch {
            artworkURL = nil
        }

        cachedURLs[catalogID] = artworkURL
        return artworkURL
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

    func artworkURL(for track: MusicTrack) async -> URL? {
        guard let provider = provider(for: track.providerID) else { return nil }
        return await provider.artworkURL(for: track)
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
