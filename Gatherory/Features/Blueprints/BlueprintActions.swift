import Foundation
import Observation

enum BlueprintPreferenceKind: String, Codable, CaseIterable, Sendable {
    case like, bookmark, notInterested
}

struct BlueprintPreferenceMutation: Codable, Sendable {
    let requestId: UUID
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let kind: BlueprintPreferenceKind
    let enabled: Bool
}

struct BlueprintPreferenceAcknowledgement: Decodable, Equatable, Sendable {
    let requestId: UUID
    let catalogKey: String
    let revision: Int
    let contentHash: String
    let liked: Bool
    let bookmarked: Bool
    let notInterested: Bool

    var state: BlueprintViewerState {
        .init(liked: liked, bookmarked: bookmarked, notInterested: notInterested)
    }
}

struct BlueprintSavedPreference: Decodable, Identifiable, Equatable, Sendable {
    struct Entry: Decodable, Equatable, Sendable {
        let name: String
        var coverImageURL: String? = nil
        var creatorName: String? = nil
    }

    let catalogKey: String
    let revision: Int
    let contentHash: String
    let liked: Bool
    let bookmarked: Bool
    let notInterested: Bool
    var likeRevision: Int? = nil
    var likeContentHash: String? = nil
    var bookmarkRevision: Int? = nil
    var bookmarkContentHash: String? = nil
    var notInterestedRevision: Int? = nil
    var notInterestedContentHash: String? = nil
    var likeAvailability: String? = nil
    let bookmarkAvailability: String
    var notInterestedAvailability: String? = nil
    var entry: Entry? = nil
    var id: String { catalogKey }
    var isAvailable: Bool { bookmarkAvailability == "available" && entry != nil }
    var isLikeAvailable: Bool { (likeAvailability ?? bookmarkAvailability) == "available" && entry != nil }
    var isNotInterestedAvailable: Bool {
        (notInterestedAvailability ?? bookmarkAvailability) == "available" && entry != nil
    }

    func binding(for kind: BlueprintPreferenceKind) -> (revision: Int, contentHash: String) {
        switch kind {
        case .like:
            return (likeRevision ?? revision, likeContentHash ?? contentHash)
        case .bookmark:
            return (bookmarkRevision ?? revision, bookmarkContentHash ?? contentHash)
        case .notInterested:
            return (notInterestedRevision ?? revision, notInterestedContentHash ?? contentHash)
        }
    }
}

struct BlueprintPreferencesPage: Decodable, Sendable {
    let items: [BlueprintSavedPreference]
    var nextCursor: String? = nil
}

struct BlueprintMeasurementSettings: Codable, Equatable, Sendable {
    let enabled: Bool
}

enum BlueprintMeasurementSignalKind: String, Codable, Sendable { case impression, open }

enum BlueprintImpressionPolicy {
    static let visibilityThreshold: CGFloat = 0.5
    static let minimumDuration: TimeInterval = 1

    static func qualifies(visibleFraction: Double, visibleDuration: TimeInterval,
                          sceneIsActive: Bool, previewIsPresented: Bool) -> Bool {
        visibleFraction >= Double(visibilityThreshold) && visibleDuration >= minimumDuration
            && sceneIsActive && !previewIsPresented
    }
}

struct BlueprintMeasurementSignal: Codable, Sendable {
    let requestId: UUID
    let exposureId: String
    let kind: BlueprintMeasurementSignalKind
}

@MainActor
protocol BlueprintActionsTransport {
    func update(_ mutation: BlueprintPreferenceMutation) async throws -> BlueprintPreferenceAcknowledgement
    func preferences(cursor: String?) async throws -> BlueprintPreferencesPage
    func measurementSettings() async throws -> BlueprintMeasurementSettings
    func setMeasurementSettings(requestID: UUID, enabled: Bool) async throws -> BlueprintMeasurementSettings
    func record(_ signal: BlueprintMeasurementSignal) async throws
}

