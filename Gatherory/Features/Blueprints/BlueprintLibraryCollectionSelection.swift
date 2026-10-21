import Foundation

enum BlueprintLibraryCollection: String, CaseIterable, Identifiable, Sendable {
    case installedTemplates
    case inProgress

    var id: Self { self }

    var other: Self { self == .installedTemplates ? .inProgress : .installedTemplates }
}

enum BlueprintLibraryCollectionSelection {
    static func resolve(
        preferred: BlueprintLibraryCollection?,
        hasInstalledTemplates: Bool,
        hasInProgressContent: Bool
    ) -> BlueprintLibraryCollection {
        if let preferred, hasContent(preferred, hasInstalledTemplates: hasInstalledTemplates, hasInProgressContent: hasInProgressContent) {
            return preferred
        }
        if hasInstalledTemplates { return .installedTemplates }
        if hasInProgressContent { return .inProgress }
        return preferred ?? .installedTemplates
    }

    private static func hasContent(
        _ collection: BlueprintLibraryCollection,
        hasInstalledTemplates: Bool,
        hasInProgressContent: Bool
    ) -> Bool {
        switch collection {
        case .installedTemplates: hasInstalledTemplates
        case .inProgress: hasInProgressContent
        }
    }
}

struct BlueprintLibraryCollectionPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func collection(ownerID: String) -> BlueprintLibraryCollection? {
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rawValue = defaults.string(forKey: key(ownerID: ownerID))
        else { return nil }
        return BlueprintLibraryCollection(rawValue: rawValue)
    }

    func save(_ collection: BlueprintLibraryCollection, ownerID: String) {
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        defaults.set(collection.rawValue, forKey: key(ownerID: ownerID))
    }

    func removeAll(accountID: String) throws {
        defaults.removeObject(forKey: key(ownerID: accountID))
    }

    private func key(ownerID: String) -> String {
        let encodedOwner = Data(ownerID.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "blueprintLibrary.lastCollection.\(encodedOwner)"
    }
}
