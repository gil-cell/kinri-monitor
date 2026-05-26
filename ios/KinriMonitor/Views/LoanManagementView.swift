import SwiftUI

struct LoanManagementView: View {
    @ObservedObject private var store = LoanStore.shared
    @ObservedObject private var portfolio = PortfolioStore.shared
    @State private var editingLoan: SavedLoan?
    @State private var editName = ""
    @State private var selectedLoan: SavedLoan?
    @State private var contractTarget: SavedLoan?
    @State private var selectedTab = 0

    /// ポートフォリオに登録済みかどうか
    private func isContracted(_ loan: SavedLoan) -> Bool {
        portfolio.loans.contains { $0.name == loan.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("ローン管理").tag(0)
                Text("ポートフォリオ").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                loanManagementContent
            } else {
                PortfolioView()
            }
        }
        .navigationTitle(selectedTab == 0 ? "ローン管理" : "ポートフォリオ")
        .sheet(item: $contractTarget) { loan in
            ContractSheet(loan: loan) {
                selectedTab = 1
            }
        }
        .alert("名前を変更", isPresented: Binding(
            get: { editingLoan != nil },
            set: { if !$0 { editingLoan = nil } }
        )) {
            TextField("ローン名", text: $editName)
            Button("保存") {
                if let loan = editingLoan {
                    store.renameLoan(loan, to: editName)
                }
                editingLoan = nil
            }
            Button("キャンセル", role: .cancel) { editingLoan = nil }
        }
        .sheet(item: $selectedLoan) { loan in
            LoanDetailSheet(loan: loan)
        }
    }

    // MARK: - ローン管理コンテンツ

    @ViewBuilder
    private var loanManagementContent: some View {
        if store.savedLoans.isEmpty {
            ContentUnavailableView {
                Label("保存済みローンなし", systemImage: "tray")
            } description: {
                Text("シミュレーション画面で「この条件を管理に保存」を選ぶと、ここに追加されます。")
            }
        } else {
            List {
                ForEach(store.savedLoans) { loan in
                    let contracted = isContracted(loan)

                    VStack(spacing: 0) {
                        // ステータスバー
                        HStack(spacing: 6) {
                            Image(systemName: contracted ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 14))
                                .foregroundStyle(contracted ? Theme.accent : Theme.textMuted)
                            Text(contracted ? "契約済み" : "計画")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(contracted ? Theme.accent : Theme.textMuted)
                            Spacer()
                            Text(loan.savedAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.bottom, 6)

                        // カード本体
                        Button {
                            selectedLoan = loan
                        } label: {
                            LoanCardRow(loan: loan)
                        }
                        .buttonStyle(.plain)

                        // アクションバー
                        HStack(spacing: 12) {
                            Button {
                                store.loadCondition(from: loan)
                            } label: {
                                Label("読み込み", systemImage: "arrow.up.doc")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.info)

                            Spacer()

                            if contracted {
                                // 契約済み表示
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                    Text("ポートフォリオに登録済み")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(Theme.accent)
                            } else {
                                // 返済開始日を入力して契約
                                Button {
                                    contractTarget = loan
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar.badge.plus")
                                            .font(.system(size: 12))
                                        Text("返済開始日を入力して契約")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteLoan(loan)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        Button {
                            editingLoan = loan
                            editName = loan.name
                        } label: {
                            Label("名前変更", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete { offsets in
                    store.deleteLoan(at: offsets)
                }
            }
        }
    }
}

// MARK: - 契約シート（返済開始日を入力してポートフォリオ追加）

struct ContractSheet: View {
    let loan: SavedLoan
    let onComplete: () -> Void

    @ObservedObject private var portfolio = PortfolioStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var startDate = Date()
    @State private var method: PortfolioLoan.RepaymentMethod = .equalPayment
    @State private var penaltyRate = "14.6"

    private var paymentDay: Int {
        Calendar.current.component(.day, from: startDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // ローン概要
                Section {
                    HStack {
                        Text("ローン名")
                        Spacer()
                        Text(loan.name)
                            .font(.system(.body, design: .rounded).bold())
                    }
                    HStack {
                        Text("借入額")
                        Spacer()
                        Text("\(loan.condition.principal.formatted())円")
                            .font(Theme.numericSmall(14))
                    }
                    HStack {
                        Text("金利")
                        Spacer()
                        Text(String(format: "%.3f%%", loan.condition.annualRate))
                            .font(Theme.numericSmall(14))
                    }
                    HStack {
                        Text("期間")
                        Spacer()
                        Text("\(loan.condition.termYears)年")
                            .font(Theme.numericSmall(14))
                    }
                } header: {
                    Text("ローン概要")
                }

                // 返済開始日
                Section {
                    DatePicker(
                        "返済開始日",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)

                    // 自動判定された毎月の支払日
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.info)
                        Text("毎月の支払日：\(paymentDay)日")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text("（返済開始日から自動設定）")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                    }
                } header: {
                    Text("返済開始日")
                } footer: {
                    Text("返済開始日を選択すると、毎月の支払日が自動で設定されます。ここから返済スケジュールが生成されます。")
                        .font(.caption2)
                }

                // 返済方式
                Section {
                    Picker("返済方式", selection: $method) {
                        ForEach(PortfolioLoan.RepaymentMethod.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("返済方式")
                } footer: {
                    Text(method == .equalPayment
                         ? "元利均等：毎月の返済額が一定。返済計画が立てやすい方式です。"
                         : "元金均等：元金部分が一定。初期の返済額は高いが、総利息は少なくなります。")
                    .font(.caption2)
                }

                // 遅延損害金利率
                Section {
                    HStack {
                        Text("遅延損害金利率")
                        Spacer()
                        TextField("", text: $penaltyRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("％")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("その他")
                } footer: {
                    Text("延滞時の遅延損害金計算に使用します。一般的な上限は年14.6%です。")
                        .font(.caption2)
                }

                // 確定ボタン
                Section {
                    Button {
                        contract()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                            Text("契約済みとしてポートフォリオに追加")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.accent)
                }
            }
            .navigationTitle("契約設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func contract() {
        let rate = Double(penaltyRate) ?? 14.6
        let pLoan = PortfolioLoan(
            name: loan.name,
            condition: loan.condition,
            paymentDay: paymentDay,
            contractDate: startDate,
            method: method,
            penaltyRate: rate
        )
        portfolio.addLoan(pLoan)
        dismiss()
        onComplete()
    }
}

// MARK: - ローンカード行

struct LoanCardRow: View {
    let loan: SavedLoan
    private var c: LoanCondition { loan.condition }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loan.name)
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 12) {
                if c.downPayment > 0 {
                    chip("総額", value: "\(c.totalAmount.formatted())円")
                    chip("頭金", value: "\(c.downPayment.formatted())円")
                }
                chip("借入額", value: "\(c.principal.formatted())円")
                chip("金利", value: String(format: "%.2f%%", c.annualRate))
                chip("期間", value: "\(c.termYears)年")
            }

            let ep = RepaymentScheduleCalculator.equalPaymentSchedule(
                principal: c.principal, annualRate: c.annualRate, termYears: c.termYears
            )
            if let first = ep.first {
                HStack {
                    Text("月額返済額（元利均等）").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(first.payment.formatted())円").font(.system(.subheadline, design: .rounded).bold())
                }
            }
            let totalInterest = ep.reduce(0) { $0 + $1.interest }
            HStack {
                Text("利息総額").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(totalInterest.formatted())円").font(.system(.subheadline, design: .rounded)).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }
}

// MARK: - ローン詳細シート

struct LoanDetailSheet: View {
    let loan: SavedLoan
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LoanStore.shared
    @State private var selectedMethod: RepaymentScheduleView.ScheduleMethod = .equalPayment
    private var c: LoanCondition { loan.condition }

    private var schedule: [MonthlyBreakdown] {
        switch selectedMethod {
        case .equalPayment:
            return RepaymentScheduleCalculator.equalPaymentSchedule(principal: c.principal, annualRate: c.annualRate, termYears: c.termYears)
        case .equalPrincipal:
            return RepaymentScheduleCalculator.equalPrincipalSchedule(principal: c.principal, annualRate: c.annualRate, termYears: c.termYears)
        }
    }

    private var totalInterest: Int { schedule.reduce(0) { $0 + $1.interest } }

    var body: some View {
        NavigationStack {
            List {
                Section(loan.name) {
                    if c.downPayment > 0 {
                        detailRow("総額", value: "\(c.totalAmount.formatted())円")
                        detailRow("頭金", value: "\(c.downPayment.formatted())円（\(String(format: "%.1f%%", c.downPaymentRatio))）")
                    }
                    detailRow("借入額", value: "\(c.principal.formatted())円")
                    detailRow("金利", value: String(format: "%.3f%%", c.annualRate))
                    detailRow("返済期間", value: "\(c.termYears)年（\(c.termYears * 12)回）")
                    detailRow("利息総額", value: "\(totalInterest.formatted())円")
                    detailRow("返済総額", value: "\((c.principal + totalInterest).formatted())円")
                }

                Section {
                    Picker("返済方式", selection: $selectedMethod) {
                        ForEach(RepaymentScheduleView.ScheduleMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("返済明細（抜粋）") {
                    ForEach(schedule.prefix(12)) { row in scheduleRow(row) }
                    if schedule.count > 24 {
                        HStack { Spacer(); Text("… \(schedule.count - 24)件省略 …").font(.caption).foregroundStyle(.secondary); Spacer() }
                    }
                    if schedule.count > 12 {
                        ForEach(schedule.suffix(12)) { row in scheduleRow(row) }
                    }
                }

                Section {
                    Button { store.loadCondition(from: loan); dismiss() } label: {
                        Label("シミュレーションに読み込み", systemImage: "arrow.up.doc")
                    }
                }
            }
            .navigationTitle("ローン詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { dismiss() } }
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.system(.body, design: .rounded)) }
    }

    private func scheduleRow(_ row: MonthlyBreakdown) -> some View {
        HStack {
            Text("\(row.id)").frame(width: 35).font(.system(size: 11, design: .monospaced))
            Text(row.payment.formatted()).frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 11, design: .monospaced))
            Text(row.principal.formatted()).frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 11, design: .monospaced))
            Text(row.interest.formatted()).frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange)
            Text(row.balance.formatted()).frame(maxWidth: .infinity, alignment: .trailing).font(.system(size: 11, design: .monospaced))
        }
    }
}
