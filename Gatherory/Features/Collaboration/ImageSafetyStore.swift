import Foundation
import Observation

enum ImageReportReason: String, CaseIterable, Identifiable, Codable {
    case inappropriate, harassment, privacy, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inappropriate: AppCopy.Safety.inappropriate
        case .harassment: AppCopy.Safety.harassment
        case .privacy: AppCopy.Safety.privacy
        case .other: AppCopy.Safety.other
        }
    }
}

@MainActor protocol ImageSafetyPolicyClient {
    func blockedPeople() async throws -> [BlockedPerson]
    func hiddenIDs() async throws -> Set<UUID>
    func block(_ userID: String) async throws
    func unblock(_ userID: String) async throws
}

struct ImageSafetyClient: ImageSafetyPolicyClient {
    let baseURL: URL
    var session: URLSession = .shared
    var tokenStore: any SessionTokenStore = KeychainSessionTokenStore()

    func report(_ mediaAssetID: UUID, reason: ImageReportReason, detail: String) async throws {
        _ = try await perform(path: "api/moderation/reports", body: ["mediaAssetId": mediaAssetID.uuidString, "reason": reason.rawValue, "detail": detail])
    }

    func hide(_ mediaAssetID: UUID) async throws {
        _ = try await perform(path: "api/moderation/hide", body: ["mediaAssetId": mediaAssetID.uuidString])
    }

    func hiddenIDs() async throws -> Set<UUID> {
        let data = try await perform(path: "api/moderation/hide", body: nil)
        return Set(try JSONDecoder().decode(HiddenImagesEnvelope.self, from: data).data?.mediaAssetIds ?? [])
    }

    func blockedPeople() async throws -> [BlockedPerson] {
        let data = try await perform(path: "api/moderation/blocks", body: nil)
        return try JSONDecoder().decode(BlockedPeopleEnvelope.self, from: data).data.blockedUsers
    }
    func block(_ userID: String) async throws {
        _ = try await perform(path: "api/moderation/blocks", body: ["blockedUserId": userID])
    }
    func unblock(_ userID: String) async throws {
        _ = try await perform(path: "api/moderation/blocks", body: ["blockedUserId": userID], method: "DELETE")
    }

    private func perform(path: String, body: [String: String]?, method: String? = nil) async throws -> Data {
        guard let token = try tokenStore.read(), !token.isEmpty else { throw CloudSyncFailure.invalidSession }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MediaSyncFailure.invalidResponse }
        if response.statusCode == 401 { throw CloudSyncFailure.invalidSession }
        let envelope = try JSONDecoder().decode(SafetyEnvelope.self, from: data)
        guard (200..<300).contains(response.statusCode), envelope.ok else {
            throw MediaSyncFailure.server(envelope.error?.userMessage ?? AppCopy.Safety.failed)
        }
        return data
    }
}

private struct SafetyEnvelope: Decodable {
    let ok: Bool
    let error: SafeError?
    struct SafeError: Decodable { let userMessage: String }
}
private struct HiddenImagesEnvelope: Decodable {
    let data: HiddenImages?
    struct HiddenImages: Decodable { let mediaAssetIds: [UUID] }
}

struct BlockedPerson: Decodable { let userId: String; let name: String }
private struct BlockedPeopleEnvelope: Decodable {
    let data: People
    struct People: Decodable { let blockedUsers: [BlockedPerson] }
}

/** Personal preferences never modify an event's shared outbox or album. */
@Observable @MainActor
final class ImageSafetyStore {
    private(set) var hiddenIDs: Set<UUID> = []
    private(set) var moderatedIDs: Set<UUID> = []
    private(set) var accountID: String?
    private(set) var blockedUserIDs: Set<String> = []
    private(set) var pendingBlockIDs: Set<String> = []
    private(set) var blockedNames: [String: String] = [:]
    private let defaults: UserDefaults
    private let injectedClient: (any ImageSafetyPolicyClient)?
    private var revision = 0
    init(defaults: UserDefaults = .standard, client: (any ImageSafetyPolicyClient)? = nil) {
        self.defaults = defaults
        injectedClient = client
    }

    private var policyClient: (any ImageSafetyPolicyClient)? {
        if let injectedClient { return injectedClient }
        return AppRuntimeConfiguration.authenticationBaseURL.map { ImageSafetyClient(baseURL: $0) }
    }

