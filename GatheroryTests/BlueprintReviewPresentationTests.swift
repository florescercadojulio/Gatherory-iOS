import Foundation
import Testing
@testable import Gatherory

@MainActor struct BlueprintReviewPresentationTests {
    @Test("Schedule review uses relative day wording and the supplied local time")
    func relativeScheduleWording() throws {
        let locale = Locale(identifier: "en_US")
        let cases: [(offset: Int, prefix: String)] = [
            (0, "Same day · "),
            (-1, "The day before · "),
            (1, "The next day · "),
            (-4, "4 days before · "),
            (4, "4 days after · "),
        ]

        for item in cases {
            let value = try #require(
                BlueprintReviewPresentation.schedule(dayOffset: item.offset, localTime: "09:05", locale: locale)
            )
            #expect(value.hasPrefix(item.prefix))
            #expect(value.contains("9:05"))
            #expect(value.contains("AM"))
        }
    }

    @Test("Schedule review formats short time using the requested 12 or 24 hour locale")
    func localeTimeFormatting() throws {
        let us = try #require(
            BlueprintReviewPresentation.schedule(
                dayOffset: 0, localTime: "14:30", locale: Locale(identifier: "en_US")
            )
        )
        let uk = try #require(
            BlueprintReviewPresentation.schedule(
                dayOffset: 0, localTime: "14:30", locale: Locale(identifier: "en_GB")
            )
        )

        #expect(us.contains("2:30"))
        #expect(us.contains("PM"))
        #expect(uk.contains("14:30"))
        #expect(!uk.contains("PM"))
    }

    @Test("Schedule time remains local across midnight and is not shifted by a date")
    func localTimeHasNoDateOrTimezoneShift() throws {
        let midnight = try #require(
            BlueprintReviewPresentation.schedule(
                dayOffset: -1, localTime: "00:15", locale: Locale(identifier: "en_US")
            )
        )
        let late = try #require(
            BlueprintReviewPresentation.schedule(
                dayOffset: 1, localTime: "23:45", locale: Locale(identifier: "en_GB")
            )
        )

        #expect(midnight.contains("12:15"))
        #expect(midnight.contains("AM"))
        #expect(late.contains("23:45"))
    }

    @Test("Schedule review rejects malformed times and unrepresentable offsets")
    func invalidScheduleInput() {
        let invalidTimes = ["9:05", "09:5", "24:00", "12:60", "09:xx", " 09:05", "٠٩:٠٥"]
        for time in invalidTimes {
            #expect(BlueprintReviewPresentation.schedule(dayOffset: 0, localTime: time) == nil)
        }

        #expect(BlueprintReviewPresentation.schedule(dayOffset: .min, localTime: "09:05") == nil)
    }
}
