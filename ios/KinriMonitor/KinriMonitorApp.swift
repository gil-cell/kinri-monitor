import SwiftUI
import BackgroundTasks

@main
struct KinriMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AlertManager.registerBGTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    PushManager.shared.requestPermissionAndRegister()
                    await AlertManager.shared.checkAndNotify()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    AlertManager.scheduleBGTask()
                }
        }
    }
}

// MARK: - AppDelegate for APNs token

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}
