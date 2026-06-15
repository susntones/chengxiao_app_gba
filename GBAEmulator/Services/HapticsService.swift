import UIKit

/// Haptic feedback service
final class HapticsService {
    static let shared = HapticsService()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        // Pre-warm generators
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
    }

    @available(iOS 17.0, *)
    func buttonPress() {
        let strength = SettingsManager.shared.hapticStrength
        switch strength {
        case .off:
            break
        case .light:
            lightGenerator.impactOccurred()
        case .medium:
            mediumGenerator.impactOccurred()
        case .heavy:
            heavyGenerator.impactOccurred()
        }
    }

    func saveState() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}
