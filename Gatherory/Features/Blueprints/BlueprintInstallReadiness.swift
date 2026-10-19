import Foundation

/// Display only: never reinterpret a confirmed instant using a different zone.
nonisolated enum BlueprintSetupDateLabel {
    static func text(_ date: Date, timeZone: TimeZone, locale: Locale = .autoupdatingCurrent,
                     includesOffset: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let text = formatter.string(from: date)
        guard includesOffset else { return text }
        formatter.dateFormat = "ZZZZ"
        return "\(text) · \(formatter.string(from: date))"
    }
}

/// Local confirmation policy only. Suggestions never count as confirmed dates.
nonisolated enum BlueprintInstallReadiness {
    static func missingChildren(selected: Set<String>, confirmed: [String: Date]) -> Set<String> {
        selected.subtracting(confirmed.filter { $0.value.timeIntervalSince1970.isFinite }.map(\.key))
    }

    static func isReady(mainDateConfirmed: Bool?, selected: Set<String>, confirmed: [String: Date]) -> Bool {
        mainDateConfirmed == true && missingChildren(selected: selected, confirmed: confirmed).isEmpty
    }
}
