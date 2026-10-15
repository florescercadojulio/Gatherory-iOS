import Foundation

/// In-memory date choices made while setting up a blueprint.
///
/// Confirmed dates are absolute instants. Refreshing suggestions therefore
/// never changes a date the person has already chosen, regardless of timezone.
@MainActor
struct BlueprintScheduleDraft {
    private(set) var confirmedDates: [String: Date] = [:]
    private(set) var suggestions: [String: BlueprintScheduleSuggestion] = [:]
    private(set) var refreshToken = UUID()
    private(set) var isRefreshing = false
    private(set) var refreshFailed = false

    /// Seeds the manual editor without confirming or changing any saved choice.
    /// Ambiguous clock-change times still require choosing an occurrence; never
    /// silently select the first candidate. Unavailable/stale suggestions fall
    /// back to the main event, while a person's confirmed edit always wins.
    func initialManualDate(for key: String, fallback: Date) -> Date {
        if let confirmed = confirmedDates[key] { return confirmed }
        guard !isRefreshing, !refreshFailed,
              let suggestion = suggestions[key],
              suggestion.status == "suggested",
              suggestion.candidates.count == 1,
              let candidate = suggestion.candidates.first,
              candidate.timeIntervalSinceReferenceDate.isFinite
        else { return fallback }
        return candidate
    }

    /// Starts a new suggestion request and immediately expires old suggestions.
    /// Existing confirmed dates remain untouched.
    mutating func beginRefresh() -> UUID {
        let token = UUID()
        refreshToken = token
        suggestions = [:]
        isRefreshing = true
        refreshFailed = false
        return token
    }

    /// Publishes suggestions only when they belong to the latest refresh.
    /// Suggestion data is never treated as a date confirmation.
    @discardableResult
    mutating func apply(_ suggestions: [BlueprintScheduleSuggestion], token: UUID) -> Bool {
        guard token == refreshToken else { return false }

        self.suggestions = suggestions.reduce(into: [:]) { result, suggestion in
            result[suggestion.key] = suggestion
        }
        isRefreshing = false
        refreshFailed = false
        return true
    }

    /// Records a failure for the current request and expires its token so a late
    /// completion cannot publish results after the failure.
    mutating func failRefresh(token: UUID) {
        guard token == refreshToken else { return }

        suggestions = [:]
        refreshToken = UUID()
        isRefreshing = false
        refreshFailed = true
    }

    /// Stores a date explicitly chosen or edited by the person.
    mutating func confirm(key: String, date: Date) {
        confirmedDates[key] = date
    }

    /// Confirms a candidate only from the latest refresh and only for a known,
    /// confirmable status with an in-range, finite candidate date.
    @discardableResult
    mutating func confirmSuggestion(key: String, candidateIndex: Int, token: UUID) -> Bool {
        guard token == refreshToken,
              let suggestion = suggestions[key],
              suggestion.status == "suggested" || suggestion.status == "ambiguous",
              suggestion.candidates.indices.contains(candidateIndex)
        else { return false }

        let date = suggestion.candidates[candidateIndex]
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }

        confirmedDates[key] = date
        return true
    }

    /// Removes a deselected item's confirmation.
    mutating func remove(key: String) {
        confirmedDates.removeValue(forKey: key)
    }
}
