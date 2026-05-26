import SwiftUI

struct PortfolioDetailView: View {
    let loanID: UUID
    @ObservedObject private var store = PortfolioStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPrepayment = false
    @State private var showReschedule = false
    @State private var showOverdueAlert = false
    @State private var overdueMonth = 0
    @State private var overdueDays = "7"
    @State private var showUndoConfirm = false
    @State private var undoMonth = 0

    private var loan: PortfolioLoan? {
        store.loans.first(where: { $0.id == loanID })
    }

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    private let shortDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var body: some View {
        NavigationStack {
            if let loan {
                List {
                    // サマリー
                    Section {
                        row("借入額", value: "\(loan.condition.principal.formatted())円")
                        row("金利", value: String(format: "%.3f%%", loan.condition.annualRate))
                        row("残高", value: "\(loan.remainingPrincipal.formatted())円")
                        row("進捗", value: String(format: "%.1f%%", loan.progressRatio))
                        row("残り回数", value: "\(loan.remainingPayments)回")
                        if let last = loan.expectedCompletionDate {
                            row("完済予定", value: shortDateFmt.string(from: last))
                        }
                    } header: {
                        Text(loan.name)
                    }

                    // リマインダー設定
                    Section {
                        Toggle(isOn: Binding(
                            get: { loan.reminderEnabled },
                            set: { _ in store.toggleReminder(loanID: loanID) }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(Theme.warning)
                                Text("返済リマインダー")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                        .tint(Theme.accent)

                        if loan.reminderEnabled {
                            HStack {
                                Text("通知タイミング")
                                    .font(.system(size: 13))
                                Spacer()
                                Text(loan.reminderDaysBefore.map { "\($0)日前" }.joined(separator: "・"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.accent)
                            }

                            // 通知日カスタマイズ
                            HStack(spacing: 8) {
                                ForEach([1, 2, 3, 5, 7], id: \.self) { day in
                                    let isSelected = loan.reminderDaysBefore.contains(day)
                                    Button {
                                        var days = loan.reminderDaysBefore
                                        if isSelected {
                                            days.removeAll { $0 == day }
                                        } else {
                                            days.append(day)
                                        }
                                        if !days.isEmpty {
                                            store.setReminderDays(loanID: loanID, days: days)
                                        }
                                    } label: {
                                        Text("\(day)日前")
                                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                            .foregroundStyle(isSelected ? .white : Theme.textPrimary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(isSelected ? Theme.accent : Theme.accent.opacity(0.1))
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text("毎月\(loan.paymentDay)日の返済日に対して、選択した日数前の朝9時に通知します")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted)
                        }
                    } header: {
                        Text("リマインダー")
                    }

                    // アクション
                    Section {
                        Button { showPrepayment = true } label: {
                            Label("繰上返済", systemImage: "arrow.up.circle")
                                .foregroundStyle(Theme.accent)
                        }
                        Button { showReschedule = true } label: {
                            Label("条件変更（リスケジュール）", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Theme.info)
                        }
                    } header: {
                        Text("操作")
                    }

                    // イベント履歴
                    if !loan.events.isEmpty {
                        Section {
                            ForEach(loan.events) { event in
                                HStack {
                                    BadgeView(text: event.type.rawValue,
                                              color: event.type == .prepayment ? Theme.accent
                                              : event.type == .reschedule ? Theme.info : Theme.warning)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.description)
                                            .font(.system(size: 12))
                                        Text(shortDateFmt.string(from: event.date))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                }
                            }
                        } header: {
                            Text("イベント履歴")
                        }
                    }

                    // ── 返済スケジュール（全件表示） ──
                    Section {
                        // 支払い済み分
                        ForEach(loan.payments.sorted(by: { $0.month < $1.month })) { payment in
                            paymentRow(payment: payment, loan: loan)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        undoMonth = payment.month
                                        showUndoConfirm = true
                                    } label: {
                                        Label("取消", systemImage: "arrow.uturn.backward")
                                    }
                                }
                        }

                        // 未払いスケジュール（全件）
                        ForEach(loan.schedule.filter({ !$0.isPaid })) { entry in
                            scheduleRow(entry: entry)
                        }
                    } header: {
                        HStack {
                            Text("返済スケジュール")
                            Spacer()
                            Text("全\(loan.payments.count + loan.schedule.filter({ !$0.isPaid }).count)件")
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    } footer: {
                        Text("支払済みの行を左スワイプで取り消せます。")
                            .font(.caption2)
                    }
                }
                .navigationTitle("ローン詳細")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { dismiss() }
                    }
                }
                .sheet(isPresented: $showPrepayment) {
                    PrepaymentSheet(loanID: loanID)
                }
                .sheet(isPresented: $showReschedule) {
                    RescheduleSheet(loanID: loanID)
                }
                .alert("延滞として記録", isPresented: $showOverdueAlert) {
                    TextField("遅延日数", text: $overdueDays)
                        .keyboardType(.numberPad)
                    Button("記録") {
                        if let days = Int(overdueDays) {
                            store.markAsOverdue(loanID: loanID, month: overdueMonth, delayDays: days)
                        }
                    }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("第\(overdueMonth)回の遅延日数を入力してください。遅延損害金が自動計算されます。")
                }
                .alert("支払い記録を取り消し", isPresented: $showUndoConfirm) {
                    Button("取り消す", role: .destructive) {
                        store.undoPayment(loanID: loanID, month: undoMonth)
                    }
                    Button("やめる", role: .cancel) {}
                } message: {
                    Text("第\(undoMonth)回の支払い記録を取り消して、未払い状態に戻します。")
                }
            }
        }
    }

    // MARK: - 支払い済み行

    private func paymentRow(payment: PaymentRecord, loan: PortfolioLoan) -> some View {
        HStack(spacing: 8) {
            // ステータスアイコン
            Image(systemName: payment.status == .paid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(payment.status == .paid ? Theme.positive : Theme.negative)
                .frame(width: 24)

            // 回数 + 日付
            VStack(alignment: .leading, spacing: 2) {
                Text("第\(payment.month)回")
                    .font(.system(size: 13, weight: .semibold))
                Text(dateFmt.string(from: payment.dueDate))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 75, alignment: .leading)

            Spacer()

            // 金額内訳
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(payment.amount.formatted())円")
                    .font(Theme.numericSmall(13))
                HStack(spacing: 4) {
                    Text("元金\(payment.principalPart.formatted())")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted)
                    Text("利息\(payment.interestPart.formatted())")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                if payment.penaltyAmount > 0 {
                    Text("延滞金+\(payment.penaltyAmount.formatted())")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.negative)
                }
            }

            // ステータスバッジ
            BadgeView(
                text: payment.status.rawValue,
                color: payment.status == .paid ? Theme.positive : Theme.negative
            )
        }
        .padding(.vertical, 2)
    }

    // MARK: - 未払いスケジュール行

    private func scheduleRow(entry: ScheduleEntry) -> some View {
        HStack(spacing: 8) {
            // 未払いアイコン
            Image(systemName: "circle")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted.opacity(0.4))
                .frame(width: 24)

            // 回数 + 日付
            VStack(alignment: .leading, spacing: 2) {
                Text("第\(entry.month)回")
                    .font(.system(size: 13, weight: .medium))
                Text(dateFmt.string(from: entry.dueDate))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .frame(width: 75, alignment: .leading)

            Spacer()

            // 金額内訳
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.payment.formatted())円")
                    .font(Theme.numericSmall(13))
                HStack(spacing: 4) {
                    Text("元金\(entry.principalPart.formatted())")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textMuted)
                    Text("利息\(entry.interestPart.formatted())")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text("残\(entry.balance.formatted())")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
            }

            // 操作ボタン
            VStack(spacing: 6) {
                Button {
                    store.markAsPaid(loanID: loanID, month: entry.month)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                Button {
                    overdueMonth = entry.month
                    showOverdueAlert = true
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.negative.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 30)
        }
        .padding(.vertical, 2)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.numericSmall(14))
        }
    }
}

