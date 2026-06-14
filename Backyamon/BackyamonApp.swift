import SwiftUI
import UIKit

@main
struct BackyamonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.gold)
        }
    }
}

// MARK: - Orientation control

/// App delegate that reports the currently-allowed interface orientations.
/// The app supports portrait + landscape in Info.plist; this lets us restrict
/// it per-screen at runtime — menus stay portrait, the game forces landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Mutated by `AppOrientation.lock(_:)`. Defaults to portrait so the app
    /// launches into the menus in portrait.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

/// Runtime orientation control. Call `lock(.landscape)` when entering the game
/// and `lock(.portrait)` when leaving it. The active window scene is asked to
/// rotate immediately so the user doesn't have to physically turn the device.
enum AppOrientation {
    static func lock(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask

        guard let scene = (UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene)
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
        else { return }

        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }
}
