import Foundation
import Testing
@testable import Gatherory

@MainActor
struct EventScheduleShareAttachmentTests {
    @Test("CSV shares use a real attachment and remove only their own temporary files")
    func attachmentLifecycle() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let data = Data("\u{FEFF}Event,Start\r\nDinner,2032-11-07\r\n".utf8)
        let first = try EventScheduleShareAttachment(data: data, temporaryDirectory: base)
        let second = try EventScheduleShareAttachment(data: data, temporaryDirectory: base)
        #expect(first.url.pathExtension == "csv")
        #expect(first.url.lastPathComponent == "Event Schedule.csv")
        #expect(first.url != second.url)
        #expect(try Data(contentsOf: first.url) == data)
        // The simulator omits file-protection metadata. Validate it on a device;
        // the protected write is still used for both builds.
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.url.path)
        let protection = attributes[.protectionKey]
        let value = (protection as? FileProtectionType)?.rawValue ?? (protection as? String)
        #expect(value == FileProtectionType.complete.rawValue)
        #endif
        first.cleanup()
        first.cleanup()
        #expect(!FileManager.default.fileExists(atPath: first.url.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        second.cleanup()
    }

    @Test("Releasing a canceled share removes its attachment without deleting sibling data")
    func releaseCleanup() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let sibling = base.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: sibling)
        var attachment: EventScheduleShareAttachment? = try EventScheduleShareAttachment(data: Data(), temporaryDirectory: base)
        let url = try #require(attachment?.url)
        attachment = nil
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: sibling.path))
    }

    @Test("Guest exports use a fixed CSV filename and cleanup cannot remove a schedule or another guest export")
    func crossExportIsolation() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: base) }
        let guestData = Data("\u{FEFF}\"Name\",\"RSVP Status\"\r\n\"Morgan\",\"Going\"\r\n".utf8)
        let schedule = try EventScheduleShareAttachment(data: Data("schedule".utf8), temporaryDirectory: base)
        let firstGuest = try EventScheduleShareAttachment(data: guestData, kind: .guestList, temporaryDirectory: base)
        let secondGuest = try EventScheduleShareAttachment(data: guestData, kind: .guestList, temporaryDirectory: base)
        #expect(firstGuest.url.lastPathComponent == "Guest List.csv")
        #expect(secondGuest.url.lastPathComponent == "Guest List.csv")
        #expect(firstGuest.url != secondGuest.url)
        #expect(firstGuest.url.deletingLastPathComponent() != schedule.url.deletingLastPathComponent())
        #expect(try Data(contentsOf: firstGuest.url) == guestData)
        firstGuest.cleanup()
        #expect(!FileManager.default.fileExists(atPath: firstGuest.url.path))
        #expect(FileManager.default.fileExists(atPath: secondGuest.url.path))
        #expect(FileManager.default.fileExists(atPath: schedule.url.path))
    }

    @Test("An attachment failure leaves existing data untouched")
    func creationFailure() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = Data("existing data".utf8)
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: (any Error).self) {
            _ = try EventScheduleShareAttachment(data: Data("CSV".utf8), temporaryDirectory: file)
        }
        #expect(try Data(contentsOf: file) == data)
    }
}
