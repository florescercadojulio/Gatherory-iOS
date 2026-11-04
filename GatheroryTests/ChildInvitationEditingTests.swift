import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ChildInvitationEditingTests {
    @Test("An edit remains bound to its exact child event")
    func exactChildAndEventBoundaries() {
        let (request, rootID, child, member) = fixture()
        #expect(matches(request, rootEventID: rootID, member: member))

        let sibling = makeChild(parentEventID: rootID)
        #expect(!matches(request, rootEventID: rootID, reference: .main, member: member))
        #expect(!matches(request, rootEventID: rootID, reference: .subevent(sibling.id), member: member))
        #expect(!matches(request, rootEventID: UUID(), member: member))
        #expect(!matches(request, rootEventID: rootID, omitItem: true, member: member))

        var changedChild = child
        changedChild.title = "Changed while editor was open"
        #expect(!matches(request, rootEventID: rootID, item: changedChild, member: member))
        #expect(!matches(request, rootEventID: rootID, item: sibling, member: member))
    }

    @Test("Concurrent lifecycle changes invalidate an open editor")
    func concurrentLifecycleChangesInvalidateOpenEditor() {
        let (request, rootID, child, member) = fixture()

        var archived = child
        archived.status = .archived
        #expect(!matches(request, rootEventID: rootID, item: archived, member: member))

        var cancelled = child
        cancelled.status = .cancelled
        #expect(!matches(request, rootEventID: rootID, item: cancelled, member: member))
        #expect(matches(makeRequest(item: cancelled, rootEventID: rootID, member: member),
                        rootEventID: rootID, item: cancelled, member: member))

        var completed = child
        completed.completionStatus = .complete
        #expect(!matches(request, rootEventID: rootID, item: completed, member: member))
        #expect(matches(makeRequest(item: completed, rootEventID: rootID, member: member),
                        rootEventID: rootID, item: completed, member: member))
    }

    @Test("Account, local profile, and principal generation must still match")
    func principalChangesRejectEdit() {
        let (request, rootID, _, member) = fixture()
        #expect(!matches(request, rootEventID: rootID, accountID: "other-account", member: member))
        #expect(!matches(request, rootEventID: rootID, localGuestProfileID: UUID(), member: member))
        #expect(!matches(request, rootEventID: rootID, generation: 8, member: member))
        #expect(!matches(request, rootEventID: rootID, generation: nil, member: member))
        #expect(!matches(request, rootEventID: rootID, accountID: nil, member: member))
        #expect(!request.matches(
            rootEventID: rootID, reference: .subevent(request.item.id), item: request.item,
            accountID: nil, localGuestProfileID: nil, principalGeneration: 7,
            member: member, canEditTodos: true, isInvitationProjection: false,
            isScopedEvent: false, isMainEventDeleted: false
        ))
    }

    @Test("A local host can edit only with the same local guest profile")
    func localGuestProfileIdentityIsScopedExactly() {
        let rootID = UUID()
        let profile = LocalGuestProfile(displayName: "Local host")
        let member = WorkspaceMember(
            userID: profile.storageID, name: "Local host", participantRole: .host,
            initials: "L", planningPermission: .manage
        )
        let child = makeChild(parentEventID: rootID)
        let request = ChildInvitationEditRequest(
            item: child, rootEventID: rootID, accountID: nil,
            localGuestProfileID: profile.id, principalGeneration: 7, memberID: member.id,
            role: member.participantRole, permission: member.planningPermission,
            invitationStatus: member.invitationStatus
        )
        #expect(matches(request, rootEventID: rootID, accountID: nil,
                        localGuestProfileID: profile.id, member: member))
        #expect(!matches(request, rootEventID: rootID, accountID: nil,
                         localGuestProfileID: UUID(), member: member))
    }

    @Test("Permission loss, inactive membership, and invalid workspace identity reject edits")
    func accessChangesRejectEdit() {
        let (request, rootID, _, member) = fixture()
        let readOnly = makeMember(id: member.id, role: .host, permission: .viewOnly)
        let guest = makeMember(id: member.id, role: .guest, permission: .manage)
        let invited = WorkspaceMember(
            id: member.id, userID: "editor-account", name: "Editor", participantRole: .host,
            initials: "E", planningPermission: .manage, invitationStatus: .invited
        )
        #expect(!matches(request, rootEventID: rootID, member: readOnly))
        #expect(!matches(request, rootEventID: rootID, member: guest))
        #expect(!matches(request, rootEventID: rootID, member: invited))
        #expect(!matches(request, rootEventID: rootID, member: nil))
        #expect(!matches(request, rootEventID: rootID, member: member, canEditTodos: false))
        #expect(!matches(request, rootEventID: rootID, member: member, projection: true))
        #expect(!matches(request, rootEventID: rootID, member: member, scoped: true))
        #expect(!matches(request, rootEventID: rootID, member: member, mainEventDeleted: true))
    }

    private func fixture() -> (ChildInvitationEditRequest, UUID, TimelineItem, WorkspaceMember) {
        let rootID = UUID()
        let member = makeMember(id: UUID(), role: .host, permission: .manage)
        let child = makeChild(parentEventID: rootID)
        let request = ChildInvitationEditRequest(
            item: child, rootEventID: rootID, accountID: "editor-account",
            localGuestProfileID: nil, principalGeneration: 7, memberID: member.id,
            role: member.participantRole, permission: member.planningPermission,
            invitationStatus: member.invitationStatus
        )
        return (request, rootID, child, member)
    }

    private func makeMember(id: UUID, role: WorkspaceRole, permission: PlanningPermission) -> WorkspaceMember {
        WorkspaceMember(
            id: id, userID: "editor-account", name: "Editor", participantRole: role,
            initials: "E", planningPermission: permission
        )
    }

    private func makeChild(parentEventID: UUID) -> TimelineItem {
        TimelineItem(
            title: "Dinner", category: .other, scheduledAt: .now, location: "",
            participantIDs: [], parentEventID: parentEventID
        )
    }

    private func makeRequest(item: TimelineItem, rootEventID: UUID, member: WorkspaceMember) -> ChildInvitationEditRequest {
        ChildInvitationEditRequest(
            item: item, rootEventID: rootEventID, accountID: "editor-account",
            localGuestProfileID: nil, principalGeneration: 7, memberID: member.id,
            role: member.participantRole, permission: member.planningPermission,
            invitationStatus: member.invitationStatus
        )
    }

    private func matches(
        _ request: ChildInvitationEditRequest,
        rootEventID: UUID,
        reference: EventReference? = nil,
        item: TimelineItem? = nil,
        omitItem: Bool = false,
        accountID: String? = "editor-account",
        localGuestProfileID: UUID? = nil,
        generation: UInt64? = 7,
        member: WorkspaceMember?,
        canEditTodos: Bool = true,
        projection: Bool = false,
        scoped: Bool = false,
        mainEventDeleted: Bool = false
    ) -> Bool {
        request.matches(
            rootEventID: rootEventID,
            reference: reference ?? .subevent(request.item.id),
            item: omitItem ? nil : (item ?? request.item),
            accountID: accountID,
            localGuestProfileID: localGuestProfileID,
            principalGeneration: generation,
            member: member,
            canEditTodos: canEditTodos,
            isInvitationProjection: projection,
            isScopedEvent: scoped,
            isMainEventDeleted: mainEventDeleted
        )
    }
}