// MARK: - 繰上返済シート

struct PrepaymentSheet: View {
    let loanID: UUID
    @ObservedObject private var store = PortfolioStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var type: PortfolioStore.PrepaymentType = .shortenTerm

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("金額（円）", text: $amount)
                        .keyboardType(.numberPad)
                } header: {
                    Text("繰上返済額")
                }

                Section {
                    Picker("繰上返済方式", selection: $type) {
                        Text("期間短縮型").tag(PortfolioStore.PrepaymentType.shortenTerm)
                        Text("返済額軽減型").tag(PortfolioStore.PrepaymentType.reducePayment)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("方式")
                } footer: {
                    Text(type == .shortenTerm
                         ? "月額返済額はそのまま、返済期間を短縮します。総利息の削減効果が大きい方式です。"
                         : "返済期間はそのまま、月額返済額を軽減します。毎月の負担を減らしたい場合に適しています。")
                    .font(.caption2)
                }

                Section {
                    Button {
                        if let val = Int(amount), val > 0 {
                            store.prepay(loanID: loanID, amount: val, type: type)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("繰上返済を実行").font(.headline).foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.accent)
                }
            }
            .navigationTitle("繰上返済")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 条件変更シート

struct RescheduleSheet: View {
    let loanID: UUID
    @ObservedObject private var store = PortfolioStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newRate = ""
    @State private var newTermYears = ""

    private var currentLoan: PortfolioLoan? {
        store.loans.first(where: { $0.id == loanID })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loan = currentLoan {
                    Section {
                        HStack {
                            Text("金利"); Spacer()
                            Text(String(format: "%.3f%%", loan.condition.annualRate)).foregroundStyle(Theme.textMuted)
                        }
                        HStack {
                            Text("残り回数"); Spacer()
                            Text("\(loan.remainingPayments)回").foregroundStyle(Theme.textMuted)
                        }
                    } header: {
                        Text("現在の条件")
                    }
                }

                Section {
                    HStack {
                        Text("新金利"); Spacer()
                        TextField("変更なし", text: $newRate)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("％").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("新返済期間"); Spacer()
                        TextField("変更なし", text: $newTermYears)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60)
                        Text("年").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("新しい条件")
                } footer: {
                    Text("過去の支払い実績は変更されません。未来の返済予定のみ新条件で再計算されます。").font(.caption2)
                }

                Section {
                    Button {
                        let rate = Double(newRate); let years = Int(newTermYears)
                        if rate != nil || years != nil {
                            store.reschedule(loanID: loanID, newRate: rate, newTermYears: years)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("条件変更を実行").font(.headline).foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.info)
                }
            }
            .navigationTitle("条件変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
