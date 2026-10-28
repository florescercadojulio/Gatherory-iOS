import Foundation
import Testing
@testable import Gatherory

@MainActor
struct InvitationHeroSchedulePresentationTests {
    private let locale = Locale(identifier: "en_US")
    private let timeZone = "America/New_York"

    @Test("Single-day events use localized yesterday, today, and tomorrow labels")
    func relativeDayBoundaries() throws {
        let now = try date("2026-10-27T15:00:00Z")
        let yesterday = presentation(
            startsAt: try date("2026-10-26T17:00:00Z"),
            now: now
        )
        let today = presentation(
            startsAt: try date("2026-10-27T21:00:00Z"),
            now: now
        )
        let tomorrow = presentation(
            startsAt: try date("2026-10-28T15:00:00Z"),
            now: now
        )

        #expect(yesterday.text.hasPrefix("Yesterday · "))
        #expect(today.text.hasPrefix("Today · "))
        #expect(tomorrow.text.hasPrefix("Tomorrow · "))
    }

    @Test("Relative dates use the event-local calendar near midnight and across DST")
    func eventLocalCalendarBoundaries() throws {
        let nearMidnight = presentation(
            startsAt: try date("2026-10-27T05:00:00Z"),
            now: try date("2026-10-27T03:30:00Z")
        )
        #expect(nearMidnight.text.hasPrefix("Tomorrow · "))

        let daylightSavingBoundary = presentation(
            startsAt: try date("2026-03-08T07:30:00Z"),
            now: try date("2026-03-08T04:30:00Z")
        )
        #expect(daylightSavingBoundary.text.hasPrefix("Tomorrow · "))
    }

    @Test("Multiday events show a concise date interval without relative wording or times")
    func multidayRangeOmitsTimeAndRelativeLabel() throws {
        let start = try date("2026-10-28T14:00:00Z")
        let end = try date("2026-10-30T21:00:00Z")
        let hero = presentation(
            startsAt: start,
            endsAt: end,
            now: try date("2026-10-27T15:00:00Z")
        )

        #expect(hero.text.contains("Oct"))
        #expect(hero.text.contains("28"))
        #expect(hero.text.contains("30"))
        #expect(hero.text.contains("2026"))
        #expect(!hero.text.contains("Tomorrow"))
        #expect(!hero.text.contains("10:00"))
        #expect(!hero.text.contains("5:00"))
        #expect(!hero.text.contains("EDT"))

        let detailed = InvitationSchedulePresentation(
            startsAt: start,
            endsAt: end,
            isAllDay: false,
            timeZoneIdentifier: timeZone,
            locale: locale,
            now: try date("2026-10-27T15:00:00Z")
        )
        #expect(hero.accessibilityText == detailed.accessibilityText)
    }

    @Test("Single-day dates outside the relative window use localized month day and year")
    func datedStartOnlySchedule() throws {
        let start = try date("2027-02-20T15:00:00Z")
        let hero = presentation(
            startsAt: start,
            now: try date("2026-10-27T15:00:00Z")
        )

        #expect(hero.text.contains("Feb"))
        #expect(hero.text.contains("20"))
        #expect(hero.text.contains("2027"))
        #expect(hero.text.contains("10:00"))
        #expect(!hero.text.contains("EDT"))
    }

    @Test("All-day single dates omit the time while retaining full accessibility schedule")
    func allDayHeroIsDateOnly() throws {
        let start = try date("2026-10-28T04:00:00Z")
        let now = try date("2026-10-27T15:00:00Z")
        let hero = presentation(startsAt: start, isAllDay: true, now: now)

        #expect(hero.text == "Tomorrow")
        #expect(!hero.text.contains("·"))
        let detailed = InvitationSchedulePresentation(
            startsAt: start,
            endsAt: nil,
            isAllDay: true,
            timeZoneIdentifier: timeZone,
            locale: locale,
            now: now
        )
        #expect(hero.accessibilityText == detailed.accessibilityText)
    }

    @Test("Relative labels and date text honor the requested locale")
    func spanishRelativeLabel() throws {
        let hero = InvitationHeroSchedulePresentation(
            startsAt: try date("2026-10-28T15:00:00Z"),
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: timeZone,
            locale: Locale(identifier: "es_ES"),
            now: try date("2026-10-27T15:00:00Z")
        )

        #expect(hero.text.lowercased().contains("mañana"))
        #expect(hero.text.contains("·"))
    }

    @Test("Unscheduled schedules retain the localized existing placeholder")
    func unscheduledPlaceholder() {
        let hero = InvitationHeroSchedulePresentation(
            startsAt: nil,
            endsAt: .now,
            isAllDay: false,
            timeZoneIdentifier: timeZone,
            locale: locale
        )

        #expect(hero.text == "Date to be decided")
        #expect(hero.accessibilityText == nil)
    }

    private func presentation(
        startsAt: Date,
        endsAt: Date? = nil,
        isAllDay: Bool = false,
        now: Date
    ) -> InvitationHeroSchedulePresentation {
        InvitationHeroSchedulePresentation(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZone,
            locale: locale,
            now: now
        )
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