/// Account-bound remote preferences. Commands are serialized and local state
/// changes only after the server acknowledges the exact requested revision.
@MainActor @Observable
final class BlueprintActionStore {
    private(set) var states: [String: BlueprintViewerState] = [:]
    private(set) var savedItems: [BlueprintSavedPreference] = []
    private(set) var measurementEnabled = false
    private(set) var isLoading = false
    private(set) var preferencesLoadFailed = false
    private(set) var error: Error?
    let ownerID: String
    private let transport: any BlueprintActionsTransport
    private var generation = UUID()
    private var preferencesLoadGeneration = UUID()
    private var mutationGeneration: UInt64 = 0
    private var mutationGenerationByKey: [String: UInt64] = [:]
    private var measurementSettingGeneration: UInt64 = 0
    private var measurementSettingIntentGeneration: UInt64 = 0
    private var commandTail: Task<Void, Never>?
    private var commandTasks: [UUID: Task<Bool, Never>] = [:]
    private var pending: [String: BlueprintPreferenceMutation] = [:]
    private var pendingMeasurementSetting: (requestID: UUID, enabled: Bool)?
    private var lastFailedMutation: BlueprintPreferenceMutation?
    private var lastFailedEntry: BlueprintCatalogEntry?
    private var lastFailedSavedItem: BlueprintSavedPreference?
    private var sentSignals = Set<String>()
    var sessionIdentity: UUID { generation }

    func isCurrentSession(_ identity: UUID) -> Bool { generation == identity }

    /// Resolves a collection reference only against freshly fetched public data.
    /// Personal list rows never carry a private or stale Blueprint definition.
    func publicEntry(for item: BlueprintSavedPreference,
                     in currentPublicEntries: [BlueprintCatalogEntry]) -> BlueprintCatalogEntry? {
        guard !ownerID.isEmpty,
              let current = currentPublicEntries
            .filter({ $0.catalogKey == item.catalogKey && $0.definition.supportsCurrentSchema })
            .max(by: { $0.revision < $1.revision }) else { return nil }
        let viewerState = current.viewerState ?? states[item.catalogKey]
            ?? BlueprintViewerState(liked: item.liked, bookmarked: item.bookmarked,
                                    notInterested: item.notInterested)
        return BlueprintCatalogEntry(catalogKey: current.catalogKey, revision: current.revision,
            contentHash: current.contentHash, definition: current.definition,
            discovery: current.discovery, description: current.description, creator: current.creator,
            viewerState: viewerState, discoveryContext: nil)
    }

    init(ownerID: String, transport: any BlueprintActionsTransport) {
        self.ownerID = ownerID
        self.transport = transport
    }

    func resetForAccountChange() {
        generation = UUID()
        preferencesLoadGeneration = UUID()
        mutationGeneration = 0
        mutationGenerationByKey = [:]
        measurementSettingGeneration = 0
        measurementSettingIntentGeneration = 0
        commandTail?.cancel()
        commandTail = nil
        commandTasks.values.forEach { $0.cancel() }
        commandTasks.removeAll()
        states = [:]
        savedItems = []
        measurementEnabled = false
        preferencesLoadFailed = false
        pending = [:]
        pendingMeasurementSetting = nil
        sentSignals = []
        error = nil
        lastFailedMutation = nil
        lastFailedEntry = nil
        lastFailedSavedItem = nil
        isLoading = false
    }

