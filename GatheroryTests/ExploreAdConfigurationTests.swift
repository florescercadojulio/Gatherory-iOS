import Testing
@testable import Gatherory

struct ExploreAdConfigurationTests {
    @Test("Release stays off until its explicit enable flag is turned on")
    func releaseDisabledByDefault() {
        #expect(!ExploreAdConfiguration.allowsAds(
            isDebugBuild: false,
            enabled: false,
            testMode: false,
            applicationID: ExploreAdConfiguration.productionApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.productionNativeAdUnitID
        ))
    }

    @Test("Release accepts only the configured production app and native unit IDs")
    func releaseProductionConfiguration() {
        #expect(ExploreAdConfiguration.allowsAds(
            isDebugBuild: false,
            enabled: true,
            testMode: false,
            applicationID: ExploreAdConfiguration.productionApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.productionNativeAdUnitID
        ))

        let rejectedConfigurations: [(String?, String?, Bool)] = [
            (nil, ExploreAdConfiguration.productionNativeAdUnitID, false),
            (ExploreAdConfiguration.productionApplicationID, nil, false),
            ("malformed", ExploreAdConfiguration.productionNativeAdUnitID, false),
            (ExploreAdConfiguration.productionApplicationID, "malformed", false),
            (ExploreAdConfiguration.googleTestApplicationID, ExploreAdConfiguration.googleTestNativeAdUnitID, false),
            (ExploreAdConfiguration.productionApplicationID, ExploreAdConfiguration.productionNativeAdUnitID, true)
        ]

        for (applicationID, nativeAdUnitID, testMode) in rejectedConfigurations {
            #expect(!ExploreAdConfiguration.allowsAds(
                isDebugBuild: false,
                enabled: true,
                testMode: testMode,
                applicationID: applicationID,
                nativeAdUnitID: nativeAdUnitID
            ))
        }
    }

    @Test("Debug uses sample inventory and requires Gatherory consent")
    func debugUsesSampleInventoryAndAppConsent() {
        #expect(ExploreAdConfiguration.allowsAds(
            isDebugBuild: true,
            enabled: true,
            testMode: true,
            applicationID: ExploreAdConfiguration.productionApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.googleTestNativeAdUnitID
        ))
        #expect(ExploreAdConfiguration.allowsAds(
            isDebugBuild: true,
            enabled: true,
            testMode: true,
            applicationID: ExploreAdConfiguration.googleTestApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.googleTestNativeAdUnitID
        ))

        for (applicationID, nativeAdUnitID, testMode) in [
            (ExploreAdConfiguration.productionApplicationID, ExploreAdConfiguration.productionNativeAdUnitID, true),
            (ExploreAdConfiguration.googleTestApplicationID, ExploreAdConfiguration.googleTestNativeAdUnitID, false),
            (ExploreAdConfiguration.googleTestApplicationID, "wrong-unit", true)
        ] {
            #expect(!ExploreAdConfiguration.allowsAds(
                isDebugBuild: true,
                enabled: true,
                testMode: testMode,
                applicationID: applicationID,
                nativeAdUnitID: nativeAdUnitID
            ))
        }

        #expect(!ExploreAdConfiguration.maySkipConsent(
            isDebugBuild: true,
            testMode: true,
            applicationID: ExploreAdConfiguration.productionApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.googleTestNativeAdUnitID
        ))
        #expect(ExploreAdConfiguration.maySkipConsent(
            isDebugBuild: true,
            testMode: true,
            applicationID: ExploreAdConfiguration.googleTestApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.googleTestNativeAdUnitID
        ))
        #expect(!ExploreAdConfiguration.maySkipConsent(
            isDebugBuild: false,
            testMode: true,
            applicationID: ExploreAdConfiguration.googleTestApplicationID,
            nativeAdUnitID: ExploreAdConfiguration.googleTestNativeAdUnitID
        ))
    }
}
