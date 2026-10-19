import Foundation
import Testing
@testable import Gatherory

struct BlueprintInstallReadinessTests {
    @MainActor
    @Test("Confirmed dates remain available for editing and only selected dates affect readiness")
    func confirmedDatesStayEditable() {
        let original = Date(timeIntervalSince1970: 1_800_000_000)
        let edited = original.addingTimeInterval(3600)
        var draft = BlueprintScheduleDraft()
        draft.confirm(key: "activity", date: original)
        #expect(draft.initialManualDate(for: "activity", fallback: .distantFuture) == original)
        draft.confirm(key: "activity", date: edited)
        #expect(draft.initialManualDate(for: "activity", fallback: original) == edited)
        #expect(draft.confirmedDates.keys.contains("activity"))
        #expect(BlueprintInstallReadiness.isReady(mainDateConfirmed: true, selected: ["activity"], confirmed: draft.confirmedDates))
        #expect(!BlueprintInstallReadiness.isReady(mainDateConfirmed: false, selected: ["activity"], confirmed: draft.confirmedDates))
        #expect(draft.confirmedDates["activity"] == edited)
    }
    @Test("Compact dates hide technical zone names but preserve the event's wall time")
    func compactDates() throws {
        let zone = try #require(TimeZone(identifier: "America/Detroit"))
        let date = try #require(ISO8601DateFormatter().date(from: "2027-04-20T14:00:00Z"))
        let label = BlueprintSetupDateLabel.text(date, timeZone: zone, locale: Locale(identifier: "en_US"))
        #expect(label.contains("10:00"))
        #expect(!label.contains("GMT"))
        #expect(!label.contains("America/"))
        #expect(date == ISO8601DateFormatter().date(from: "2027-04-20T14:00:00Z"))
    }

    @Test("Repeated local times remain distinguishable when explicit offsets are needed")
    func repeatedDateLabels() throws {
        let zone = try #require(TimeZone(identifier: "America/Detroit"))
        let first = try #require(ISO8601DateFormatter().date(from: "2026-11-01T05:30:00Z"))
        let second = first.addingTimeInterval(3600)
        let locale = Locale(identifier: "en_US")
        #expect(BlueprintSetupDateLabel.text(first, timeZone: zone, locale: locale)
                == BlueprintSetupDateLabel.text(second, timeZone: zone, locale: locale))
        #expect(BlueprintSetupDateLabel.text(first, timeZone: zone, locale: locale, includesOffset: true)
                != BlueprintSetupDateLabel.text(second, timeZone: zone, locale: locale, includesOffset: true))
    }
    @Test("A legacy or unconfirmed main date never starts installation")
    func requiresExplicitMainConfirmation() {
        #expect(!BlueprintInstallReadiness.isReady(mainDateConfirmed: nil, selected: [], confirmed: [:]))
        #expect(!BlueprintInstallReadiness.isReady(mainDateConfirmed: false, selected: [], confirmed: [:]))
        #expect(BlueprintInstallReadiness.isReady(mainDateConfirmed: true, selected: [], confirmed: [:]))
    }

    @Test("Only missing selected dates are requested; existing edits and excluded dates are left alone")
    func missingSelectedDates() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let confirmed = ["edited": date, "excluded": date]
        #expect(BlueprintInstallReadiness.missingChildren(selected: ["edited", "missing"], confirmed: confirmed) == ["missing"])
        #expect(!BlueprintInstallReadiness.isReady(mainDateConfirmed: true, selected: ["edited", "missing"], confirmed: confirmed))
        #expect(BlueprintInstallReadiness.isReady(mainDateConfirmed: true, selected: ["edited"], confirmed: confirmed))
        #expect(confirmed["edited"] == date)
        #expect(BlueprintInstallReadiness.missingChildren(selected: ["invalid"], confirmed: ["invalid": Date(timeIntervalSince1970: .infinity)]) == ["invalid"])
    }
}
