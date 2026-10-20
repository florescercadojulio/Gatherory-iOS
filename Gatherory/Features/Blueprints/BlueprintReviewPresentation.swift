import Foundation

@MainActor enum BlueprintReviewPresentation {
    static func schedule(
        dayOffset: Int,
        localTime: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let time = formattedTime(localTime, locale: locale) else { return nil }

        switch dayOffset {
        case 0:
            return String.localizedStringWithFormat(BlueprintCopy.reviewSameDayFormat, time)
        case -1:
            return String.localizedStringWithFormat(BlueprintCopy.reviewDayBeforeFormat, time)
        case 1:
            return String.localizedStringWithFormat(BlueprintCopy.reviewDayAfterFormat, time)
        case ..<0:
            guard dayOffset.magnitude <= UInt(Int64.max) else { return nil }
            return String.localizedStringWithFormat(
                BlueprintCopy.reviewDaysBeforeFormat,
                Int64(dayOffset.magnitude),
                time
            )
        default:
            guard dayOffset.magnitude <= UInt(Int64.max) else { return nil }
            return String.localizedStringWithFormat(
                BlueprintCopy.reviewDaysAfterFormat,
                Int64(dayOffset.magnitude),
                time
            )
        }
    }

    private static func formattedTime(_ value: String, locale: Locale) -> String? {
        guard value.utf8.count == 5 else { return nil }
        let bytes = Array(value.utf8)
        guard bytes[2] == 58,
              bytes[0].isASCIIDigit,
              bytes[1].isASCIIDigit,
              bytes[3].isASCIIDigit,
              bytes[4].isASCIIDigit,
              let hour = Int(value.prefix(2)),
              let minute = Int(value.suffix(2)),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = utc
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = utc
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool { (48...57).contains(self) }
}
