import Foundation

/// The exact request body is retained so a retry after a lost response cannot
/// silently change the reviewed plan or its idempotency key.
struct BlueprintInstallationIntent: Codable, Equatable, Sendable {
    let requestID: UUID
    let ownerUserID: String
    let requestBody: Data
    let createdAt: Date
}

enum BlueprintInstallationIntentFailure: Error, Equatable {
    case requestIDAlreadyUsed
}

/// Durable local retry state, isolated by canonical Better Auth user ID.
/// Intents remain until the install result has been imported through bootstrap.
final class BlueprintInstallationIntentStore {
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
    }

    @discardableResult
    func prepare(
        ownerUserID: String,
        requestID: UUID,
        requestBody: Data,
        createdAt: Date = .now
    ) throws -> BlueprintInstallationIntent {
        let url = intentURL(ownerUserID: ownerUserID, requestID: requestID)
        if FileManager.default.fileExists(atPath: url.path) {
            let existingData = try Data(contentsOf: url)
            let existing = try decoder.decode(BlueprintInstallationIntent.self, from: existingData)
            guard existing.requestBody == requestBody else {
                throw BlueprintInstallationIntentFailure.requestIDAlreadyUsed
            }
            return existing
        }

        let intent = BlueprintInstallationIntent(
            requestID: requestID,
            ownerUserID: ownerUserID,
            requestBody: requestBody,
            createdAt: createdAt
        )
        try FileManager.default.createDirectory(
            at: accountDirectory(ownerUserID: ownerUserID),
            withIntermediateDirectories: true
        )
        try encoder.encode(intent).write(to: url, options: .atomic)
        return intent
    }

    func pending(ownerUserID: String) throws -> [BlueprintInstallationIntent] {
        let directory = accountDirectory(ownerUserID: ownerUserID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            let intent = try decoder.decode(BlueprintInstallationIntent.self, from: Data(contentsOf: url))
            guard intent.ownerUserID == ownerUserID else { return nil }
            return intent
        }
    }

    func complete(ownerUserID: String, requestID: UUID) throws {
        let url = intentURL(ownerUserID: ownerUserID, requestID: requestID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func accountDirectory(ownerUserID: String) -> URL {
        directoryURL.appending(path: encoded(ownerUserID), directoryHint: .isDirectory)
    }

    private func intentURL(ownerUserID: String, requestID: UUID) -> URL {
        accountDirectory(ownerUserID: ownerUserID)
            .appending(path: requestID.uuidString.lowercased() + ".json")
    }

    private func encoded(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static var defaultDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport.appending(path: "Gatherory/BlueprintInstallIntents", directoryHint: .isDirectory)
    }
}

@MainActor
final class BlueprintInstallationCoordinator {
    private let transport: PostgresSyncTransport
    private let persistence: WorkspacePersistenceController
    private let library: WorkspaceLibrary
    private let intents: BlueprintInstallationIntentStore
    private let setupDrafts: BlueprintSetupDraftStore
    private let boundOwnerUserID: String?
    private let boundAccountGeneration: UUID
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        persistence: WorkspacePersistenceController,
        library: WorkspaceLibrary,
        intents: BlueprintInstallationIntentStore? = nil,
        setupDrafts: BlueprintSetupDraftStore? = nil,
        transport: PostgresSyncTransport? = nil
    ) {
        self.transport = transport ?? PostgresSyncTransport(baseURL: baseURL)
        self.persistence = persistence
        self.library = library
        self.intents = intents ?? BlueprintInstallationIntentStore()
        self.setupDrafts = setupDrafts ?? BlueprintSetupDraftStore()
        self.boundOwnerUserID = persistence.activeUserID
        self.boundAccountGeneration = persistence.activeUserGeneration
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func catalog() async throws -> BlueprintCatalogResponse {
        try requireBoundAccount()
        let response = try await transport.blueprintCatalog()
        try requireBoundAccount()
        return response
    }

    func sharedBlueprint(token: String) async throws -> BlueprintCatalogEntry {
        try requireBoundAccount()
        let entry = try await transport.sharedBlueprint(token: token)
        try requireBoundAccount()
        guard entry.definition.supportsCurrentSchema else { throw CloudSyncFailure.invalidResponse }
        return entry
    }

    func schedule(_ input: BlueprintScheduleInput) async throws -> BlueprintScheduleResponse {
        try requireBoundAccount()
        let response = try await transport.blueprintSchedule(input)
        try requireBoundAccount()
        // Pin the response to the request, even if an intermediary returns stale data.
        guard response.catalogKey == input.catalogKey,
              response.revision == input.revision,
              response.contentHash == input.contentHash,
              response.mainEvent.timeZone == input.mainEvent.timeZone,
              abs(response.mainEvent.startsAt.timeIntervalSince(input.mainEvent.startsAt)) < 0.001 else {
            throw CloudSyncFailure.invalidResponse
        }
        return response
    }

    func preview(_ input: BlueprintInstallInput) async throws -> BlueprintPreviewResponse {
        try requireBoundAccount()
        let response = try await transport.previewBlueprint(input)
        try requireBoundAccount()
        return response
    }

    /// Account-bound entry point for native views. The account is obtained
    /// from the persistence controller, never accepted from view input.
    func install(_ input: BlueprintInstallInput) async throws -> PlanningWorkspace {
        try requireBoundAccount()
        guard let ownerUserID = boundOwnerUserID else {
            throw CloudSyncFailure.invalidSession
        }
        return try await install(input, ownerUserID: ownerUserID)
    }

    func pendingIntentsForActiveAccount() throws -> [BlueprintInstallationIntent] {
        try requireBoundAccount()
        guard let ownerUserID = persistence.activeUserID else { return [] }
        return try intents.pending(ownerUserID: ownerUserID)
    }

    func pendingIntents(ownerUserID: String) throws -> [BlueprintInstallationIntent] {
        try intents.pending(ownerUserID: ownerUserID)
    }

    func install(_ input: BlueprintInstallInput, ownerUserID: String) async throws -> PlanningWorkspace {
        let body = try encoder.encode(input)
        let intent = try intents.prepare(
            ownerUserID: ownerUserID,
            requestID: input.requestID,
            requestBody: body
        )
        return try await resume(intent)
    }

    /// Retries the exact persisted request, recovers completed receipts after a
    /// lost response, then imports through the same atomic bootstrap merger used
    /// by normal account sync.
    func resume(_ intent: BlueprintInstallationIntent) async throws -> PlanningWorkspace {
        try requireBoundAccount()
        guard intent.ownerUserID == boundOwnerUserID else { throw CancellationError() }
        let accountGeneration = boundAccountGeneration
        try requireActiveAccount(intent.ownerUserID, generation: accountGeneration)
        let status = try await transport.blueprintInstallationStatus(requestID: intent.requestID)
        try requireActiveAccount(intent.ownerUserID, generation: accountGeneration)

        let result: BlueprintInstallationResult
        if status?.state == .completed {
            guard let completed = status?.result else { throw CloudSyncFailure.invalidResponse }
            result = completed
        } else {
            // A failed receipt records an attempt, not a terminal request. The
            // server releases that receipt so this exact idempotency key/body
            // can safely reacquire it.
            let data = try await transport.installBlueprint(
                requestID: intent.requestID,
                requestBody: intent.requestBody
            )
            do {
                result = try decoder.decode(BlueprintInstallationResult.self, from: data)
            } catch {
                throw CloudSyncFailure.invalidResponse
            }
        }

        try requireActiveAccount(intent.ownerUserID, generation: accountGeneration)
        let bootstrap = try await transport.bootstrap()
        try requireActiveAccount(intent.ownerUserID, generation: accountGeneration)
        // The bootstrap response can include every account scope. Flush any
        // edits made while it was in flight before the merge checks persisted
        // outboxes, so those scopes are protected from stale remote snapshots.
        try persistence.saveChanges(in: library)
        try persistence.applyBootstrap(
            bootstrap.snapshots,
            entities: bootstrap.entitySnapshots,
            to: library
        )
        guard let workspace = library.workspaces.first(where: { $0.mainEventID == result.scopeID }) else {
            throw BlueprintInstallationFailure.workspaceNotInBootstrap
        }
        library.open(workspace)
        // Clear only the draft behind this exact request after durable import.
        // If cleanup fails, retain the install intent so retry recovers the same
        // receipt rather than offering another creation from the old draft.
        let source = try decoder.decode(SetupDraftSource.self, from: intent.requestBody)
        try setupDrafts.remove(
            ownerUserID: intent.ownerUserID,
            catalogKey: source.catalogKey,
            requestID: intent.requestID,
            shareToken: source.shareToken
        )
        try intents.complete(ownerUserID: intent.ownerUserID, requestID: intent.requestID)
        return workspace
    }

    private func requireActiveAccount(_ ownerUserID: String, generation: UUID) throws {
        guard persistence.activeUserID == ownerUserID,
              persistence.activeUserGeneration == generation else {
            throw CancellationError()
        }
    }

    private struct SetupDraftSource: Decodable {
        let catalogKey: String
        let shareToken: String?
    }

    private func requireBoundAccount() throws {
        guard let boundOwnerUserID else { throw CloudSyncFailure.invalidSession }
        try requireActiveAccount(boundOwnerUserID, generation: boundAccountGeneration)
    }
}

enum BlueprintInstallationFailure: LocalizedError {
    case workspaceNotInBootstrap

    var errorDescription: String? {
        switch self {
        case .workspaceNotInBootstrap:
            BlueprintCopy.workspaceNotInBootstrap
        }
    }
}
