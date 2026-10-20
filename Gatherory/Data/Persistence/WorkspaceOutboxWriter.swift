import Foundation
import SwiftData

/// Stages outbox changes in the controller's transaction.
/// The caller supplies mutations already filtered to this account and owns
/// saving, rollback, and notification after the transaction succeeds.
@MainActor
struct WorkspaceOutboxWriter {
    private let context: ModelContext
    private let codec: WorkspaceArchiveCodec
    private let ownerUserID: String?

    init(context: ModelContext, codec: WorkspaceArchiveCodec, ownerUserID: String?) {
        self.context = context
        self.codec = codec
        self.ownerUserID = ownerUserID
    }

    func coalesceDeletion(
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
            ownerUserID: ownerUserID,
            in: context
        )
    }

    /// Repeated local edits should update one unsent outbox entry rather than
    /// create an unbounded mutation stream. Once an entry is leased or needs
    /// attention, a fresh update is inserted and the earlier identity remains
    /// stable for safe retries.
    func coalesceMutation(
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
            if entityType != .todo || pending.operation == .create {
                pending.baseVersion = baseVersion
            }
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
            ownerUserID: ownerUserID,
            in: context
        )
    }

    func coalesceEntityMutations(
        scopeID: UUID,
        previousArchive: WorkspaceArchiveV1?,
        archive: WorkspaceArchiveV1,
        pendingMutations: [PendingMutation]
    ) throws {
        let previousEntities = try previousArchive?.syncEntities(using: codec) ?? [:]
        let entities = try archive.syncEntities(using: codec)

        for (key, payload) in entities {
            let previousPayload = previousEntities[key]
            guard previousPayload != payload else { continue }
            if key.type == .todo {
                guard let todo = try? codec.decode(EventTodo.self, from: payload),
                      archive.canEditTodo(eventID: todo.eventID, ownerUserID: ownerUserID) else { continue }
            }
            if archive.isScopedEvent == true,
               !isAllowedScopedMutation(
                key: key,
                previousPayload: previousPayload,
                payload: payload,
                archive: archive
               ) {
                continue
            }
            let baseVersion: Int? = if key.type == .todo {
                previousPayload == nil ? 0 : (try RemoteEntityVersionRecord.version(
                    in: context, scopeID: scopeID, entityType: .todo,
                    entityID: key.id, ownerUserID: ownerUserID
                ) ?? 0)
            } else {
                nil
            }
            coalesceMutation(
                scopeID: scopeID,
                entityType: key.type,
                entityID: key.id,
                payload: payload,
                operation: previousPayload == nil ? .create : .update,
                baseVersion: baseVersion,
                pendingMutations: pendingMutations
            )
        }

        for key in previousEntities.keys where entities[key] == nil {
            if key.type == .todo {
                guard let previousPayload = previousEntities[key],
                      let todo = try? codec.decode(EventTodo.self, from: previousPayload),
                      archive.canEditTodo(eventID: todo.eventID, ownerUserID: ownerUserID),
                      previousArchive?.canEditTodo(eventID: todo.eventID, ownerUserID: ownerUserID) == true else { continue }
            }
            if archive.isScopedEvent == true,
               key.type == .participant || key.type == .eventParticipation
                || (key.type == .event && key.id != archive.mainEventID) {
                continue
            }
            coalesceEntityDeletion(
                scopeID: scopeID,
                key: key,
                baseVersion: key.type == .todo
                    ? (try RemoteEntityVersionRecord.version(
                        in: context, scopeID: scopeID, entityType: .todo,
                        entityID: key.id, ownerUserID: ownerUserID
                    ) ?? 0)
                    : nil,
                pendingMutations: pendingMutations
            )
        }
    }

    private func isAllowedScopedMutation(
        key: WorkspaceSyncEntityKey,
        previousPayload: Data?,
        payload: Data,
        archive: WorkspaceArchiveV1
    ) -> Bool {
        switch key.type {
        case .participant:
            guard let member = try? codec.decode(WorkspaceMember.self, from: payload) else { return false }
            // New people are authorized by the server's manager check. Existing
            // shared profiles may only be edited by their own account.
            return previousPayload == nil || member.userID == ownerUserID
        case .eventParticipation:
            guard let previousPayload,
                  let previous = try? codec.decode(EventParticipation.self, from: previousPayload),
                  let current = try? codec.decode(EventParticipation.self, from: payload),
                  previous.memberID == current.memberID,
                  let member = archive.members.first(where: { $0.id == current.memberID }),
                  member.userID == ownerUserID else { return false }
            // Planning permissions and invitation roles are canonical server
            // state. Native sync may carry only this account's RSVP change.
            return previous.role == current.role
                && previous.planningPermission == current.planningPermission
                && previous.invitationStatus == current.invitationStatus
                && previous.attendance != current.attendance
        case .todo:
            guard let todo = try? codec.decode(EventTodo.self, from: payload) else { return false }
            return todo.id == key.id
                && todo.eventID == archive.mainEventID
                && EventTodo.normalizedTitle(todo.title) == todo.title
                && EventTodo.isValidDueDate(todo.dueDate)
                && EventTodo.isValidWebsiteURL(todo.websiteURL)
        default:
            return true
        }
    }

    private func coalesceEntityDeletion(
        scopeID: UUID,
        key: WorkspaceSyncEntityKey,
        baseVersion: Int?,
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
                // Preserve the CAS version at which an unsent edit began.
                // Remote pulls must not silently rebase a conflicting todo.
                if key.type != .todo { pending.baseVersion = baseVersion }
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
                baseVersion: baseVersion
            ),
            ownerUserID: ownerUserID,
            in: context
        )
    }
}
