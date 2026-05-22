import SwiftUI
import Charts

struct DashboardView: View {
    @State private var rates: [LatestRate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedHistory: RateHistory?
    @State private var selectedKey: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // ヘッダー
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("市場金利")
                            .font(.title2.bold())
                        Text("日本銀行 時系列統計データ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    ContentUnavailableView {
                        Label("データ取得エラー", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("再読み込み") { Task { await loadRates() } }
                    }
                } else {
                    // チャート（選択中の系列）
                    if let history = selectedHistory {
                        chartSection(history)
                    }

                    // 金利カード一覧
                    rateCardsSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("ダッシュボード")
        .refreshable { await loadRates() }
        .task { await loadRates() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func chartSection(_ history: RateHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(history.label)
                .font(.headline)
                .padding(.horizontal)

            let dataPoints = history.data.compactMap { dp -> (String, Double)? in
                guard let v = dp.value else { return nil }
                return (dp.date, v)
            }

            Chart(dataPoints, id: \.0) { point in
                LineMark(
                    x: .value("日付", point.0),
                    y: .value("金利", point.1)
                )
                .foregroundStyle(.blue)

                AreaMark(
                    x: .value("日付", point.0),
                    y: .value("金利", point.1)
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
            .chartYAxisLabel("年％")
            .frame(height: 200)
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var rateCardsSection: some View {
        LazyVStack(spacing: 10) {
            // 中核金利
            sectionHeader("貸出約定平均金利（新規）")
            ForEach(rates.filter { $0.key.hasPrefix("LENDING_NEW") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }

            sectionHeader("貸出約定平均金利（ストック）")
            ForEach(rates.filter { $0.key.hasPrefix("LENDING_STOCK") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }

            sectionHeader("政策金利・市場金利")
            ForEach(rates.filter { !$0.key.hasPrefix("LENDING") }) { rate in
                RateCardView(rate: rate, isSelected: selectedKey == rate.key) {
                    selectRate(rate.key)
                }
            }
        }
        .padding(.horizontal)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func loadRates() async {
        isLoading = true
        errorMessage = nil
        do {
            rates = try await APIClient.shared.fetchLatestRates()
            // デフォルトで最初の系列を選択
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
        Task {
            do {
                selectedHistory = try await APIClient.shared.fetchHistory(key: key)
            } catch {
                // チャートはエラーでも金利カードは表示し続ける
            }
        }
    }
}
