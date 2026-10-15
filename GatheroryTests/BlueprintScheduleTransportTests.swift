import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct BlueprintScheduleTransportTests {
    @Test("Schedule posts the authenticated catalog pin and zoned anchor and decodes candidates")
    func scheduleTransportContract() async throws {
        let fixture = try ScheduleHTTPFixture("valid")
        defer { fixture.cleanUp() }
        let input = scheduleInput()

        let response = try await fixture.transport.blueprintSchedule(input)

        #expect(response.catalogKey == input.catalogKey)
        #expect(response.revision == input.revision)
        #expect(response.contentHash == input.contentHash)
        #expect(response.mainEvent.startsAt == input.mainEvent.startsAt)
        #expect(response.mainEvent.timeZone == "America/Detroit")
        #expect(response.suggestions.count == 3)
        let suggested = try #require(response.suggestions.first { $0.key == "venue_visit" })
        #expect(suggested.status == "suggested")
        #expect(suggested.localDateTime == "2023-11-14T17:13:20")
        #expect(suggested.candidates == [Date(timeIntervalSince1970: 1_700_000_000)])
        let ambiguous = try #require(response.suggestions.first { $0.key == "ceremony" })
        #expect(ambiguous.status == "ambiguous")
        #expect(ambiguous.localDateTime == "2023-11-05T01:30:00")
        #expect(ambiguous.candidates == [
            Date(timeIntervalSince1970: 1_699_162_200),
            Date(timeIntervalSince1970: 1_699_165_800)
        ])
        let unavailable = try #require(response.suggestions.first { $0.key == "reception" })
        #expect(unavailable.localDateTime == nil)
        #expect(unavailable.candidates.isEmpty)
    }

    @Test("A fractional input accepts the server's whole-second anchor echo")
    func fractionalAnchorEchoIsAccepted() async throws {
        let fixture = try ScheduleHTTPFixture("valid")
        defer { fixture.cleanUp() }
        let input = scheduleInput(startsAt: Date(timeIntervalSince1970: 1_700_000_000.875))

        let response = try await fixture.coordinator.schedule(input)

        #expect(response.mainEvent.startsAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(response.mainEvent.startsAt == input.mainEvent.startsAt)
        #expect(response.suggestions.count == 3)
    }

    @Test("Schedule rejects a stale response with a different catalog pin or anchor",
          arguments: ["catalog", "revision", "hash", "anchor", "timezone"])
    func mismatchedResponseIsRejected(field: String) async throws {
        let fixture = try ScheduleHTTPFixture(field)
        defer { fixture.cleanUp() }

        await #expect {
            try await fixture.coordinator.schedule(scheduleInput())
        } throws: { error in
            if case CloudSyncFailure.invalidResponse = error { return true }
            return false
        }

        #expect(try fixture.intents.pending(ownerUserID: fixture.ownerID).isEmpty)
        #expect(fixture.library.workspaces.isEmpty)
    }

    @Test("An account switch discards an in-flight schedule, including an A to B to A switch",
          arguments: [false, true])
    func accountSwitchDropsResponse(returnToOriginalAccount: Bool) async throws {
        let fixture = try ScheduleHTTPFixture("held")
        defer { fixture.cleanUp() }
        ScheduleHTTPProtocol.gate.reset()
        let input = scheduleInput()
        let request = Task { try await fixture.coordinator.schedule(input) }
        defer {
            ScheduleHTTPProtocol.gate.release.signal()
            request.cancel()
        }

        let started = await waitForHeldRequest()
        try #require(started, "The schedule request must be in flight before switching accounts")
        fixture.persistence.activate(userID: "another-schedule-account", in: fixture.library)
        if returnToOriginalAccount {
            fixture.persistence.activate(userID: fixture.ownerID, in: fixture.library)
        }
        ScheduleHTTPProtocol.gate.release.signal()

        await #expect(throws: CancellationError.self) {
            try await request.value
        }
        #expect(fixture.library.workspaces.isEmpty)
        #expect(try fixture.intents.pending(ownerUserID: fixture.ownerID).isEmpty)
        #expect(try fixture.intents.pending(ownerUserID: "another-schedule-account").isEmpty)
    }

    @Test("Scheduling and refreshing never create a durable installation intent")
    func scheduleDoesNotPrepareInstallation() async throws {
        let fixture = try ScheduleHTTPFixture("valid")
        defer { fixture.cleanUp() }
        #expect(!FileManager.default.fileExists(atPath: fixture.intentDirectory.path))

        for _ in 0..<2 {
            _ = try await fixture.coordinator.schedule(scheduleInput())
            let reopenedStore = BlueprintInstallationIntentStore(directoryURL: fixture.intentDirectory)
            #expect(try reopenedStore.pending(ownerUserID: fixture.ownerID).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.intentDirectory.path))
            #expect(fixture.library.workspaces.isEmpty)
        }
    }

    private func scheduleInput(startsAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> BlueprintScheduleInput {
        BlueprintScheduleInput(
            catalogKey: "wedding", revision: 7, contentHash: String(repeating: "a", count: 64),
            mainEvent: .init(startsAt: startsAt, timeZone: "America/Detroit")
        )
    }

    private func waitForHeldRequest() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if ScheduleHTTPProtocol.gate.hasStarted { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

@MainActor
private struct ScheduleHTTPFixture {
    let ownerID: String
    let intentDirectory: URL
    let intents: BlueprintInstallationIntentStore
    let persistence: WorkspacePersistenceController
    let library: WorkspaceLibrary
    let session: URLSession
    let transport: PostgresSyncTransport
    let coordinator: BlueprintInstallationCoordinator

    init(_ scenario: String) throws {
        ownerID = "schedule-owner-\(UUID().uuidString)"
        intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        intents = BlueprintInstallationIntentStore(directoryURL: intentDirectory)
        persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScheduleHTTPProtocol.self]
        session = URLSession(configuration: configuration)
        let baseURL = URL(string: "https://\(scenario).invalid")!
        transport = PostgresSyncTransport(baseURL: baseURL, urlSession: session, tokenStore: ScheduleTokenStore())
        coordinator = BlueprintInstallationCoordinator(
            baseURL: baseURL, persistence: persistence, library: library,
            intents: intents, transport: transport
        )
    }

    func cleanUp() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: intentDirectory)
    }
}

