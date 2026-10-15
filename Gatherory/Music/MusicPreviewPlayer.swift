import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MusicPreviewPlayer {
    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed
    }

    private let player = AVPlayer()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var playbackRequestID = UUID()

    // iOS 26's synchronous audio-session API must not block the main actor.
    // Serialize activation and deactivation requests on the fallback path.
    nonisolated private static let legacyAudioSessionQueue = DispatchQueue(
        label: "com.gatherory.music-preview.audio-session"
    )

    private(set) var activeTrackID: String?
    private(set) var state: PlaybackState = .idle
    private(set) var progress = 0.0
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var durationSeconds: TimeInterval = 0
    private(set) var errorMessage: String?

    func toggle(_ track: MusicTrack) {
        guard track.previewURL != nil else { return }

        if activeTrackID == track.id {
            switch state {
            case .playing, .loading:
                pause()
            case .paused, .failed, .idle:
                play(track)
            }
        } else {
            play(track)
        }
    }

    func play(_ track: MusicTrack) {
        guard let previewURL = track.previewURL else { return }

        if activeTrackID != track.id || player.currentItem == nil || state == .failed {
            monitorTask?.cancel()
            activeTrackID = track.id
            progress = 0
            elapsedSeconds = 0
            durationSeconds = 0
            errorMessage = nil
            player.replaceCurrentItem(with: AVPlayerItem(url: previewURL))
        }

        state = .loading
        let requestID = UUID()
        playbackRequestID = requestID
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await activateAudioSession()
                try Task.checkCancellation()
                guard playbackRequestID == requestID,
                      activeTrackID == track.id,
                      state == .loading else {
                    return
                }

                player.play()
                monitor(trackID: track.id)
            } catch is CancellationError {
                // Activation itself can't be cancelled after AVFAudio accepts
                // it. If playback was paused or stopped while it completed,
                // release the session again without blocking the UI.
                if state != .loading, state != .playing {
                    requestAudioSessionDeactivation()
                }
            } catch {
                guard playbackRequestID == requestID else { return }
                fail(trackID: track.id, message: "The song preview couldn’t start.")
            }
        }
    }

    func pause() {
        guard activeTrackID != nil else { return }
        playbackRequestID = UUID()
        activationTask?.cancel()
        activationTask = nil
        monitorTask?.cancel()
        player.pause()
        state = .paused
        requestAudioSessionDeactivation()
    }

    func stop() {
        playbackRequestID = UUID()
        activationTask?.cancel()
        activationTask = nil
        monitorTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        activeTrackID = nil
        state = .idle
        progress = 0
        elapsedSeconds = 0
        durationSeconds = 0
        errorMessage = nil
        requestAudioSessionDeactivation()
    }

    func state(for track: MusicTrack) -> PlaybackState {
        activeTrackID == track.id ? state : .idle
    }

    func progress(for track: MusicTrack) -> Double {
        activeTrackID == track.id ? progress : 0
    }

    private func monitor(trackID: String) {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeTrackID == trackID else { return }
                let item = self.player.currentItem

                if item?.status == .failed {
                    self.fail(
                        trackID: trackID,
                        message: item?.error?.localizedDescription ?? "The song preview couldn’t be played."
                    )
                    return
                }

                let elapsed = self.player.currentTime().seconds
                let duration = item?.duration.seconds ?? 0
                if elapsed.isFinite, elapsed >= 0 {
                    self.elapsedSeconds = elapsed
                }
                if elapsed.isFinite, duration.isFinite, duration > 0 {
                    self.durationSeconds = duration
                    self.progress = min(max(elapsed / duration, 0), 1)
                }

                switch self.player.timeControlStatus {
                case .playing:
                    self.state = .playing
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
                case .paused:
                    if duration.isFinite, duration > 0, elapsed >= duration - 0.15 {
                        self.stop()
                        return
                    }
                @unknown default:
                    break
                }

                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func fail(trackID: String, message: String) {
        playbackRequestID = UUID()
        activationTask?.cancel()
        activationTask = nil
        monitorTask?.cancel()
        player.pause()
        activeTrackID = trackID
        state = .failed
        errorMessage = message
        requestAudioSessionDeactivation()
    }

    private func activateAudioSession() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        guard #available(iOS 27.0, *) else {
            try await Self.setLegacyAudioSessionActive(true)
            return
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            session.activate(options: []) { activated, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if activated {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: MusicPreviewAudioSessionError.activationFailed
                    )
                }
            }
        }
    }

    private func requestAudioSessionDeactivation() {
        Task {
            guard #available(iOS 27.0, *) else {
                // Match the newer API path's best-effort deactivation.
                try? await Self.setLegacyAudioSessionActive(false)
                return
            }
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                AVAudioSession.sharedInstance().deactivate(
                    options: [.notifyOthersOnDeactivation]
                ) { _, _ in
                    continuation.resume()
                }
            }
        }
    }

    nonisolated private static func setLegacyAudioSessionActive(_ active: Bool) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            legacyAudioSessionQueue.async {
                do {
                    try AVAudioSession.sharedInstance().setActive(
                        active,
                        options: active ? [] : [.notifyOthersOnDeactivation]
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private enum MusicPreviewAudioSessionError: Error {
    case activationFailed
}

struct MusicPreviewButton: View {
    @Environment(MusicPreviewPlayer.self) private var previewPlayer

    let track: MusicTrack
    var tint: Color = AppTheme.ColorToken.accent

    private var state: MusicPreviewPlayer.PlaybackState {
        previewPlayer.state(for: track)
    }

    private var accessibilityTitle: String {
        switch state {
        case .playing, .loading:
            "Pause preview of \(track.title)"
        case .paused:
            "Resume preview of \(track.title)"
        case .failed:
            "Retry preview of \(track.title)"
        case .idle:
            "Play preview of \(track.title)"
        }
    }

    var body: some View {
        Button {
            previewPlayer.toggle(track)
        } label: {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))

                Circle()
                    .stroke(tint.opacity(0.24), lineWidth: 2)

                if previewPlayer.activeTrackID == track.id,
                   state == .playing || state == .paused {
                    Circle()
                        .trim(from: 0, to: previewPlayer.progress(for: track))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                switch state {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                case .playing:
                    Image(systemName: "pause.fill")
                        .font(.callout.weight(.semibold))
                case .failed:
                    Image(systemName: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                case .idle, .paused:
                    Image(systemName: "play.fill")
                        .font(.callout.weight(.semibold))
                        .offset(x: 1)
                }
            }
            .foregroundStyle(tint)
            .frame(width: AppTheme.Layout.minimumTouchTarget, height: AppTheme.Layout.minimumTouchTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(state == .failed ? (previewPlayer.errorMessage ?? "Preview unavailable") : "")
        .accessibilityHint("Plays a short Apple Music preview in Gatherory")
    }
}
