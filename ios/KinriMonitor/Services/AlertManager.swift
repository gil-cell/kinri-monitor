import Foundation
import UserNotifications

/// 金利アラート管理
/// アプリ起動時にAPIから最新値を取得し、閾値超過時にローカル通知をスケジュール
class AlertManager: ObservableObject {
    static let shared = AlertManager()

    private let defaults = UserDefaults.standard

    // アラート設定
    @Published var alertEnabled: Bool {
        didSet { defaults.set(alertEnabled, forKey: "alert_enabled") }
    }
    @Published var callRateThreshold: Double {
        didSet { defaults.set(callRateThreshold, forKey: "alert_call_rate_threshold") }
    }
    @Published var lendingRateThreshold: Double {
        didSet { defaults.set(lendingRateThreshold, forKey: "alert_lending_rate_threshold") }
    }

    private init() {
        self.alertEnabled = defaults.object(forKey: "alert_enabled") as? Bool ?? false
        self.callRateThreshold = defaults.object(forKey: "alert_call_rate_threshold") as? Double ?? 1.0
        self.lendingRateThreshold = defaults.object(forKey: "alert_lending_rate_threshold") as? Double ?? 2.0
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.alertEnabled = true
                }
            }
        }
    }

    /// アプリ起動時に呼び出し：最新金利を取得してアラート判定
    func checkAndNotify() async {
        guard alertEnabled else { return }

        do {
            let rates = try await APIClient.shared.fetchLatestRates()

            // 無担保コールレート
            if let callRate = rates.first(where: { $0.key == "CALL_RATE_ON_AVG" })?.latest?.value,
               callRate >= callRateThreshold {
                scheduleNotification(
                    id: "call_rate_alert",
                    title: "金利アラート",
                    body: "無担保コールレート(O/N)が\(String(format: "%.3f", callRate))%に達しました（閾値: \(String(format: "%.2f", callRateThreshold))%）。借入金利への影響にご注意ください。"
                )
            }

            // 新規貸出金利（国内銀行・総合）
            if let lendingRate = rates.first(where: { $0.key == "LENDING_NEW_TOTAL_DOMESTIC" })?.latest?.value,
               lendingRate >= lendingRateThreshold {
                scheduleNotification(
                    id: "lending_rate_alert",
                    title: "金利アラート",
                    body: "貸出約定平均金利（新規/総合）が\(String(format: "%.3f", lendingRate))%に達しました（閾値: \(String(format: "%.2f", lendingRateThreshold))%）。"
                )
            }
        } catch {
            // 通知チェック失敗は静かに無視
        }
    }

    private func scheduleNotification(id: String, title: String, body: String) {
        // 同じIDの既存通知を削除して重複防止
        let lastKey = "last_alert_\(id)"
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = defaults.object(forKey: lastKey) as? Date,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return // 本日既に通知済み
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
        defaults.set(today, forKey: lastKey)
    }
}
