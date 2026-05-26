import SwiftUI

struct SimulationView: View {
    @ObservedObject private var store = LoanStore.shared
    @State private var repayment: RepaymentResponse?
    @State private var deviation: DeviationResult?
    @State private var scenarios: [SimulationScenario] = []
    @State private var isLoading = false
    @State private var hasRun = false
    @State private var showSchedule = false
    @State private var showShareSheet = false
    @State private var shareText = ""
    @State private var showSaveAlert = false
    @State private var saveName = ""
    @FocusState private var focusedField: Bool
    @State private var exportFileURL: URL?
    @State private var showExportShare = false

    var body: some View {
        List {
            // ── 借入条件入力 ──
            Section {
                HStack {
                    Text("総額")
                    Spacer()
                    TextField("", value: $store.condition.totalAmount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                        .focused($focusedField)
                    Text("円")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("頭金")
                    Spacer()
                    TextField("", value: $store.condition.downPayment, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                        .focused($focusedField)
                    Text("円")
                        .foregroundStyle(.secondary)
                }

                // 借入額（自動計算）
                HStack {
                    Text("借入額")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(store.condition.principal.formatted() + "円")
                        .font(Theme.numericMedium(16))
                        .foregroundStyle(Theme.accent)
                }
                if store.condition.downPayment > 0 {
                    HStack {
                        Text("頭金比率")
                        Spacer()
                        Text(String(format: "%.1f%%", store.condition.downPaymentRatio))
                            .font(Theme.numericSmall())
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                HStack {
                    Text("金利（年利）")
                    Spacer()
                    TextField("", value: $store.condition.annualRate, format: .number.precision(.fractionLength(1...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($focusedField)
                    Text("％")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("返済期間")
                    Spacer()
                    TextField("", value: $store.condition.termYears, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($focusedField)
                    Text("年")
                        .foregroundStyle(.secondary)
                }

                Picker("比較対象", selection: $store.condition.bankType) {
                    ForEach(LoanCondition.BankType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
            } header: {
                Text("借入条件")
            } footer: {
                Text("借入額は「総額 − 頭金」で自動計算されます。入力データは端末内にのみ保存されます。")
                    .font(.caption2)
            }

            // ── 実行ボタン ──
            Section {
                Button {
                    focusedField = false
                    Task { await runAll() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("計算・シミュレーション実行", systemImage: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .foregroundStyle(.white)
                }
                .listRowBackground(Theme.accent)
                .disabled(isLoading)
            }

            if hasRun {
                // ── 返済結果 ──
                if let r = repayment {
                    Section("元利均等返済") {
                        resultRow("月額返済額", value: r.equalPayment.monthlyFirst)
                        resultRow("年間返済額", value: r.equalPayment.annualPayment)
                        resultRow("利息総額", value: r.equalPayment.totalInterest)
                        resultRow("返済総額", value: r.equalPayment.totalPayment)
                    }

                    Section("元金均等返済") {
                        resultRow("初月返済額", value: r.equalPrincipal.monthlyFirst)
                        resultRow("最終月返済額", value: r.equalPrincipal.monthlyLast)
                        resultRow("利息総額", value: r.equalPrincipal.totalInterest)
                        resultRow("返済総額", value: r.equalPrincipal.totalPayment)
                    }
                }

                // ── 乖離診断 ──
                if let d = deviation {
                    Section("市場平均との乖離診断") {
                        HStack {
                            Text("市場平均")
                            Spacer()
                            Text(String(format: "%.3f%%", d.marketRate))
                                .font(.system(.body, design: .rounded).bold())
                        }
                        HStack {
                            Text("お借入金利")
                            Spacer()
                            Text(String(format: "%.3f%%", d.userRate))
                                .font(.system(.body, design: .rounded).bold())
                        }
                        HStack {
                            Text("乖離")
                            Spacer()
                            Text(String(format: "%+.3f%% (%+dbp)", d.deviation, d.deviationBps))
                                .font(.system(.body, design: .rounded).bold())
                                .foregroundStyle(d.deviationBps > 30 ? .red : d.deviationBps < -30 ? .green : .primary)
                        }
                        if d.annualDifference > 0 {
                            HStack {
                                Text("年間差額")
                                Spacer()
                                Text("約\(d.annualDifference.formatted())円")
                                    .font(.system(.body, design: .rounded).bold())
                            }
                        }
                        Text(d.comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // ── 金利上昇シミュレーション ──
                Section {
                    // ヘッダーカード
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Theme.negative)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("金利が上がったらどうなる？")
                                    .font(.system(size: 14, weight: .bold))
                                Text("将来の金利上昇に備えて、返済額の変化を確認できます")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                    ForEach(scenarios) { scenario in
                        VStack(spacing: 10) {
                            // シナリオヘッダー
                            HStack {
                                Text("金利が")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                Text("+\(String(format: "%.2f", scenario.rateIncrease))%")
                                    .font(Theme.numericMedium(16))
                                    .foregroundStyle(Theme.negative)
                                Text("上昇した場合")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                BadgeView(text: String(format: "%.2f%%", scenario.newRate), color: Theme.negative)
                            }

                            Divider()

                            // 数値グリッド
                            HStack(spacing: 0) {
                                impactItem(
                                    label: "月額返済額",
                                    value: scenario.equalPayment.monthlyFirst.formatted() + "円",
                                    change: "+\(scenario.monthlyIncrease.formatted())円"
                                )
                                dividerLine
                                impactItem(
                                    label: "年間増加額",
                                    value: "+\(scenario.annualIncrease.formatted())円",
                                    change: nil
                                )
                                if let base = repayment {
                                    dividerLine
                                    let totalIncrease = scenario.equalPayment.totalPayment - base.equalPayment.totalPayment
                                    impactItem(
                                        label: "返済総額増加",
                                        value: "+\(totalIncrease.formatted())円",
                                        change: nil
                                    )
                                }
                            }
                        }
                        .padding(12)
                        .background(Theme.negative.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } header: {
                    Text("金利上昇シミュレーション")
                } footer: {
                    Text("将来の金利を保証するものではありません。あくまで参考としてご活用ください。")
                        .font(.caption2)
                }

                // ── 管理に保存（強調） ──
                Section {
                    Button {
                        saveName = ""
                        showSaveAlert = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Theme.info)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("この条件を管理に保存")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("保存した条件はポートフォリオで管理・比較できます")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                // ── その他アクション ──
                Section {
                    Button {
                        showSchedule = true
                    } label: {
                        Label("返済明細一覧を表示", systemImage: "list.number")
                    }

                    if let d = deviation, let r = repayment {
                        Button {
                            shareText = ShareService.generateSummary(
                                condition: store.condition, deviation: d, repayment: r
                            )
                            showShareSheet = true
                        } label: {
                            Label("比較サマリーを共有", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("アクション")
                }

                // ── エクスポート ──
                Section {
                    Button { exportPDF() } label: {
                        Label("PDF出力", systemImage: "doc.richtext")
                    }
                    Button { exportCSV() } label: {
                        Label("CSV出力（Excel対応）", systemImage: "tablecells")
                    }
                } header: {
                    Text("エクスポート")
                }
            }
        }
        .navigationTitle("シミュレーション")
        .sheet(isPresented: $showSchedule) {
            RepaymentScheduleView(condition: store.condition)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(text: shareText)
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportFileURL {
                FileShareSheet(url: url)
            }
        }
        .alert("ローンに名前をつけて保存", isPresented: $showSaveAlert) {
            TextField("例: A銀行 運転資金", text: $saveName)
            Button("保存") {
                let name = saveName.isEmpty ? "ローン \(store.savedLoans.count + 1)" : saveName
                store.saveLoan(name: name)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(store.condition.principal.formatted())円 / \(String(format: "%.2f", store.condition.annualRate))% / \(store.condition.termYears)年")
        }
    }

    // MARK: - Helpers

    // MARK: - Scenario Helpers

    private func impactItem(label: String, value: String, change: String?) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.numericSmall(12))
                .foregroundStyle(Theme.negative)
            if let change {
                Text(change)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.negative.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Theme.textMuted.opacity(0.2))
            .frame(width: 1, height: 36)
    }

    private func resultRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.formatted() + "円")
                .font(.system(.body, design: .rounded))
        }
    }

    private func runAll() async {
        isLoading = true
        do {
            repayment = try await APIClient.shared.calcRepayment(condition: store.condition)
            scenarios = try await APIClient.shared.calcSimulation(condition: store.condition)

            let rates = try await APIClient.shared.fetchLatestRates()
            if let market = rates.first(where: { $0.key == store.condition.bankType.rawValue })?.latest?.value {
                deviation = try await APIClient.shared.calcDeviation(
                    userRate: store.condition.annualRate,
                    marketRate: market,
                    principal: store.condition.principal,
                    termYears: store.condition.termYears
                )
            }
            hasRun = true
        } catch {
            // エラーは静かに処理
        }
        isLoading = false
    }

    private func exportPDF() {
        if let url = ExportService.generatePDF(
            condition: store.condition,
            repayment: repayment,
            scenarios: scenarios,
            deviation: deviation
        ) {
            exportFileURL = url
            showExportShare = true
        }
    }

    private func exportCSV() {
        if let url = ExportService.generateCSV(
            condition: store.condition,
            repayment: repayment,
            scenarios: scenarios
        ) {
            exportFileURL = url
            showExportShare = true
        }
    }
}
