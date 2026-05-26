import Foundation
import UserNotifications

class PortfolioStore: ObservableObject {
    static let shared = PortfolioStore()

    private let key = "portfolio_loans"

    @Published var loans: [PortfolioLoan] = []

    private init() { load() }

    // MARK: - CRUD

    func addLoan(_ loan: PortfolioLoan) {
        loans.append(loan)
        save()
        if loan.reminderEnabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            scheduleAllReminders()
        }
    }

    func deleteLoan(_ loan: PortfolioLoan) {
        loans.removeAll { $0.id == loan.id }
        save()
    }

    func deleteLoan(at offsets: IndexSet) {
        loans.remove(atOffsets: offsets)
        save()
    }

    // MARK: - 支払い取消

    /// 支払い済み/延滞の記録を取り消してスケジュールに戻す
    func undoPayment(loanID: UUID, month: Int) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }) else { return }

        // paymentsから削除
        loans[li].payments.removeAll { $0.month == month }

        // scheduleのisPaidをfalseに戻す
        if let si = loans[li].schedule.firstIndex(where: { $0.month == month }) {
            loans[li].schedule[si].isPaid = false
        }
        save()
    }

    // MARK: - 支払い記録

    /// 指定月を「支払済」にする
    func markAsPaid(loanID: UUID, month: Int, paidDate: Date = Date()) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }),
              let si = loans[li].schedule.firstIndex(where: { $0.month == month && !$0.isPaid }) else { return }

        let entry = loans[li].schedule[si]
        let record = PaymentRecord(
            id: UUID(), month: month, dueDate: entry.dueDate,
            paidDate: paidDate, amount: entry.payment,
            principalPart: entry.principalPart, interestPart: entry.interestPart,
            penaltyAmount: 0, status: .paid
        )
        loans[li].payments.append(record)
        loans[li].schedule[si].isPaid = true
        save()
    }

    /// 指定月を「延滞」にする（遅延損害金を計算）
    func markAsOverdue(loanID: UUID, month: Int, delayDays: Int) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }),
              let si = loans[li].schedule.firstIndex(where: { $0.month == month && !$0.isPaid }) else { return }

        let entry = loans[li].schedule[si]
        let loan = loans[li]

        // 遅延損害金 = 残元金 × 遅延損害金利率 × 遅延日数 / 365
        let remaining = entry.balance + entry.principalPart // 支払い前の残高
        let penalty = Int(round(Double(remaining) * loan.penaltyRate / 100.0 * Double(delayDays) / 365.0))

        let record = PaymentRecord(
            id: UUID(), month: month, dueDate: entry.dueDate,
            paidDate: nil, amount: entry.payment + penalty,
            principalPart: entry.principalPart, interestPart: entry.interestPart,
            penaltyAmount: penalty, status: .overdue
        )
        loans[li].payments.append(record)
        loans[li].schedule[si].isPaid = true
        save()
    }

    /// 延滞を解消（遅延損害金込みで支払い）
    func resolveOverdue(loanID: UUID, month: Int, paidDate: Date = Date()) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }),
              let pi = loans[li].payments.firstIndex(where: { $0.month == month && $0.status == .overdue }) else { return }

        let old = loans[li].payments[pi]
        let resolved = PaymentRecord(
            id: old.id, month: old.month, dueDate: old.dueDate,
            paidDate: paidDate, amount: old.amount,
            principalPart: old.principalPart, interestPart: old.interestPart,
            penaltyAmount: old.penaltyAmount, status: .paid
        )
        loans[li].payments[pi] = resolved

        loans[li].events.append(LoanEvent(
            type: .overdueResolved,
            description: "第\(month)回の延滞を解消（遅延損害金\(old.penaltyAmount.formatted())円含む）"
        ))
        save()
    }

    // MARK: - 1. 繰上返済

    enum PrepaymentType: String {
        case shortenTerm = "期間短縮型"
        case reducePayment = "返済額軽減型"
    }

    func prepay(loanID: UUID, amount: Int, type: PrepaymentType) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }) else { return }
        var loan = loans[li]

        // 残元金を計算
        let totalPrincipalPaid = loan.payments.reduce(0) { $0 + $1.principalPart }
        let pastPrepayments = loan.events.filter { $0.type == .prepayment }.reduce(0) { $0 + $1.amount }
        let currentRemaining = max(loan.condition.principal - totalPrincipalPaid - pastPrepayments, 0)
        let newRemaining = max(currentRemaining - amount, 0)

        // イベント記録
        loan.events.append(LoanEvent(
            type: .prepayment,
            amount: amount,
            description: "\(type.rawValue)で\(amount.formatted())円を繰上返済"
        ))

        // 未払いスケジュールを再生成
        let paidCount = loan.payments.count
        let nextMonth = paidCount + 1
        let lastDueDate = loan.schedule.first(where: { !$0.isPaid })?.dueDate ?? Date()

        switch type {
        case .shortenTerm:
            // 月額は変えず期間を短縮
            loan.schedule = regenerateScheduleShortenTerm(
                remaining: newRemaining, rate: loan.condition.annualRate,
                method: loan.repaymentMethod, startMonth: nextMonth,
                startDate: lastDueDate, paymentDay: loan.paymentDay,
                originalPayment: loan.schedule.first(where: { !$0.isPaid })?.payment ?? 0
            )
        case .reducePayment:
            // 期間は変えず月額を軽減
            let remainingMonths = loan.schedule.filter { !$0.isPaid }.count
            loan.schedule = regenerateSchedule(
                remaining: newRemaining, rate: loan.condition.annualRate,
                termMonths: remainingMonths, method: loan.repaymentMethod,
                startMonth: nextMonth, startDate: lastDueDate, paymentDay: loan.paymentDay
            )
        }

        loans[li] = loan
        save()
    }

    // MARK: - 3. 条件変更（リスケジュール）

    func reschedule(loanID: UUID, newRate: Double?, newTermYears: Int?) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }) else { return }
        var loan = loans[li]

        let totalPrincipalPaid = loan.payments.reduce(0) { $0 + $1.principalPart }
        let pastPrepayments = loan.events.filter { $0.type == .prepayment }.reduce(0) { $0 + $1.amount }
        let currentRemaining = max(loan.condition.principal - totalPrincipalPaid - pastPrepayments, 0)

        let rate = newRate ?? loan.condition.annualRate
        let paidCount = loan.payments.count
        let termMonths: Int
        if let newYears = newTermYears {
            termMonths = newYears * 12
        } else {
            termMonths = loan.schedule.filter({ !$0.isPaid }).count
        }

        let nextMonth = paidCount + 1
        let lastDueDate = loan.schedule.first(where: { !$0.isPaid })?.dueDate ?? Date()

        var desc = "条件変更："
        if let r = newRate { desc += "金利\(String(format: "%.3f%%", r))" }
        if let y = newTermYears { desc += " 期間\(y)年" }

        loan.events.append(LoanEvent(
            type: .reschedule, description: desc, newRate: newRate, newTermYears: newTermYears
        ))

        // 過去の支払いは変更しない。未来スケジュールのみ再生成
        loan.schedule = regenerateSchedule(
            remaining: currentRemaining, rate: rate, termMonths: termMonths,
            method: loan.repaymentMethod, startMonth: nextMonth,
            startDate: lastDueDate, paymentDay: loan.paymentDay
        )

        // 条件も更新
        if let r = newRate { loan.condition.annualRate = r }

        loans[li] = loan
        save()
    }

    // MARK: - スケジュール再生成

    private func regenerateSchedule(remaining: Int, rate: Double, termMonths: Int, method: PortfolioLoan.RepaymentMethod, startMonth: Int, startDate: Date, paymentDay: Int) -> [ScheduleEntry] {
        let P = Double(remaining)
        let r = rate / 100.0 / 12.0
        let n = termMonths
        var entries: [ScheduleEntry] = []
        var balance = P
        let calendar = Calendar.current

        for i in 0..<n {
            guard var dueDate = calendar.date(byAdding: .month, value: i + 1, to: startDate) else { continue }
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
                month: startMonth + i, dueDate: dueDate,
                payment: Int(round(payment)), principalPart: Int(round(principalPart)),
                interestPart: Int(round(interest)), balance: Int(round(balance))
            ))
        }
        return entries
    }

    private func regenerateScheduleShortenTerm(remaining: Int, rate: Double, method: PortfolioLoan.RepaymentMethod, startMonth: Int, startDate: Date, paymentDay: Int, originalPayment: Int) -> [ScheduleEntry] {
        let r = rate / 100.0 / 12.0
        var balance = Double(remaining)
        var entries: [ScheduleEntry] = []
        let calendar = Calendar.current
        var i = 0

        while balance > 1 {
            guard var dueDate = calendar.date(byAdding: .month, value: i + 1, to: startDate) else { break }
            var comps = calendar.dateComponents([.year, .month], from: dueDate)
            comps.day = min(paymentDay, 28)
            dueDate = calendar.date(from: comps) ?? dueDate

            let interest = balance * r
            let payment = min(Double(originalPayment), balance + interest)
            let principalPart = payment - interest
            balance -= principalPart
            if balance < 1 { balance = 0 }

            entries.append(ScheduleEntry(
                month: startMonth + i, dueDate: dueDate,
                payment: Int(round(payment)), principalPart: Int(round(principalPart)),
                interestPart: Int(round(interest)), balance: Int(round(balance))
            ))
            i += 1
            if i > 600 { break } // 安全弁
        }
        return entries
    }

    // MARK: - 集計

    var totalRemainingPrincipal: Int { loans.reduce(0) { $0 + $1.remainingPrincipal } }
    var totalMonthlyPayment: Int {
        loans.reduce(0) { total, loan in
            total + (loan.schedule.first(where: { !$0.isPaid })?.payment ?? 0)
        }
    }
    var totalPaid: Int { loans.reduce(0) { $0 + $1.totalPaid } }
    var totalInterestPaid: Int { loans.reduce(0) { $0 + $1.totalInterestPaid } }

    /// 円グラフ用データ
    var chartData: [(name: String, amount: Int, color: Int)] {
        loans.enumerated().map { (i, loan) in
            (loan.name, loan.remainingPrincipal, i)
        }
    }

    // MARK: - リマインダー設定

    func toggleReminder(loanID: UUID) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }) else { return }
        loans[li].reminderEnabled.toggle()
        save()
        scheduleAllReminders()
    }

    func setReminderDays(loanID: UUID, days: [Int]) {
        guard let li = loans.firstIndex(where: { $0.id == loanID }) else { return }
        loans[li].reminderDaysBefore = days.sorted(by: >)
        save()
        scheduleAllReminders()
    }

    // MARK: - リマインダー通知スケジュール

    /// 全ローンの返済リマインダーを再スケジュール
    func scheduleAllReminders() {
        let center = UNUserNotificationCenter.current()
        // 既存のリマインダー通知を全削除して再作成
        center.getPendingNotificationRequests { requests in
            let reminderIDs = requests.filter { $0.identifier.hasPrefix("reminder_") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: reminderIDs)

            // 再スケジュール
            for loan in self.loans where loan.reminderEnabled {
                self.scheduleRemindersForLoan(loan)
            }
        }
    }

    private func scheduleRemindersForLoan(_ loan: PortfolioLoan) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()

        // 未払いスケジュールから直近6ヶ月分のリマインダーを設定
        let upcoming = loan.schedule.filter { !$0.isPaid && $0.dueDate > now }

        for entry in upcoming.prefix(6) {
            for daysBefore in loan.reminderDaysBefore {
                guard let reminderDate = calendar.date(byAdding: .day, value: -daysBefore, to: entry.dueDate),
                      reminderDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "返済リマインダー"
                content.body = "【\(loan.name)】の返済日まであと\(daysBefore)日です。\(entry.payment.formatted())円の返済予定があります。"
                content.sound = .default

                var comps = calendar.dateComponents([.year, .month, .day], from: reminderDate)
                comps.hour = 9
                comps.minute = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "reminder_\(loan.id.uuidString)_\(entry.month)_\(daysBefore)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

                center.add(request)
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(loans) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PortfolioLoan].self, from: data) else { return }
        loans = decoded
    }
}