    func loadPreferences() async {
        let token = generation
        let loadToken = UUID()
        preferencesLoadGeneration = loadToken
        let mutationSnapshot = mutationGeneration
        preferencesLoadFailed = false
        isLoading = true
        defer {
            if token == generation, loadToken == preferencesLoadGeneration {
                isLoading = false
            }
        }
        do {
            var cursor: String?
            var seenCursors = Set<String>()
            var pageCount = 0
            var received: [BlueprintSavedPreference] = []
            repeat {
                if let cursor, !seenCursors.insert(cursor).inserted { throw CloudSyncFailure.invalidResponse }
                pageCount += 1
                guard pageCount <= 1_000 else { throw CloudSyncFailure.invalidResponse }
                let page = try await transport.preferences(cursor: cursor)
                guard token == generation, loadToken == preferencesLoadGeneration,
                      !Task.isCancelled else { return }
                received.append(contentsOf: page.items)
                cursor = page.nextCursor
            } while cursor != nil
            guard token == generation, loadToken == preferencesLoadGeneration,
                  !Task.isCancelled else { return }
            let changedKeys = Set(mutationGenerationByKey.compactMap { key, revision in
                revision > mutationSnapshot ? key : nil
            })
            var mergedStates = Dictionary(uniqueKeysWithValues: received.map {
                ($0.catalogKey, BlueprintViewerState(liked: $0.liked, bookmarked: $0.bookmarked,
                                                       notInterested: $0.notInterested))
            })
            for key in changedKeys {
                if let state = states[key] { mergedStates[key] = state }
                else { mergedStates.removeValue(forKey: key) }
            }
            states = mergedStates

            var mergedItems = Dictionary(uniqueKeysWithValues: received.map { ($0.catalogKey, $0) })
            for key in changedKeys {
                if let local = savedItems.first(where: { $0.catalogKey == key }) { mergedItems[key] = local }
                else { mergedItems.removeValue(forKey: key) }
            }
            savedItems = mergedItems.values.sorted { $0.catalogKey < $1.catalogKey }
            preferencesLoadFailed = false
        } catch {
            guard token == generation, loadToken == preferencesLoadGeneration,
                  !Task.isCancelled else { return }
            preferencesLoadFailed = true
        }
    }

    func loadMeasurementSetting() async {
        let token = generation
        let settingSnapshot = measurementSettingGeneration
        let intentSnapshot = measurementSettingIntentGeneration
        do {
            let setting = try await transport.measurementSettings()
            guard token == generation, !Task.isCancelled else { return }
            guard settingSnapshot == measurementSettingGeneration,
                  intentSnapshot == measurementSettingIntentGeneration else { return }
            measurementEnabled = setting.enabled
            error = nil
            // A missing preference defaults to enabled for signed-in accounts. Only
            // expose the setting as enabled after the server acknowledges the write.
            if !setting.enabled, !ownerID.isEmpty {
                _ = await setMeasurementEnabled(true)
            }
        } catch {
            guard token == generation else { return }
        }
    }

    func setMeasurementEnabled(_ enabled: Bool) async -> Bool {
        measurementSettingIntentGeneration &+= 1
        let token = generation
        let pending = pendingMeasurementSetting.flatMap { $0.enabled == enabled ? $0 : nil }
            ?? (requestID: UUID(), enabled: enabled)
        pendingMeasurementSetting = pending
        let previous = commandTail
        let taskID = UUID()
        let work = Task { @MainActor in
            await previous?.value
            guard token == self.generation, !Task.isCancelled else { return false }
            do {
                let setting = try await self.transport.setMeasurementSettings(requestID: pending.requestID, enabled: enabled)
                guard token == self.generation, !Task.isCancelled else { return false }
                guard setting.enabled == enabled else { throw CloudSyncFailure.invalidResponse }
                self.measurementEnabled = setting.enabled
                self.measurementSettingGeneration &+= 1
                if self.pendingMeasurementSetting?.requestID == pending.requestID {
                    self.pendingMeasurementSetting = nil
                }
                self.error = nil
                return true
            } catch {
                if token == self.generation { self.error = error }
                return false
            }
        }
        commandTasks[taskID] = work
        commandTail = Task { _ = await work.value }
        let result = await work.value
        commandTasks.removeValue(forKey: taskID)
        return result
    }

