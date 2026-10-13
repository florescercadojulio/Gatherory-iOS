import Foundation

/// Home removes child events by archiving their existing records. Only a
/// draft main event supports the existing destructive deletion operation.
enum EventRemovalAction: Equatable {
    case deleteDraftMainEvent
    case archiveSubevent

    var title: String {
        switch self {
        case .deleteDraftMainEvent: AppCopy.EventRemoval.deleteTitle
        case .archiveSubevent: AppCopy.EventRemoval.archiveTitle
        }
    }

    var symbol: String {
        switch self {
        case .deleteDraftMainEvent: "trash"
        case .archiveSubevent: "archivebox"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .deleteDraftMainEvent: AppCopy.EventRemoval.deleteMessage
        case .archiveSubevent: AppCopy.EventRemoval.archiveMessage
        }
    }
}
