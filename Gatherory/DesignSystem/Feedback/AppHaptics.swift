import SwiftUI
import UIKit

enum AppHaptic: Equatable, Sendable {
    case selection
    case impact
    case success
    case warning
    case error
}

@MainActor
final class AppHapticPlayer {
    static let shared = AppHapticPlayer()

    nonisolated static let preferenceKey = "app.haptics.enabled"

    private let defaults: UserDefaults
    private let isForeground: @MainActor () -> Bool
    private let emitter: @MainActor (AppHaptic) -> Void

    init(
        defaults: UserDefaults = .standard,
        isForeground: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
        emitter: @escaping @MainActor (AppHaptic) -> Void = AppHapticPlayer.emitSystemHaptic
    ) {
        self.defaults = defaults
        self.isForeground = isForeground
        self.emitter = emitter
    }

    func play(_ feedback: AppHaptic) {
        guard defaults.object(forKey: Self.preferenceKey) as? Bool ?? true,
              isForeground() else { return }
        emitter(feedback)
    }

    private static func emitSystemHaptic(_ feedback: AppHaptic) {
        switch feedback {
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .impact:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

enum AppHaptics {
    nonisolated static let preferenceKey = AppHapticPlayer.preferenceKey

    @MainActor
    static func play(_ feedback: AppHaptic) {
        AppHapticPlayer.shared.play(feedback)
    }
}

private struct AppHapticChangeModifier<Trigger: Equatable>: ViewModifier {
    let feedback: AppHaptic
    let trigger: Trigger
    let condition: (Trigger, Trigger) -> Bool

    func body(content: Content) -> some View {
        content.onChange(of: trigger) { oldValue, newValue in
            guard condition(oldValue, newValue) else { return }
            AppHaptics.play(feedback)
        }
    }
}

extension View {
    func appHaptic<Trigger: Equatable>(
        _ feedback: AppHaptic,
        trigger: Trigger,
        condition: @escaping (Trigger, Trigger) -> Bool = { _, _ in true }
    ) -> some View {
        modifier(AppHapticChangeModifier(feedback: feedback, trigger: trigger, condition: condition))
    }
}
