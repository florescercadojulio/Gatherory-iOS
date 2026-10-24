import SwiftUI

enum MainInvitationEditField: String, Identifiable, Equatable {
    case title
    case date
    case location

    var id: String { rawValue }
}

struct MainInvitationDateValue: Equatable {
    var startsAt: Date
    var endsAt: Date?
    var isAllDay: Bool
    var timeZoneIdentifier: String
}

struct MainInvitationEditSnapshot: Identifiable {
    let field: MainInvitationEditField
    let accountID: String?
    let localGuestProfileID: UUID?
    let principalGeneration: UInt64
    let mainEventID: UUID
    let isScopedEvent: Bool
    let memberID: UUID
    let role: WorkspaceRole
    let permission: PlanningPermission
    let title: String
    let startsAt: Date
    let endsAt: Date?
    let isAllDay: Bool
    let timeZoneIdentifier: String
    let location: EventLocation?
    let invitationDateIsUndecided: Bool

    var id: String { "\(field.rawValue)-\(mainEventID.uuidString)" }

    func matches(
        accountID currentAccountID: String?,
        localGuestProfileID currentLocalGuestProfileID: UUID?,
        principalGeneration currentPrincipalGeneration: UInt64?,
        mainEventID currentMainEventID: UUID,
        isScopedEvent currentIsScopedEvent: Bool,
        reference currentReference: EventReference,
        member currentMember: WorkspaceMember?,
        canManageMainEvent: Bool,
        isCurrentPrincipal: Bool,
        isInvitationProjection: Bool,
        title currentTitle: String,
        startsAt currentStartsAt: Date,
        endsAt currentEndsAt: Date?,
        isAllDay currentIsAllDay: Bool,
        timeZoneIdentifier currentTimeZoneIdentifier: String,
        location currentLocation: EventLocation?,
        invitationDateIsUndecided currentInvitationDateIsUndecided: Bool
    ) -> Bool {
        guard canManageMainEvent, isCurrentPrincipal, !isInvitationProjection,
              !currentIsScopedEvent, !isScopedEvent,
              currentAccountID == accountID,
              currentLocalGuestProfileID == localGuestProfileID,
              (currentAccountID != nil) != (currentLocalGuestProfileID != nil),
              currentPrincipalGeneration == principalGeneration,
              currentMainEventID == mainEventID,
              currentReference == .main,
              let currentMember,
              currentMember.id == memberID,
              currentMember.participantRole == role,
              currentMember.participantRole != .guest,
              currentMember.planningPermission == permission,
              currentMember.planningPermission != .viewOnly,
              currentMember.invitationStatus == .active else { return false }
        switch field {
        case .title:
            return currentTitle == title
        case .date:
            return currentStartsAt == startsAt
                && currentEndsAt == endsAt
                && currentIsAllDay == isAllDay
                && currentTimeZoneIdentifier == timeZoneIdentifier
                && currentInvitationDateIsUndecided == invitationDateIsUndecided
        case .location:
            return currentLocation == location
        }
    }

    init(
        field: MainInvitationEditField,
        accountID: String?,
        localGuestProfileID: UUID? = nil,
        principalGeneration: UInt64,
        mainEventID: UUID,
        isScopedEvent: Bool,
        member: WorkspaceMember,
        title: String,
        startsAt: Date,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        location: EventLocation?,
        invitationDateIsUndecided: Bool
    ) {
        self.field = field
        self.accountID = accountID
        self.localGuestProfileID = localGuestProfileID
        self.principalGeneration = principalGeneration
        self.mainEventID = mainEventID
        self.isScopedEvent = isScopedEvent
        self.memberID = member.id
        self.role = member.participantRole
        self.permission = member.planningPermission
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.location = location
        self.invitationDateIsUndecided = invitationDateIsUndecided
    }
}

struct MainInvitationEventValues: Equatable {
    var title: String
    var date: MainInvitationDateValue
    var location: EventLocation?

    mutating func apply(title: String) { self.title = title }
    mutating func apply(date: MainInvitationDateValue) { self.date = date }
    mutating func apply(location: EventLocation?) { self.location = location }
}

