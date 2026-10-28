import Foundation
import Testing
@testable import Gatherory

@MainActor
struct HomeEventTimePresentationTests {
    private let english = Locale(identifier: "en_US")

    @Test("Same-day timed events show a compact localized time interval")
    func sameDayInterval() throws {
        let presentation = HomeEventTimePresentation(
            startsAt: try date("2026-07-03T16:00:00Z"),
            endsAt: try date("2026-07-03T18:30:00Z"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )

        #expect(presentation.text?.contains("12:00") == true)
        #expect(presentation.text?.contains("2:30") == true)
        #expect(presentation.text?.contains("July") != true)
        #expect(presentation.text?.contains("2026") != true)
        #expect(presentation.accessibilityText?.contains("July 3, 2026") == true)
        #expect(presentation.accessibilityText?.contains("EDT") == true)
    }

    @Test("Cross-midnight intervals include a date for clarity")
    func crossMidnightInterval() throws {
        let presentation = HomeEventTimePresentation(
            startsAt: try date("2026-07-03T23:00:00-04:00"),
            endsAt: try date("2026-07-04T01:00:00-04:00"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )

        #expect(presentation.text?.contains("11:00") == true)
        #expect(presentation.text?.contains("1:00") == true)
        #expect(presentation.text?.contains("Jul 4") == true)
        #expect(presentation.text?.contains("7/3") != true)
        #expect(presentation.text?.contains("2026") != true)
        #expect(presentation.text?.components(separatedBy: "Jul").count == 2)
        #expect(presentation.accessibilityText?.contains("July 3, 2026") == true)
        #expect(presentation.accessibilityText?.contains("July 4, 2026") == true)
    }

    @Test("Cross-year compact intervals include the end year")
    func crossYearInterval() throws {
        let presentation = HomeEventTimePresentation(
            startsAt: try date("2026-12-31T23:00:00-05:00"),
            endsAt: try date("2027-01-01T01:00:00-05:00"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )

        #expect(presentation.text?.contains("11:00") == true)
        #expect(presentation.text?.contains("1:00") == true)
        #expect(presentation.text?.contains("2027") == true)
        #expect(presentation.text?.contains("2026") != true)
    }

    @Test("Accessible schedule keeps daylight-saving timezone changes explicit")
    func daylightSavingTransition() throws {
        let presentation = HomeEventTimePresentation(
            startsAt: try date("2026-03-08T04:30:00Z"),
            endsAt: try date("2026-03-08T07:30:00Z"),
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )

        #expect(presentation.text?.contains("11:30") == true)
        #expect(presentation.text?.contains("3:30") == true)
        #expect(presentation.accessibilityText?.contains("EST–EDT") == true)
    }

    @Test("Spanish uses localized 24-hour time formatting")
    func spanish24HourFormatting() throws {
        let presentation = HomeEventTimePresentation(
            startsAt: try date("2026-07-03T18:00:00Z"),
            endsAt: try date("2026-07-03T19:30:00Z"),
            isAllDay: false,
            timeZoneIdentifier: "Europe/Madrid",
            locale: Locale(identifier: "es_ES")
        )

        #expect(presentation.text?.contains("20:00") == true)
        #expect(presentation.text?.contains("21:30") == true)
        #expect(presentation.text?.contains("PM") != true)
    }

    @Test("All-day, unscheduled, and invalid-end events keep the expected compact text")
    func specialScheduleCases() throws {
        let startsAt = try date("2026-07-03T16:00:00Z")
        let allDay = HomeEventTimePresentation(
            startsAt: startsAt,
            endsAt: nil,
            isAllDay: true,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )
        #expect(allDay.text == "All-day")
        #expect(allDay.accessibilityText?.contains("All-day") == true)

        let unscheduled = HomeEventTimePresentation(
            startsAt: nil,
            endsAt: startsAt,
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )
        #expect(unscheduled.text == nil)
        #expect(unscheduled.accessibilityText == nil)

        let invalidEnd = HomeEventTimePresentation(
            startsAt: startsAt,
            endsAt: startsAt,
            isAllDay: false,
            timeZoneIdentifier: "America/New_York",
            locale: english
        )
        #expect(invalidEnd.text?.contains("12:00") == true)
        #expect(invalidEnd.text?.contains("July") != true)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
