import Testing
@testable import Gatherory

struct AnalyticsConfigurationTests {
    @Test("Telemetry defaults on for normal Debug and Release app sessions")
    func enabledByDefault() {
        for value: String? in [nil, "YES", "true", "1", " yes "] {
            #expect(AppRuntimeConfiguration.analyticsEnabled(configurationValue: value, usesEphemeralStore: false, isRunningTests: false))
        }
    }

    @Test("Build configurations can explicitly disable telemetry")
    func configuredOff() {
        for value in ["NO", "false", "0", "invalid"] {
            #expect(!AppRuntimeConfiguration.analyticsEnabled(configurationValue: value, usesEphemeralStore: false, isRunningTests: false))
        }
    }

    @Test("Unit tests and ephemeral UI fixtures never send telemetry")
    func isolatedTests() {
        #expect(!AppRuntimeConfiguration.analyticsEnabled(configurationValue: "YES", usesEphemeralStore: false, isRunningTests: true))
        #expect(!AppRuntimeConfiguration.analyticsEnabled(configurationValue: "YES", usesEphemeralStore: true, isRunningTests: false))
    }
}
