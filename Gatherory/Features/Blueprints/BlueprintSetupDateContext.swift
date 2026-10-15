import Foundation

/// Capture device settings once for a new setup, without requesting GPS access.
/// A later system-zone change must not silently move a plan the person is editing.
struct BlueprintSetupDateContext {
    var startsAt: Date
    private(set) var timeZoneIdentifier: String

    init(startsAt: Date, timeZone: TimeZone) {
        self.startsAt = startsAt
        timeZoneIdentifier = timeZone.identifier
    }

    init(now: Date = .now, timeZone: TimeZone = .current, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone
        startsAt = calendar.date(byAdding: .month, value: 6, to: now) ?? now
        timeZoneIdentifier = timeZone.identifier
    }

    /// Changing display zone preserves the selected absolute instant.
    @discardableResult
    mutating func selectTimeZone(_ identifier: String) -> Bool {
        guard identifier != timeZoneIdentifier, TimeZone(identifier: identifier) != nil else { return false }
        timeZoneIdentifier = identifier
        return true
    }

    @discardableResult
    mutating func useDeviceTimeZone(_ timeZone: TimeZone = .current) -> Bool {
        selectTimeZone(timeZone.identifier)
    }

    struct TimeZoneOption: Identifiable {
        let id: String
        let title: String

        init(id: String) {
            self.id = id
            title = id.replacingOccurrences(of: "_", with: " ")
        }
    }

    // The setup form redraws when an idea/event toggle changes. Do not rebuild
    // and sort the system's full time-zone catalog for each of those changes.
    static let knownTimeZones = TimeZone.knownTimeZoneIdentifiers.sorted().map { TimeZoneOption(id: $0) }
    private static let knownIdentifiers = Set(knownTimeZones.map(\.id))

    var timeZoneOptions: [TimeZoneOption] {
        // The system may return GMT or an alias absent from the curated list.
        // Always supply a matching Picker tag for the current selection.
        if Self.knownIdentifiers.contains(timeZoneIdentifier) { return Self.knownTimeZones }
        return [TimeZoneOption(id: timeZoneIdentifier)] + Self.knownTimeZones
    }
}
