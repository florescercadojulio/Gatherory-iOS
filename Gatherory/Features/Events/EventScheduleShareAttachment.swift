import Foundation

/// Only these fixed filenames can cross the share-sheet boundary.
nonisolated enum EventCSVExportKind: Equatable, Sendable {
    case schedule
    case guestList

    var fileName: String {
        switch self {
        case .schedule: "Event Schedule.csv"
        case .guestList: "Guest List.csv"
        }
    }
}

/// One protected temporary attachment per share, never an account cache or sync asset.
/// Its fixed filename contains no user, account, event or invitation identifiers.
final class EventScheduleShareAttachment {
    let url: URL
    private let directory: URL

    init(data: Data, kind: EventCSVExportKind = .schedule,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws {
        directory = temporaryDirectory.appendingPathComponent("gatherory-csv-export-\(UUID().uuidString)", isDirectory: true)
        url = directory.appendingPathComponent(kind.fileName, isDirectory: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
