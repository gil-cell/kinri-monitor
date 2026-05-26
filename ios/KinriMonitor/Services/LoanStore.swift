import Foundation

// MARK: - 保存済みローン

struct SavedLoan: Codable, Identifiable {
    var id: UUID
    var name: String
    var condition: LoanCondition
    var savedAt: Date

    init(name: String, condition: LoanCondition) {
        self.id = UUID()
        self.name = name
        self.condition = condition
        self.savedAt = Date()
    }
}

/// 借入条件の端末内保存（UserDefaults）
/// サーバーには送らない（プライバシー優先）
class LoanStore: ObservableObject {
    static let shared = LoanStore()

    private let conditionKey = "loan_condition"
    private let savedLoansKey = "saved_loans"

    /// 現在編集中の借入条件
    @Published var condition: LoanCondition {
        didSet { saveCondition() }
    }

    /// 保存済みローン一覧
    @Published var savedLoans: [SavedLoan] = []

    /// 将来 StoreKit2 サブスク導入時にここを切り替え
    @Published var isPremium: Bool = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: conditionKey),
           let decoded = try? JSONDecoder().decode(LoanCondition.self, from: data) {
            condition = decoded
        } else {
            condition = .default
        }
        loadSavedLoans()
    }

    // MARK: - 現在の条件

    private func saveCondition() {
        if let data = try? JSONEncoder().encode(condition) {
            UserDefaults.standard.set(data, forKey: conditionKey)
        }
    }

    func reset() {
        condition = .default
    }

    // MARK: - 保存済みローン管理

    func saveLoan(name: String) {
        let loan = SavedLoan(name: name, condition: condition)
        savedLoans.append(loan)
        persistSavedLoans()
    }

    func deleteLoan(_ loan: SavedLoan) {
        savedLoans.removeAll { $0.id == loan.id }
        persistSavedLoans()
    }

    func deleteLoan(at offsets: IndexSet) {
        savedLoans.remove(atOffsets: offsets)
        persistSavedLoans()
    }

    func renameLoan(_ loan: SavedLoan, to newName: String) {
        guard let idx = savedLoans.firstIndex(where: { $0.id == loan.id }) else { return }
        savedLoans[idx].name = newName
        persistSavedLoans()
    }

    func loadCondition(from loan: SavedLoan) {
        condition = loan.condition
    }

    private func loadSavedLoans() {
        guard let data = UserDefaults.standard.data(forKey: savedLoansKey),
              let decoded = try? JSONDecoder().decode([SavedLoan].self, from: data) else { return }
        savedLoans = decoded
    }

    private func persistSavedLoans() {
        if let data = try? JSONEncoder().encode(savedLoans) {
            UserDefaults.standard.set(data, forKey: savedLoansKey)
        }
    }
}
