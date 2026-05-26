import Foundation

// MARK: - ポートフォリオローン

struct PortfolioLoan: Codable, Identifiable {
    var id: UUID
    var name: String
    var condition: LoanCondition
    var paymentDay: Int                         // 毎月の支払日（1〜28）
    var contractDate: Date                      // 契約日
    var repaymentMethod: RepaymentMethod        // 元利均等 or 元金均等
    var penaltyRate: Double                     // 遅延損害金の年利（%）デフォルト14.6
    var payments: [PaymentRecord]               // 支払い実績（過去データ、変更不可）
    var schedule: [ScheduleEntry]               // 返済予定（未来、再計算で上書き可）
    var events: [LoanEvent]                     // イベント履歴（繰上返済・条件変更など）
    var reminderDaysBefore: [Int]               // 返済日の何日前に通知するか（例: [3, 5]）
    var reminderEnabled: Bool                   // リマインダーON/OFF
    var createdAt: Date

    enum RepaymentMethod: String, Codable, CaseIterable {
        case equalPayment = "元利均等"
        case equalPrincipal = "元金均等"
    }

    /// 現在の残元金（支払い済み分を差し引き）
    var remainingPrincipal: Int {
        let totalPrincipalPaid = payments.reduce(0) { $0 + $1.principalPart }
        let prepayments = events.filter { $0.type == .prepayment }.reduce(0) { $0 + ($0 == 0 ? $1.amount : $1.amount) }
        let prepayTotal = events.filter { $0.type == .prepayment }.reduce(0) { $0 + $1.amount }
        return max(condition.principal - totalPrincipalPaid - prepayTotal, 0)
    }

    /// 総返済済み額
    var totalPaid: Int {
        payments.reduce(0) { $0 + $1.amount }
    }

    /// 総利息支払い済み額
    var totalInterestPaid: Int {
        payments.reduce(0) { $0 + $1.interestPart }
    }

    /// 残りの返済回数
    var remainingPayments: Int {
        schedule.filter { !$0.isPaid }.count
    }

    /// 完済予定日
    var expectedCompletionDate: Date? {
        schedule.last?.dueDate
    }

    /// ローンの進捗率（%）
    var progressRatio: Double {
        guard condition.principal > 0 else { return 0 }
        let paid = payments.reduce(0) { $0 + $1.principalPart }
        return min(Double(paid) / Double(condition.principal) * 100, 100)
    }

    init(name: String, condition: LoanCondition, paymentDay: Int, contractDate: Date, method: RepaymentMethod, penaltyRate: Double = 14.6) {
        self.id = UUID()
        self.name = name
        self.condition = condition
        self.paymentDay = paymentDay
        self.contractDate = contractDate
        self.repaymentMethod = method
        self.penaltyRate = penaltyRate
        self.payments = []
        self.schedule = []
        self.events = []
        self.reminderDaysBefore = [3, 5]
        self.reminderEnabled = true
        self.createdAt = Date()
        self.schedule = Self.generateSchedule(principal: condition.principal, rate: condition.annualRate, termYears: condition.termYears, method: method, startDate: contractDate, paymentDay: paymentDay)
    }
}

// MARK: - 支払い実績（過去データ、immutable）

struct PaymentRecord: Codable, Identifiable {
    let id: UUID
    let month: Int              // 回数（1始まり）
    let dueDate: Date           // 支払期日
    let paidDate: Date?         // 実際の支払日（nil=未払い）
    let amount: Int             // 支払額
    let principalPart: Int      // 元金部分
    let interestPart: Int       // 利息部分
    let penaltyAmount: Int      // 遅延損害金
    let status: PaymentStatus

    enum PaymentStatus: String, Codable {
        case paid = "支払済"
        case overdue = "延滞"
        case pending = "未到来"
    }
}

// MARK: - 返済予定（未来、再計算可能）

struct ScheduleEntry: Codable, Identifiable {
    let id: UUID
    let month: Int
    let dueDate: Date
    var payment: Int
    var principalPart: Int
    var interestPart: Int
    var balance: Int            // 支払い後の残高
    var isPaid: Bool            // 支払い実績に変換済みか

    init(month: Int, dueDate: Date, payment: Int, principalPart: Int, interestPart: Int, balance: Int) {
        self.id = UUID()
        self.month = month
        self.dueDate = dueDate
        self.payment = payment
        self.principalPart = principalPart
        self.interestPart = interestPart
        self.balance = balance
        self.isPaid = false
    }
}

// MARK: - ローンイベント

struct LoanEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let type: EventType
    let amount: Int             // 繰上返済額 or 0
    let description: String
    let newRate: Double?        // 条件変更時の新金利
    let newTermYears: Int?      // 条件変更時の新期間

    enum EventType: String, Codable {
        case prepayment = "繰上返済"
        case reschedule = "条件変更"
        case overdueResolved = "延滞解消"
    }

    init(type: EventType, amount: Int = 0, description: String, newRate: Double? = nil, newTermYears: Int? = nil) {
        self.id = UUID()
        self.date = Date()
        self.type = type
        self.amount = amount
        self.description = description
        self.newRate = newRate
        self.newTermYears = newTermYears
    }
}

// MARK: - スケジュール生成

extension PortfolioLoan {
    static func generateSchedule(principal: Int, rate: Double, termYears: Int, method: RepaymentMethod, startDate: Date, paymentDay: Int) -> [ScheduleEntry] {
        let P = Double(principal)
        let r = rate / 100.0 / 12.0
        let n = termYears * 12
        var entries: [ScheduleEntry] = []
        var balance = P

        let calendar = Calendar.current

        for i in 1...n {
            guard var dueDate = calendar.date(byAdding: .month, value: i, to: startDate) else { continue }
            var comps = calendar.dateComponents([.year, .month], from: dueDate)
            comps.day = min(paymentDay, 28)
            dueDate = calendar.date(from: comps) ?? dueDate

            let interest = balance * r
            let principalPart: Double
            let payment: Double

            switch method {
            case .equalPayment:
                if r > 0 {
                    let rn = pow(1 + r, Double(n))
                    payment = P * r * rn / (rn - 1)
                } else {
                    payment = P / Double(n)
                }
                principalPart = payment - interest
            case .equalPrincipal:
                principalPart = P / Double(n)
                payment = principalPart + interest
            }

            balance -= principalPart
            if balance < 0 { balance = 0 }

            entries.append(ScheduleEntry(
                month: i,
                dueDate: dueDate,
                payment: Int(round(payment)),
                principalPart: Int(round(principalPart)),
                interestPart: Int(round(interest)),
                balance: Int(round(balance))
            ))
        }
        return entries
    }
}