enum MainInvitationEditValue {
    case title(String)
    case date(MainInvitationDateValue)
    case location(EventLocation?)
}

@MainActor
enum MainInvitationEditCommand {
    static func isCurrent(
        _ snapshot: MainInvitationEditSnapshot,
        in workspace: PlanningWorkspace,
        accountID: String?,
        localGuestProfileID: UUID?,
        principalGeneration: UInt64?,
        reference: EventReference,
        isCurrentPrincipal: Bool
    ) -> Bool {
        guard workspace.selectedEventReference == reference else { return false }
        let date = MainInvitationDateValue(
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier
        )
        return snapshot.matches(
            accountID: accountID,
            localGuestProfileID: localGuestProfileID,
            principalGeneration: principalGeneration,
            mainEventID: workspace.mainEventID,
            isScopedEvent: workspace.isScopedEvent,
            reference: reference,
            member: workspace.currentViewerMember(for: .main),
            canManageMainEvent: workspace.canManageMainEvent,
            isCurrentPrincipal: isCurrentPrincipal,
            isInvitationProjection: workspace.isInvitationProjection,
            title: workspace.title,
            startsAt: date.startsAt,
            endsAt: date.endsAt,
            isAllDay: date.isAllDay,
            timeZoneIdentifier: date.timeZoneIdentifier,
            location: workspace.mainEventLocation,
            invitationDateIsUndecided: workspace.invitationDateIsUndecided
        )
    }

    @discardableResult
    static func commit(
        _ value: MainInvitationEditValue,
        for snapshot: MainInvitationEditSnapshot,
        in workspace: PlanningWorkspace,
        accountID: String?,
        localGuestProfileID: UUID?,
        principalGeneration: UInt64?,
        reference: EventReference,
        isCurrentPrincipal: Bool
    ) -> Bool {
        guard isCurrent(
            snapshot,
            in: workspace,
            accountID: accountID,
            localGuestProfileID: localGuestProfileID,
            principalGeneration: principalGeneration,
            reference: reference,
            isCurrentPrincipal: isCurrentPrincipal
        ) else { return false }

        let date = MainInvitationDateValue(
            startsAt: workspace.mainEventStartsAt,
            endsAt: workspace.mainEventEndsAt,
            isAllDay: workspace.mainEventIsAllDay,
            timeZoneIdentifier: workspace.mainEventTimeZoneIdentifier
        )

        var values = MainInvitationEventValues(
            title: workspace.title,
            date: date,
            location: workspace.mainEventLocation
        )
        switch (snapshot.field, value) {
        case (.title, .title(let title)):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return false }
            values.apply(title: trimmedTitle)
        case (.date, .date(let updatedDate)):
            values.apply(date: updatedDate)
        case (.location, .location(let location)):
            values.apply(location: location)
        default:
            return false
        }

        workspace.updateMainEvent(
            title: values.title,
            status: workspace.mainEventStatus,
            startsAt: values.date.startsAt,
            endsAt: values.date.endsAt,
            isAllDay: values.date.isAllDay,
            timeZoneIdentifier: values.date.timeZoneIdentifier,
            eventLocation: values.location,
            imageData: workspace.mainEventImageData,
            dressCode: workspace.dressCode,
            message: workspace.eventMessage
        )
        if snapshot.field == .date { workspace.invitationDateIsUndecided = false }
        return true
    }
}

struct MainInvitationTitleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTitleFocused: Bool
    @State private var title: String

    let save: (String) -> Void

    init(title: String, save: @escaping (String) -> Void) {
        _title = State(initialValue: title)
        self.save = save
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Name") {
                    TextField("Event Name", text: $title)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("invitation.edit.title.field")
                        .focused($isTitleFocused)
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("invitation.edit.title.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(trimmedTitle)
                        dismiss()
                    }
                    .disabled(trimmedTitle.isEmpty)
                    .accessibilityIdentifier("invitation.edit.title.save")
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .task { isTitleFocused = true }
    }
}
