import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventTodoTests {
    @Test("To-do titles trim whitespace and count Unicode scalars without truncation")
    func titleValidation() {
        #expect(EventTodo.normalizedTitle(" \n Confirm the cake \t") == "Confirm the cake")
        #expect(EventTodo.normalizedTitle(" \n ") == nil)
        #expect(EventTodo.normalizedTitle(String(repeating: "🌿", count: 200)) != nil)
        #expect(EventTodo.normalizedTitle(String(repeating: "🌿", count: 201)) == nil)
    }

    @Test("Due dates are strict Gregorian calendar values")
    func dueDateValidation() {
        #expect(EventTodo.isValidDueDate(nil))
        #expect(EventTodo.isValidDueDate("2032-02-29"))
        #expect(EventTodo.isValidDueDate("2000-02-29"))
        #expect(!EventTodo.isValidDueDate("2031-02-29"))
        #expect(!EventTodo.isValidDueDate("1900-02-29"))
        #expect(!EventTodo.isValidDueDate("2032-13-01"))
        #expect(!EventTodo.isValidDueDate("2032-2-09"))
        #expect(!EventTodo.isValidDueDate("2032-02-09T00:00:00Z"))
    }

    @Test("To-do website links trim safely and reject unsupported or ambiguous URLs")
    func websiteURLValidation() {
        #expect(EventTodo.normalizedWebsiteURL(nil) == nil)
        #expect(EventTodo.normalizedWebsiteURL("  https://example.test/vendor  ") == "https://example.test/vendor")
        #expect(EventTodo.normalizedWebsiteURL("https://example.test/path") == "https://example.test/path")
        let prefix = "https://example.test/"
        let boundary = prefix + String(repeating: "x", count: 2_048 - prefix.unicodeScalars.count)
        #expect(boundary.unicodeScalars.count == 2_048)
        #expect(EventTodo.normalizedWebsiteURL(boundary) == boundary)
        #expect(EventTodo.isValidWebsiteURL(nil))
        #expect(EventTodo.isValidWebsiteURL("  "))
        for invalid in [
            "ftp://example.test/item",
            "https:example.test/item",
            "https:///example.test/item",
            "https://example.test:65536/item",
            "javascript:alert(1)",
            "https://user:password@example.test/item",
            "https://example.test/a b",
            "https://example.test/a\\b",
            "https://example.test/line\nfeed",
            "https://example.test/\u{0000}",
            "https://example.test/\(String(repeating: "x", count: 2040))",
        ] {
            #expect(EventTodo.normalizedWebsiteURL(invalid) == nil)
            #expect(!EventTodo.isValidWebsiteURL(invalid))
        }
    }

    @Test("Eligible assignees use active exact-event host and planning permissions")
    func eligibleAssigneesAreEventScoped() throws {
        let mainID = UUID()
        let childID = UUID()
        let manager = WorkspaceMember(
            userID: "manager", name: "Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        )
        let host = WorkspaceMember(
            userID: "host", name: "Host", participantRole: .host,
            initials: "H", planningPermission: .viewOnly
        )
        let viewer = WorkspaceMember(
            userID: "viewer", name: "Viewer", participantRole: .collaborator,
            initials: "V", planningPermission: .viewOnly
        )
        let guest = WorkspaceMember(
            userID: "guest", name: "Guest", participantRole: .guest,
            initials: "G", planningPermission: .contribute
        )
        let invited = WorkspaceMember(
            userID: "invited", name: "Invited", participantRole: .collaborator,
            initials: "I", planningPermission: .contribute, invitationStatus: .invited
        )
        let childOnly = WorkspaceMember(
            userID: "child-only", name: "Child only", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let workspace = workspace(
            permission: .contribute,
            mainEventID: mainID,
            childEventID: childID,
            extraMembers: [manager, host, viewer, guest, invited, childOnly],
            extraMainParticipations: [manager, host, viewer, guest, invited].map {
                EventParticipation(eventID: mainID, memberID: $0.id,
                    role: $0.participantRole, planningPermission: $0.planningPermission,
                    attendance: .going, invitationStatus: $0.invitationStatus)
            },
            extraChildParticipations: [EventParticipation(eventID: childID, memberID: childOnly.id,
                role: .collaborator, planningPermission: .contribute, attendance: .going,
                invitationStatus: .active)]
        )

        let mainAssignees = workspace.eligibleTodoAssignees(for: .main)
        #expect(Set(mainAssignees.map(\.id)) == Set([workspace.members[0].id, manager.id, host.id]))
        #expect(!mainAssignees.contains { $0.id == viewer.id || $0.id == guest.id || $0.id == invited.id })
        let childAssignees = workspace.eligibleTodoAssignees(for: .subevent(childID))
        #expect(childAssignees.contains { $0.id == childOnly.id })
        #expect(childAssignees.contains { $0.id == workspace.members[0].id })
        #expect(!childAssignees.contains { $0.id == manager.id || $0.id == host.id })
        #expect(workspace.addTodo(
            title: "Wrong event assignee", assigneePersonID: childOnly.id, to: .main
        ) == nil)
    }

    @Test("To-do assignee lookup returns only active planners from the exact readable event")
    func todoAssigneeLookupIsEventScoped() throws {
        let mainID = UUID()
        let childID = UUID()
        let avatarURL = try #require(URL(string: "https://example.test/profiles/planner.png"))
        let host = WorkspaceMember(
            userID: "event-host", name: "Event Host", participantRole: .host,
            initials: "EH", email: "host@example.test", profileImageAssetName: "host-avatar",
            profileImageURL: avatarURL, planningPermission: .viewOnly
        )
        let guest = WorkspaceMember(
            userID: "event-guest", name: "Event Guest", participantRole: .guest,
            initials: "EG", planningPermission: .contribute
        )
        let invited = WorkspaceMember(
            userID: "invited-planner", name: "Invited Planner", participantRole: .collaborator,
            initials: "IP", planningPermission: .manage, invitationStatus: .invited
        )
        let readOnlyCollaborator = WorkspaceMember(
            userID: "read-only-collaborator", name: "Read-only Collaborator",
            participantRole: .collaborator, initials: "RC", planningPermission: .viewOnly
        )
        let mainOnlyPlanner = WorkspaceMember(
            userID: "main-only", name: "Main Only", participantRole: .collaborator,
            initials: "MO", planningPermission: .contribute
        )
        let todos = [
            EventTodo(eventID: mainID, title: "Host task", assigneePersonID: host.id),
            EventTodo(eventID: mainID, title: "Unassigned"),
            EventTodo(eventID: mainID, title: "Unknown assignee", assigneePersonID: UUID()),
            EventTodo(eventID: mainID, title: "Guest assignee", assigneePersonID: guest.id),
            EventTodo(eventID: mainID, title: "Invited assignee", assigneePersonID: invited.id),
            EventTodo(eventID: childID, title: "Wrong-event assignee", assigneePersonID: mainOnlyPlanner.id),
        ]
        let workspace = workspace(
            permission: .contribute,
            todos: todos,
            mainEventID: mainID,
            childEventID: childID,
            extraMembers: [host, guest, invited, readOnlyCollaborator, mainOnlyPlanner],
            extraMainParticipations: [host, guest, invited, readOnlyCollaborator, mainOnlyPlanner].map {
                EventParticipation(eventID: mainID, memberID: $0.id,
                    role: $0.participantRole, planningPermission: $0.planningPermission,
                    attendance: .going, invitationStatus: $0.invitationStatus)
            }
        )

        let resolvedHost = try #require(workspace.todoAssignee(for: todos[0]))
        #expect(resolvedHost.id == host.id)
        #expect(resolvedHost.name == host.name)
        #expect(resolvedHost.email == host.email)
        #expect(resolvedHost.profileImageAssetName == host.profileImageAssetName)
        #expect(resolvedHost.profileImageURL == host.profileImageURL)
        #expect(workspace.todoAssignee(for: EventTodo(
            eventID: mainID, title: "Assigned to a readable collaborator",
            assigneePersonID: readOnlyCollaborator.id
        ))?.id == readOnlyCollaborator.id)
        for todo in todos.dropFirst() {
            #expect(workspace.todoAssignee(for: todo) == nil)
        }

        let unreadableWorkspace = self.workspace(
            role: .guest,
            permission: .viewOnly,
            todos: [todos[0]],
            mainEventID: mainID,
            childEventID: childID,
            extraMembers: [host],
            extraMainParticipations: [EventParticipation(
                eventID: mainID, memberID: host.id, role: .host,
                planningPermission: .viewOnly, attendance: .going, invitationStatus: .active
            )]
        )
        #expect(!unreadableWorkspace.canReadTodos(for: .main))
        #expect(unreadableWorkspace.todoAssignee(for: todos[0]) == nil)
    }

    @Test("Taking a to-do claims only an unassigned item and never overwrites an assignment")
    func takingTodoIsSelfOnlyAndUnassignedOnly() throws {
        let planningWorkspace = workspace(permission: .contribute)
        let unassigned = try #require(planningWorkspace.addTodo(title: "Confirm the cake", to: .main))
        #expect(planningWorkspace.canTakeTodo(id: unassigned.id))
        #expect(planningWorkspace.takeTodo(id: unassigned.id))
        #expect(planningWorkspace.todos(for: .main).first?.assigneePersonID == planningWorkspace.members[0].id)
        #expect(!planningWorkspace.canTakeTodo(id: unassigned.id))
        #expect(!planningWorkspace.takeTodo(id: unassigned.id))

        let assigned = try #require(planningWorkspace.addTodo(
            title: "Book the florist", assigneePersonID: planningWorkspace.members[0].id, to: .main
        ))
        #expect(!planningWorkspace.canTakeTodo(id: assigned.id))

        let readOnlyID = UUID()
        let readOnlyTodo = EventTodo(eventID: readOnlyID, title: "Read only")
        let readOnlyWorkspace = self.workspace(
            permission: .viewOnly, todos: [readOnlyTodo], mainEventID: readOnlyID
        )
        #expect(!readOnlyWorkspace.canTakeTodo(id: readOnlyTodo.id))
        #expect(!readOnlyWorkspace.takeTodo(id: readOnlyTodo.id))
    }

    @Test("To-do assignment can change or clear, while unchanged stale assignees remain editable")
    func assignmentChangesAndStalePreservation() throws {
        let mainID = UUID()
        let manager = WorkspaceMember(
            userID: "manager", name: "Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        )
        let staleAssigneeID = UUID()
        let todo = EventTodo(eventID: mainID, title: "Confirm the cake", assigneePersonID: staleAssigneeID)
        let workspace = workspace(
            permission: .contribute,
            todos: [todo],
            mainEventID: mainID,
            extraMembers: [manager],
            extraMainParticipations: [EventParticipation(eventID: mainID, memberID: manager.id,
                role: .collaborator, planningPermission: .manage, attendance: .going,
                invitationStatus: .active)]
        )
        #expect(workspace.assignTodo(id: todo.id, assigneePersonID: staleAssigneeID))
        #expect(workspace.updateTodo(
            id: todo.id, title: "Confirm with venue", dueDate: nil,
            websiteURL: nil, assigneePersonID: staleAssigneeID
        ))
        #expect(workspace.assignTodo(id: todo.id, assigneePersonID: manager.id))
        #expect(workspace.todos(for: .main).first?.assigneePersonID == manager.id)
        #expect(workspace.assignTodo(id: todo.id, assigneePersonID: nil))
        #expect(workspace.todos(for: .main).first?.assigneePersonID == nil)
    }

    @Test("Next to-do ignores completed work and orders by earliest due date")
    func nextTodoOrdering() throws {
        let planningWorkspace = workspace(permission: .contribute)
        let later = try #require(planningWorkspace.addTodo(title: "Later", dueDate: "2032-04-10", to: .main))
        let earliest = try #require(planningWorkspace.addTodo(title: "Soon", dueDate: "2032-04-01", to: .main))
        let completed = try #require(planningWorkspace.addTodo(title: "Done", dueDate: "2032-03-01", to: .main))
        #expect(planningWorkspace.setTodoCompleted(id: completed.id, isCompleted: true))
        #expect(planningWorkspace.nextTodo(for: .main)?.id == earliest.id)

        let sameDueWorkspace = self.workspace(permission: .contribute)
        _ = try #require(sameDueWorkspace.addTodo(
            title: "First with same date", dueDate: "2032-04-10", to: .main
        ))
        let newestSameDate = try #require(sameDueWorkspace.addTodo(
            title: "Newest with same date", dueDate: "2032-04-10", to: .main
        ))
        #expect(sameDueWorkspace.nextTodo(for: .main)?.id == newestSameDate.id)

        let mainID = UUID()
        let undatedWorkspace = self.workspace(
            permission: .contribute,
            todos: [
                EventTodo(id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
                    eventID: mainID, title: "Old", createdAt: Date(timeIntervalSince1970: 10)),
                EventTodo(id: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!,
                    eventID: mainID, title: "New", createdAt: Date(timeIntervalSince1970: 20)),
            ],
            mainEventID: mainID
        )
        #expect(undatedWorkspace.nextTodo(for: .main)?.title == "New")
        #expect(later.id != earliest.id)
    }

    @Test("Next to-do prioritizes my unfinished work before earlier unassigned or other people's work")
    func nextTodoPrioritizesCurrentAssignee() throws {
        let otherPlanner = WorkspaceMember(
            userID: "other-planner", name: "Other Planner", participantRole: .collaborator,
            initials: "O", planningPermission: .contribute
        )
        let mainID = UUID()
        let planningWorkspace = workspace(
            permission: .contribute,
            mainEventID: mainID,
            extraMembers: [otherPlanner],
            extraMainParticipations: [EventParticipation(
                eventID: mainID, memberID: otherPlanner.id,
                role: .collaborator, planningPermission: .contribute,
                attendance: .going, invitationStatus: .active
            )]
        )
        let viewerID = try #require(planningWorkspace.members.first?.id)
        let otherAssigned = try #require(planningWorkspace.addTodo(
            title: "Other person's early task", dueDate: "2032-04-01",
            assigneePersonID: otherPlanner.id, to: .main
        ))
        _ = try #require(planningWorkspace.addTodo(
            title: "Unassigned early task", dueDate: "2032-04-02", to: .main
        ))
        let viewerTask = try #require(planningWorkspace.addTodo(
            title: "My later task", dueDate: "2032-04-10", assigneePersonID: viewerID, to: .main
        ))

        #expect(planningWorkspace.nextTodo(for: .main)?.id == viewerTask.id)
        #expect(otherAssigned.id != viewerTask.id)

        #expect(planningWorkspace.setTodoCompleted(id: viewerTask.id, isCompleted: true))
        #expect(planningWorkspace.nextTodo(for: .main)?.title == "Unassigned early task")
    }

    @Test("Next to-do returns nil when all unfinished tasks belong to other people or the viewer is read-only")
    func nextTodoHidesNonClaimableWork() throws {
        let other = WorkspaceMember(
            userID: "assigned-person", name: "Assigned Person", participantRole: .collaborator,
            initials: "A", planningPermission: .contribute
        )
        let mainID = UUID()
        let otherAssigned = EventTodo(
            eventID: mainID, title: "Assigned elsewhere", dueDate: "2032-04-01",
            assigneePersonID: other.id
        )
        let workspace = workspace(
            permission: .contribute,
            todos: [otherAssigned],
            mainEventID: mainID,
            extraMembers: [other],
            extraMainParticipations: [EventParticipation(
                eventID: mainID, memberID: other.id,
                role: .collaborator, planningPermission: .contribute,
                attendance: .going, invitationStatus: .active
            )]
        )
        #expect(workspace.nextTodo(for: .main) == nil)

        let unassigned = EventTodo(eventID: mainID, title: "Not claimable in read-only mode")
        let readOnly = self.workspace(permission: .viewOnly, todos: [unassigned], mainEventID: mainID)
        #expect(readOnly.canReadTodos(for: .main))
        #expect(!readOnly.canEditTodos(for: .main))
        #expect(!readOnly.canTakeTodo(id: unassigned.id))
        #expect(readOnly.nextTodo(for: .main) == nil)
    }

    @Test("Next to-do follows the selected account and exact child event")
    func nextTodoUsesCurrentAccountAndEventScope() throws {
        let mainID = UUID()
        let childID = UUID()
        let manager = WorkspaceMember(
            userID: "main-manager", name: "Main Manager", participantRole: .collaborator,
            initials: "M", planningPermission: .manage
        )
        let childPlanner = WorkspaceMember(
            userID: "child-planner", name: "Child Planner", participantRole: .collaborator,
            initials: "C", planningPermission: .contribute
        )
        let mainTask = EventTodo(
            eventID: mainID, title: "Main manager task", dueDate: "2032-04-10",
            assigneePersonID: manager.id
        )
        let childTask = EventTodo(
            eventID: childID, title: "Child planner task", dueDate: "2032-04-01",
            assigneePersonID: childPlanner.id
        )
        let workspace = workspace(
            permission: .contribute,
            todos: [mainTask, childTask],
            mainEventID: mainID,
            childEventID: childID,
            extraMembers: [manager, childPlanner],
            extraMainParticipations: [EventParticipation(
                eventID: mainID, memberID: manager.id,
                role: .collaborator, planningPermission: .manage,
                attendance: .going, invitationStatus: .active
            )],
            extraChildParticipations: [EventParticipation(
                eventID: childID, memberID: childPlanner.id,
                role: .collaborator, planningPermission: .contribute,
                attendance: .going, invitationStatus: .active
            )]
        )

        workspace.configureViewer(UserAccount(
            id: manager.userID!, email: "manager@example.test", displayName: manager.name,
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        #expect(workspace.nextTodo(for: .main)?.id == mainTask.id)
        #expect(workspace.nextTodo(for: .subevent(childID)) == nil)

        workspace.configureViewer(UserAccount(
            id: childPlanner.userID!, email: "child@example.test", displayName: childPlanner.name,
            role: .planner, authenticationProvider: .password, createdAt: .now
        ))
        #expect(workspace.nextTodo(for: .subevent(childID))?.id == childTask.id)
        #expect(workspace.nextTodo(for: .main) == nil)
    }

    @Test("Contributors can add, edit, complete, undo, and delete shared to-dos")
    func todoLifecycle() throws {
        let workspace = workspace(permission: .contribute)
        let child = try #require(workspace.timeline.first)

        let first = try #require(workspace.addTodo(title: "  Confirm the cake  ", to: .main))
        let duplicateTitle = try #require(workspace.addTodo(title: "Confirm the cake", to: .main))
        let childTodo = try #require(workspace.addTodo(
            title: "Arrange the chairs", dueDate: "2032-02-29", to: .subevent(child.id)
        ))
        #expect(first.title == "Confirm the cake")
        #expect(duplicateTitle.id != first.id)
        #expect(workspace.todos(for: .main).map(\.id).contains(first.id))
        #expect(!workspace.todos(for: .main).contains { $0.id == childTodo.id })
        #expect(workspace.todos(for: .subevent(child.id)).map(\.id) == [childTodo.id])

        #expect(workspace.updateTodo(id: first.id, title: "  Book the florist ", dueDate: nil))
        #expect(workspace.todos(for: .main).first { $0.id == first.id }?.title == "Book the florist")
        #expect(workspace.setTodoCompleted(id: first.id, isCompleted: true))
        #expect(workspace.todos(for: .main).first { $0.id == first.id }?.isCompleted == true)
        #expect(workspace.setTodoCompleted(id: first.id, isCompleted: false))
        #expect(workspace.todos(for: .main).first { $0.id == first.id }?.isCompleted == false)
        #expect(workspace.deleteTodo(id: duplicateTitle.id))
        #expect(!workspace.todos(for: .main).contains { $0.id == duplicateTitle.id })
    }

    @Test("Invalid edits and event references leave shared to-dos unchanged")
    func invalidEditsAreNoOps() throws {
        let workspace = workspace(permission: .contribute)
        let child = try #require(workspace.timeline.first)
        let todo = try #require(workspace.addTodo(title: "Confirm the cake", to: .main))
        let before = workspace.todos(for: .main)

        #expect(workspace.addTodo(title: " \n ", to: .main) == nil)
        #expect(workspace.addTodo(title: "Invalid date", dueDate: "2031-02-29", to: .main) == nil)
        #expect(workspace.addTodo(title: "Wrong event", to: .subevent(UUID())) == nil)
        #expect(workspace.addTodo(title: "Idea context", to: .idea(UUID())) == nil)
        #expect(!workspace.updateTodo(id: todo.id, title: "", dueDate: nil))
        #expect(!workspace.updateTodo(id: todo.id, title: "Moved", dueDate: "not-a-date"))
        #expect(!workspace.setTodoCompleted(id: UUID(), isCompleted: true))
        #expect(!workspace.deleteTodo(id: UUID()))
        #expect(workspace.todos(for: .main) == before)
        #expect(workspace.todos(for: .subevent(child.id)).isEmpty)
    }

    @Test("Read-only collaborators can read but cannot mutate; guests cannot read or mutate")
    func permissions() throws {
        let readOnly = workspace(permission: .viewOnly)
        #expect(readOnly.canReadTodos(for: .main))
        #expect(readOnly.canReadTodos(for: .subevent(try #require(readOnly.timeline.first?.id))))
        #expect(!readOnly.canEditTodos(for: .main))
        #expect(readOnly.addTodo(title: "No write", to: .main) == nil)

        let guest = workspace(role: .guest, permission: .viewOnly)
        #expect(!guest.canReadTodos(for: .main))
        #expect(!guest.canEditTodos(for: .main))
        #expect(guest.todos(for: .main).isEmpty)
        #expect(guest.addTodo(title: "No guest task", to: .main) == nil)

        let invited = workspace(permission: .contribute, invitationStatus: .invited)
        #expect(!invited.canReadTodos(for: .main))
        #expect(invited.addTodo(title: "Not active", to: .main) == nil)
    }

    private func workspace(
        role: WorkspaceRole = .collaborator,
        permission: PlanningPermission,
        invitationStatus: CollaborationInvitationStatus = .active,
        todos: [EventTodo] = [],
        mainEventID: UUID = UUID(),
        childEventID: UUID = UUID(),
        extraMembers: [WorkspaceMember] = [],
        extraMainParticipations: [EventParticipation] = [],
        extraChildParticipations: [EventParticipation] = []
    ) -> PlanningWorkspace {
        let mainID = mainEventID
        let childID = childEventID
        let member = WorkspaceMember(
            userID: "todo-planner",
            name: "Planner",
            participantRole: role,
            initials: "P",
            planningPermission: permission,
            invitationStatus: invitationStatus
        )
        let rootParticipation = EventParticipation(
            eventID: mainID,
            memberID: member.id,
            role: role,
            planningPermission: permission,
            attendance: .going,
            invitationStatus: invitationStatus
        )
        let childParticipation = EventParticipation(
            eventID: childID,
            memberID: member.id,
            role: role,
            planningPermission: permission,
            attendance: .going,
            invitationStatus: invitationStatus
        )
        let child = TimelineItem(
            id: childID,
            title: "Dinner",
            category: .other,
            scheduledAt: .now.addingTimeInterval(86_400),
            location: "",
            participantIDs: [member.id],
            parentEventID: mainID,
            status: .approved
        )
        let workspace = PlanningWorkspace(
            mainEventID: mainID,
            title: "To-do test",
            mainEventStartsAt: .now.addingTimeInterval(86_400),
            venueName: "",
            location: "",
            planningMode: .openToIdeas,
            members: [member] + extraMembers,
            eventParticipations: [rootParticipation, childParticipation]
                + extraMainParticipations + extraChildParticipations,
            mainEventParticipantIDs: [member.id],
            ideas: [],
            timeline: [child],
            todos: todos,
            registry: []
        )
        workspace.configureViewer(UserAccount(
            id: "todo-planner",
            email: "todo@example.test",
            displayName: "Planner",
            role: .planner,
            authenticationProvider: .password,
            createdAt: .now
        ))
        return workspace
    }
}