    func configure(accountID: String?) {
        guard self.accountID != accountID else { return }
        revision += 1
        self.accountID = accountID
        blockedNames = [:]
        blockedUserIDs = accountID.map { Set(defaults.stringArray(forKey: "blockedPeople.\($0)") ?? []) } ?? []
        pendingBlockIDs = accountID.map { Set(defaults.stringArray(forKey: "pendingBlocks.\($0)") ?? []) } ?? []
        moderatedIDs = accountID.map { Set((defaults.stringArray(forKey: "moderatedImages.\($0)") ?? []).compactMap(UUID.init(uuidString:))) } ?? []
        hiddenIDs = accountID.map { Set((defaults.stringArray(forKey: "hiddenImages.\($0)") ?? []).compactMap(UUID.init(uuidString:))) } ?? []
    }

    func isHidden(_ moment: EventMoment) -> Bool {
        isBlocked(moment.addedByUserID) || hiddenIDs.contains(moment.id) || moment.mediaAssetID.map { hiddenIDs.contains($0) || moderatedIDs.contains($0) } == true
    }

    func isBlocked(_ userID: String?) -> Bool { userID.map(blockedUserIDs.contains) ?? false }

    func block(_ userID: String, name: String) async throws {
        guard let accountID, accountID != userID else { return }
        revision += 1
        blockedUserIDs.insert(userID); pendingBlockIDs.insert(userID); blockedNames[userID] = name
        persistBlocks()
        guard let client = policyClient else { throw MediaSyncFailure.invalidResponse }
        try await client.block(userID)
        guard self.accountID == accountID else { return }
        pendingBlockIDs.remove(userID); persistBlocks()
        await refresh()
    }

    func unblock(_ userID: String) async throws {
        guard let accountID, let client = policyClient else { throw CloudSyncFailure.invalidSession }
        revision += 1
        try await client.unblock(userID)
        guard self.accountID == accountID else { return }
        blockedUserIDs.remove(userID); pendingBlockIDs.remove(userID); blockedNames.removeValue(forKey: userID)
        persistBlocks()
        await refresh()
    }

    private func persistBlocks() {
        guard let accountID else { return }
        defaults.set(blockedUserIDs.sorted(), forKey: "blockedPeople.\(accountID)")
        defaults.set(pendingBlockIDs.sorted(), forKey: "pendingBlocks.\(accountID)")
    }

    func visibleImageData(_ data: Data?, assetID: UUID?) -> Data? {
        guard let assetID else { return data }
        return hiddenIDs.contains(assetID) || moderatedIDs.contains(assetID) ? nil : data
    }

    func hide(_ moment: EventMoment) {
        guard let accountID else { return }
        hiddenIDs.insert(moment.mediaAssetID ?? moment.id)
        defaults.set(hiddenIDs.map(\.uuidString).sorted(), forKey: "hiddenImages.\(accountID)")
    }

    func refresh() async {
        guard let accountID, let client = policyClient else { return }
        let requestRevision = revision
        for userID in pendingBlockIDs.sorted() {
            guard self.accountID == accountID, revision == requestRevision else { return }
            do {
                try await client.block(userID)
                guard self.accountID == accountID, revision == requestRevision else { return }
                pendingBlockIDs.remove(userID)
                persistBlocks()
            } catch { /* Keep the personal hide and retry on the next refresh. */ }
        }
        if let people = try? await client.blockedPeople(), self.accountID == accountID, revision == requestRevision {
            blockedUserIDs = Set(people.map(\.userId)).union(pendingBlockIDs)
            blockedNames.merge(Dictionary(uniqueKeysWithValues: people.map { ($0.userId, $0.name) })) { _, incoming in incoming }
            persistBlocks()
        }
        // Never put an old account's in-flight result into the next account.
        guard self.accountID == accountID, revision == requestRevision else { return }
        if let ids = try? await client.hiddenIDs(), self.accountID == accountID, revision == requestRevision {
            moderatedIDs = ids
            defaults.set(ids.map(\.uuidString).sorted(), forKey: "moderatedImages.\(accountID)")
        }
    }

    func purge(accountID: String) {
        for prefix in ["hiddenImages", "moderatedImages", "blockedPeople", "pendingBlocks"] {
            defaults.removeObject(forKey: "\(prefix).\(accountID)")
        }
        if self.accountID == accountID { configure(accountID: nil) }
    }
}
