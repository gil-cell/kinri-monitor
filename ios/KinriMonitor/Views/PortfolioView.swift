import SwiftUI
import Charts

struct PortfolioView: View {
    @ObservedObject private var store = PortfolioStore.shared
    @State private var selectedLoan: PortfolioLoan?

    var body: some View {
        Group {
            if store.loans.isEmpty {
                ContentUnavailableView {
                    Label("ポートフォリオなし", systemImage: "chart.pie")
                } description: {
                    Text("ローン管理から「契約済み」にしたローンがここに表示されます。")
                }
            } else {
                List {
                    // サマリーカード
                    Section {
                        summaryCard
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    // 円グラフ
                    Section {
                        pieChartCard
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                    // ローンカード一覧（スワイプ削除対応）
                    Section {
                        ForEach(store.loans) { loan in
                            Button {
                                selectedLoan = loan
                            } label: {
                                portfolioLoanCard(loan)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            store.deleteLoan(at: offsets)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $selectedLoan) { loan in
            PortfolioDetailView(loanID: loan.id)
        }
    }

    // MARK: - サマリーカード

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("借入残高合計")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(store.totalRemainingPrincipal.formatted() + "円")
                        .font(Theme.numericLarge(28))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("月間返済額")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(store.totalMonthlyPayment.formatted() + "円")
                        .font(Theme.numericMedium(16))
                        .foregroundStyle(.white)
                }
            }

            Divider().overlay(Color.white.opacity(0.2))

            HStack {
                miniStat("ローン数", value: "\(store.loans.count)件")
                Spacer()
                miniStat("返済済み", value: store.totalPaid.formatted() + "円")
                Spacer()
                miniStat("利息累計", value: store.totalInterestPaid.formatted() + "円")
            }
        }
        .padding(18)
        .background(Theme.navyGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.navy.opacity(0.3), radius: 10, y: 4)
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(Theme.numericSmall(11))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - 円グラフ

    private let chartColors: [Color] = [
        Theme.accent, Theme.info, Theme.warning, Theme.negative,
        .purple, .cyan, .mint, .indigo
    ]

    private var pieChartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ローン内訳")
                .font(.system(size: 14, weight: .bold))

            Chart(store.loans) { loan in
                SectorMark(
                    angle: .value("残高", loan.remainingPrincipal),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(by: .value("名称", loan.name))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(
                domain: store.loans.map(\.name),
                range: Array(chartColors.prefix(store.loans.count))
            )
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 200)
        }
        .cardStyle()
    }

    // MARK: - ローンカード

    private func portfolioLoanCard(_ loan: PortfolioLoan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loan.name)
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(String(format: "%.2f%%", loan.condition.annualRate))
                    .font(Theme.numericMedium(16))
                    .foregroundStyle(Theme.accent)
            }

            // プログレスバー
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * min(loan.progressRatio / 100, 1), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(String(format: "%.1f%% 返済済み", loan.progressRatio))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Text("残り\(loan.remainingPayments)回")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            HStack(spacing: 16) {
                statItem("残高", value: "\(loan.remainingPrincipal.formatted())円")
                statItem("月額", value: "\(loan.schedule.first(where: { !$0.isPaid })?.payment.formatted() ?? "-")円")
                statItem("利息累計", value: "\(loan.totalInterestPaid.formatted())円")
            }
        }
        .cardStyle()
    }

    private func statItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(Theme.textMuted)
            Text(value).font(Theme.numericSmall(12))
        }
    }
}
