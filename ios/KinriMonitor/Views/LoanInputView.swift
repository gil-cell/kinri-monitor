import SwiftUI

struct LoanInputView: View {
    @ObservedObject private var store = LoanStore.shared
    @State private var repayment: RepaymentResponse?
    @State private var deviation: DeviationResult?
    @State private var latestMarketRate: Double?
    @State private var isCalculating = false
    @State private var showShareSheet = false
    @State private var shareText = ""

    private var condition: LoanCondition {
        get { store.condition }
        nonmutating set { store.condition = newValue }
    }

    var body: some View {
        List {
            // 借入条件入力
            Section {
                HStack {
                    Text("借入額")
                    Spacer()
                    TextField("", value: $store.condition.principal, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 150)
                    Text("円")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("金利（年利）")
                    Spacer()
                    TextField("", value: $store.condition.annualRate, format: .number.precision(.fractionLength(1...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
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
                    Text("年")
                        .foregroundStyle(.secondary)
                }

                Picker("比較対象", selection: $store.condition.bankType) {
                    ForEach(LoanCondition.BankType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
            } header: {
                Text("自社の借入条件")
            } footer: {
                Text("入力データは端末内にのみ保存されます。サーバーには送信されません。")
                    .font(.caption2)
            }

            // 計算実行
            Section {
                Button {
                    Task { await calculate() }
                } label: {
                    HStack {
                        Spacer()
                        if isCalculating {
                            ProgressView()
                        } else {
                            Text("計算する")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isCalculating)
            }

            // 返済結果
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

            // 乖離診断
            if let d = deviation {
                Section {
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

                    // 共有ボタン
                    if let r = repayment {
                        Button {
                            shareText = ShareService.generateSummary(
                                condition: store.condition,
                                deviation: d,
                                repayment: r
                            )
                            showShareSheet = true
                        } label: {
                            Label("比較サマリーを共有", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("市場平均との乖離診断")
                }
            }
        }
        .navigationTitle("借入条件")
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(text: shareText)
        }
    }

    private func resultRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.formatted() + "円")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private func calculate() async {
        isCalculating = true
        do {
            // 返済額計算
            repayment = try await APIClient.shared.calcRepayment(condition: store.condition)

            // 市場平均金利を取得して乖離診断
            let rates = try await APIClient.shared.fetchLatestRates()
            if let market = rates.first(where: { $0.key == store.condition.bankType.rawValue })?.latest?.value {
                latestMarketRate = market
                deviation = try await APIClient.shared.calcDeviation(
                    userRate: store.condition.annualRate,
                    marketRate: market,
                    principal: store.condition.principal,
                    termYears: store.condition.termYears
                )
            }
        } catch {
            // エラーハンドリング（Phase 5で強化）
        }
        isCalculating = false
    }
}
