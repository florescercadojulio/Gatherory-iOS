import Foundation

@MainActor
struct HomeEventTimePresentation: Equatable {
    let text: String?
    let accessibilityText: String?

    init(
        startsAt: Date?,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        locale: Locale = .current
    ) {
        let schedule = InvitationSchedulePresentation(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            locale: locale
        )
        accessibilityText = schedule.accessibilityText

        guard let startsAt else {
            text = nil
            return
        }
        if isAllDay {
            text = schedule.timeText
            return
        }

        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        calendar.timeZone = timeZone

        guard let endsAt, endsAt > startsAt else {
            text = Self.dateIntervalText(
                from: startsAt,
                to: startsAt,
                dateStyle: .none,
                timeStyle: .short,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
            return
        }

        let crossesLocalDate = !calendar.isDate(startsAt, inSameDayAs: endsAt)
        if crossesLocalDate {
            let crossesYear = calendar.component(.year, from: startsAt) != calendar.component(.year, from: endsAt)
            let startTime = Self.dateTimeText(
                startsAt,
                dateStyle: .none,
                timeStyle: .short,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
            let endDate = Self.dateComponentText(
                crossesYear ? "yMMMd" : "MMMd",
                endsAt,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
            let endTime = Self.dateTimeText(
                endsAt,
                dateStyle: .none,
                timeStyle: .short,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
            text = "\(startTime)–\(endDate), \(endTime)"
        } else {
            text = Self.dateIntervalText(
                from: startsAt,
                to: endsAt,
                dateStyle: .none,
                timeStyle: .short,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
        }
    }

    private static func dateIntervalText(
        from start: Date,
        to end: Date,
        dateStyle: DateIntervalFormatter.Style,
        timeStyle: DateIntervalFormatter.Style,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: start, to: end)
    }

    private static func dateTimeText(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func dateComponentText(
        _ template: String,
        _ date: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
