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
    /// Artwork returned for a library item can use MusicKit's private URL
    /// scheme. `AsyncImage` can only load web URLs, so keep that reference as
    /// metadata and recover a catalog image before rendering it.
    var displayArtworkURL: URL? {
        guard let artworkURL,
              let scheme = artworkURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        return artworkURL
    }

    init(appleMusicSong song: Song) {
        self.init(
            providerID: .appleMusic,
            catalogID: song.id.rawValue,
            title: song.title,
            artistName: song.artistName,
            albumTitle: song.albumTitle,
            artworkURL: song.artwork?.url(width: 600, height: 600).flatMap { url in
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "https" || scheme == "http" else {
                    return nil
                }
                return url
            },
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
        if let artworkURL = track.displayArtworkURL {
            return artworkURL
        }

        return await AppleMusicArtworkLookup.shared.artworkURL(
            catalogID: track.catalogID,
            title: track.title,
            artistName: track.artistName,
            cacheKey: "\(track.providerID.rawValue):\(track.catalogID)"
        )
    }
}

/// A failed or omitted artwork URL must not make a shared playlist look
/// incomplete. Apple Music catalog IDs survive local persistence and cloud
/// sync, so use them to recover artwork on the device that is rendering it.
private actor AppleMusicArtworkLookup {
    static let shared = AppleMusicArtworkLookup()

    private var cachedURLs: [String: URL?] = [:]

    /// Authorization can change after a failed catalog or library lookup.
    /// Drop display-only URLs so visible playlist artwork can be resolved from
    /// the newly available MusicKit session.
    func invalidateCache() {
        cachedURLs.removeAll()
    }

    func artworkURL(
        catalogID: String,
        title: String,
        artistName: String,
        cacheKey: String
    ) async -> URL? {
        if let cachedURL = cachedURLs[cacheKey] {
            return cachedURL
        }

        // Catalog IDs can be resolved directly. Library IDs (for example
        // `i.…`) belong to the signed-in person's library, so try that lookup
        // first and fall back to the public catalog using the durable song
        // metadata. The catalog result has an HTTPS artwork URL that every
        // participant can render.
        let artworkURL: URL?
        if let catalogArtworkURL = await catalogArtworkURL(for: catalogID) {
            artworkURL = catalogArtworkURL
        } else if let libraryArtworkURL = await libraryArtworkURL(for: catalogID) {
            artworkURL = libraryArtworkURL
        } else {
            artworkURL = await searchedArtworkURL(title: title, artistName: artistName)
        }

        cachedURLs[cacheKey] = artworkURL
        return artworkURL
    }

    private func catalogArtworkURL(for catalogID: String) async -> URL? {
        do {
            let request = MusicCatalogResourceRequest<Song>(
                matching: \.id,
                equalTo: MusicItemID(catalogID)
            )
            let response = try await request.response()
            return response.items.first?.artwork?.url(width: 900, height: 900).flatMap(webArtworkURL)
        } catch {
            return nil
        }
    }

    private func libraryArtworkURL(for libraryID: String) async -> URL? {
        do {
            var request = MusicLibraryRequest<Song>()
            request.filter(matching: \.id, equalTo: MusicItemID(libraryID))
            let response = try await request.response()
            return response.items.first?.artwork?.url(width: 900, height: 900).flatMap(webArtworkURL)
        } catch {
            return nil
        }
    }

    private func searchedArtworkURL(title: String, artistName: String) async -> URL? {
        do {
            var request = MusicCatalogSearchRequest(
                term: "\(title) \(artistName)",
                types: [Song.self]
            )
            request.limit = 10
            let response = try await request.response()
            let song = response.songs.first(where: {
                $0.title.caseInsensitiveCompare(title) == .orderedSame
                    && $0.artistName.caseInsensitiveCompare(artistName) == .orderedSame
            }) ?? response.songs.first
            return song?.artwork?.url(width: 900, height: 900).flatMap(webArtworkURL)
        } catch {
            return nil
        }
    }

    private func webArtworkURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}

@MainActor
@Observable
final class MusicCatalog {
    private let providers: [any MusicCatalogProviding]
    private var observedAuthorizationStates: [MusicProviderID: MusicAuthorizationState] = [:]

    /// Views include this value in their artwork task identity. Incrementing
    /// it deliberately retries persisted tracks whose first lookup happened
    /// before the person approved Music access.
    private(set) var artworkRefreshRevision = 0

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
        let state = await provider.requestAuthorization()
        await recordAuthorizationState(state, for: id)
        return state
    }

    /// Rechecks provider access when the app returns from Settings. This is
    /// intentionally separate from rendering so the app can recover artwork
    /// without making the person reopen each playlist.
    func refreshAuthorizationStates() async {
        for provider in providers {
            await recordAuthorizationState(provider.authorizationState(), for: provider.id)
        }
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

    private func recordAuthorizationState(
        _ state: MusicAuthorizationState,
        for id: MusicProviderID
    ) async {
        let previousState = observedAuthorizationStates[id]
        observedAuthorizationStates[id] = state

        guard state == .authorized, previousState != .authorized else { return }

        if id == .appleMusic {
            await AppleMusicArtworkLookup.shared.invalidateCache()
        }
        artworkRefreshRevision &+= 1
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
