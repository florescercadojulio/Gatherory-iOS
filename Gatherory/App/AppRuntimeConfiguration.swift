import Foundation

enum AppRuntimeConfiguration {
    enum Environment: String {
        case development
        case staging
        case production
    }

    static let environment = Environment(
        rawValue: infoString(forKey: "APP_ENVIRONMENT")
    ) ?? .production

    static var alwaysShowsOnboarding: Bool {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-UseProductionOnboarding") {
            return false
        }

        if arguments.contains("-AlwaysShowOnboarding") {
            return true
        }

        return infoBoolean(forKey: "FORCE_ONBOARDING") ?? false
    }

    static var seedsDevelopmentData: Bool {
        let arguments = ProcessInfo.processInfo.arguments

        guard environment == .development else { return false }

        if arguments.contains("-DisableSeedData") {
            return false
        }

        if arguments.contains("-SeedDevelopmentData") {
            return true
        }

        return infoBoolean(forKey: "SEED_DEVELOPMENT_DATA") ?? false
    }

    static var skipsAuthentication: Bool {
        let arguments = ProcessInfo.processInfo.arguments

        guard environment == .development else { return false }

        if arguments.contains("-RequireAuthentication") {
            return false
        }

        if arguments.contains("-SkipAuthentication") {
            return true
        }

        return infoBoolean(forKey: "SKIP_AUTH_LOGIN") ?? false
    }

    private static func infoString(forKey key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    private static func infoBoolean(forKey key: String) -> Bool? {
        switch Bundle.main.object(forInfoDictionaryKey: key) {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "true", "1":
                return true
            case "no", "false", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
