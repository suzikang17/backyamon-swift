import UIKit

/// Lightweight wrapper around UIKit haptics. Pre-warms generators so the first
/// tap doesn't feel laggy.
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notify = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        notify.prepare()
        selection.prepare()
    }

    func tap() { selection.selectionChanged() }
    func light() { lightImpact.impactOccurred() }
    func medium() { mediumImpact.impactOccurred() }
    func heavy() { heavyImpact.impactOccurred() }
    func success() { notify.notificationOccurred(.success) }
    func warning() { notify.notificationOccurred(.warning) }
    func error() { notify.notificationOccurred(.error) }
}
