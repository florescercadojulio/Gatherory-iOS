import Foundation

/// Shared spreadsheet-safe CSV encoding for explicit event exports.
nonisolated enum EventCSVEncoder {
    static func encode(rows: [[String]]) -> String {
        rows.map { $0.map(escapedCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// A UTF-8 BOM preserves accented names/headers in spreadsheet importers.
    static func data(for csv: String) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
    }

    static func localizationBundle(for locale: Locale) -> Bundle {
        // String's locale controls interpolation/formatting. Select the actual
        // language resources as well so explicit export locales are honored.
        guard let language = Bundle.preferredLocalizations(
            from: Bundle.main.localizations, forPreferences: [locale.identifier]
        ).first,
              let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    private static func escapedCell(_ value: String) -> String {
        // CSV quoting does not stop spreadsheet formulas. Neutralize the first
        // meaningful character, including formulas hidden behind tabs/controls.
        let ignored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        let first = value.unicodeScalars.first { !ignored.contains($0) }
        let safeValue: String
        if let first, ["=", "+", "-", "@"].contains(String(first)) {
            safeValue = "'" + value
        } else {
            safeValue = value
        }
        return "\"" + safeValue.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
