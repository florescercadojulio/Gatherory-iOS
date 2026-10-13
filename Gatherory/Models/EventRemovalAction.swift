import Foundation

/// Home removes child events by archiving their existing records. Only a
/// draft main event supports the existing destructive deletion operation.
enum EventRemovalAction: Equatable {
    case deleteDraftMainEvent
    case archiveSubevent
    case cancelEvent

    var title: String {
        switch self {
        case .deleteDraftMainEvent: AppCopy.EventRemoval.deleteTitle
        case .archiveSubevent: AppCopy.EventRemoval.archiveTitle
        case .cancelEvent: AppCopy.Lifecycle.cancelEvent
        }
    }

    var symbol: String {
        switch self {
        case .deleteDraftMainEvent: "trash"
        case .archiveSubevent: "archivebox"
        case .cancelEvent: "calendar.badge.minus"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .deleteDraftMainEvent: AppCopy.EventRemoval.deleteMessage
        case .archiveSubevent: AppCopy.EventRemoval.archiveMessage
        case .cancelEvent: AppCopy.Lifecycle.cancelMessage
        }
    }
}