    func set(_ kind: BlueprintPreferenceKind, enabled: Bool, for entry: BlueprintCatalogEntry,
             retry: Bool = false) async -> Bool {
        guard !ownerID.isEmpty, entry.viewerState != nil else { return false }
        let key = "\(entry.catalogKey)|\(kind.rawValue)"
        let token = generation
        let mutation: BlueprintPreferenceMutation
        if let saved = pending[key], (retry || saved.enabled == enabled),
           saved.revision == entry.revision, saved.contentHash == entry.contentHash {
            mutation = saved
        } else {
            mutation = BlueprintPreferenceMutation(requestId: UUID(), catalogKey: entry.catalogKey,
                revision: entry.revision, contentHash: entry.contentHash, kind: kind, enabled: enabled)
            pending[key] = mutation
        }
        let previous = commandTail
        let taskID = UUID()
        let work = Task { @MainActor in
            await previous?.value
            guard token == self.generation, !Task.isCancelled else { return false }
            do {
                let acknowledgement = try await self.transport.update(mutation)
                guard token == self.generation, !Task.isCancelled else { return false }
                guard acknowledgement.requestId == mutation.requestId,
                      acknowledgement.catalogKey == mutation.catalogKey,
                      acknowledgement.revision == mutation.revision,
                      acknowledgement.contentHash == mutation.contentHash else {
                    throw CloudSyncFailure.invalidResponse
                }
                self.apply(acknowledgement, mutation: mutation, entry: entry, savedItem: nil)
                self.pending.removeValue(forKey: key)
                self.error = nil
                self.lastFailedMutation = nil
                self.lastFailedEntry = nil
                self.lastFailedSavedItem = nil
                return true
            } catch {
                if token == self.generation {
                    self.error = error
                    self.lastFailedMutation = mutation
                    self.lastFailedEntry = entry
                }
                return false
            }
        }
        commandTasks[taskID] = work
        commandTail = Task { _ = await work.value }
        let result = await work.value
        commandTasks.removeValue(forKey: taskID)
        return result
    }

    func retryMeasurementSetting() async {
        if let pendingMeasurementSetting {
            _ = await setMeasurementEnabled(pendingMeasurementSetting.enabled)
        }
    }

    func retryLastAction() async {
        if let mutation = lastFailedMutation {
            if let entry = lastFailedEntry {
                _ = await set(mutation.kind, enabled: mutation.enabled, for: entry, retry: true)
            } else if let item = lastFailedSavedItem {
                _ = await set(mutation.kind, enabled: mutation.enabled, for: item)
            }
        } else if let pendingMeasurementSetting {
            _ = await setMeasurementEnabled(pendingMeasurementSetting.enabled)
        }
    }

    func clearError() { error = nil }

    func set(_ kind: BlueprintPreferenceKind, enabled: Bool, for item: BlueprintSavedPreference) async -> Bool {
        guard !ownerID.isEmpty else { return false }
        let key = "\(item.catalogKey)|\(kind.rawValue)"
        let mutation: BlueprintPreferenceMutation
        if let saved = pending[key], saved.enabled == enabled,
           saved.revision == item.binding(for: kind).revision,
           saved.contentHash == item.binding(for: kind).contentHash {
            mutation = saved
        } else {
            let binding = item.binding(for: kind)
            mutation = BlueprintPreferenceMutation(requestId: UUID(), catalogKey: item.catalogKey,
                revision: binding.revision, contentHash: binding.contentHash, kind: kind, enabled: enabled)
            pending[key] = mutation
        }
        let token = generation
        let previous = commandTail
        let taskID = UUID()
        let work = Task { @MainActor in
            await previous?.value
            guard token == self.generation, !Task.isCancelled else { return false }
            do {
                let acknowledgement = try await self.transport.update(mutation)
                guard token == self.generation, !Task.isCancelled else { return false }
                guard acknowledgement.requestId == mutation.requestId,
                      acknowledgement.catalogKey == mutation.catalogKey,
                      acknowledgement.revision == mutation.revision,
                      acknowledgement.contentHash == mutation.contentHash else {
                    throw CloudSyncFailure.invalidResponse
                }
                self.pending.removeValue(forKey: key)
                self.lastFailedMutation = nil
                self.lastFailedEntry = nil
                self.lastFailedSavedItem = nil
                self.apply(acknowledgement, mutation: mutation, entry: nil, savedItem: item)
                self.error = nil
                return true
            } catch {
                if token == self.generation {
                    self.error = error
                    self.lastFailedMutation = mutation
                    self.lastFailedEntry = nil
                    self.lastFailedSavedItem = item
                }
                return false
            }
        }
        commandTasks[taskID] = work
        commandTail = Task { _ = await work.value }
        let result = await work.value
        commandTasks.removeValue(forKey: taskID)
        return result
    }

