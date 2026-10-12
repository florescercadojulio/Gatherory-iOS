import Foundation
import Observation
import SwiftData

/// The first durable representation of a Gatherory workspace.
///
/// The app's observable domain graph remains optimized for SwiftUI. Keeping a
/// versioned archive at the persistence boundary lets us adopt SwiftData now
/// without forcing views to understand storage concerns. A later schema can
/// promote frequently queried children into their own models without changing
/// the feature-facing `WeddingWorkspace` API.
struct WorkspaceArchiveV1: Codable {
    static let schemaVersion = 1

    let mainEventID: UUID
    let title: String
    let weddingDate: Date
    let mainEventEndsAt: Date?
    let mainEventIsAllDay: Bool
    let mainEventTimeZoneIdentifier: String
    let mainEventLocation: EventLocation?
    var mainEventImageData: Data?
    let mainEventMediaAssetID: UUID?
    let venueName: String
    let location: String
    let dressCode: String
    let eventMessage: String
    let planningMode: PlanningMode
    var members: [WeddingMember]
    /// Optional so archives written before relationship normalization migrate.
    var eventParticipations: [EventParticipation]?
    let mainEventParticipantIDs: [UUID]
    var ideas: [WeddingIdea]
    var timeline: [TimelineItem]
    var eventExpenses: [EventExpense]
    let workspaceBudgetCap: Decimal?
    /// Optional for archives written before currency was workspace-scoped.
    let currencyCode: String?
    let mainEventBudgetCap: Decimal?
    var notes: [EventNote]
    let mainEventStatus: MainEventStatus
    let mainEventResponse: EventResponse?
    var eventMoments: [EventMoment]
    let isMainEventDeleted: Bool
    var registry: [RegistryItem]
    let isRegistryShared: Bool
    let isCollaboratorLinkEnabled: Bool
    let requiresCollaboratorApproval: Bool
    let defaultCollaboratorPermission: PlanningPermission
    let collaboratorInviteURL: URL

    init(workspace: WeddingWorkspace) {
        mainEventID = workspace.mainEventID
        title = workspace.title
        weddingDate = workspace.weddingDate
        mainEventEndsAt = workspace.mainEventEndsAt
        mainEventIsAllDay = workspace.mainEventIsAllDay
        mainEventTimeZoneIdentifier = workspace.mainEventTimeZoneIdentifier
        mainEventLocation = workspace.mainEventLocation
        mainEventImageData = workspace.mainEventImageData
        mainEventMediaAssetID = workspace.mainEventMediaAssetID
        venueName = workspace.venueName
        location = workspace.location
        dressCode = workspace.dressCode
        eventMessage = workspace.eventMessage
        planningMode = workspace.planningMode
        members = workspace.members
        eventParticipations = workspace.eventParticipations
        mainEventParticipantIDs = workspace.mainEventParticipantIDs
        ideas = workspace.ideas
        timeline = workspace.timeline
        eventExpenses = workspace.eventExpenses
        workspaceBudgetCap = workspace.workspaceBudgetCap
        currencyCode = workspace.currencyCode
        mainEventBudgetCap = workspace.mainEventBudgetCap
        notes = workspace.notes
        mainEventStatus = workspace.mainEventStatus
        mainEventResponse = workspace.mainEventResponse
        eventMoments = workspace.eventMoments
        isMainEventDeleted = workspace.isMainEventDeleted
        registry = workspace.registry
        isRegistryShared = workspace.isRegistryShared
        isCollaboratorLinkEnabled = workspace.isCollaboratorLinkEnabled
        requiresCollaboratorApproval = workspace.requiresCollaboratorApproval
        defaultCollaboratorPermission = workspace.defaultCollaboratorPermission
        collaboratorInviteURL = workspace.collaboratorInviteURL
    }

    func makeWorkspace() -> WeddingWorkspace {
        WeddingWorkspace(
            mainEventID: mainEventID,
            title: title,
            weddingDate: weddingDate,
            mainEventEndsAt: mainEventEndsAt,
            mainEventIsAllDay: mainEventIsAllDay,
            mainEventTimeZoneIdentifier: mainEventTimeZoneIdentifier,
            mainEventLocation: mainEventLocation,
            mainEventImageData: mainEventImageData,
            mainEventMediaAssetID: mainEventMediaAssetID,
            venueName: venueName,
            location: location,
            dressCode: dressCode,
            eventMessage: eventMessage,
            planningMode: planningMode,
            members: members,
            eventParticipations: eventParticipations,
            mainEventParticipantIDs: mainEventParticipantIDs,
            ideas: ideas,
            timeline: timeline,
            eventExpenses: eventExpenses,
            workspaceBudgetCap: workspaceBudgetCap,
            currencyCode: currencyCode ?? Locale.current.currency?.identifier ?? "USD",
            mainEventBudgetCap: mainEventBudgetCap,
            notes: notes,
            mainEventStatus: mainEventStatus,
            mainEventResponse: mainEventResponse,
            eventMoments: eventMoments,
            isMainEventDeleted: isMainEventDeleted,
            registry: registry,
            isRegistryShared: isRegistryShared,
            isCollaboratorLinkEnabled: isCollaboratorLinkEnabled,
            requiresCollaboratorApproval: requiresCollaboratorApproval,
            defaultCollaboratorPermission: defaultCollaboratorPermission,
            collaboratorInviteURL: collaboratorInviteURL
        )
    }
}

