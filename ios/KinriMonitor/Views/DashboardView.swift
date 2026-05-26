import SwiftUI
import Charts

struct DashboardView: View {
    @State private var rates: [LatestRate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedHistory: RateHistory?
    @State private var selectedKey: String?
    @State private var selectedChartPoint: ChartDataPoint?

    struct ChartDataPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let value: Double
        let label: String
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ── ヒーローカード ──
                heroCard
                    .padding(.horizontal)

                if let error = errorMessage {
                    ContentUnavailableView {
                        Label("データ取得エラー", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("再読み込み") { Task { await loadRates() } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                    }
                } else {
                    // チャート
                    if let history = selectedHistory {
                        chartSection(history)
                    }

                    // 金利カード一覧
                    rateCardsSection
                }

                // フッター
                Text("データ出典：日本銀行 時系列統計データ検索サイト")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.bottom, 8)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ダッシュボード")
        .refreshable { await loadRates() }
        .task { await loadRates() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("市場金利モニター")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))

                    if let main = rates.first(where: { $0.key == "LENDING_NEW_TOTAL_DOMESTIC" }),
                       let latest = main.latest {
                        Text(String(format: "%.3f", latest.value))
                            .font(Theme.numericLarge(36))
                            .foregroundStyle(.white)
                        + Text("%")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))

                        Text("新規貸出金利（国内銀行・総合）")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    } else if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }
                Spacer()

                if let main = rates.first(where: { $0.key == "LENDING_NEW_TOTAL_DOMESTIC" }),
                   let change = main.change {
                    VStack(spacing: 4) {
                        Image(systemName: change > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(String(format: "%+.3f", change))
                            .font(Theme.numericSmall(13))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("前月比")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // ミニ指標バー
            if !rates.isEmpty {
                Divider().overlay(Color.white.opacity(0.2))
                HStack(spacing: 0) {
                    miniIndicator("コールO/N", key: "CALL_RATE_ON_AVG")
                    miniDivider
                    miniIndicator("基準貸付", key: "BASE_RATE")
                    miniDivider
                    miniIndicator("ストック", key: "LENDING_STOCK_TOTAL")
                }
            }
        }
        .padding(18)
        .background(Theme.navyGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Theme.navy.opacity(0.3), radius: 12, y: 6)
    }

    private func miniIndicator(_ label: String, key: String) -> some View {
        let rate = rates.first(where: { $0.key == key })
        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            if let v = rate?.latest?.value {
                Text(String(format: "%.3f%%", v))
                    .font(Theme.numericSmall(12))
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                Text("--")
                    .font(Theme.numericSmall(12))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var miniDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1, height: 28)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chartSection(_ history: RateHistory) -> some View {
        let points = chartDataPoints(from: history)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(history.label)
                        .font(.system(size: 14, weight: .bold))
                    Text("過去24ヶ月推移")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if let sel = selectedChartPoint {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.3f%%", sel.value))
                            .font(Theme.numericMedium(20))
                            .foregroundStyle(Theme.accent)
                        Text(sel.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }

            Chart(points) { point in
                LineMark(
                    x: .value("日付", point.date),
                    y: .value("金利", point.value)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("日付", point.date),
                    y: .value("金利", point.value)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [Theme.accent.opacity(0.2), Theme.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                if let sel = selectedChartPoint, sel.date == point.date {
                    PointMark(
                        x: .value("日付", point.date),
                        y: .value("金利", point.value)
                    )
                    .foregroundStyle(Theme.accent)
                    .symbolSize(50)

                    RuleMark(x: .value("日付", point.date))
                        .foregroundStyle(Theme.accent.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: xAxisStride(count: points.count))) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Theme.textMuted.opacity(0.3))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisLabel(date))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                        .foregroundStyle(Theme.textMuted.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.2f", v))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let x = drag.location.x - geo[proxy.plotFrame!].origin.x
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    if let closest = points.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }) {
                                        selectedChartPoint = closest
                                    }
                                }
                        )
                }
            }
            .frame(height: 200)
        }
        .cardStyle()
        .padding(.horizontal)
    }

    // MARK: - Rate Cards

    private var rateCardsSection: some View {
        VStack(spacing: 10) {
            FinSectionHeader("貸出約定平均金利（新規）", icon: "building.columns")
                .padding(.horizontal)
            ForEach(rates.filter { $0.key.hasPrefix("LENDING_NEW") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }
            .padding(.horizontal)

            FinSectionHeader("貸出約定平均金利（ストック）", icon: "banknote")
                .padding(.horizontal)
            ForEach(rates.filter { $0.key.hasPrefix("LENDING_STOCK") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }
            .padding(.horizontal)

            FinSectionHeader("政策金利・市場金利", icon: "chart.xyaxis.line")
                .padding(.horizontal)
            ForEach(rates.filter { !$0.key.hasPrefix("LENDING") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Chart Helpers

    private func chartDataPoints(from history: RateHistory) -> [ChartDataPoint] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "ja_JP")
        let labelFormatter = DateFormatter()
        labelFormatter.dateFormat = "yyyy年M月"
        labelFormatter.locale = Locale(identifier: "ja_JP")

        return history.data.compactMap { dp in
            guard let value = dp.value, let date = formatter.date(from: dp.date) else { return nil }
            return ChartDataPoint(date: date, value: value, label: labelFormatter.string(from: date))
        }
    }

    private func xAxisStride(count: Int) -> Int {
        if count <= 6 { return 1 }
        if count <= 12 { return 2 }
        if count <= 24 { return 4 }
        return 6
    }

    private func formatAxisLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let year = cal.component(.year, from: date)
        if month == 1 || month == 4 || month == 7 || month == 10 {
            return "\(year)/\(month)"
        }
        return "\(month)月"
    }

    // MARK: - Actions

    private func loadRates() async {
        isLoading = true
        errorMessage = nil
        do {
            rates = try await APIClient.shared.fetchLatestRates()
            if selectedKey == nil, let first = rates.first {
                selectRate(first.key)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func selectRate(_ key: String) {
        selectedKey = key
        selectedChartPoint = nil
        Task {
            do {
                selectedHistory = try await APIClient.shared.fetchHistory(key: key)
            } catch {}
        }
    }
}
