import GoogleMobileAds
import Observation
import SwiftUI
import UIKit
import UserMessagingPlatform

/// Build and AdMob IDs must agree before an ad SDK request can be made.
/// Live native inventory is accepted only by Release with explicit enablement.
/// Debug uses a sample ad unit with Gatherory's or Google's sample app ID.
enum ExploreAdConfiguration {
    static let googleTestApplicationID = "ca-app-pub-3940256099942544~1458002511"
    static let googleTestNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    static let productionApplicationID = "ca-app-pub-4218523458506277~8970323130"
    static let productionNativeAdUnitID = "ca-app-pub-4218523458506277/9237741437"

    static func allowsAds(
        isDebugBuild: Bool,
        enabled: Bool,
        testMode: Bool,
        applicationID: String?,
        nativeAdUnitID: String?
    ) -> Bool {
        guard enabled, let applicationID, let nativeAdUnitID else { return false }
        if isDebugBuild {
            return testMode && nativeAdUnitID == googleTestNativeAdUnitID
                && (applicationID == productionApplicationID || applicationID == googleTestApplicationID)
        }
        return !testMode
            && applicationID == productionApplicationID
            && nativeAdUnitID == productionNativeAdUnitID
    }

    static func maySkipConsent(
        isDebugBuild: Bool,
        testMode: Bool,
        applicationID: String?,
        nativeAdUnitID: String?
    ) -> Bool {
        isDebugBuild
            && testMode
            && applicationID == googleTestApplicationID
            && nativeAdUnitID == googleTestNativeAdUnitID
    }
}

/// Consent-gated, account-scoped inventory for Explore. The scope identifier
/// is intentionally kept local and is never added to an ad request.
@Observable
@MainActor
final class ExploreAdSession: NSObject, NativeAdLoaderDelegate {
    static let nativeTestApplicationID = ExploreAdConfiguration.googleTestApplicationID
    static let nativeTestAdUnitID = ExploreAdConfiguration.googleTestNativeAdUnitID
    private static let maxCachedAds = 3
    private static let maxPendingSlots = 12
    private static let adLifetime: TimeInterval = 55 * 60

    private(set) var isPrivacyOptionsRequired = false
    private(set) var loadedSlotIDs: Set<String> = []
    private(set) var loadingSlotIDs: Set<String> = []
    /// Changes whenever inventory and slot ownership are invalidated. Slot
    /// loaders observe this so mounted feed items can reclaim after reset.
    private(set) var lifecycleGeneration = 0
    /// Full privacy/account/inventory invalidation, independent of preview pause.
    private(set) var resetGeneration = 0
    private(set) var isPrepared = false
    private(set) var isSuspended = false

    /// Local account or guest scope used by the owning Explore view. It is
    /// never copied into targeting, request extras, logs, or analytics.
    let scopeID: String
    @ObservationIgnored private var adsBySlot: [String: CachedNativeAd] = [:]
    @ObservationIgnored private var ownersBySlot: [String: Set<UUID>] = [:]
    @ObservationIgnored private var loadersBySlot: [String: AdLoader] = [:]
    @ObservationIgnored private var slotByLoader: [ObjectIdentifier: String] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pendingSlotIDs: Set<String> = []
    @ObservationIgnored private var pendingSlotOrder: [String] = []
    @ObservationIgnored private var cacheOrder: [String] = []
    @ObservationIgnored private var retryCountBySlot: [String: Int] = [:]
    @ObservationIgnored private var retryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var expiryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTaskGeneration: Int?
    @ObservationIgnored private var isSDKReady = false

    private struct CachedNativeAd {
        let ad: NativeAd
        let receivedAt: Date
    }

    init(scopeID: String) {
        self.scopeID = scopeID
        super.init()
    }