private struct WorkspaceSyncEntityKey: Hashable {
    let type: SyncEntityType
    let id: UUID
}

private extension WorkspaceArchiveV1 {
    func syncPayload(using encoder: JSONEncoder) throws -> Data {
        var remote = self
        remote.mainEventImageData = nil
        remote.ideas = remote.ideas.map { idea in
            var idea = idea
            idea.imageData = nil
            return idea
        }
        remote.timeline = remote.timeline.map { event in
            var event = event
            event.imageData = nil
            return event
        }
        remote.registry = remote.registry.map { item in
            var item = item
            item.imageData = nil
            return item
        }
        remote.eventMoments = remote.eventMoments.map { moment in
            var moment = moment
            moment.imageData = Data()
            return moment
        }
        return try encoder.encode(remote)
    }

    func syncEntities(using encoder: JSONEncoder) throws -> [WorkspaceSyncEntityKey: Data] {
        var entities: [WorkspaceSyncEntityKey: Data] = [:]

        for member in members {
            entities[.init(type: .participant, id: member.id)] = try encoder.encode(member)
        }
        for participation in eventParticipations ?? [] {
            entities[.init(type: .eventParticipation, id: participation.id)] = try encoder.encode(participation)
        }
        for idea in ideas {
            var remote = idea
            remote.imageData = nil
            entities[.init(type: .idea, id: idea.id)] = try encoder.encode(remote)
        }
        for event in timeline {
            var remote = event
            remote.imageData = nil
            entities[.init(type: .event, id: event.id)] = try encoder.encode(remote)
        }
        for expense in eventExpenses {
            entities[.init(type: .expense, id: expense.id)] = try encoder.encode(expense)
        }
        for note in notes {
            entities[.init(type: .note, id: note.id)] = try encoder.encode(note)
        }
        for moment in eventMoments {
            var remote = moment
            remote.imageData = Data()
            entities[.init(type: .moment, id: moment.id)] = try encoder.encode(remote)
        }
        for item in registry {
            var remote = item
            remote.imageData = nil
            entities[.init(type: .registryItem, id: item.id)] = try encoder.encode(remote)
        }

        return entities
    }

    mutating func preserveCollaborativeEntities(from local: WorkspaceArchiveV1) {
        if mainEventImageData == nil,
           mainEventMediaAssetID == local.mainEventMediaAssetID {
            mainEventImageData = local.mainEventImageData
        }
        members = local.members
        eventParticipations = local.eventParticipations
        ideas = local.ideas
        timeline = local.timeline
        eventExpenses = local.eventExpenses
        notes = local.notes
        eventMoments = local.eventMoments
        registry = local.registry
    }

