import SwiftUI

struct SimulationView: View {
    @ObservedObject private var store = LoanStore.shared
    @State private var scenarios: [SimulationScenario] = []
    @State private var isLoading = false
    @State private var hasRun = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("現在の借入条件")
                        .font(.subheadline.bold())
                    HStack {
                        infoChip("借入額", value: "\(store.condition.principal.formatted())円")
                        infoChip("金利", value: String(format: "%.2f%%", store.condition.annualRate))
                        infoChip("期間", value: "\(store.condition.termYears)年")
                    }
                }
                .padding(.vertical, 4)

                Button {
                    Task { await runSimulation() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("シミュレーション実行", systemImage: "play.fill")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isLoading)
            } header: {
                Text("金利上昇シミュレーション")
            } footer: {
                Text("金利が上昇した場合に、返済額がどれだけ増えるかを試算します。将来の金利を保証するものではありません。")
                    .font(.caption2)
            }

            if hasRun {
                ForEach(scenarios) { scenario in
                    Section("+\(String(format: "%.2f", scenario.rateIncrease))% → \(String(format: "%.2f", scenario.newRate))%") {
                        HStack {
                            Text("月額返済額")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(scenario.equalPayment.monthlyFirst.formatted() + "円")
                                    .font(.system(.body, design: .rounded).bold())
                                Text("+\(scenario.monthlyIncrease.formatted())円/月")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        HStack {
                            Text("年間返済額増加")
                            Spacer()
                            Text("+\(scenario.annualIncrease.formatted())円")
                                .font(.system(.body, design: .rounded).bold())
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Text("利息総額")
                            Spacer()
                            Text(scenario.equalPayment.totalInterest.formatted() + "円")
                                .font(.system(.body, design: .rounded))
                        }
                    }
                }
            }
        }
        .navigationTitle("シミュレーション")
    }

    private func infoChip(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runSimulation() async {
        isLoading = true
        do {
            scenarios = try await APIClient.shared.calcSimulation(condition: store.condition)
            hasRun = true
        } catch {
            // Phase 5で強化
        }
        isLoading = false
    }
}
