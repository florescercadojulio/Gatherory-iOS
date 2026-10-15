import Foundation

/// The first durable representation of a Gatherory workspace.
///
/// The app's observable domain graph remains optimized for SwiftUI. Keeping a
/// versioned archive at the persistence boundary lets us adopt SwiftData now
/// without forcing views to understand storage concerns. A later schema can
/// promote frequently queried children into their own models without changing
/// the feature-facing `PlanningWorkspace` API.
struct WorkspaceArchiveV1: Codable {
    static let schemaVersion = 1

    let mainEventID: UUID
    var title: String
    var mainEventStartsAt: Date
    var mainEventEndsAt: Date?
    var mainEventIsAllDay: Bool
    var mainEventTimeZoneIdentifier: String
    var mainEventLocation: EventLocation?
    var mainEventImageData: Data?
    var mainEventMediaAssetID: UUID?
    let venueName: String
    let location: String
    var dressCode: String
    var eventMessage: String
    let planningMode: PlanningMode
    var members: [WorkspaceMember]
    /// Optional so archives written before relationship normalization migrate.
    var eventParticipations: [EventParticipation]?
    var mainEventParticipantIDs: [UUID]
    var ideas: [PlanningIdea]
    var timeline: [TimelineItem]
    var eventExpenses: [EventExpense]
    var workspaceBudgetCap: Decimal?
    /// Optional for archives written before currency was workspace-scoped.
    let currencyCode: String?
    var mainEventBudgetCap: Decimal?
    var notes: [EventNote]
    var ideaResponses: [IdeaResponse]?
    var mainEventStatus: MainEventStatus
    let mainEventResponse: EventResponse?
    var eventMoments: [EventMoment]
    /// Optional in version 1 archives written before installed guides existed.
    var guides: [ExperienceGuide]?
    /// Optional for ordinary workspaces and archives predating blueprints.
    var experienceConfiguration: InstalledExperienceConfiguration?
    let isMainEventDeleted: Bool
    var registry: [RegistryItem]
    let isRegistryShared: Bool
    let isCollaboratorLinkEnabled: Bool
    let requiresCollaboratorApproval: Bool
    let defaultCollaboratorPermission: PlanningPermission
    /// Absent in archives written before child events became independent scopes.
    var isScopedEvent: Bool?
    /// Optional server projection retaining fields not represented by the
    /// workspace's main-event editor, such as purpose and scheduling state.
    var scopedEvent: TimelineItem?

    init(workspace: PlanningWorkspace) {
        mainEventID = workspace.mainEventID
        title = workspace.title
        mainEventStartsAt = workspace.mainEventStartsAt
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
        ideaResponses = workspace.ideaResponses
        mainEventStatus = workspace.mainEventStatus
        mainEventResponse = workspace.mainEventResponse
        eventMoments = workspace.eventMoments
        guides = workspace.guides
        experienceConfiguration = workspace.experienceConfiguration
        isMainEventDeleted = workspace.isMainEventDeleted
        registry = workspace.registry
        isRegistryShared = workspace.isRegistryShared
        isCollaboratorLinkEnabled = workspace.isCollaboratorLinkEnabled
        requiresCollaboratorApproval = workspace.requiresCollaboratorApproval
        defaultCollaboratorPermission = workspace.defaultCollaboratorPermission
        isScopedEvent = workspace.isScopedEvent
        scopedEvent = workspace.scopedMainEventDetails
    }

    func makeWorkspace() -> PlanningWorkspace {
        let workspace = PlanningWorkspace(
            mainEventID: mainEventID,
            isScopedEvent: isScopedEvent == true,
            title: title,
            mainEventStartsAt: mainEventStartsAt,
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
            timeline: isScopedEvent == true ? [] : timeline,
            eventExpenses: eventExpenses,
            workspaceBudgetCap: workspaceBudgetCap,
            currencyCode: currencyCode ?? Locale.current.currency?.identifier ?? "USD",
            mainEventBudgetCap: mainEventBudgetCap,
            notes: notes,
            ideaResponses: ideaResponses ?? [],
            mainEventStatus: mainEventStatus,
            mainEventResponse: mainEventResponse,
            eventMoments: eventMoments,
            guides: guides ?? [],
            experienceConfiguration: experienceConfiguration,
            isMainEventDeleted: isMainEventDeleted,
            registry: registry,
            isRegistryShared: isRegistryShared,
            isCollaboratorLinkEnabled: isCollaboratorLinkEnabled,
            requiresCollaboratorApproval: requiresCollaboratorApproval,
            defaultCollaboratorPermission: defaultCollaboratorPermission
        )
        if var scopedEvent, isScopedEvent == true {
            scopedEvent.parentEventID = nil
            scopedEvent.linkedIdeaID = nil
            workspace.scopedMainEventDetails = scopedEvent
        } else {
            workspace.scopedMainEventDetails = scopedEvent
        }
        return workspace
    }
}
