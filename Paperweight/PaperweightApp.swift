import SwiftUI
import UIKit

@main
struct PaperweightApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

/// Shared channel for Home-screen quick actions. The scene delegate writes the
/// selected shortcut type here; HomeView observes it and performs the action.
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()
    @Published var pendingShortcutType: String?
    private init() {}
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Cold launch: the shortcut arrives here, never in didFinishLaunching.
        if let shortcut = connectionOptions.shortcutItem {
            ShortcutManager.shared.pendingShortcutType = shortcut.type
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Warm launch: app already running, brought to foreground.
        ShortcutManager.shared.pendingShortcutType = shortcutItem.type
        completionHandler(true)
    }
}
