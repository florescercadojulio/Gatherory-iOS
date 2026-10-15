import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintScheduleDraftTests {
    @Test("Manual venue/rehearsal pickers start with their blueprint suggestions without confirming", arguments: [
        ("venue_visit", "2027-03-16T16:00:00Z"),
        ("rehearsal", "2027-04-14T21:00:00Z")
    ])
    func manualPickerUsesSuggestion(key: String, instant: String) {
        var draft = BlueprintScheduleDraft()
        let main = date("2027-04-15T15:56:14Z")
        let proposed = date(instant)
        let token = draft.beginRefresh()
        _ = draft.apply([suggestion(key, status: "suggested", candidates: [proposed])], token: token)

        let pickerDate = draft.initialManualDate(for: key, fallback: main)
        #expect(pickerDate == proposed)
        #expect(draft.confirmedDates.isEmpty) // Opening, or then cancelling, is not consent.
        draft.confirm(key: key, date: pickerDate)
        #expect(draft.confirmedDates[key] == proposed)
    }

    @Test("An edited date wins over refreshed suggestions and a changed main date")
    func manualPickerPreservesEditedDate() {
        var draft = BlueprintScheduleDraft()
        let edited = date("2027-04-13T20:00:00Z")
        let main = date("2027-05-15T16:00:00Z")
        draft.confirm(key: "rehearsal", date: edited)
        let token = draft.beginRefresh()
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == edited)
        _ = draft.apply([suggestion("rehearsal", status: "suggested", candidates: [main])], token: token)
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == edited)
        let failedToken = draft.beginRefresh()
        draft.failRefresh(token: failedToken)
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == edited)
    }

    @Test("Manual picker ignores expired suggestions while refreshing or after failure")
    func manualPickerRejectsStaleSuggestions() {
        var draft = BlueprintScheduleDraft()
        let main = date("2027-04-15T15:56:14Z")
        let proposed = date("2027-04-14T21:00:00Z")
        let oldToken = draft.beginRefresh()
        _ = draft.apply([suggestion("rehearsal", status: "suggested", candidates: [proposed])], token: oldToken)
        let newToken = draft.beginRefresh()
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == main)
        #expect(draft.apply([suggestion("rehearsal", status: "suggested", candidates: [proposed])], token: oldToken) == false)
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == main)
        draft.failRefresh(token: newToken)
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == main)
        #expect(draft.confirmedDates.isEmpty)
    }

    @Test("An open manual draft stays independent of late suggestions until confirmation")
    func refreshDoesNotReplaceOpenPickerEdit() {
        var draft = BlueprintScheduleDraft()
        let main = date("2027-04-15T15:56:14Z")
        let initial = date("2027-04-14T21:00:00Z")
        let token = draft.beginRefresh()
        _ = draft.apply([suggestion("rehearsal", status: "suggested", candidates: [initial])], token: token)
        var pickerDate = draft.initialManualDate(for: "rehearsal", fallback: main)
        #expect(pickerDate == initial)
        pickerDate = date("2027-04-13T19:00:00Z")
        let edited = pickerDate
        let refreshedToken = draft.beginRefresh()
        _ = draft.apply([suggestion("rehearsal", status: "suggested", candidates: [main])], token: refreshedToken)
        #expect(pickerDate == edited)
        #expect(draft.confirmedDates.isEmpty)
        draft.confirm(key: "rehearsal", date: pickerDate)
        #expect(draft.initialManualDate(for: "rehearsal", fallback: main) == edited)
    }

    @Test("Manual picker falls back for missing, ambiguous, nonexistent or invalid suggestions")
    func manualPickerFallbacks() {
        var draft = BlueprintScheduleDraft()
        let main = date("2027-04-15T15:56:14Z")
        let first = date("2027-11-07T05:30:00Z")
        let second = date("2027-11-07T06:30:00Z")
        let token = draft.beginRefresh()
        _ = draft.apply([
            suggestion("ambiguous", status: "ambiguous", candidates: [first, second]),
            suggestion("nonexistent", status: "nonexistent", candidates: []),
            suggestion("unknown", status: "future_status", candidates: [first]),
            suggestion("empty", status: "suggested", candidates: []),
            suggestion("multiple", status: "suggested", candidates: [first, second]),
            suggestion("invalid", status: "suggested", candidates: [Date(timeIntervalSinceReferenceDate: .infinity)])
        ], token: token)
        for key in ["missing", "ambiguous", "nonexistent", "unknown", "empty", "multiple", "invalid"] {
            #expect(draft.initialManualDate(for: key, fallback: main) == main)
        }
        #expect(draft.confirmedDates.isEmpty)
        // Explicitly choosing the later occurrence still takes precedence.
        #expect(draft.confirmSuggestion(key: "ambiguous", candidateIndex: 1, token: token) == true)
        #expect(draft.initialManualDate(for: "ambiguous", fallback: main) == second)
    }

    @Test("Applying suggestions never confirms a date automatically")
    func suggestionsDoNotConfirmAutomatically() {
        var draft = BlueprintScheduleDraft()
        let candidate = date("2026-06-20T16:00:00Z")
        let token = draft.beginRefresh()

        #expect(draft.apply([suggestion("ceremony", status: "suggested", candidates: [candidate])], token: token) == true)
        #expect(draft.confirmedDates.isEmpty)
    }

    @Test("A person can confirm one valid suggestion candidate explicitly")
    func confirmsOneCandidate() {
        var draft = BlueprintScheduleDraft()
        let first = date("2026-06-20T16:00:00Z")
        let second = date("2026-06-21T16:00:00Z")
        let token = draft.beginRefresh()
        _ = draft.apply([suggestion("ceremony", status: "ambiguous", candidates: [first, second])], token: token)

        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 1, token: token) == true)
        #expect(draft.confirmedDates["ceremony"] == second)
        #expect(draft.confirmedDates.count == 1)
    }

    @Test("Refreshing preserves manually confirmed dates even when suggestions change")
    func refreshPreservesConfirmedDate() {
        var draft = BlueprintScheduleDraft()
        let chosen = date("2026-06-20T16:00:00Z")
        let replacement = date("2026-06-22T16:00:00Z")
        draft.confirm(key: "ceremony", date: chosen)

        let token = draft.beginRefresh()
        #expect(draft.suggestions.isEmpty)
        #expect(draft.confirmedDates["ceremony"] == chosen)
        #expect(draft.apply([suggestion("ceremony", status: "suggested", candidates: [replacement])], token: token) == true)
        #expect(draft.confirmedDates["ceremony"] == chosen)
    }

    @Test("An old token stays stale across an A to B to A refresh sequence")
    func staleTokenIgnoredWhenInputsRepeat() {
        var draft = BlueprintScheduleDraft()
        let repeatedSuggestion = suggestion("ceremony", status: "suggested", candidates: [date("2026-06-20T16:00:00Z")])
        let tokenA = draft.beginRefresh()
        _ = draft.apply([repeatedSuggestion], token: tokenA)
        let tokenB = draft.beginRefresh()
        _ = draft.apply([suggestion("ceremony", status: "suggested", candidates: [date("2026-06-22T16:00:00Z")])], token: tokenB)
        let tokenAAgain = draft.beginRefresh()

        #expect(tokenA != tokenAAgain)
        draft.failRefresh(token: tokenA)
        #expect(draft.isRefreshing)
        #expect(draft.apply([repeatedSuggestion], token: tokenA) == false)
        #expect(draft.suggestions.isEmpty)
        #expect(draft.apply([repeatedSuggestion], token: tokenAAgain) == true)
    }

    @Test("A refreshed suggestion cannot be confirmed with its previous token")
    func refreshedSuggestionRejectsOldToken() {
        var draft = BlueprintScheduleDraft()
        let oldToken = draft.beginRefresh()
        _ = draft.apply([suggestion("ceremony", status: "suggested", candidates: [date("2026-06-20T16:00:00Z")])], token: oldToken)
        let newToken = draft.beginRefresh()
        _ = draft.apply([suggestion("ceremony", status: "suggested", candidates: [date("2026-06-21T16:00:00Z")])], token: newToken)

        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 0, token: oldToken) == false)
        #expect(draft.confirmedDates.isEmpty)
        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 0, token: newToken) == true)
    }

    @Test("A failed refresh preserves dates, and manual confirmation remains available")
    func failurePreservesDatesAndManualConfirmationWorks() {
        var draft = BlueprintScheduleDraft()
        let chosen = date("2026-06-20T16:00:00Z")
        draft.confirm(key: "ceremony", date: chosen)
        let token = draft.beginRefresh()
        draft.failRefresh(token: token)

        #expect(draft.confirmedDates["ceremony"] == chosen)
        #expect(draft.suggestions.isEmpty)
        #expect(draft.refreshFailed)
        let edited = date("2026-06-20T18:30:00Z")
        draft.confirm(key: "ceremony", date: edited)
        #expect(draft.confirmedDates["ceremony"] == edited)
    }

    @Test("Deselecting removes its confirmed date and reselection requires confirmation")
    func deselectionRequiresConfirmationAgain() {
        var draft = BlueprintScheduleDraft()
        let chosen = date("2026-06-20T16:00:00Z")
        let token = draft.beginRefresh()
        _ = draft.apply([suggestion("ceremony", status: "suggested", candidates: [chosen])], token: token)
        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 0, token: token) == true)

        draft.remove(key: "ceremony")
        #expect(draft.confirmedDates["ceremony"] == nil)
        #expect(draft.suggestions["ceremony"] != nil)

        // Selecting the item again does not restore its old confirmed date.
        #expect(draft.confirmedDates["ceremony"] == nil)
        #expect(draft.confirmSuggestion(key: "ceremony", candidateIndex: 0, token: token) == true)
        #expect(draft.confirmedDates["ceremony"] == chosen)
    }

    @Test("Unknown statuses and invalid candidate indices fail closed")
    func invalidSuggestionCannotBeConfirmed() {
        var draft = BlueprintScheduleDraft()
        let token = draft.beginRefresh()
        _ = draft.apply([
            suggestion("unknown", status: "future_status", candidates: [date("2026-06-20T16:00:00Z")]),
            suggestion("empty", status: "suggested", candidates: [])
        ], token: token)

        #expect(draft.confirmSuggestion(key: "unknown", candidateIndex: 0, token: token) == false)
        #expect(draft.confirmSuggestion(key: "empty", candidateIndex: 0, token: token) == false)
        #expect(draft.confirmedDates.isEmpty)
    }

    private func suggestion(_ key: String, status: String, candidates: [Date]) -> BlueprintScheduleSuggestion {
        BlueprintScheduleSuggestion(key: key, status: status, localDateTime: nil, candidates: candidates)
    }

    private func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let parsed = formatter.date(from: iso8601) else {
            fatalError("Invalid test date: \(iso8601)")
        }
        return parsed
    }
}
