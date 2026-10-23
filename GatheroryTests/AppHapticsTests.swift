import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AppHapticsTests {
    @Test("Haptics are enabled by default")
    func testHapticsAreEnabledByDefault() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var emitted: [AppHaptic] = []
        let player = AppHapticPlayer(defaults: defaults, isForeground: { true }) { emitted.append($0) }

        player.play(.selection)

        #expect(emitted == [.selection])
    }

    @Test("A disabled preference suppresses haptics")
    func testDisabledPreferenceSuppressesHaptics() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppHaptics.preferenceKey)
        var emissionCount = 0
        let player = AppHapticPlayer(defaults: defaults, isForeground: { true }) { _ in emissionCount += 1 }

        player.play(.success)

        #expect(emissionCount == 0)
    }

    @Test("Haptics are suppressed while the app is not foregrounded")
    func testHapticsAreSuppressedWhileAppIsNotForegrounded() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var foreground = false
        var emitted: [AppHaptic] = []
        let player = AppHapticPlayer(defaults: defaults, isForeground: { foreground }) { emitted.append($0) }

        player.play(.impact)
        foreground = true
        player.play(.impact)

        #expect(emitted == [.impact])
    }

    @Test("Preference changes apply to an existing player")
    func testPreferenceChangesApplyToExistingPlayer() {
        let (defaults, suiteName) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var emitted: [AppHaptic] = []
        let player = AppHapticPlayer(defaults: defaults, isForeground: { true }) { emitted.append($0) }

        player.play(.selection)
        defaults.set(false, forKey: AppHaptics.preferenceKey)
        player.play(.warning)
        defaults.set(true, forKey: AppHaptics.preferenceKey)
        player.play(.error)

        #expect(emitted == [.selection, .error])
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "AppHapticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }
}
