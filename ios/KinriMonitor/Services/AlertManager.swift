import Foundation
import UserNotifications
import BackgroundTasks

// MARK: - アラートルール

struct AlertRule: Codable, Identifiable {
    var id: UUID
    var seriesKey: String           // SERIES のキー
    var label: String               // 表示名
    var isEnabled: Bool
    var direction: Direction        // 上昇 or 下降
    var threshold: Double           // 閾値（%）

    enum Direction: String, Codable, CaseIterable {
        case above = "以上で通知"
        case below = "以下で通知"
    }

    init(seriesKey: String, label: String, threshold: Double, direction: Direction = .above) {
        self.id = UUID()
        self.seriesKey = seriesKey
        self.label = label
        self.isEnabled = false
        self.direction = direction
        self.threshold = threshold
    }
}

// MARK: - AlertManager

class AlertManager: ObservableObject {
    static let shared = AlertManager()
    static let bgTaskID = "com.kinrimonitor.app.ratecheck"

    private let rulesKey = "alert_rules_v2"
    private let defaults = UserDefaults.standard

    @Published var rules: [AlertRule] = []

    private init() {
        loadRules()
        if rules.isEmpty {
            rules = Self.defaultRules()
            saveRules()
        }
    }

    // MARK: - デフォルトルール（全12指標）

    static func defaultRules() -> [AlertRule] {
        [
            AlertRule(seriesKey: "LENDING_NEW_TOTAL_DOMESTIC", label: "新規/総合/国内銀行", threshold: 2.0),
            AlertRule(seriesKey: "LENDING_NEW_SHORT_DOMESTIC", label: "新規/短期/国内銀行", threshold: 2.0),
            AlertRule(seriesKey: "LENDING_NEW_LONG_DOMESTIC",  label: "新規/長期/国内銀行", threshold: 2.0),
            AlertRule(seriesKey: "LENDING_NEW_TOTAL_CITY",     label: "新規/総合/都市銀行", threshold: 2.0),
            AlertRule(seriesKey: "LENDING_NEW_TOTAL_REGIONAL", label: "新規/総合/地方銀行", threshold: 2.0),
            AlertRule(seriesKey: "LENDING_NEW_TOTAL_SHINKIN",  label: "新規/総合/信用金庫", threshold: 2.5),
            AlertRule(seriesKey: "LENDING_STOCK_TOTAL",        label: "ストック/総合/国内銀行", threshold: 1.5),
            AlertRule(seriesKey: "LENDING_STOCK_SHORT",        label: "ストック/短期/国内銀行", threshold: 1.5),
            AlertRule(seriesKey: "LENDING_STOCK_LONG",         label: "ストック/長期/国内銀行", threshold: 1.5),
            AlertRule(seriesKey: "BASE_RATE",                  label: "基準割引率・基準貸付利率", threshold: 1.0),
            AlertRule(seriesKey: "CALL_RATE_ON_AVG",           label: "無担保コールレート O/N", threshold: 1.0),
            AlertRule(seriesKey: "PRIME_RATE_TOTAL",           label: "貸出金利 総合", threshold: 1.0),
        ]
    }

    // MARK: - ルール操作

    func toggleRule(id: UUID) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].isEnabled.toggle()
        saveRules()
        if rules[idx].isEnabled { requestPermission() }
    }

    func updateThreshold(id: UUID, threshold: Double) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].threshold = threshold
        saveRules()
    }

    func updateDirection(id: UUID, direction: AlertRule.Direction) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].direction = direction
        saveRules()
    }

    var hasAnyEnabled: Bool {
        rules.contains { $0.isEnabled }
    }

    // MARK: - 通知権限

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - チェック＆通知（起動時 + バックグラウンド共用）

    func checkAndNotify() async {
        let enabled = rules.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        do {
            let rates = try await APIClient.shared.fetchLatestRates()

            for rule in enabled {
                guard let rate = rates.first(where: { $0.key == rule.seriesKey }),
                      let value = rate.latest?.value else { continue }

                let triggered: Bool
                switch rule.direction {
                case .above: triggered = value >= rule.threshold
                case .below: triggered = value <= rule.threshold
                }

                if triggered {
                    let dirText = rule.direction == .above ? "以上" : "以下"
                    scheduleNotification(
                        id: "alert_\(rule.seriesKey)",
                        title: "金利アラート：\(rule.label)",
                        body: "\(rule.label)が\(String(format: "%.3f", value))%になりました（閾値\(String(format: "%.2f", rule.threshold))%\(dirText)）。借入金利への影響にご注意ください。"
                    )
                }
            }
        } catch {
            // 静かに無視
        }
    }

    private func scheduleNotification(id: String, title: String, body: String) {
        let lastKey = "last_alert_\(id)"
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = defaults.object(forKey: lastKey) as? Date,
           Calendar.current.isDate(lastDate, inSameDayAs: today) {
            return
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

    // MARK: - BGAppRefreshTask

    static func registerBGTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskID, using: nil) { task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            handleBGTask(bgTask)
        }
    }

    static func scheduleBGTask() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskID)
        // 日銀更新は8:50頃。9時以降にチェック
        request.earliestBeginDate = nextCheckDate()
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func nextCheckDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = 9
        comps.minute = 5

        if let today9am = cal.date(from: comps), now < today9am {
            return today9am
        }
        // 既に9時過ぎなら翌日
        comps.day! += 1
        return cal.date(from: comps) ?? now.addingTimeInterval(3600)
    }

    private static func handleBGTask(_ task: BGAppRefreshTask) {
        // 次回もスケジュール
        scheduleBGTask()

        let checkTask = Task {
            await AlertManager.shared.checkAndNotify()
        }

        task.expirationHandler = {
            checkTask.cancel()
        }

        Task {
            _ = await checkTask.result
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Persistence

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: rulesKey)
        }
    }

    private func loadRules() {
        guard let data = defaults.data(forKey: rulesKey),
              let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) else { return }
        rules = decoded
    }
}
