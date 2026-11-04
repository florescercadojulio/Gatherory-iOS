import Foundation

/// Home removes child events by archiving their existing records. Main event
/// deletion is revalidated against its current lifecycle and viewer access.
enum EventRemovalAction: Equatable {
    case deleteMainEvent
    case archiveSubevent
    case cancelEvent

    var title: String {
        switch self {
        case .deleteMainEvent: AppCopy.EventRemoval.deleteTitle
        case .archiveSubevent: AppCopy.EventRemoval.archiveTitle
        case .cancelEvent: AppCopy.Lifecycle.cancelEvent
        }
    }

    var symbol: String {
        switch self {
        case .deleteMainEvent: "trash"
        case .archiveSubevent: "archivebox"
        case .cancelEvent: "calendar.badge.minus"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .deleteMainEvent: AppCopy.EventRemoval.deleteMessage
        case .archiveSubevent: AppCopy.EventRemoval.archiveMessage
        case .cancelEvent: AppCopy.Lifecycle.cancelMessage
        }
    }
}
