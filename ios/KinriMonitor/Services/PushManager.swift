import Foundation
import UIKit
import UserNotifications

/// APNs デバイストークンの取得とサーバー登録を管理
class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published var deviceToken: String?
    @Published var isRegistered = false

    private override init() {
        super.init()
    }

    /// プッシュ通知の権限をリクエストしてAPNs登録
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// AppDelegate から呼ばれる: トークン取得成功時
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            self.deviceToken = token
        }
        // サーバーに登録
        registerWithServer(token: token)
    }

    /// アラートルールをサーバーに同期
    func syncAlertRules() {
        guard let token = deviceToken else { return }
        let rules = AlertManager.shared.rules.filter(\.isEnabled).map { rule in
            [
                "series_key": rule.seriesKey,
                "direction": rule.direction.rawValue == "以上で通知" ? "above" : "below",
                "threshold": rule.threshold,
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "device_token": token,
            "alert_rules": rules,
        ]

        postToServer(path: "/api/device/alerts", body: body)
    }

    // MARK: - Private

    private func registerWithServer(token: String) {
        let rules = AlertManager.shared.rules.filter(\.isEnabled).map { rule in
            [
                "series_key": rule.seriesKey,
                "direction": rule.direction.rawValue == "以上で通知" ? "above" : "below",
                "threshold": rule.threshold,
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "device_token": token,
            "alert_rules": rules,
        ]

        postToServer(path: "/api/device/register", body: body)
    }

    private func postToServer(path: String, body: [String: Any]) {
        guard let url = URL(string: "https://kinri-monitor-api.kinritilyusyou.workers.dev\(path)"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { data, resp, error in
            if let error {
                print("[Push] Error: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.isRegistered = true
                }
                print("[Push] Server sync OK")
            }
        }.resume()
    }
}