    func record(_ kind: BlueprintMeasurementSignalKind, for entry: BlueprintCatalogEntry) async {
        guard measurementEnabled, entry.viewerState != nil,
              let context = entry.discoveryContext, context.expiresAt > Date(),
              !context.exposureId.isEmpty else { return }
        let dedupeKey = "\(entry.id)|\(context.exposureId)|\(kind.rawValue)"
        guard sentSignals.insert(dedupeKey).inserted else { return }
        let token = generation
        do {
            try await transport.record(.init(requestId: UUID(), exposureId: context.exposureId, kind: kind))
            guard token == generation else { return }
        } catch { /* Measurement is best effort and must never interrupt a preview. */ }
    }

    private func apply(_ acknowledgement: BlueprintPreferenceAcknowledgement,
                       mutation: BlueprintPreferenceMutation,
                       entry: BlueprintCatalogEntry?, savedItem: BlueprintSavedPreference?) {
        let key = mutation.catalogKey
        mutationGeneration &+= 1
        mutationGenerationByKey[key] = mutationGeneration
        let state = acknowledgement.state
        if state.liked || state.bookmarked || state.notInterested { states[key] = state }
        else { states.removeValue(forKey: key) }

        guard state.liked || state.bookmarked || state.notInterested else {
            savedItems.removeAll { $0.catalogKey == key }
            return
        }
        let prior = savedItems.first { $0.catalogKey == key } ?? savedItem
        let itemEntry: BlueprintSavedPreference.Entry?
        if let entry {
            itemEntry = .init(name: entry.definition.blueprint.name,
                              coverImageURL: entry.discovery?.coverImageURL,
                              creatorName: entry.creator?.displayName)
        } else {
            itemEntry = prior?.entry
        }
        let likeBinding = state.liked
            ? (mutation.kind == .like
                ? (revision: mutation.revision, contentHash: mutation.contentHash)
                : prior?.binding(for: .like))
            : nil
        let bookmarkBinding = state.bookmarked
            ? (mutation.kind == .bookmark
                ? (revision: mutation.revision, contentHash: mutation.contentHash)
                : prior?.binding(for: .bookmark))
            : nil
        let notInterestedBinding = state.notInterested
            ? (mutation.kind == .notInterested
                ? (revision: mutation.revision, contentHash: mutation.contentHash)
                : prior?.binding(for: .notInterested))
            : nil
        let bookmarkAvailability = entry != nil ? "available" : (prior?.bookmarkAvailability ?? "unavailable")
        let likeAvailability = entry != nil ? "available" : (prior?.likeAvailability ?? prior?.bookmarkAvailability ?? "unavailable")
        let notInterestedAvailability = entry != nil ? "available" : (prior?.notInterestedAvailability ?? prior?.bookmarkAvailability ?? "unavailable")
        let updated = BlueprintSavedPreference(catalogKey: key, revision: mutation.revision,
            contentHash: mutation.contentHash, liked: state.liked, bookmarked: state.bookmarked,
            notInterested: state.notInterested,
            likeRevision: likeBinding?.revision,
            likeContentHash: likeBinding?.contentHash,
            bookmarkRevision: bookmarkBinding?.revision,
            bookmarkContentHash: bookmarkBinding?.contentHash,
            notInterestedRevision: notInterestedBinding?.revision,
            notInterestedContentHash: notInterestedBinding?.contentHash,
            likeAvailability: likeAvailability,
            bookmarkAvailability: bookmarkAvailability,
            notInterestedAvailability: notInterestedAvailability,
            entry: itemEntry)
        savedItems.removeAll { $0.catalogKey == key }
        savedItems.append(updated)
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return value
    }()
}
