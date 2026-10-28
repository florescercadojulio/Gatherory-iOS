import Foundation

@MainActor
struct InvitationHeroSchedulePresentation: Equatable {
    let text: String
    let accessibilityText: String?

    init(
        startsAt: Date?,
        endsAt: Date?,
        isAllDay: Bool,
        timeZoneIdentifier: String,
        locale: Locale = .current,
        now: Date = .now
    ) {
        let detailedSchedule = InvitationSchedulePresentation(
            startsAt: startsAt,
            endsAt: endsAt,
            isAllDay: isAllDay,
            timeZoneIdentifier: timeZoneIdentifier,
            locale: locale,
            now: now
        )
        accessibilityText = detailedSchedule.accessibilityText

        guard let startsAt else {
            let bundle = EventCSVEncoder.localizationBundle(for: locale)
            text = String(
                localized: "Date to be decided",
                defaultValue: "Date to be decided",
                bundle: bundle,
                locale: locale
            )
            return
        }

        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .autoupdatingCurrent
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        calendar.timeZone = timeZone
        let validEnd = endsAt.flatMap { $0 > startsAt ? $0 : nil }
        let isMultiDay = validEnd.map { !calendar.isDate(startsAt, inSameDayAs: $0) } ?? false
        let dateText: String

        if isMultiDay, let validEnd {
            dateText = Self.dateIntervalText(
                from: startsAt,
                to: validEnd,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
        } else if let dayOffset = Self.relativeDayOffset(
            for: startsAt,
            calendar: calendar,
            now: now
        ), (-1...1).contains(dayOffset) {
            dateText = Self.relativeDayText(dayOffset, locale: locale)
        } else {
            let eventYear = calendar.component(.year, from: startsAt)
            let currentYear = calendar.component(.year, from: now)
            let template = eventYear == currentYear ? "MMM d" : "yMMM d"
            dateText = Self.dateText(
                template: template,
                date: startsAt,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
        }

        guard !isAllDay, !isMultiDay else {
            text = dateText
            return
        }

        let timeText = Self.timeText(
            startsAt,
            calendar: calendar,
            timeZone: timeZone,
            locale: locale
        )
        text = "\(dateText) · \(timeText)"
    }

    private static func relativeDayOffset(
        for date: Date,
        calendar: Calendar,
        now: Date
    ) -> Int? {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEvent = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startOfToday, to: startOfEvent).day
    }

    private static func relativeDayText(_ dayOffset: Int, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        var components = DateComponents()
        components.day = dayOffset
        let localized = formatter.localizedString(from: components)
        return localized.prefix(1).uppercased(with: locale) + String(localized.dropFirst())
    }

    private static func dateText(
        template: String,
        date: Date,
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

    private static func timeText(
        _ date: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func dateIntervalText(
        from start: Date,
        to end: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateIntervalFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}