    /// Call when Explore becomes active. UMP is refreshed before SDK startup
    /// and before any native ad request is allowed.
    func prepare(from viewController: UIViewController? = nil) async {
        guard !isSuspended,
              Self.adsAreEnabled,
              !Self.isRunningInSwiftUIPreview,
              UIApplication.shared.applicationState == .active else { return }

        while let existingTask = preparationTask,
              let existingGeneration = preparationTaskGeneration {
            await existingTask.value
            if Task.isCancelled || isSuspended { return }
            if preparationTaskGeneration == existingGeneration {
                preparationTask = nil
                preparationTaskGeneration = nil
            }
            if existingGeneration == generation { return }
        }
        guard !isPrepared else { return }

        let requestGeneration = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPreparation(from: viewController, generation: requestGeneration)
        }
        preparationTask = task
        preparationTaskGeneration = requestGeneration
        await task.value
        if preparationTaskGeneration == requestGeneration {
            preparationTask = nil
            preparationTaskGeneration = nil
        }
    }

    private func performPreparation(from viewController: UIViewController?, generation requestGeneration: Int) async {
        let consentParameters = RequestParameters()
        await requestConsentInfoUpdate(with: consentParameters)
        guard generation == requestGeneration, !isSuspended else { return }

        do {
            try await ConsentForm.loadAndPresentIfRequired(from: viewController)
        } catch {
            // If UMP has a previously valid choice, canRequestAds may still be
            // true after a transient form error. The gate below remains final.
        }
        guard generation == requestGeneration, !isSuspended else { return }

        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds || Self.mayUseGoogleTestInventory else { return }

        configurePrivacyDefaults()
        await Self.startSDKIfNeeded()
        guard generation == requestGeneration, !isSuspended else { return }

        isSDKReady = true
        isPrepared = true
        pumpPendingLoads()
    }

    func load(slotID: String) {
        guard !slotID.isEmpty,
              !isSuspended,
              Self.adsAreEnabled,
              !Self.isRunningInSwiftUIPreview,
              UIApplication.shared.applicationState == .active else { return }
        purgeExpiredAds()
        guard adsBySlot[slotID] == nil, !loadingSlotIDs.contains(slotID) else { return }

        if !isPrepared || !isSDKReady {
            enqueue(slotID: slotID)
            return
        }

        enqueue(slotID: slotID)
        pumpPendingLoads()
    }

    func ad(forSlotID slotID: String) -> NativeAd? {
        // This tracked read invalidates SwiftUI when the ignored NativeAd
        // dictionary gains or loses the corresponding object. Keep this getter
        // pure: view evaluation must never mutate session state.
        guard loadedSlotIDs.contains(slotID),
              let cached = adsBySlot[slotID],
              cached.receivedAt.timeIntervalSinceNow > -Self.adLifetime else { return nil }
        return cached.ad
    }

    func isLoading(slotID: String) -> Bool {
        loadingSlotIDs.contains(slotID)
    }

    /// Slot owners keep a cached ad eligible while either its zero-size feed
    /// loader or its registered NativeAdView is mounted.
    func claim(slotID: String, ownerID: UUID) -> Bool {
        guard !isSuspended, Self.adsAreEnabled, !Self.isRunningInSwiftUIPreview else { return false }
        ownersBySlot[slotID, default: []].insert(ownerID)
        return true
    }

    func release(slotID: String, ownerID: UUID) {
        guard var owners = ownersBySlot[slotID], owners.remove(ownerID) != nil else { return }
        if owners.isEmpty {
            ownersBySlot.removeValue(forKey: slotID)
        } else {
            ownersBySlot[slotID] = owners
        }
        guard owners.isEmpty else { return }
        removeFromPendingQueue(slotID: slotID)
        retryTasks[slotID]?.cancel()
        retryTasks.removeValue(forKey: slotID)
        guard !isSuspended else { return }
        pumpPendingLoads()
    }

    /// Pause Explore while a preview covers it. Keep unexpired cached ads so
    /// returning to the same account can reuse its inventory without a feed jump.
    /// In-flight work is invalidated and mounted slot hooks reclaim ownership
    /// when the preview returns.
    func suspendForCoveredPreview() {
        guard !isSuspended else { return }
        isSuspended = true
        generation &+= 1

        preparationTask?.cancel()
        preparationTask = nil
        preparationTaskGeneration = nil
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
        retryCountBySlot.removeAll()
        pendingSlotIDs.removeAll()
        pendingSlotOrder.removeAll()

        loadersBySlot.values.forEach { $0.delegate = nil }
        loadersBySlot.removeAll()
        slotByLoader.removeAll()
        generationByLoader.removeAll()
        loadingSlotIDs.removeAll()
        for (slotID, cached) in adsBySlot {
            scheduleExpiry(for: slotID, receivedAt: cached.receivedAt, generation: generation)
        }
    }

    /// Re-enable the retained session after a covered preview returns. Bumping
    /// lifecycleGeneration makes mounted slot hooks claim their owners again.
    func resumeFromCoveredPreview() {
        guard isSuspended else { return }
        isSuspended = false
        lifecycleGeneration &+= 1
        purgeExpiredAds()
        for (slotID, cached) in adsBySlot {
            scheduleExpiry(for: slotID, receivedAt: cached.receivedAt, generation: generation)
        }
    }

    /// Drop loaded and in-flight inventory when Explore is dismissed, the
    /// account changes, or the app backgrounds. SDK callbacks are invalidated
    /// by the generation increment and cannot repopulate this session.
    func reset() {
        resetGeneration &+= 1
        generation &+= 1
        lifecycleGeneration &+= 1
        isSuspended = false
        preparationTask?.cancel()
        preparationTask = nil
        preparationTaskGeneration = nil
        adsBySlot.removeAll()
        loadedSlotIDs.removeAll()
        loadingSlotIDs.removeAll()
        pendingSlotIDs.removeAll()
        pendingSlotOrder.removeAll()
        cacheOrder.removeAll()
        ownersBySlot.removeAll()
        retryCountBySlot.removeAll()
        retryTasks.values.forEach { $0.cancel() }
        retryTasks.removeAll()
        expiryTasks.values.forEach { $0.cancel() }
        expiryTasks.removeAll()
        loadersBySlot.removeAll()
        slotByLoader.removeAll()
        generationByLoader.removeAll()
        isPrepared = false
        isSDKReady = false
        isPrivacyOptionsRequired = false
    }

    func presentPrivacyOptions(from viewController: UIViewController? = nil) async {
        guard isPrivacyOptionsRequired, !isSuspended else { return }
        let requestGeneration = generation
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: viewController)
        } catch {
            return
        }
        guard !isSuspended, generation == requestGeneration else { return }
        let visibleOwners = ownersBySlot
        let privacyOptionsRemainRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        reset()
        ownersBySlot = visibleOwners
        isPrivacyOptionsRequired = privacyOptionsRemainRequired
        for slotID in visibleOwners.keys {
            enqueue(slotID: slotID)
        }
        await prepare(from: viewController)
    }

    private func requestConsentInfoUpdate(with parameters: RequestParameters) async {
        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { _ in
                continuation.resume()
            }
        }
    }

    private func configurePrivacyDefaults() {
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
    }

    private func startLoad(slotID: String, generation requestGeneration: Int) {
        let adLoader = AdLoader(
            adUnitID: Self.nativeAdUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        adLoader.delegate = self
        loadersBySlot[slotID] = adLoader
        slotByLoader[ObjectIdentifier(adLoader)] = slotID
        loadingSlotIDs.insert(slotID)

        let request = Request()
        let nonPersonalizedAds = Extras()
        nonPersonalizedAds.additionalParameters = ["npa": "1"]
        request.register(nonPersonalizedAds)
        // Keep the value captured with the loader so stale delegate callbacks
        // are discarded if reset or preview suspension invalidates the generation.
        generationByLoader[ObjectIdentifier(adLoader)] = requestGeneration
        adLoader.load(request)
    }

    @ObservationIgnored private var generationByLoader: [ObjectIdentifier: Int] = [:]

    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        let loaderID = ObjectIdentifier(adLoader)
        guard let slotID = slotByLoader.removeValue(forKey: loaderID),
              generationByLoader.removeValue(forKey: loaderID) == generation,
              !isSuspended else { return }

        loadersBySlot.removeValue(forKey: slotID)
        loadingSlotIDs.remove(slotID)
        retryTasks[slotID]?.cancel()
        retryTasks.removeValue(forKey: slotID)
        retryCountBySlot.removeValue(forKey: slotID)
        guard ownersBySlot[slotID]?.isEmpty == false else {
            pumpPendingLoads()
            return
        }
        let cached = CachedNativeAd(ad: nativeAd, receivedAt: Date())
        adsBySlot[slotID] = cached
        cacheOrder.append(slotID)
        loadedSlotIDs.insert(slotID)
        scheduleExpiry(for: slotID, receivedAt: cached.receivedAt, generation: generation)
        pumpPendingLoads()
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        let loaderID = ObjectIdentifier(adLoader)
        guard let slotID = slotByLoader.removeValue(forKey: loaderID) else { return }
        let callbackGeneration = generationByLoader.removeValue(forKey: loaderID)
        loadersBySlot.removeValue(forKey: slotID)
        loadingSlotIDs.remove(slotID)
        if callbackGeneration == generation,
           !isSuspended,
           ownersBySlot[slotID]?.isEmpty == false,
           retryCountBySlot[slotID, default: 0] < 1 {
            retryCountBySlot[slotID, default: 0] += 1
            let retryGeneration = generation
            retryTasks[slotID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self,
                      !self.isSuspended,
                      self.generation == retryGeneration,
                      self.ownersBySlot[slotID]?.isEmpty == false,
                      self.adsBySlot[slotID] == nil else { return }
                self.retryTasks.removeValue(forKey: slotID)
                self.enqueue(slotID: slotID)
                self.pumpPendingLoads()
            }
        }
        pumpPendingLoads()
    }

    private func purgeExpiredAds() {
        let expiry = Date().addingTimeInterval(-Self.adLifetime)
        let expiredSlotIDs = adsBySlot.compactMap { slotID, cached in
            cached.receivedAt < expiry ? slotID : nil
        }
        for slotID in expiredSlotIDs {
            removeCachedAd(forSlotID: slotID)
            if !isSuspended, ownersBySlot[slotID]?.isEmpty == false { enqueue(slotID: slotID) }
        }
        pumpPendingLoads()
    }

    private func enqueue(slotID: String) {
        guard !isSuspended,
              !slotID.isEmpty,
              !pendingSlotIDs.contains(slotID),
              pendingSlotOrder.count < Self.maxPendingSlots else { return }
        pendingSlotIDs.insert(slotID)
        pendingSlotOrder.append(slotID)
    }

    private func removeFromPendingQueue(slotID: String) {
        pendingSlotIDs.remove(slotID)
        pendingSlotOrder.removeAll { $0 == slotID }
    }

    private func pumpPendingLoads() {
        guard !isSuspended,
              isPrepared,
              isSDKReady,
              UIApplication.shared.applicationState == .active else { return }

        while !pendingSlotOrder.isEmpty {
            let slotID = pendingSlotOrder.removeFirst()
            pendingSlotIDs.remove(slotID)
            guard ownersBySlot[slotID]?.isEmpty == false,
                  adsBySlot[slotID] == nil,
                  !loadingSlotIDs.contains(slotID) else { continue }
            guard makeRoomForNextAd() else {
                enqueue(slotID: slotID)
                break
            }
            startLoad(slotID: slotID, generation: generation)
        }
    }

    private func makeRoomForNextAd() -> Bool {
        while adsBySlot.count + loadingSlotIDs.count >= Self.maxCachedAds {
            guard let oldestUnownedSlot = cacheOrder.first(where: {
                ownersBySlot[$0]?.isEmpty != false && !loadingSlotIDs.contains($0)
            }) else { return false }
            removeCachedAd(forSlotID: oldestUnownedSlot)
        }
        return true
    }

    private func removeCachedAd(forSlotID slotID: String) {
        guard adsBySlot.removeValue(forKey: slotID) != nil else { return }
        loadedSlotIDs.remove(slotID)
        cacheOrder.removeAll { $0 == slotID }
        expiryTasks[slotID]?.cancel()
        expiryTasks.removeValue(forKey: slotID)
    }

    private func scheduleExpiry(for slotID: String, receivedAt: Date, generation expiryGeneration: Int) {
        expiryTasks[slotID]?.cancel()
        expiryTasks[slotID] = Task { @MainActor [weak self] in
            let remainingLifetime = max(0, Self.adLifetime - Date().timeIntervalSince(receivedAt))
            try? await Task.sleep(for: .seconds(remainingLifetime))
            guard !Task.isCancelled,
                  let self,
                  self.generation == expiryGeneration,
                  self.adsBySlot[slotID]?.receivedAt == receivedAt else { return }
            self.removeCachedAd(forSlotID: slotID)
            if !self.isSuspended, self.ownersBySlot[slotID]?.isEmpty == false { self.enqueue(slotID: slotID) }
            self.pumpPendingLoads()
        }
    }

    private static var adsAreEnabled: Bool {
#if DEBUG
        let isDebugBuild = true
#else
        let isDebugBuild = false
#endif
        return ExploreAdConfiguration.allowsAds(
            isDebugBuild: isDebugBuild,
            enabled: infoFlag("EXPLORE_ADS_ENABLED"),
            testMode: isTestMode,
            applicationID: Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
            nativeAdUnitID: Bundle.main.object(forInfoDictionaryKey: "ADMOB_NATIVE_AD_UNIT_ID") as? String
        )
    }

    private static var isTestMode: Bool {
        infoFlag("EXPLORE_ADS_TEST_MODE")
    }

    private static func infoFlag(_ key: String) -> Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            return ["YES", "TRUE", "1"].contains(value.uppercased())
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private static var nativeAdUnitID: String {
        let configuredID = Bundle.main.object(forInfoDictionaryKey: "ADMOB_NATIVE_AD_UNIT_ID") as? String
        guard isTestMode else { return configuredID ?? "" }
#if DEBUG
        // Never let a development setting accidentally target live inventory.
        return configuredID == nativeTestAdUnitID ? nativeTestAdUnitID : ""
#else
        return ""
#endif
    }

    private static var mayUseGoogleTestInventory: Bool {
#if DEBUG
        ExploreAdConfiguration.maySkipConsent(
            isDebugBuild: true,
            testMode: isTestMode,
            applicationID: Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
            nativeAdUnitID: Bundle.main.object(forInfoDictionaryKey: "ADMOB_NATIVE_AD_UNIT_ID") as? String
        )
#else
        false
#endif
    }

    private static var isRunningInSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static func startSDKIfNeeded() async {
        guard !sdkStarted else { return }
        if let sdkStartTask {
            await sdkStartTask.value
            return
        }

        let task = Task { @MainActor in
            await withCheckedContinuation { continuation in
                MobileAds.shared.start { _ in
                    continuation.resume()
                }
            }
        }
        sdkStartTask = task
        await task.value
        sdkStarted = true
        sdkStartTask = nil
    }

    private static var sdkStarted = false
    private static var sdkStartTask: Task<Void, Never>?
}

struct ExploreAdvertisingPrivacyButton: View {
    @Bindable var session: ExploreAdSession

    var body: some View {
        if session.isPrivacyOptionsRequired {
            Button(String(localized: "explore.ads.privacyChoices", defaultValue: "Privacy choices")) {
                Task { await session.presentPrivacyOptions() }
            }
            .accessibilityHint(String(localized: "explore.ads.privacyHint", defaultValue: "Review or change your advertising privacy choices"))
        }
    }
}
