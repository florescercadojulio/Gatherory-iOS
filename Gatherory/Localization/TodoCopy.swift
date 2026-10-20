import Foundation

enum TodoCopy {
    static var title: String { String(localized: "todo.title", defaultValue: "To-dos") }
    static var listFilter: String { String(localized: "todo.listFilter", defaultValue: "To-do list") }
    static var upcoming: String { String(localized: "todo.upcoming", defaultValue: "Upcoming") }
    static var upcomingEmpty: String { String(localized: "todo.upcomingEmpty", defaultValue: "No Upcoming To-dos") }
    static var upcomingEmptyHelp: String { String(localized: "todo.upcomingEmptyHelp", defaultValue: "You're all caught up.") }
    static var completedEmpty: String { String(localized: "todo.completedEmpty", defaultValue: "No Completed To-dos Yet") }
    static var add: String { String(localized: "todo.add", defaultValue: "Add a To-do") }
    static var newTitle: String { String(localized: "todo.newTitle", defaultValue: "New To-do") }
    static var addingTo: String { String(localized: "Adding To", defaultValue: "Adding To") }
    static var event: String { String(localized: "Event", defaultValue: "Event") }
    static var taskSection: String { String(localized: "todo.taskSection", defaultValue: "To-do") }
    static var edit: String { String(localized: "todo.edit", defaultValue: "Edit To-do") }
    static var name: String { String(localized: "todo.name", defaultValue: "What needs doing?") }
    static var completed: String { String(localized: "todo.completed", defaultValue: "Completed") }
    static var collapsed: String { String(localized: "todo.collapsed", defaultValue: "Collapsed") }
    static var expanded: String { String(localized: "todo.expanded", defaultValue: "Expanded") }
    static var yourNext: String { String(localized: "todo.yourNext", defaultValue: "Your Next") }
    static var availableToTake: String { String(localized: "todo.availableToTake", defaultValue: "Available to Take") }
    static var markComplete: String { String(localized: "todo.markComplete", defaultValue: "Mark Complete") }
    static var markIncomplete: String { String(localized: "todo.markIncomplete", defaultValue: "Mark Incomplete") }
    static var dueDate: String { String(localized: "todo.dueDate", defaultValue: "Due Date") }
    static var addDueDate: String { String(localized: "todo.addDueDate", defaultValue: "Add Due Date") }
    static var changeDueDate: String { String(localized: "todo.changeDueDate", defaultValue: "Change Due Date") }
    static var removeDueDate: String { String(localized: "todo.removeDueDate", defaultValue: "Remove Due Date") }
    static var done: String { String(localized: "todo.done", defaultValue: "Done") }
    static var assignee: String { String(localized: "todo.assignee", defaultValue: "Assigned To") }
    static var unassigned: String { String(localized: "todo.unassigned", defaultValue: "Unassigned") }
    static var assigneeUnavailable: String { String(localized: "todo.assigneeUnavailable", defaultValue: "Assignee unavailable") }
    static var take: String { String(localized: "todo.take", defaultValue: "Take This To-do") }
    static var takeShort: String { String(localized: "todo.takeShort", defaultValue: "Take") }
    static var website: String { String(localized: "todo.website", defaultValue: "Website") }
    static var websitePlaceholder: String { String(localized: "todo.websitePlaceholder", defaultValue: "https://example.com") }
    static var invalidWebsite: String { String(localized: "todo.invalidWebsite", defaultValue: "Enter a valid website address.") }
    static var openWebsite: String { String(localized: "todo.openWebsite", defaultValue: "Open Website") }
    static var previewEmpty: String { String(localized: "todo.previewEmpty", defaultValue: "No to-dos for you right now") }
    static var undo: String { String(localized: "todo.undo", defaultValue: "Undo") }
    static var itemChangedTitle: String { String(localized: "todo.itemChangedTitle", defaultValue: "This To-do Changed") }
    static var itemChangedHelp: String { String(localized: "todo.itemChangedHelp", defaultValue: "Close and reopen it to see the latest changes before editing.") }
    static var empty: String { String(localized: "todo.empty", defaultValue: "No To-dos Yet") }
    static var emptyHelp: String { String(localized: "todo.emptyHelp", defaultValue: "Add something you want to get done for this event.") }
    static var emptyReadOnly: String { String(localized: "todo.emptyReadOnly", defaultValue: "Your planning team's to-dos will appear here.") }
    static var unavailable: String { String(localized: "todo.unavailable", defaultValue: "To-dos Unavailable") }
    static var unavailableHelp: String { String(localized: "todo.unavailableHelp", defaultValue: "You don't have planning access to this event.") }
    static var invalidTitle: String { String(localized: "todo.invalidTitle", defaultValue: "Enter a title up to 200 characters.") }
    static var delete: String { String(localized: "todo.delete", defaultValue: "Delete To-do") }
    static var confirmDelete: String { String(localized: "todo.confirmDelete", defaultValue: "Delete This To-do?") }
    static var deleteHelp: String { String(localized: "todo.deleteHelp", defaultValue: "This removes it for everyone planning this event.") }
    static var saveFailed: String { String(localized: "todo.saveFailed", defaultValue: "Couldn't Save To-do") }
    static var saveFailedHelp: String { String(localized: "todo.saveFailedHelp", defaultValue: "Your change wasn't saved. Try again.") }
    static func due(_ date: String) -> String {
        String.localizedStringWithFormat(String(localized: "todo.dueFormat", defaultValue: "Due %@"), date)
    }

    static func assignedTo(_ name: String) -> String {
        String.localizedStringWithFormat(String(localized: "todo.assignedToFormat", defaultValue: "Assigned to %@"), name)
    }

    static func addingTodoTo(_ title: String) -> String {
        String.localizedStringWithFormat(String(localized: "todo.addingToEventFormat", defaultValue: "Adding this to-do to %@"), title)
    }
}
