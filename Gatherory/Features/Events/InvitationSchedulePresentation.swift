import Foundation

@MainActor
struct InvitationSchedulePresentation: Equatable {
    let isScheduled: Bool
    let isAllDay: Bool
    let monthText: String?
    let dayText: String?
    let endMonthText: String?
    let endDayText: String?
    let startWeekdayText: String?
    let endWeekdayText: String?
    let dateText: String?
    let timeText: String?
    let startTimeText: String?
    let endTimeText: String?
    let timezoneText: String?
    let accessibilityText: String?
    var hasDateRange: Bool { endDayText != nil }

    init(
        startsAt: Date?,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        locale: Locale = .current,
        now: Date = .now
    ) {
        self.isAllDay = isAllDay
        guard let startsAt else {
            isScheduled = false
            monthText = nil
            dayText = nil
            endMonthText = nil
            endDayText = nil
            startWeekdayText = nil
            endWeekdayText = nil
            dateText = nil
            timeText = nil
            startTimeText = nil
            endTimeText = nil
            timezoneText = nil
            accessibilityText = nil
            return
        }

        isScheduled = true
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        calendar.timeZone = timeZone
        let validEnd = endsAt.flatMap { $0 > startsAt ? $0 : nil }
        let crossesLocalDate = validEnd.map { !calendar.isDate(startsAt, inSameDayAs: $0) } ?? false
        let currentYear = calendar.component(.year, from: now)
        let startYear = calendar.component(.year, from: startsAt)
        let endYear = validEnd.map { calendar.component(.year, from: $0) }

        let showsYearInStamps = startYear != currentYear || endYear.map { $0 != startYear } == true
        monthText = Self.dateComponentText(showsYearInStamps ? "MMM y" : "MMM", startsAt, calendar: calendar, timeZone: timeZone, locale: locale)
        dayText = Self.dateComponentText("d", startsAt, calendar: calendar, timeZone: timeZone, locale: locale)
        startWeekdayText = Self.dateComponentText("EEE", startsAt, calendar: calendar, timeZone: timeZone, locale: locale)
        if crossesLocalDate, let validEnd {
            endMonthText = Self.dateComponentText(showsYearInStamps ? "MMM y" : "MMM", validEnd, calendar: calendar, timeZone: timeZone, locale: locale)
            endDayText = Self.dateComponentText("d", validEnd, calendar: calendar, timeZone: timeZone, locale: locale)
            endWeekdayText = Self.dateComponentText("EEE", validEnd, calendar: calendar, timeZone: timeZone, locale: locale)
            dateText = nil
        } else {
            endMonthText = nil
            endDayText = nil
            endWeekdayText = nil
            dateText = startWeekdayText
        }

        if isAllDay {
            let bundle = EventCSVEncoder.localizationBundle(for: locale)
            let allDayText = String(localized: "All-day", defaultValue: "All-day", bundle: bundle, locale: locale)
            timeText = allDayText
            startTimeText = nil
            endTimeText = nil
            timezoneText = nil
            let fullDate = if crossesLocalDate, let validEnd {
                Self.intervalText(from: startsAt, to: validEnd, dateStyle: .full, timeStyle: .none, calendar: calendar, timeZone: timeZone, locale: locale)
            } else {
                Self.dateTimeText(startsAt, dateStyle: .full, timeStyle: .none, calendar: calendar, timeZone: timeZone, locale: locale)
            }
            accessibilityText = "\(fullDate), \(allDayText)"
        } else {
            let startZoneText = Self.timeZoneLabel(timeZone, at: startsAt, locale: locale)
            let endZoneText = validEnd.map { Self.timeZoneLabel(timeZone, at: $0, locale: locale) }
            let zoneText = endZoneText.flatMap { $0 == startZoneText ? nil : $0 }.map { "\(startZoneText)–\($0)" } ?? startZoneText
            timezoneText = nil
            if let validEnd {
                if crossesLocalDate {
                    startTimeText = Self.dateTimeText(startsAt, dateStyle: .none, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                    endTimeText = Self.dateTimeText(validEnd, dateStyle: .none, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                    timeText = nil
                } else {
                    startTimeText = nil
                    endTimeText = nil
                    timeText = Self.intervalText(from: startsAt, to: validEnd, dateStyle: .none, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                }
                let accessibleInterval = Self.intervalText(from: startsAt, to: validEnd, dateStyle: .full, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                accessibilityText = "\(accessibleInterval), \(zoneText)"
            } else {
                startTimeText = nil
                endTimeText = nil
                timeText = Self.dateTimeText(startsAt, dateStyle: .none, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                let accessibleDate = Self.dateTimeText(startsAt, dateStyle: .full, timeStyle: .short, calendar: calendar, timeZone: timeZone, locale: locale)
                accessibilityText = "\(accessibleDate), \(zoneText)"
            }
        }
    }

    private static func dateComponentText(_ template: String, _ date: Date, calendar: Calendar, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func dateTimeText(_ date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style, calendar: Calendar, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func intervalText(from start: Date, to end: Date, dateStyle: DateIntervalFormatter.Style, timeStyle: DateIntervalFormatter.Style, calendar: Calendar, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: start, to: end)
    }

    private static func timeZoneLabel(_ timeZone: TimeZone, at date: Date, locale: Locale) -> String {
        timeZone.abbreviation(for: date) ?? timeZone.localizedName(for: .shortGeneric, locale: locale) ?? timeZone.identifier
    }
}
