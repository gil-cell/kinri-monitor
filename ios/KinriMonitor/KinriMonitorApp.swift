import SwiftUI

@main
struct KinriMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await AlertManager.shared.checkAndNotify()
                }
        }
    }
}
