import SwiftUI

struct MusicSearchView: View {
    @Environment(MusicCatalog.self) private var musicCatalog
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
    }

    private var providerName: String {
        musicCatalog.providerName(for: providerID)
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
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "Find a Wedding Song",
                    systemImage: "music.note.list",
                    description: Text("Search by song, artist, or album.")
                )
                .listRowSeparator(.hidden)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(results) { track in
                    Button {
                        onSelect(track)
                        dismiss()
                    } label: {
                        MusicTrackRow(track: track)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds this song to the idea")
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
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authorizationState == .authorized, !term.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            isSearching = true
            errorMessage = nil
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
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct MusicTrackArtwork: View {
    let track: MusicTrack

    var body: some View {
        AsyncImage(url: track.artworkURL) { phase in
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
        .accessibilityHidden(true)
    }
}