private struct ScheduleTokenStore: SessionTokenStore {
    func read() -> String? { "schedule-test-token" }
    func save(_ token: String) {}
    func delete() {}
}

/// The suite serializes the two held-response cases. All other responses are
/// selected by URL, without installing shared mutable request handlers.
nonisolated private final class ScheduleResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    let release = DispatchSemaphore(value: 0)

    var hasStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func reset() {
        lock.lock()
        started = false
        lock.unlock()
        while release.wait(timeout: .now()) == .success {}
    }

    func hold() -> Bool {
        lock.lock()
        started = true
        lock.unlock()
        return release.wait(timeout: .now() + 10) == .success
    }
}

private final class ScheduleHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let gate = ScheduleResponseGate()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.path == "/api/blueprints/schedule")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer schedule-test-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            var payload = try #require(try JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
            #expect(Set(payload.keys) == Set(["catalogKey", "revision", "contentHash", "mainEvent"]))
            #expect(payload["catalogKey"] as? String == "wedding")
            #expect(payload["revision"] as? Int == 7)
            #expect(payload["contentHash"] as? String == String(repeating: "a", count: 64))
            var anchor = try #require(payload["mainEvent"] as? [String: Any])
            #expect(Set(anchor.keys) == Set(["startsAt", "timeZone"]))
            #expect(anchor["startsAt"] as? String == "2023-11-14T22:13:20Z")
            #expect(anchor["timeZone"] as? String == "America/Detroit")

            switch url.host {
            case "valid.invalid": break
            case "held.invalid":
                try #require(Self.gate.hold(), "The account-switch test must release the held response")
            case "catalog.invalid": payload["catalogKey"] = "birthday"
            case "revision.invalid": payload["revision"] = 8
            case "hash.invalid": payload["contentHash"] = String(repeating: "b", count: 64)
            case "anchor.invalid": anchor["startsAt"] = "2023-11-14T22:13:21Z"
            case "timezone.invalid": anchor["timeZone"] = "America/Los_Angeles"
            default:
                Issue.record("Unexpected schedule fixture URL: \(url)")
                throw URLError(.badURL)
            }
            payload["mainEvent"] = anchor
            payload["suggestions"] = [
                ["key": "venue_visit", "status": "suggested", "localDateTime": "2023-11-14T17:13:20",
                 "candidates": ["2023-11-14T22:13:20Z"]],
                ["key": "ceremony", "status": "ambiguous", "localDateTime": "2023-11-05T01:30:00",
                 "candidates": ["2023-11-05T05:30:00Z", "2023-11-05T06:30:00Z"]],
                ["key": "reception", "status": "unavailable", "localDateTime": NSNull(), "candidates": []]
            ] as [[String: Any]]
            let response = try #require(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func bodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
