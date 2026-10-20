import Foundation

struct WorkspaceSyncEntityKey: Hashable {
    let type: SyncEntityType
    let id: UUID
}

extension WorkspaceArchiveV1 {
    func syncPayload(using codec: WorkspaceArchiveCodec) throws -> Data {
        var remote = self
        remote.scopedEvent = nil
        // To-dos have independent versions and are projected only to planners.
        remote.todos = nil
        // Responses have independent versions; a workspace snapshot must not
        // overwrite a teammate's input or resend it under another account.
        remote.ideaResponses = nil
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
        return try codec.encode(remote)
    }

    func syncEntities(using codec: WorkspaceArchiveCodec) throws -> [WorkspaceSyncEntityKey: Data] {
        var entities: [WorkspaceSyncEntityKey: Data] = [:]

        if isScopedEvent == true {
            entities[.init(type: .event, id: mainEventID)] = try codec.encode(scopedMainEvent)
        }

        for member in members {
            entities[.init(type: .participant, id: member.id)] = try codec.encode(member)
        }
        for participation in eventParticipations ?? [] {
            entities[.init(type: .eventParticipation, id: participation.id)] = try codec.encode(participation)
        }
        for idea in ideas {
            var remote = idea
            remote.imageData = nil
            entities[.init(type: .idea, id: idea.id)] = try codec.encode(remote)
        }
        if isScopedEvent != true {
            for event in timeline {
                var remote = event
                remote.imageData = nil
                entities[.init(type: .event, id: event.id)] = try codec.encode(remote)
            }
        }
        for expense in eventExpenses {
            entities[.init(type: .expense, id: expense.id)] = try codec.encode(expense)
        }
        for note in notes {
            entities[.init(type: .note, id: note.id)] = try codec.encode(note)
        }
        for response in ideaResponses ?? [] {
            entities[.init(type: .ideaResponse, id: response.id)] = try codec.encode(response)
        }
        for todo in todos ?? [] where isScopedEvent != true || todo.eventID == mainEventID {
            entities[.init(type: .todo, id: todo.id)] = try codec.encode(todo)
        }
        for moment in eventMoments {
            var remote = moment
            remote.imageData = Data()
            entities[.init(type: .moment, id: moment.id)] = try codec.encode(remote)
        }
        for item in registry {
            var remote = item
            remote.imageData = nil
            entities[.init(type: .registryItem, id: item.id)] = try codec.encode(remote)
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
        // New server projections carry the authorized canonical todo list.
        // Keep the local list only for older snapshots that omit it; pending
        // mutations are overlaid separately by the remote merger.
        if todos == nil {
            todos = local.todos
        }
        ideaResponses = local.ideaResponses
        eventMoments = local.eventMoments
        registry = local.registry
    }

    /// Bootstrap is metadata-only. Keep this account's downloaded bytes when
    /// the server still references exactly the same asset, without restoring
    /// removed records or overwriting remote fields with an older local copy.
    mutating func preserveDownloadedMedia(from local: WorkspaceArchiveV1) {
        if mainEventImageData == nil, let assetID = mainEventMediaAssetID,
           assetID == local.mainEventMediaAssetID {
            mainEventImageData = local.mainEventImageData
        }
        for index in ideas.indices {
            guard ideas[index].imageData == nil, let assetID = ideas[index].mediaAssetID,
                  let cached = local.ideas.first(where: { $0.id == ideas[index].id && $0.mediaAssetID == assetID }) else { continue }
            ideas[index].imageData = cached.imageData
        }
        for index in timeline.indices {
            guard timeline[index].imageData == nil, let assetID = timeline[index].mediaAssetID,
                  let cached = local.timeline.first(where: { $0.id == timeline[index].id && $0.mediaAssetID == assetID }) else { continue }
            timeline[index].imageData = cached.imageData
        }
        for index in registry.indices {
            guard registry[index].imageData == nil, let assetID = registry[index].mediaAssetID,
                  let cached = local.registry.first(where: { $0.id == registry[index].id && $0.mediaAssetID == assetID }) else { continue }
            registry[index].imageData = cached.imageData
        }
        for index in eventMoments.indices {
            guard eventMoments[index].imageData.isEmpty, let assetID = eventMoments[index].mediaAssetID,
                  let cached = local.eventMoments.first(where: { $0.id == eventMoments[index].id && $0.mediaAssetID == assetID }) else { continue }
            eventMoments[index].imageData = cached.imageData
        }
    }

    mutating func applyEntity(
        type: SyncEntityType,
        id: UUID,
        operation: SyncMutationOperation,
        payload: Data,
        codec: WorkspaceArchiveCodec
    ) throws {
        switch type {
        case .participant:
            try applyRecord(WorkspaceMember.self, id: id, operation: operation, payload: payload, codec: codec, to: &members)
        case .eventParticipation:
            var records = eventParticipations ?? []
            try applyRecord(EventParticipation.self, id: id, operation: operation, payload: payload, codec: codec, to: &records)
            eventParticipations = records
        case .idea:
            try applyMediaRecord(PlanningIdea.self, id: id, operation: operation, payload: payload, codec: codec, to: &ideas) { remote, local in
                var remote = remote
                if remote.imageData == nil, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .event:
            if isScopedEvent == true, id == mainEventID, operation != .delete {
                let event = try codec.decode(TimelineItem.self, from: payload)
                applyScopedMainEvent(event)
                return
            }
            if isScopedEvent == true { return }
            try applyMediaRecord(TimelineItem.self, id: id, operation: operation, payload: payload, codec: codec, to: &timeline) { remote, local in
                var remote = remote
                if remote.imageData == nil, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .expense:
            try applyRecord(EventExpense.self, id: id, operation: operation, payload: payload, codec: codec, to: &eventExpenses)
        case .note:
            try applyRecord(EventNote.self, id: id, operation: operation, payload: payload, codec: codec, to: &notes)
        case .todo:
            var records = todos ?? []
            if operation == .delete {
                records.removeAll { $0.id == id }
            } else {
                let todo = try codec.decode(EventTodo.self, from: payload)
                let validEventIDs = Set([mainEventID] + (isScopedEvent == true ? [] : timeline.map(\.id)))
                guard todo.id == id, validEventIDs.contains(todo.eventID),
                      EventTodo.normalizedTitle(todo.title) == todo.title,
                      EventTodo.isValidDueDate(todo.dueDate),
                      EventTodo.isValidWebsiteURL(todo.websiteURL) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Invalid event to-do entity.")
                    )
                }
                if let index = records.firstIndex(where: { $0.id == id }) {
                    records[index] = todo
                } else {
                    records.append(todo)
                }
            }
            todos = records
        case .ideaResponse:
            var responses = ideaResponses ?? []
            try applyRecord(IdeaResponse.self, id: id, operation: operation, payload: payload, codec: codec, to: &responses)
            ideaResponses = responses
        case .moment:
            try applyMediaRecord(EventMoment.self, id: id, operation: operation, payload: payload, codec: codec, to: &eventMoments) { remote, local in
                var remote = remote
                if remote.imageData.isEmpty, remote.mediaAssetID == local.mediaAssetID {
                    remote.imageData = local.imageData
                }
                return remote
            }
        case .registryItem:
            try applyMediaRecord(RegistryItem.self, id: id, operation: operation, payload: payload, codec: codec, to: &registry) { remote, local in
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

extension WorkspaceArchiveV1 {
    fileprivate var scopedMainEvent: TimelineItem {
        let projectedStatus: MainEventStatus? = if let scopedEvent {
            Self.projectedMainStatus(scopedEvent)
        } else {
            nil
        }
        let status: EventStatus = if let scopedEvent,
                                    projectedStatus == mainEventStatus {
            scopedEvent.status
        } else {
            switch mainEventStatus {
            case .draft: .draft
            case .ongoing, .finished: .approved
            case .cancelled: .cancelled
            }
        }
        var event = scopedEvent ?? TimelineItem(
            id: mainEventID, title: title, category: .other, purpose: .eventExperience,
            scheduledAt: mainEventStartsAt,
            eventLocation: mainEventLocation,
            endsAt: mainEventEndsAt,
            isAllDay: mainEventIsAllDay, timeZoneIdentifier: mainEventTimeZoneIdentifier,
            participantIDs: mainEventParticipantIDs,
            status: status, completionStatus: mainEventStatus == .finished ? .complete : .upcoming
        )
        let schedulingChanged = event.scheduledAt != mainEventStartsAt
            || event.endsAt != mainEventEndsAt
            || event.isAllDay != mainEventIsAllDay
            || event.timeZoneIdentifier != mainEventTimeZoneIdentifier
        if schedulingChanged { event.schedulingState = .scheduled }
        event.title = title
        event.scheduledAt = mainEventStartsAt
        event.endsAt = mainEventEndsAt
        event.isAllDay = mainEventIsAllDay
        event.timeZoneIdentifier = mainEventTimeZoneIdentifier
        event.eventLocation = mainEventLocation
        event.participantIDs = mainEventParticipantIDs
        event.status = status
        if projectedStatus != mainEventStatus {
            event.completionStatus = mainEventStatus == .finished ? .complete : .upcoming
        }
        event.parentEventID = nil
        event.linkedIdeaID = nil
        event.imageData = nil
        event.mediaAssetID = mainEventMediaAssetID
        event.eventDescription = eventMessage
        event.dressCode = dressCode
        event.budgetCap = mainEventBudgetCap
        return event
    }

    static func projectedMainStatus(_ event: TimelineItem) -> MainEventStatus {
        if event.status == .cancelled { return .cancelled }
        if event.completionStatus == .complete { return .finished }
        return event.status == .draft ? .draft : .ongoing
    }

    mutating func applyScopedMainEvent(_ event: TimelineItem) {
        var isolatedEvent = event
        isolatedEvent.parentEventID = nil
        isolatedEvent.linkedIdeaID = nil
        scopedEvent = isolatedEvent
        title = event.title
        mainEventStartsAt = event.scheduledAt
        mainEventEndsAt = event.endsAt
        mainEventIsAllDay = event.isAllDay
        mainEventTimeZoneIdentifier = event.timeZoneIdentifier
        mainEventLocation = event.eventLocation
        mainEventParticipantIDs = event.participantIDs
        mainEventStatus = event.status == .cancelled ? .cancelled
            : event.completionStatus == .complete ? .finished
            : event.status == .draft ? .draft : .ongoing
        mainEventMediaAssetID = event.mediaAssetID
        eventMessage = event.eventDescription
        dressCode = event.dressCode
        mainEventBudgetCap = event.budgetCap
        if event.imageData != nil { mainEventImageData = event.imageData }
    }

    mutating func enforceScopedIsolation() {
        guard isScopedEvent == true else { return }
        timeline = []
        workspaceBudgetCap = nil
        if let eventParticipations {
            self.eventParticipations = eventParticipations.filter { $0.eventID == mainEventID }
        }
        todos = (todos ?? []).filter { $0.eventID == mainEventID }
        if var scopedEvent {
            scopedEvent.parentEventID = nil
            scopedEvent.linkedIdeaID = nil
            self.scopedEvent = scopedEvent
        }
    }

    func canEditTodo(eventID: UUID, ownerUserID: String?) -> Bool {
        // A missing account identity is used by local previews and persistence
        // fixtures. Authenticated sync always supplies an owner identity.
        guard let ownerUserID else { return true }
        guard let member = members.first(where: { $0.userID == ownerUserID }) else { return false }

        let participation = eventParticipations?.first { $0.eventID == eventID && $0.memberID == member.id }
        let eventParticipantIDs: [UUID]
        if eventID == mainEventID {
            eventParticipantIDs = mainEventParticipantIDs
        } else if isScopedEvent != true,
                  let event = timeline.first(where: { $0.id == eventID && $0.parentEventID == mainEventID }) {
            eventParticipantIDs = event.participantIDs
        } else {
            return false
        }
        let invitationStatus = participation?.invitationStatus ?? member.invitationStatus
        guard (participation != nil || eventParticipantIDs.contains(member.id)),
              invitationStatus == .active else { return false }
        let role = participation?.role ?? member.participantRole
        let permission = participation?.planningPermission ?? member.planningPermission
        switch role {
        case .host:
            return true
        case .collaborator:
            return permission == .manage || permission == .contribute
        case .guest:
            return false
        }
    }
}

private func applyMediaRecord<Record: Identifiable & Decodable>(
    _ recordType: Record.Type,
    id: Record.ID,
    operation: SyncMutationOperation,
    payload: Data,
    codec: WorkspaceArchiveCodec,
    to records: inout [Record],
    merging: (Record, Record) -> Record
) throws where Record.ID: Equatable {
    guard operation != .delete else {
        records.removeAll { $0.id == id }
        return
    }
    let remote = try codec.decode(recordType, from: payload)
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
    codec: WorkspaceArchiveCodec,
    to records: inout [Record]
) throws where Record.ID == UUID {
    if operation == .delete {
        records.removeAll { $0.id == id }
        return
    }

    let record = try codec.decode(recordType, from: payload)
    if let index = records.firstIndex(where: { $0.id == id }) {
        records[index] = record
    } else {
        records.append(record)
    }
}
