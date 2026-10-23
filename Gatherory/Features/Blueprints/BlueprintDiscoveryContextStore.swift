import Foundation
import Observation

nonisolated enum BlueprintDiscoveryContextPolicy {
    static let historyLimit = 200
    static let maximumCatalogKeyLength = 160
    static let historyLifetime: TimeInterval = 30 * 24 * 60 * 60
    static let sessionIdleLifetime: TimeInterval = 30 * 60
    static let headerByteLimit = 16_384
}

nonisolated struct BlueprintDiscoverySeenRecord: Codable, Equatable, Sendable {
    let catalogKey: String
    let lastSeenAt: Date
}

nonisolated struct BlueprintDiscoveryRequestContext: Codable, Equatable, Sendable {
    let version: Int
    let sessionId: UUID
    let startedAt: Date
    let seen: [BlueprintDiscoverySeenRecord]

    private enum CodingKeys: String, CodingKey { case version, sessionId, startedAt, seen }

    init(sessionId: UUID, startedAt: Date, seen: [BlueprintDiscoverySeenRecord]) {
        version = 1
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.seen = seen
    }

    func encodedHeaderValue() throws -> String {
        guard version == 1, seen.count <= BlueprintDiscoveryContextPolicy.historyLimit,
              Set(seen.map(\.catalogKey)).count == seen.count,
              seen.allSatisfy({ !$0.catalogKey.isEmpty
                  && $0.catalogKey.utf8.count <= BlueprintDiscoveryContextPolicy.maximumCatalogKeyLength
                  && $0.lastSeenAt <= startedAt
                  && startedAt.timeIntervalSince($0.lastSeenAt) <= BlueprintDiscoveryContextPolicy.historyLifetime }) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "Invalid discovery context"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let formatter = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(formatter.format(date))
        }
        return String(data: try encoder.encode(self), encoding: .utf8) ?? ""
    }

}

/// Device-local discovery history, isolated by the active account. The frozen
/// request context only changes when a new browsing session begins.
@MainActor
@Observable
final class BlueprintDiscoveryContextStore {
    static let historyLimit = BlueprintDiscoveryContextPolicy.historyLimit
    static let historyLifetime = BlueprintDiscoveryContextPolicy.historyLifetime
    static let sessionIdleLifetime = BlueprintDiscoveryContextPolicy.sessionIdleLifetime
    static let headerByteLimit = BlueprintDiscoveryContextPolicy.headerByteLimit

    private(set) var accountID: String
    private let defaults: UserDefaults
    private let storageKey: String
    private var history: [String: Date]
    private(set) var session: BlueprintDiscoveryRequestContext?
    private var awaySince: Date?
    private var generation = UUID()
    private(set) var isValid = true

    init(accountID: String, defaults: UserDefaults = .standard) {
        self.accountID = accountID
        self.defaults = defaults
        storageKey = Self.storageKey(accountID: accountID)
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            history = decoded
        } else {
            history = [:]
        }
        pruneHistory(now: .now)
    }

    var callbackGeneration: UUID { generation }

    var liveSeenKeys: [String] {
        history.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map(\.key)
    }

    func invalidate() {
        isValid = false
        generation = UUID()
        session = nil
        awaySince = nil
    }

    @discardableResult
    func beginOrResumeSession(now: Date = .now, forceNew: Bool = false) -> BlueprintDiscoveryRequestContext? {
        guard isValid else { return nil }
        pruneHistory(now: now)
        let awayExpired = awaySince.map { now.timeIntervalSince($0) >= Self.sessionIdleLifetime } == true
        let clockMovedBack = session.map { $0.startedAt.timeIntervalSince(now) > 60 } == true
        if forceNew || session == nil || awayExpired || clockMovedBack {
            let snapshot = history
                .filter { $0.value <= now }
                .map { BlueprintDiscoverySeenRecord(catalogKey: $0.key, lastSeenAt: $0.value) }
                .sorted { lhs, rhs in
                    if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
                    return lhs.catalogKey < rhs.catalogKey
                }
            session = makeBoundedContext(startedAt: now, snapshot: snapshot)
        }
        awaySince = nil
        return session
    }

    func markAway(now: Date = .now) {
        guard isValid, session != nil, awaySince == nil else { return }
        awaySince = now
    }

    /// Records meaningful visibility independently of analytics consent. The
    /// callback token prevents a card task from writing after account reset.
    func recordSeen(catalogKey: String, at date: Date = .now,
                    accountID callbackAccountID: String, generation callbackGeneration: UUID) {
        guard isValid, callbackAccountID == accountID, callbackGeneration == generation,
              !catalogKey.isEmpty,
              catalogKey.utf8.count <= BlueprintDiscoveryContextPolicy.maximumCatalogKeyLength else { return }
        pruneHistory(now: date)
        history[catalogKey] = date
        history = Dictionary(history.sorted { $0.value > $1.value }.prefix(Self.historyLimit)
            .map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        persist()
    }

    func headerValue(for context: BlueprintDiscoveryRequestContext?) -> String? {
        guard isValid, let context, context == session,
              let value = try? context.encodedHeaderValue(),
              value.utf8.count <= Self.headerByteLimit else { return nil }
        return value
    }

    static func clear(accountID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey(accountID: accountID))
    }

    private static func storageKey(accountID: String) -> String {
        "blueprint.discovery.seen.v1.\(accountID)"
    }

    private func makeBoundedContext(startedAt: Date, snapshot: [BlueprintDiscoverySeenRecord]) -> BlueprintDiscoveryRequestContext {
        let sessionId = UUID()
        let boundedCount = min(snapshot.count, Self.historyLimit)
        var lowerBound = 0
        var upperBound = boundedCount
        while lowerBound < upperBound {
            let candidateCount = (lowerBound + upperBound + 1) / 2
            let candidate = BlueprintDiscoveryRequestContext(
                sessionId: sessionId, startedAt: startedAt,
                seen: Array(snapshot.prefix(candidateCount))
            )
            if let bytes = try? candidate.encodedHeaderValue().utf8.count,
               bytes <= Self.headerByteLimit {
                lowerBound = candidateCount
            } else {
                upperBound = candidateCount - 1
            }
        }
        return BlueprintDiscoveryRequestContext(
            sessionId: sessionId, startedAt: startedAt,
            seen: Array(snapshot.prefix(lowerBound))
        )
    }

    private func pruneHistory(now: Date) {
        history = history.filter {
            !$0.key.isEmpty && $0.key.utf8.count <= BlueprintDiscoveryContextPolicy.maximumCatalogKeyLength
                && $0.value <= now && now.timeIntervalSince($0.value) <= Self.historyLifetime
        }
        if history.count > Self.historyLimit {
            history = Dictionary(history.sorted { $0.value > $1.value }.prefix(Self.historyLimit)
                .map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
