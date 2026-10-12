import SwiftUI

struct MusicSearchView: View {
    @Environment(MusicCatalog.self) private var musicCatalog
    @Environment(MusicPreviewPlayer.self) private var previewPlayer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let providerID: MusicProviderID
    let onSelect: (MusicTrack) -> Void

    @State private var authorizationState: MusicAuthorizationState?
    @State private var query = ""
    @State private var results: [MusicTrack] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    init(
        providerID: MusicProviderID = .appleMusic,
        onSelect: @escaping (MusicTrack) -> Void
    ) {
        self.providerID = providerID
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            switch authorizationState {
            case nil:
                ProgressView("Checking \(providerName)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notDetermined:
                permissionView
            case .denied, .restricted:
                unavailableView
            case .authorized:
                searchResults
            }
        }
        .navigationTitle("Choose a Song")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authorizationState = musicCatalog.authorizationState(for: providerID)
        }
        .task(id: query) {
            await search()
        }
        .onDisappear {
            previewPlayer.stop()
        }
    }

    private var providerName: String {
        musicCatalog.providerName(for: providerID)
    }

    private var searchTerm: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var permissionView: some View {
        ContentUnavailableView {
            Label("Search \(providerName)", systemImage: "music.note.list")
        } description: {
            Text("Find a song and attach its title, artist, album, and artwork to this shared idea.")
        } actions: {
            Button("Continue") {
                Task {
                    authorizationState = await musicCatalog.requestAuthorization(for: providerID)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label("\(providerName) Access Is Off", systemImage: "music.note")
        } description: {
            Text("Allow music access in Settings to search for songs.")
        } actions: {
            Button("Open Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(settingsURL)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        List {
            if isSearching && results.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn’t Search \(providerName)",
                    systemImage: "exclamationmark.magnifyingglass",
                    description: Text(errorMessage)
                )
                .listRowSeparator(.hidden)
            } else if searchTerm.isEmpty {
                ContentUnavailableView(
                    "Find a Wedding Song",
                    systemImage: "music.note.list",
                    description: Text("Search by song, artist, or album.")
                )
                .listRowSeparator(.hidden)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: searchTerm)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(results) { track in
                    HStack(spacing: AppTheme.Spacing.compact) {
                        Button {
                            onSelect(track)
                            dismiss()
                        } label: {
                            MusicTrackRow(track: track, showsPreviewButton: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Adds this song to the idea")

                        if track.previewURL != nil {
                            MusicPreviewButton(track: track)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Song, artist, or album")
        .overlay(alignment: .bottom) {
            Text("Results from \(providerName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
                .allowsHitTesting(false)
        }
    }

    private func search() async {
        let term = searchTerm
        guard authorizationState == .authorized, !term.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        do {
            isSearching = true
            errorMessage = nil
            results = []
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            let matches = try await musicCatalog.searchSongs(matching: term, with: providerID)
            guard !Task.isCancelled else { return }
            results = matches
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }
}

struct MusicTrackRow: View {
    let track: MusicTrack
    var showsPreviewButton = true

    var body: some View {
        HStack(spacing: AppTheme.Spacing.standard) {
            MusicTrackArtwork(track: track)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let albumTitle = track.albumTitle {
                    Text(albumTitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppTheme.Spacing.compact)

            if showsPreviewButton, track.previewURL != nil {
                MusicPreviewButton(track: track)
            }
        }
        .contentShape(Rectangle())
    }
}

struct MusicTrackArtwork: View {
    @Environment(MusicCatalog.self) private var musicCatalog

    let track: MusicTrack
    @State private var recoveredArtworkURL: URL?

    private var artworkURL: URL? {
        track.displayArtworkURL ?? recoveredArtworkURL
    }

    var body: some View {
        AsyncImage(url: artworkURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.16)
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: track.id) {
            // Search results normally carry an artwork URL. A saved track may
            // not, however, such as when MusicKit returns a lightweight picker
            // result or an older device persisted the playlist before artwork
            // was available. Recover it from the durable catalog ID.
            guard track.displayArtworkURL == nil else { return }
            recoveredArtworkURL = await musicCatalog.artworkURL(for: track)
        }
        .accessibilityHidden(true)
    }
}

/// Artwork for Gatherory's one shared playlist per event. A custom image is
/// always respected; otherwise the first song establishes the playlist cover.
/// The catalog lookup lets old or synced tracks recover artwork that was not
/// included in their original picker payload.
struct MusicPlaylistArtwork: View {
    @Environment(MusicCatalog.self) private var musicCatalog

    let imageData: Data?
    let tracks: [MusicTrack]
    let symbol: String
    let colors: [Color]
    let accent: Color
    var ambientBlurRadius: CGFloat = 36
    var progressiveBlurRadius: CGFloat = 22
    var blurStart: CGFloat = 0.38

    @State private var recoveredArtworkURL: URL?

    private var firstTrack: MusicTrack? {
        tracks.first
    }

    private var artworkURL: URL? {
        firstTrack?.displayArtworkURL ?? recoveredArtworkURL
    }

    var body: some View {
        MediaArtwork(
            imageData: imageData,
            remoteURL: artworkURL,
            symbol: symbol,
            colors: colors,
            accent: accent,
            ambientBlurRadius: ambientBlurRadius,
            progressiveBlurRadius: progressiveBlurRadius,
            blurStart: blurStart
        )
        .task(id: firstTrack?.id) {
            guard imageData == nil,
                  let firstTrack,
                  firstTrack.displayArtworkURL == nil else {
                return
            }
            recoveredArtworkURL = await musicCatalog.artworkURL(for: firstTrack)
        }
    }
}
