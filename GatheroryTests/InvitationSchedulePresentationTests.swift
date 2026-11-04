import Foundation
import Testing
@testable import Gatherory

@MainActor
struct InvitationSchedulePresentationTests {
    private let locale = Locale(identifier: "en_US")
    private let now = try! #require(ISO8601DateFormatter().date(from: "2026-01-01T06:00:00Z"))

    @Test("Same-day schedule presents one compact date stamp and time interval")
    func sameDayInterval() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-07-03T16:00:00Z"), endsAt: try date("2026-07-03T18:30:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.monthText == "Jul")
        #expect(p.dayText == "3")
        #expect(!p.hasDateRange)
        #expect(p.dateText?.contains("Fri") == true)
        #expect(p.timeText?.contains("12:00") == true)
        #expect(p.timeText?.contains("2:30") == true)
        #expect(p.timezoneText == nil)
        #expect(p.accessibilityText?.contains("EDT") == true)
    }

    @Test("Multiday schedule exposes paired endpoint stamps and concise weekday and time")
    func multidayInterval() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-10-26T16:00:00Z"), endsAt: try date("2026-10-29T16:00:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.monthText == "Oct")
        #expect(p.dayText == "26")
        #expect(p.endMonthText == "Oct")
        #expect(p.endDayText == "29")
        #expect(p.hasDateRange)
        #expect(p.startWeekdayText?.contains("Mon") == true)
        #expect(p.endWeekdayText?.contains("Thu") == true)
        #expect(p.startTimeText?.contains("12:00") == true)
        #expect(p.endTimeText?.contains("12:00") == true)
        #expect(p.timeText == nil)
        #expect(p.startTimeText?.contains("2026") != true)
        #expect(p.startTimeText?.contains("Oct") != true)
        #expect(p.timezoneText == nil)
        #expect(p.accessibilityText?.contains("October 26, 2026") == true)
        #expect(p.accessibilityText?.contains("October 29, 2026") == true)
    }

    @Test("Equal-hour endpoint times retain localized shared meridiem formatting")
    func sharedMeridiem() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-10-26T16:00:00Z"), endsAt: try date("2026-10-29T16:00:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.startTimeText?.contains("12:00") == true)
        #expect(p.endTimeText?.contains("12:00") == true)
        #expect(p.startTimeText?.contains("PM") == true)
        #expect(p.endTimeText?.contains("PM") == true)
        #expect(p.startTimeText?.contains("EDT") != true)
        #expect(p.timeText == nil)
    }

    @Test("Year is shown in stamps for events outside the current year and across years")
    func crossYear() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-12-31T15:00:00Z"), endsAt: try date("2027-01-01T15:00:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.monthText?.contains("2026") == true)
        #expect(p.endMonthText?.contains("2027") == true)
        #expect(p.monthText?.contains("Dec") == true)
        #expect(p.endMonthText?.contains("Jan") == true)
    }

    @Test("All-day multiday schedule keeps endpoint stamps and no time zone")
    func allDay() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-07-03T04:00:00Z"), endsAt: try date("2026-07-06T03:59:00Z"), isAllDay: true, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.dayText == "3")
        #expect(p.endDayText == "5")
        #expect(p.timeText == "All-day")
        #expect(p.timezoneText == nil)
        #expect(p.accessibilityText?.contains("July 3") == true)
        #expect(p.accessibilityText?.contains("July 5, 2026") == true)
    }

    @Test("Unscheduled and invalid ends do not create an endpoint range")
    func unscheduledAndInvalidEnd() throws {
        let unscheduled = InvitationSchedulePresentation(startsAt: nil, endsAt: .now, isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(!unscheduled.isScheduled)
        #expect(unscheduled.monthText == nil)
        #expect(unscheduled.endMonthText == nil)
        #expect(unscheduled.accessibilityText == nil)
        let invalidEnd = InvitationSchedulePresentation(startsAt: try date("2026-07-03T16:00:00Z"), endsAt: try date("2026-07-03T15:00:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(!invalidEnd.hasDateRange)
        #expect(invalidEnd.endMonthText == nil)
        #expect(invalidEnd.timeText?.contains("12:00") == true)
    }

    @Test("Event local dates and times stay correct across daylight saving and locale")
    func daylightSavingAndLocale() throws {
        let p = InvitationSchedulePresentation(startsAt: try date("2026-03-08T04:30:00Z"), endsAt: try date("2026-03-08T07:30:00Z"), isAllDay: false, timeZoneIdentifier: "America/New_York", locale: locale, now: now)
        #expect(p.dayText == "7")
        #expect(p.startTimeText?.contains("11:30") == true)
        #expect(p.endTimeText?.contains("3:30") == true)
        #expect(p.timeText == nil)
        #expect(p.accessibilityText?.contains("EST–EDT") == true)
        let spanish = InvitationSchedulePresentation(startsAt: try date("2026-07-03T16:00:00Z"), endsAt: nil, isAllDay: false, timeZoneIdentifier: "America/New_York", locale: Locale(identifier: "es_ES"), now: now)
        #expect(spanish.dateText?.lowercased().contains("vie") == true)
        #expect(spanish.monthText?.lowercased().contains("jul") == true)
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
