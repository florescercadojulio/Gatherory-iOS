import Foundation

enum AppRuntimeConfiguration {
    enum Environment: String {
        case development
        case staging
        case production
    }

    static var simulatesProductionFlow: Bool {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-SimulateProductionFlow") {
            return true
        }

        if arguments.contains("-DisableProductionFlowSimulation") {
            return false
        }

        return infoBoolean(forKey: "SIMULATE_PRODUCTION_FLOW") ?? false
#else
        return false
#endif
    }

    static var environment: Environment {
        if simulatesProductionFlow {
            return .production
        }

        return Environment(
            rawValue: infoString(forKey: "APP_ENVIRONMENT")
        ) ?? .production
    }

    static var alwaysShowsOnboarding: Bool {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-AlwaysShowOnboarding") {
            return true
        }

        if arguments.contains("-UseProductionOnboarding") {
            return false
        }

        if simulatesProductionFlow {
            return false
        }

        return infoBoolean(forKey: "FORCE_ONBOARDING") ?? false
    }

    /// Production-like flows resolve first-run state from the authenticated
    /// account. Development fixtures can continue to use the local UI switch.
    static var usesRemoteAccountState: Bool {
        environment != .development
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

    /// Keeps automated UI fixtures isolated from developer and simulator data.
    static var usesEphemeralDataStore: Bool {
        ProcessInfo.processInfo.arguments.contains("-UseEphemeralDataStore")
    }

    static var postHogProjectToken: String? {
        configuredValue(forKey: "POSTHOG_PROJECT_TOKEN")
    }

    static var postHogEnabled: Bool {
        analyticsEnabled(
            configurationValue: configuredValue(forKey: "POSTHOG_ENABLED"),
            usesEphemeralStore: usesEphemeralDataStore,
            isRunningTests: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil
                || NSClassFromString("XCTest.XCTestCase") != nil
        )
    }

    nonisolated static func analyticsEnabled(configurationValue: String?, usesEphemeralStore: Bool, isRunningTests: Bool) -> Bool {
        guard !usesEphemeralStore, !isRunningTests else { return false }
        guard let value = configurationValue else { return true }
        return ["yes", "true", "1"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static var postHogHost: String? {
        configuredValue(forKey: "POSTHOG_HOST")
    }

    static var authenticationBaseURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments

        if let flagIndex = arguments.firstIndex(of: "-AuthenticationBaseURL"),
           arguments.indices.contains(flagIndex + 1),
           let overrideURL = normalizedURL(from: arguments[flagIndex + 1]) {
            return overrideURL
        }

        return normalizedURL(from: infoString(forKey: "AUTH_BASE_URL"))
    }

    private static func configuredValue(forKey key: String) -> String? {
        let value = infoString(forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !value.isEmpty,
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }

        return url
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
