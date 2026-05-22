import Foundation

/// 借入条件の端末内保存（UserDefaults）
/// サーバーには送らない（プライバシー優先）
class LoanStore: ObservableObject {
    static let shared = LoanStore()

    private let key = "loan_condition"

    @Published var condition: LoanCondition {
        didSet { save() }
    }

    /// 将来 StoreKit2 サブスク導入時にここを切り替え
    @Published var isPremium: Bool = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(LoanCondition.self, from: data) {
            condition = decoded
        } else {
            condition = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(condition) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func reset() {
        condition = .default
    }
}