    mutating func applyEntity(
        type: SyncEntityType,
        id: UUID,
        operation: SyncMutationOperation,
        payload: Data,
        decoder: JSONDecoder
    ) throws {
        switch type {
        case .participant:
            try applyRecord(WeddingMember.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &members)
        case .eventParticipation:
            var records = eventParticipations ?? []
            try applyRecord(EventParticipation.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &records)
            eventParticipations = records
        case .idea:
            try applyMediaRecord(WeddingIdea.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &ideas) { remote, local in
                var remote = remote
                if remote.imageData == nil, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .event:
            try applyMediaRecord(TimelineItem.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &timeline) { remote, local in
                var remote = remote
                if remote.imageData == nil, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .expense:
            try applyRecord(EventExpense.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &eventExpenses)
        case .note:
            try applyRecord(EventNote.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &notes)
        case .moment:
            try applyMediaRecord(EventMoment.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &eventMoments) { remote, local in
                var remote = remote
                if remote.imageData.isEmpty, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .registryItem:
            try applyMediaRecord(RegistryItem.self, id: id, operation: operation, payload: payload, decoder: decoder, to: &registry) { remote, local in
                var remote = remote
                if remote.imageData == nil, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .workspace, .attendance:
            break
        default:
            break
        }
    }
}

private func applyMediaRecord<Record: Identifiable & Decodable>(
    _ recordType: Record.Type,
    id: Record.ID,
    operation: SyncMutationOperation,
    payload: Data,
    decoder: JSONDecoder,
    to records: inout [Record],
    merging: (Record, Record) -> Record
) throws where Record.ID: Equatable {
    guard operation != .delete else {
        records.removeAll { $0.id == id }
        return
    }
    let remote = try decoder.decode(recordType, from: payload)
    if let index = records.firstIndex(where: { $0.id == id }) {
        records[index] = merging(remote, records[index])
    } else {
        records.append(remote)
    }
}

private func applyRecord<Record: Identifiable & Decodable>(
    _ recordType: Record.Type,
    id: UUID,
    operation: SyncMutationOperation,
    payload: Data,
    decoder: JSONDecoder,
    to records: inout [Record]
) throws where Record.ID == UUID {
    if operation == .delete {
        records.removeAll { $0.id == id }
        return
    }

    let record = try decoder.decode(recordType, from: payload)
    if let index = records.firstIndex(where: { $0.id == id }) {
        records[index] = record
    } else {
        records.append(record)
    }
}

@Model
final class WorkspaceRecord {
    /// A remote workspace can legitimately be cached for more than one signed-in
    /// account on the same device, so identity is `(ownerUserID, id)`.
    var id: UUID
    @Attribute(.externalStorage) var payload: Data
    var payloadSchemaVersion: Int
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String?
    var serverVersion: Int = 0

    init(
        id: UUID,
        payload: Data,
        payloadSchemaVersion: Int = WorkspaceArchiveV1.schemaVersion,
        sortOrder: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        ownerUserID: String? = nil,
        serverVersion: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.payloadSchemaVersion = payloadSchemaVersion
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ownerUserID = ownerUserID
        self.serverVersion = serverVersion
    }
}

/// Owns the one local write path for the workspace graph and its sync outbox.
/// Feature views continue to edit observable domain objects; observation below
/// turns those edits into a debounced, atomic SwiftData transaction.
@MainActor
@Observable
final class WorkspacePersistenceController {
    @ObservationIgnored let container: ModelContainer
    private(set) var lastError: Error?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder: JSONDecoder
    @ObservationIgnored private weak var observedLibrary: WorkspaceLibrary?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var suppressNextObservedChange = false
    @ObservationIgnored private(set) var activeUserID: String?
    @ObservationIgnored var onPendingMutations: (() -> Void)?

    init(
        isStoredInMemoryOnly: Bool = false,
        storeURL: URL? = nil
    ) throws {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                "Gatherory",
                schema: OfflineSyncSchema.schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "Gatherory",
                schema: OfflineSyncSchema.schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: .none
            )
        }
        container = try ModelContainer(
            for: OfflineSyncSchema.schema,
            configurations: [configuration]
        )
        context = ModelContext(container)
        context.autosaveEnabled = false

        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    static func bootstrap() -> WorkspacePersistenceController {
        do {
            return try WorkspacePersistenceController()
        } catch {
            do {
                let fallback = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
                fallback.lastError = error
                return fallback
            } catch {
                fatalError("Gatherory could not create a local data store: \(error)")
            }
        }
    }

    /// Restores the durable graph. Development fixtures are written only when
    /// the store is genuinely empty and intentionally do not enter the outbox.
    func restoreLibrary(seedData: Bool, ownerUserID: String? = nil) -> WorkspaceLibrary {
        do {
            let descriptor = FetchDescriptor<WorkspaceRecord>(
                sortBy: [SortDescriptor(\WorkspaceRecord.sortOrder)]
            )
            let records = try context.fetch(descriptor).filter {
                $0.ownerUserID == ownerUserID
            }

            activeUserID = ownerUserID

            if !records.isEmpty {
                let workspaces = try records.map { record -> WeddingWorkspace in
                    guard record.payloadSchemaVersion == WorkspaceArchiveV1.schemaVersion else {
                        throw WorkspacePersistenceError.unsupportedArchiveVersion(
                            record.payloadSchemaVersion
                        )
                    }
                    return try decoder.decode(WorkspaceArchiveV1.self, from: record.payload)
                        .makeWorkspace()
                }
                return WorkspaceLibrary(workspaces: workspaces)
            }

            let library = WorkspaceLibrary.bootstrap(seedData: seedData)
            if !library.workspaces.isEmpty {
                try persist(library, enqueuesMutations: false)
            }
            return library
        } catch {
            lastError = error
            return WorkspaceLibrary.bootstrap(seedData: seedData)
        }
    }

    func activate(
        userID: String?,
        in library: WorkspaceLibrary,
        seedData: Bool = false
    ) {
        guard activeUserID != userID else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        activeUserID = userID

        let restored = restoreLibrary(seedData: seedData, ownerUserID: userID)
        suppressNextObservedChange = true
        library.replaceAll(with: restored.workspaces)
    }

    func startObserving(_ library: WorkspaceLibrary) {
        guard observedLibrary !== library || !isObserving else { return }
        observedLibrary = library
        isObserving = true
        observeNextChange(in: library)
    }

    func flush(_ library: WorkspaceLibrary? = nil) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        guard let library = library ?? observedLibrary else { return }
        do {
            try persist(library, enqueuesMutations: true)
        } catch {
            context.rollback()
            lastError = error
        }
    }

    /// Removes every account-scoped local artifact after the backend confirms
    /// permanent account deletion. No outbox tombstones are produced because
    /// the deleted identity can no longer authenticate to deliver them.
    func purgeAllLocalData(from library: WorkspaceLibrary) throws {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        let userID = activeUserID
        let transfers = try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter { $0.ownerUserID == userID }
        for transfer in transfers {
            try? FileManager.default.removeItem(atPath: transfer.localFilePath)
            context.delete(transfer)
        }

        for record in try context.fetch(FetchDescriptor<WorkspaceRecord>())
        where record.ownerUserID == userID {
            context.delete(record)
        }
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>())
        where mutation.ownerUserID == userID {
            context.delete(mutation)
        }
        for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
        where checkpoint.ownerUserID == userID {
            context.delete(checkpoint)
        }
        for receipt in try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
        where receipt.ownerUserID == userID {
            context.delete(receipt)
        }

        try context.save()
        library.removeAll()
    }

    private func observeNextChange(in library: WorkspaceLibrary) {
        let persistence = self
        withObservationTracking {
            // Constructing archives intentionally reads every persisted field,
            // including value-type children, so any domain edit invalidates the
            // observation without feature code needing explicit save calls.
            _ = library.workspaces.map(WorkspaceArchiveV1.init(workspace:))
        } onChange: {
            Task { @MainActor in
                persistence.handleObservedChange()
            }
        }
    }

    private func handleObservedChange() {
        guard let library = observedLibrary else { return }
        observeNextChange(in: library)
        if suppressNextObservedChange {
            suppressNextObservedChange = false
            return
        }
        scheduleSave(of: library)
    }

    private func scheduleSave(of library: WorkspaceLibrary) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self, weak library] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, let library else { return }
            self.flush(library)
        }
    }

    private func persist(
        _ library: WorkspaceLibrary,
        enqueuesMutations: Bool
    ) throws {
        let archives = library.workspaces.map(WorkspaceArchiveV1.init(workspace:))
        let existingRecords = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .filter { $0.ownerUserID == activeUserID }
        let recordsByID = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })
        let pendingMutations = enqueuesMutations
            ? try context.fetch(FetchDescriptor<PendingMutation>())
                .filter { $0.ownerUserID == activeUserID }
            : []
        let persistedIDs = Set(archives.map(\.mainEventID))

        for record in existingRecords where !persistedIDs.contains(record.id) {
            context.delete(record)
            guard enqueuesMutations else { continue }
            coalesceDeletion(
                scopeID: record.id,
                baseVersion: record.serverVersion,
                pendingMutations: pendingMutations
            )
        }

        for (sortOrder, archive) in archives.enumerated() {
            let payload = try encoder.encode(archive)
            let syncPayload = try archive.syncPayload(using: encoder)
            let existingRecord = recordsByID[archive.mainEventID]
            let previousArchive = try existingRecord.map {
                try decoder.decode(WorkspaceArchiveV1.self, from: $0.payload)
            }
            let payloadChanged = existingRecord?.payload != payload
            let syncPayloadChanged = try previousArchive.map {
                try $0.syncPayload(using: encoder) != syncPayload
            } ?? true
            let orderChanged = existingRecord?.sortOrder != sortOrder

            guard existingRecord == nil || payloadChanged || orderChanged else { continue }

            if let existingRecord {
                existingRecord.payload = payload
                existingRecord.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                existingRecord.sortOrder = sortOrder
                existingRecord.updatedAt = .now
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: archive.mainEventID,
                        payload: payload,
                        sortOrder: sortOrder,
                        ownerUserID: activeUserID
                    )
                )
            }

            guard enqueuesMutations, syncPayloadChanged || existingRecord == nil else { continue }
            coalesceMutation(
                scopeID: archive.mainEventID,
                entityType: .workspace,
                entityID: archive.mainEventID,
                payload: syncPayload,
                operation: existingRecord == nil ? .create : .update,
                // Workspace snapshots are the compatibility/materialized view.
                // Independently versioned child records are the collaboration boundary.
                baseVersion: nil,
                pendingMutations: pendingMutations
            )
            try coalesceEntityMutations(
                scopeID: archive.mainEventID,
                previousArchive: previousArchive,
                archive: archive,
                pendingMutations: pendingMutations
            )
        }

        if context.hasChanges {
            try context.save()
            if enqueuesMutations {
                onPendingMutations?()
            }
        }
    }

    private func coalesceDeletion(
        scopeID: UUID,
        baseVersion: Int,
        pendingMutations: [PendingMutation]
    ) {
        if let pending = pendingMutations
            .filter({ mutation in
                mutation.scopeID == scopeID
                    && mutation.entityType == .workspace
                    && mutation.entityID == scopeID
                    && mutation.state == .pending
            })
            .max(by: { $0.createdAt < $1.createdAt }) {
            // If a local create never reached the server, deleting the create is
            // the complete operation. Otherwise the existing mutation becomes a
            // durable tombstone for the backend to acknowledge later.
            if pending.operation == .create {
                context.delete(pending)
            } else {
                pending.operation = .delete
                pending.payload = Data()
                pending.attemptCount = 0
                pending.nextAttemptAt = nil
                pending.lastFailureCode = nil
                pending.baseVersion = baseVersion
            }
            return
        }

        SyncOutbox.enqueue(
            SyncMutationDraft(
                scopeID: scopeID,
                entityType: .workspace,
                entityID: scopeID,
                operation: .delete,
                payload: Data(),
                baseVersion: baseVersion
            ),
            ownerUserID: activeUserID,
            in: context
        )
    }

    /// Repeated local edits should update one unsent outbox entry rather than
    /// create an unbounded mutation stream. Once an entry is leased or needs
    /// attention, a fresh update is inserted and the earlier identity remains
    /// stable for safe retries.
    private func coalesceMutation(
        scopeID: UUID,
        entityType: SyncEntityType,
        entityID: UUID,
        payload: Data,
        operation: SyncMutationOperation,
        baseVersion: Int?,
        pendingMutations: [PendingMutation]
    ) {
        if let pending = pendingMutations
            .filter({ mutation in
                mutation.scopeID == scopeID
                    && mutation.entityType == entityType
                    && mutation.entityID == entityID
                    && mutation.state == .pending
            })
            .max(by: { $0.createdAt < $1.createdAt }) {
            pending.payload = payload
            if pending.operation != .create {
                pending.operation = operation
            }
            pending.attemptCount = 0
            pending.nextAttemptAt = nil
            pending.lastFailureCode = nil
            pending.baseVersion = baseVersion
            return
        }

        SyncOutbox.enqueue(
            SyncMutationDraft(
                scopeID: scopeID,
                entityType: entityType,
                entityID: entityID,
                operation: operation,
                payload: payload,
                baseVersion: baseVersion
            ),
            ownerUserID: activeUserID,
            in: context
        )
    }

    private func coalesceEntityMutations(
        scopeID: UUID,
        previousArchive: WorkspaceArchiveV1?,
        archive: WorkspaceArchiveV1,
        pendingMutations: [PendingMutation]
    ) throws {
        let previousEntities = try previousArchive?.syncEntities(using: encoder) ?? [:]
        let entities = try archive.syncEntities(using: encoder)

        for (key, payload) in entities {
            let previousPayload = previousEntities[key]
            guard previousPayload != payload else { continue }
            coalesceMutation(
                scopeID: scopeID,
                entityType: key.type,
                entityID: key.id,
                payload: payload,
                operation: previousPayload == nil ? .create : .update,
                baseVersion: nil,
                pendingMutations: pendingMutations
            )
        }

        for key in previousEntities.keys where entities[key] == nil {
            coalesceEntityDeletion(
                scopeID: scopeID,
                key: key,
                pendingMutations: pendingMutations
            )
        }
    }

    private func coalesceEntityDeletion(
        scopeID: UUID,
        key: WorkspaceSyncEntityKey,
        pendingMutations: [PendingMutation]
    ) {
        if let pending = pendingMutations
            .filter({ mutation in
                mutation.scopeID == scopeID
                    && mutation.entityType == key.type
                    && mutation.entityID == key.id
                    && mutation.state == .pending
            })
            .max(by: { $0.createdAt < $1.createdAt }) {
            if pending.operation == .create {
                context.delete(pending)
            } else {
                pending.operation = .delete
                pending.payload = Data()
                pending.attemptCount = 0
                pending.nextAttemptAt = nil
                pending.lastFailureCode = nil
                pending.baseVersion = nil
            }
            return
        }

        SyncOutbox.enqueue(
            SyncMutationDraft(
                scopeID: scopeID,
                entityType: key.type,
                entityID: key.id,
                operation: .delete,
                payload: Data(),
                baseVersion: nil
            ),
            ownerUserID: activeUserID,
            in: context
        )
    }

    func pendingScopeIDs() throws -> Set<UUID> {
        Set(
            try context.fetch(FetchDescriptor<PendingMutation>())
                .filter { $0.ownerUserID == activeUserID }
                .map(\.scopeID)
        )
    }

    /// A rejection is durable state, not a connectivity problem. Surface its
    /// safe server code after relaunches so it cannot be cleared merely because
    /// there are no ready mutations left to claim.
    func pendingSyncAttentionFailureCode() throws -> String? {
        try context.fetch(FetchDescriptor<PendingMutation>())
            .filter {
                $0.ownerUserID == activeUserID
                    && $0.state == .requiresAttention
            }
            .sorted { $0.createdAt < $1.createdAt }
            .first?
            .lastFailureCode
    }

    /// Repairs a workspace scope that the server cannot materialize.
    ///
    /// This covers both legacy malformed workspace mutations and a server
    /// reset that removed a previously acknowledged scope. In the latter case
    /// only child mutations may remain locally and the server responds with
    /// `SYNC_SCOPE_NOT_FOUND`. Reusing rejected identifiers would replay their
    /// durable receipts, so replace the whole scope with a fresh workspace-first
    /// batch derived from the current local workspace.
    @discardableResult
    func repairWorkspaceScopeMismatches(from library: WorkspaceLibrary) throws -> Int {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == activeUserID }
        let workspacesByID = Dictionary(
            uniqueKeysWithValues: library.workspaces.map { ($0.mainEventID, $0) }
        )
        var repairedScopes = Set<UUID>()

        var repairs: [(corruptScopeID: UUID, workspace: WeddingWorkspace)] = []

        for mutation in mutations
        where mutation.entityType == .workspace && mutation.operation != .delete {
            let archive = try decoder.decode(WorkspaceArchiveV1.self, from: mutation.payload)
            let intendedScopeID = archive.mainEventID
            guard mutation.scopeID != intendedScopeID || mutation.entityID != intendedScopeID,
                  let workspace = workspacesByID[intendedScopeID]
            else { continue }
            repairs.append((mutation.scopeID, workspace))
        }

        // A valid local workspace can lose its server scope after a database
        // reset or interrupted migration. Re-bootstrap it from the local graph
        // rather than leaving child mutations permanently blocked.
        for mutation in mutations
        where mutation.state == .requiresAttention
            && mutation.lastFailureCode == "SYNC_SCOPE_NOT_FOUND"
            && mutation.operation != .delete
            && mutation.entityType != .workspace {
            guard let workspace = workspacesByID[mutation.scopeID] else { continue }
            repairs.append((mutation.scopeID, workspace))
        }

        for repair in repairs {
            let corruptScopeID = repair.corruptScopeID
            guard repairedScopes.insert(corruptScopeID).inserted else { continue }
            let workspace = repair.workspace
            let intendedScopeID = workspace.mainEventID
            let affected = mutations.filter { $0.scopeID == corruptScopeID }
            for affectedMutation in affected {
                context.delete(affectedMutation)
            }

            for transfer in try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            where transfer.ownerUserID == activeUserID && transfer.scopeID == corruptScopeID {
                try? FileManager.default.removeItem(atPath: transfer.localFilePath)
                context.delete(transfer)
            }

            for checkpoint in try context.fetch(FetchDescriptor<SyncCheckpoint>())
            where checkpoint.ownerUserID == activeUserID && checkpoint.scopeID == corruptScopeID {
                context.delete(checkpoint)
            }

            let repairedArchive = WorkspaceArchiveV1(workspace: workspace)
            SyncOutbox.enqueue(
                SyncMutationDraft(
                    scopeID: intendedScopeID,
                    entityType: .workspace,
                    entityID: intendedScopeID,
                    operation: .create,
                    payload: try repairedArchive.syncPayload(using: encoder),
                    baseVersion: nil
                ),
                ownerUserID: activeUserID,
                in: context
            )
            for (key, payload) in try repairedArchive.syncEntities(using: encoder) {
                SyncOutbox.enqueue(
                    SyncMutationDraft(
                        scopeID: intendedScopeID,
                        entityType: key.type,
                        entityID: key.id,
                        operation: .create,
                        payload: payload,
                        baseVersion: nil
                    ),
                    ownerUserID: activeUserID,
                    in: context
                )
            }
        }

        if context.hasChanges {
            try context.save()
            onPendingMutations?()
        }
        return repairedScopes.count
    }

    func prepareMediaTransfers(from library: WorkspaceLibrary) throws {
        let existing = try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter { $0.ownerUserID == activeUserID }
        let existingByEntity = Dictionary(
            existing.map { (($0.scopeID.uuidString + $0.entityID.uuidString), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var activeKeys = Set<String>()

        for workspace in library.workspaces {
            for attachment in workspace.mediaAttachments
            where attachment.mediaAssetID == nil {
                guard let data = attachment.imageData, !data.isEmpty else { continue }
                let key = workspace.mainEventID.uuidString + attachment.entityID.uuidString
                activeKeys.insert(key)
                if let transfer = existingByEntity[key] {
                    try data.write(to: URL(fileURLWithPath: transfer.localFilePath), options: .atomic)
                    if transfer.state == .requiresAttention {
                        transfer.state = .pending
                        transfer.nextAttemptAt = nil
                    }
                    continue
                }

                let contentType = Self.imageContentType(for: data)
                let id = UUID()
                let fileURL = try mediaOutboxURL(
                    transferID: id,
                    fileExtension: Self.fileExtension(for: contentType)
                )
                try data.write(to: fileURL, options: .atomic)
                context.insert(
                    PendingMediaTransfer(
                        id: id,
                        scopeID: workspace.mainEventID,
                        entityID: attachment.entityID,
                        localFileURL: fileURL,
                        contentType: contentType,
                        ownerUserID: activeUserID
                    )
                )
            }
        }

        for transfer in existing
        where !activeKeys.contains(transfer.scopeID.uuidString + transfer.entityID.uuidString) {
            try? FileManager.default.removeItem(atPath: transfer.localFilePath)
            context.delete(transfer)
        }
        if context.hasChanges { try context.save() }
    }

    /// Upgrades image-bearing mutations produced by builds that predate the
    /// R2 outbox. This runs before the first push so a legacy base64 payload
    /// cannot fail with HTTP 413 and block the media worker behind it.
    func sanitizePendingMediaMutations() throws {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == activeUserID && $0.operation != .delete }
        for mutation in mutations {
            let sanitized: Data?
            switch mutation.entityType {
            case .workspace:
                sanitized = try decoder.decode(WorkspaceArchiveV1.self, from: mutation.payload)
                    .syncPayload(using: encoder)
            case .idea:
                var record = try decoder.decode(WeddingIdea.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try encoder.encode(record)
            case .event:
                var record = try decoder.decode(TimelineItem.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try encoder.encode(record)
            case .moment:
                var record = try decoder.decode(EventMoment.self, from: mutation.payload)
                record.imageData = Data()
                sanitized = try encoder.encode(record)
            case .registryItem:
                var record = try decoder.decode(RegistryItem.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try encoder.encode(record)
            default:
                sanitized = nil
            }
            if let sanitized, mutation.payload != sanitized {
                mutation.payload = sanitized
                mutation.state = .pending
                mutation.leaseExpiresAt = nil
                mutation.nextAttemptAt = nil
                mutation.lastFailureCode = nil
            }
        }
        if context.hasChanges { try context.save() }
    }

    func pendingMediaTransfers(scopeID: UUID? = nil) throws -> [PendingMediaTransferSnapshot] {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter {
                $0.ownerUserID == activeUserID
                    && (scopeID == nil || $0.scopeID == scopeID)
                    && $0.state != .uploading
                    && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= .now)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                PendingMediaTransferSnapshot(
                    id: $0.id,
                    scopeID: $0.scopeID,
                    entityID: $0.entityID,
                    localFileURL: URL(fileURLWithPath: $0.localFilePath),
                    contentType: $0.contentType,
                    attemptCount: $0.attemptCount
                )
            }
    }

    func hasPendingMediaTransfers() throws -> Bool {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .contains { $0.ownerUserID == activeUserID }
    }

    func markMediaTransferUploading(_ id: UUID) throws {
        guard let transfer = try mediaTransfer(id) else { return }
        transfer.state = .uploading
        try context.save()
    }

    func completeMediaTransfer(_ id: UUID) throws {
        guard let transfer = try mediaTransfer(id) else { return }
        try? FileManager.default.removeItem(atPath: transfer.localFilePath)
        context.delete(transfer)
        try context.save()
    }

    func failMediaTransfer(_ id: UUID) throws {
        guard let transfer = try mediaTransfer(id) else { return }
        transfer.attemptCount += 1
        transfer.state = transfer.attemptCount >= 5 ? .requiresAttention : .pending
        transfer.nextAttemptAt = transfer.state == .pending
            ? Date.now.addingTimeInterval(min(pow(2, Double(transfer.attemptCount)), 60))
            : nil
        try context.save()
    }

    private func mediaTransfer(_ id: UUID) throws -> PendingMediaTransfer? {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .first { $0.id == id && $0.ownerUserID == activeUserID }
    }

    private func mediaOutboxURL(transferID: UUID, fileExtension: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appending(path: "GatheroryMediaOutbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(transferID.uuidString).\(fileExtension)")
    }

    private static func imageContentType(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "image/webp" }
        if bytes.count >= 12,
           String(bytes: bytes[4..<12], encoding: .ascii)?.contains("ftypheic") == true {
            return "image/heic"
        }
        if bytes.count >= 12,
           String(bytes: bytes[4..<12], encoding: .ascii)?.contains("ftypheif") == true {
            return "image/heif"
        }
        return "image/jpeg"
    }

    private static func fileExtension(for contentType: String) -> String {
        switch contentType {
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/heic": "heic"
        case "image/heif": "heif"
        default: "jpg"
        }
    }

    func currentCursor(for scopeID: UUID) throws -> String? {
        try context.fetch(FetchDescriptor<SyncCheckpoint>())
            .first(where: {
                $0.scopeID == scopeID && $0.ownerUserID == activeUserID
            })?
            .cursor
    }

    func applyBootstrap(
        _ snapshots: [RemoteWorkspaceSnapshot],
        entities: [RemoteEntitySnapshot] = [],
        to library: WorkspaceLibrary
    ) throws {
        let pendingScopes = try pendingScopeIDs()
        var remoteWorkspaces: [WeddingWorkspace] = []
        let entitiesByScope = Dictionary(grouping: entities, by: \.scopeID)

        for snapshot in snapshots where !pendingScopes.contains(snapshot.scopeID) {
            guard snapshot.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                    snapshot.effectivePayloadSchemaVersion
                )
            }
            var archive = try decoder.decode(WorkspaceArchiveV1.self, from: snapshot.payload)
            for entity in entitiesByScope[snapshot.scopeID] ?? [] {
                guard entity.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                    throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                        entity.effectivePayloadSchemaVersion
                    )
                }
                try archive.applyEntity(
                    type: entity.entityType,
                    id: entity.entityID,
                    operation: .update,
                    payload: entity.payload,
                    decoder: decoder
                )
            }
            let payload = try encoder.encode(archive)
            let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
                .first(where: {
                    $0.id == snapshot.scopeID && $0.ownerUserID == activeUserID
                })

            if let record {
                record.payload = payload
                record.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                record.serverVersion = snapshot.serverVersion
                record.updatedAt = snapshot.updatedAt
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: snapshot.scopeID,
                        payload: payload,
                        sortOrder: library.workspaces.count + remoteWorkspaces.count,
                        updatedAt: snapshot.updatedAt,
                        ownerUserID: activeUserID,
                        serverVersion: snapshot.serverVersion
                    )
                )
            }
            remoteWorkspaces.append(archive.makeWorkspace())
        }

        if context.hasChanges { try context.save() }
        guard !remoteWorkspaces.isEmpty else { return }
        suppressNextObservedChange = true
        remoteWorkspaces.forEach(library.upsert)
    }

    func applyRemotePage(
        _ page: SyncPullPage,
        scopeID: UUID,
        to library: WorkspaceLibrary
    ) throws {
        let appliedIDs = Set(
            try context.fetch(FetchDescriptor<AppliedSyncEnvelope>())
                .filter { $0.ownerUserID == activeUserID }
                .map(\.id)
        )
        let record = try context.fetch(FetchDescriptor<WorkspaceRecord>())
            .first(where: {
                $0.id == scopeID && $0.ownerUserID == activeUserID
            })
        var archive = try record.map {
            try decoder.decode(WorkspaceArchiveV1.self, from: $0.payload)
        }
        var workspaceServerVersion = record?.serverVersion ?? 0
        var latestUpdatedAt = record?.updatedAt ?? .distantPast
        var shouldDeleteWorkspace = false

        for change in page.changes where !appliedIDs.contains(change.id) {
            guard change.effectivePayloadSchemaVersion == SyncPayloadContract.currentVersion else {
                throw WorkspacePersistenceError.unsupportedSyncPayloadVersion(
                    change.effectivePayloadSchemaVersion
                )
            }
            if change.entityType == .workspace {
                switch change.operation {
                case .delete:
                    archive = nil
                    shouldDeleteWorkspace = true
                case .create, .update:
                    var remoteArchive = try decoder.decode(
                        WorkspaceArchiveV1.self,
                        from: change.payload
                    )
                    if let archive {
                        remoteArchive.preserveCollaborativeEntities(from: archive)
                    }
                    archive = remoteArchive
                    workspaceServerVersion = change.serverVersion
                    shouldDeleteWorkspace = false
                }
            } else if var currentArchive = archive {
                try currentArchive.applyEntity(
                    type: change.entityType,
                    id: change.entityID,
                    operation: change.operation,
                    payload: change.payload,
                    decoder: decoder
                )
                archive = currentArchive
            }
            latestUpdatedAt = max(latestUpdatedAt, change.occurredAt)

            context.insert(
                AppliedSyncEnvelope(
                    id: change.id,
                    scopeID: scopeID,
                    ownerUserID: activeUserID
                )
            )
        }

        if shouldDeleteWorkspace {
            if let record { context.delete(record) }
        } else if let archive {
            let payload = try encoder.encode(archive)
            if let record {
                record.payload = payload
                record.payloadSchemaVersion = WorkspaceArchiveV1.schemaVersion
                record.serverVersion = workspaceServerVersion
                record.updatedAt = latestUpdatedAt
            } else {
                context.insert(
                    WorkspaceRecord(
                        id: scopeID,
                        payload: payload,
                        sortOrder: library.workspaces.count,
                        updatedAt: latestUpdatedAt,
                        ownerUserID: activeUserID,
                        serverVersion: workspaceServerVersion
                    )
                )
            }
        }

        let checkpoint = try context.fetch(FetchDescriptor<SyncCheckpoint>())
            .first(where: {
                $0.scopeID == scopeID && $0.ownerUserID == activeUserID
            })
        if let checkpoint {
            checkpoint.cursor = page.nextCursor
            checkpoint.lastSuccessfulSyncAt = .now
        } else {
            context.insert(
                SyncCheckpoint(
                    scopeID: scopeID,
                    cursor: page.nextCursor,
                    lastSuccessfulSyncAt: .now,
                    ownerUserID: activeUserID
                )
            )
        }
        try context.save()

        suppressNextObservedChange = true
        if shouldDeleteWorkspace {
            library.remove(workspaceID: scopeID)
        } else if let archive {
            library.upsert(archive.makeWorkspace())
        }
    }
}

enum WorkspacePersistenceError: Error {
    case unsupportedArchiveVersion(Int)
    case unsupportedSyncPayloadVersion(Int)
}
