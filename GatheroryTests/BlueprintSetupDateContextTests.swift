import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintSetupDateContextTests {
    @Test("A new setup uses the device zone and calendar months across DST")
    func initialDateUsesDeviceZone() throws {
        let detroit = try #require(TimeZone(identifier: "America/Detroit"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let now = try date("2026-10-31T03:30:00Z") // October 30, 23:30 in Detroit.
        let context = BlueprintSetupDateContext(now: now, timeZone: detroit, calendar: calendar)

        #expect(context.timeZoneIdentifier == "America/Detroit")
        #expect(context.startsAt == (try date("2027-05-01T03:30:00Z")))
    }

    @Test("Time-zone overrides and returning to device time preserve chosen instants")
    func zoneChangesPreserveEditedDates() throws {
        let detroit = try #require(TimeZone(identifier: "America/Detroit"))
        var context = BlueprintSetupDateContext(timeZone: detroit)
        let chosen = try date("2027-05-14T17:00:00Z")
        context.startsAt = chosen
        var schedule = BlueprintScheduleDraft()
        schedule.confirm(key: "arrival", date: chosen)

        #expect(context.selectTimeZone("Pacific/Auckland") == true)
        #expect(context.startsAt == chosen)
        #expect(context.timeZoneIdentifier == "Pacific/Auckland")
        #expect(context.useDeviceTimeZone(detroit) == true)
        // This is the same refresh the view performs after a zone change.
        _ = schedule.beginRefresh()
        #expect(context.startsAt == chosen)
        #expect(schedule.confirmedDates["arrival"] == chosen)
        #expect(context.timeZoneIdentifier == "America/Detroit")
    }

    @Test("An unchanged or invalid time zone does not trigger a schedule refresh")
    func invalidOrRepeatedZoneIsNoOp() throws {
        var context = BlueprintSetupDateContext(timeZone: try #require(TimeZone(identifier: "America/Detroit")))
        let initialDate = context.startsAt
        #expect(context.selectTimeZone("America/Detroit") == false)
        #expect(context.selectTimeZone("not/a/time-zone") == false)
        #expect(context.timeZoneIdentifier == "America/Detroit")
        #expect(context.startsAt == initialDate)
    }

    @Test("Picker options always contain the device selection, including GMT aliases", arguments: ["GMT", "UTC", "America/Detroit", "Asia/Kathmandu"])
    func pickerIncludesCurrentZone(_ identifier: String) throws {
        let context = BlueprintSetupDateContext(timeZone: try #require(TimeZone(identifier: identifier)))
        let options = context.timeZoneOptions
        #expect(options.filter { $0.id == context.timeZoneIdentifier }.count == 1)
        #expect(Set(options.map(\.id)).count == options.count)
        #expect(options.contains { $0.id == "America/Detroit" })
    }

    @Test("A new setup captures current system time-zone settings without location services")
    func defaultsUseSystemZone() {
        let context = BlueprintSetupDateContext()
        #expect(context.timeZoneIdentifier == TimeZone.current.identifier)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
