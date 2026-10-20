import Foundation

/// Shared planning state for one exact event. Personal reminder settings are
/// intentionally kept outside this synchronized value.
nonisolated struct EventTodo: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eventID: UUID
    var title: String
    var dueDate: String?
    var websiteURL: String?
    var assigneePersonID: UUID?
    var isCompleted: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        eventID: UUID,
        title: String,
        dueDate: String? = nil,
        websiteURL: String? = nil,
        assigneePersonID: UUID? = nil,
        isCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.eventID = eventID
        self.title = title
        self.dueDate = dueDate
        self.websiteURL = websiteURL
        self.assigneePersonID = assigneePersonID
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, eventID, title, dueDate, websiteURL, assigneePersonID, isCompleted, createdAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(eventID, forKey: .eventID)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(dueDate, forKey: .dueDate)
        // Explicit null means the person cleared these fields. Missing fields
        // in an older archive still decode as nil and cannot erase server data.
        try values.encode(websiteURL, forKey: .websiteURL)
        try values.encode(assigneePersonID, forKey: .assigneePersonID)
        try values.encode(isCompleted, forKey: .isCompleted)
        try values.encode(createdAt, forKey: .createdAt)
    }

    static func normalizedTitle(_ value: String) -> String? {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = title.unicodeScalars.count
        guard (1...200).contains(count) else { return nil }
        return title
    }

    /// Only explicit web links can be opened from shared planning content.
    /// Nil and an empty field both mean no website; malformed links fail validation.
    static func normalizedWebsiteURL(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= 2048,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.port.map({ (0...65535).contains($0) }) ?? true,
              url.user == nil, url.password == nil,
              !trimmed.contains("\\") else { return nil }
        let normalized = url.absoluteString
        return normalized.unicodeScalars.count <= 2048 ? normalized : nil
    }

    static func isValidWebsiteURL(_ value: String?) -> Bool {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return normalizedWebsiteURL(value) != nil
    }

    /// Validates an event-zone calendar date without interpreting it as an
    /// instant or shifting it through the device's time zone.
    static func isValidDueDate(_ value: String?) -> Bool {
        guard let value else { return true }
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return false }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] where !(48...57).contains(bytes[index]) {
            return false
        }
        func number(_ range: Range<Int>) -> Int {
            range.reduce(0) { $0 * 10 + Int(bytes[$1] - 48) }
        }
        let year = number(0..<4)
        let month = number(5..<7)
        let day = number(8..<10)
        guard year >= 1, (1...12).contains(month) else { return false }
        let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let daysInMonth: [Int] = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...daysInMonth[month - 1]).contains(day)
    }
}
