import Foundation
import Testing
@testable import Gatherory

@MainActor
struct InvitationSchedulePresentationTests {
    private let locale = Locale(identifier: "en_US")

    @Test("A same-day timed interval uses localized event-local date and times")
    func sameDayTimedInterval() throws {
        let presentation = InvitationSchedulePresentation(
            startsAt: try date("2026-07-03T16:00:00Z"),
            endsAt: try date("2026-07-03T18:30:00Z"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: locale,
            now: try date("2026-01-01T06:00:00Z")
        )

        #expect(presentation.isScheduled)
        #expect(presentation.monthText?.contains("Jul") == true)
        #expect(presentation.dayText == "3")
        #expect(presentation.dateText?.contains("Friday") == true)
        #expect(presentation.dateText?.contains("2026") != true)
        #expect(presentation.timeText?.contains("12:00") == true)
        #expect(presentation.timeText?.contains("2:30") == true)
        #expect(presentation.timezoneText == "EDT")
        #expect(presentation.accessibilityText?.contains("July 3, 2026") == true)
        #expect(presentation.accessibilityText?.contains("12:00") == true)
        #expect(presentation.accessibilityText?.contains("2:30") == true)
    }

    @Test("Overnight intervals keep both dates visible in the compact date range and accessibility text")
    func overnightTimedInterval() throws {
        let presentation = InvitationSchedulePresentation(
            startsAt: try date("2026-07-03T23:30:00-04:00"),
            endsAt: try date("2026-07-04T01:00:00-04:00"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: locale,
            now: try date("2026-01-01T06:00:00Z")
        )

        #expect(presentation.dateText?.contains("Jul 3") == true)
        #expect(presentation.dateText?.contains("4") == true)
        #expect(presentation.dateText?.components(separatedBy: "2026").count == 2)
        #expect(presentation.timeText?.contains("11:30") == true)
        #expect(presentation.timeText?.contains("1:00") == true)
        #expect(presentation.accessibilityText?.contains("July 3, 2026") == true)
        #expect(presentation.accessibilityText?.contains("July 4, 2026") == true)
    }

    @Test("Multiday all-day ranges retain the inclusive end date")
    func multidayAllDayRange() throws {
        let presentation = InvitationSchedulePresentation(
            startsAt: try date("2026-07-03T04:00:00Z"),
            endsAt: try date("2026-07-06T03:59:00Z"),
            isAllDay: true,
            timeZoneIdentifier: "America/New_York",
            locale: locale,
            now: try date("2026-01-01T06:00:00Z")
        )

        #expect(presentation.monthText?.contains("Jul") == true)
        #expect(presentation.dayText == "3")
        #expect(presentation.dateText?.contains("Jul 3") == true)
        #expect(presentation.dateText?.contains("5") == true)
        #expect(presentation.dateText?.components(separatedBy: "2026").count == 2)
        #expect(presentation.timeText == "All-day")
        #expect(presentation.timezoneText == nil)
        #expect(presentation.accessibilityText?.contains("July 3") == true)
        #expect(presentation.accessibilityText?.contains("July 5, 2026") == true)
        #expect(presentation.accessibilityText?.contains("All-day") == true)
    }

    @Test("Date components and intervals follow the event time zone through daylight saving")
    func eventTimeZoneAcrossDaylightSaving() throws {
        let presentation = InvitationSchedulePresentation(
            startsAt: try date("2026-03-08T04:30:00Z"),
            endsAt: try date("2026-03-08T07:30:00Z"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: locale,
            now: try date("2026-01-01T06:00:00Z")
        )

        #expect(presentation.monthText?.contains("Mar") == true)
        #expect(presentation.dayText == "7")
        #expect(presentation.dateText?.contains("Mar 7") == true)
        #expect(presentation.dateText?.contains("8") == true)
        #expect(presentation.timeText?.contains("11:30") == true)
        #expect(presentation.timeText?.contains("3:30") == true)
        #expect(presentation.timezoneText == "EST–EDT")
        #expect(presentation.accessibilityText?.contains("March 7, 2026") == true)
        #expect(presentation.accessibilityText?.contains("March 8, 2026") == true)
        #expect(presentation.accessibilityText?.contains("EST–EDT") == true)
    }

    @Test("Unscheduled events expose no fabricated date, time, zone, or accessibility schedule")
    func unscheduledEventHasNoScheduleText() {
        let presentation = InvitationSchedulePresentation(
            startsAt: nil,
            endsAt: .now,
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: locale
        )

        #expect(!presentation.isScheduled)
        #expect(presentation.monthText == nil)
        #expect(presentation.dayText == nil)
        #expect(presentation.dateText == nil)
        #expect(presentation.timeText == nil)
        #expect(presentation.timezoneText == nil)
        #expect(presentation.accessibilityText == nil)
    }

    @Test("Date labels use the event locale and add a year only when the event year differs")
    func localizedDateLabelAndYearContext() throws {
        let startsAt = try date("2026-07-03T16:00:00Z")
        let spanish = InvitationSchedulePresentation(
            startsAt: startsAt,
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: Locale(identifier: "es_ES"),
            now: try date("2026-01-01T06:00:00Z")
        )
        #expect(spanish.dateText?.lowercased().contains("viernes") == true)
        #expect(spanish.monthText?.lowercased().contains("jul") == true)

        let otherYear = InvitationSchedulePresentation(
            startsAt: startsAt,
            endsAt: nil,
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: locale,
            now: try date("2025-01-01T06:00:00Z")
        )
        #expect(otherYear.dateText?.contains("Friday") == true)
        #expect(otherYear.dateText?.contains("2026") == true)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
