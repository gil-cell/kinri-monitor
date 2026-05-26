import SwiftUI

struct RepaymentScheduleView: View {
    let condition: LoanCondition
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMethod: ScheduleMethod = .equalPayment

    enum ScheduleMethod: String, CaseIterable {
        case equalPayment = "元利均等"
        case equalPrincipal = "元金均等"
    }

    private var schedule: [MonthlyBreakdown] {
        switch selectedMethod {
        case .equalPayment:
            return RepaymentScheduleCalculator.equalPaymentSchedule(
                principal: condition.principal,
                annualRate: condition.annualRate,
                termYears: condition.termYears
            )
        case .equalPrincipal:
            return RepaymentScheduleCalculator.equalPrincipalSchedule(
                principal: condition.principal,
                annualRate: condition.annualRate,
                termYears: condition.termYears
            )
        }
    }

    private var totalInterest: Int {
        schedule.reduce(0) { $0 + $1.interest }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 条件サマリー
                VStack(spacing: 6) {
                    HStack(spacing: 16) {
                        summaryItem("借入額", value: "\(condition.principal.formatted())円")
                        summaryItem("金利", value: String(format: "%.3f%%", condition.annualRate))
                        summaryItem("期間", value: "\(condition.termYears)年（\(condition.termYears * 12)回）")
                    }
                    HStack(spacing: 16) {
                        summaryItem("利息総額", value: "\(totalInterest.formatted())円")
                        summaryItem("返済総額", value: "\((condition.principal + totalInterest).formatted())円")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))

                // 方式切り替え
                Picker("返済方式", selection: $selectedMethod) {
                    ForEach(ScheduleMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // ヘッダー
                HStack(spacing: 0) {
                    headerCell("回", width: 40)
                    headerCell("返済額", width: nil)
                    headerCell("元金", width: nil)
                    headerCell("利息", width: nil)
                    headerCell("残高", width: nil)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))

                Divider()

                // 一覧
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(schedule) { row in
                            HStack(spacing: 0) {
                                dataCell(String(row.id), width: 40, alignment: .center, highlight: false)
                                dataCell(formatYen(row.payment), width: nil, alignment: .trailing, highlight: false)
                                dataCell(formatYen(row.principal), width: nil, alignment: .trailing, highlight: false)
                                dataCell(formatYen(row.interest), width: nil, alignment: .trailing, highlight: true)
                                dataCell(formatYen(row.balance), width: nil, alignment: .trailing, highlight: false)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 5)
                            .background(row.id % 2 == 0 ? Color(.systemGroupedBackground).opacity(0.5) : Color.clear)

                            if row.id % 12 == 0 && row.id < schedule.count {
                                yearSeparator(year: row.id / 12)
                            }
                        }
                    }
                }
            }
            .navigationTitle("返済明細一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    // MARK: - Components

    private func summaryItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    private func headerCell(_ title: String, width: CGFloat?) -> some View {
        Group {
            if let w = width {
                Text(title).frame(width: w)
            } else {
                Text(title).frame(maxWidth: .infinity)
            }
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
    }

    private func dataCell(_ text: String, width: CGFloat?, alignment: Alignment, highlight: Bool) -> some View {
        Group {
            if let w = width {
                Text(text).frame(width: w, alignment: alignment)
            } else {
                Text(text).frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(highlight ? .orange : .primary)
    }

    private func yearSeparator(year: Int) -> some View {
        HStack {
            Rectangle().fill(Color.blue.opacity(0.3)).frame(height: 1)
            Text("\(year)年目終了")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .fixedSize()
            Rectangle().fill(Color.blue.opacity(0.3)).frame(height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formatYen(_ value: Int) -> String {
        if value >= 10_000_000 {
            return String(format: "%.0f万", Double(value) / 10_000.0)
        }
        return value.formatted()
    }
}
