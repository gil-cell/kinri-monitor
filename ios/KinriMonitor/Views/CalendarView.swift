import SwiftUI

struct CalendarView: View {
    @ObservedObject private var portfolio = PortfolioStore.shared
    @State private var displayedMonth = Date()
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 月ナビゲーション
                monthNavigator
                    .padding(.horizontal)

                // 曜日ヘッダー + カレンダーグリッド
                calendarGrid
                    .padding(.horizontal)

                // 選択日の支払い詳細
                if let date = selectedDate {
                    let items = paymentsFor(date: date)
                    if !items.isEmpty {
                        selectedDateDetail(date: date, items: items)
                            .padding(.horizontal)
                    }
                }

                // 今月の支払いサマリー
                monthlySummary
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("カレンダー")
    }

    // MARK: - 月ナビゲーション

    private var monthNavigator: some View {
        HStack {
            Button {
                moveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Spacer()

            Text(monthYearString(displayedMonth))
                .font(.system(size: 18, weight: .bold))

            Spacer()

            Button {
                moveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - カレンダーグリッド

    private var calendarGrid: some View {
        VStack(spacing: 0) {
            // 曜日ヘッダー
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(day == "日" ? Theme.negative : day == "土" ? Theme.info : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .background(Theme.bgCard)

            Divider()

            // 日付グリッド
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear
                            .frame(height: 64)
                    }
                }
            }
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let payments = paymentsFor(date: date)
        let hasPayment = !payments.isEmpty
        let totalAmount = payments.reduce(0) { $0 + $1.amount }

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 2) {
                // 日付
                Text("\(day)")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? .white :
                        isToday ? Theme.accent :
                        Theme.textPrimary
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? Theme.accent : isToday ? Theme.accent.opacity(0.12) : .clear)
                    )

                // 支払いインジケーター
                if hasPayment {
                    Text(shortAmount(totalAmount))
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.negative)
                        .lineLimit(1)
                } else {
                    Text(" ")
                        .font(.system(size: 8))
                }

                // ドットインジケーター
                HStack(spacing: 2) {
                    ForEach(payments.prefix(3), id: \.loanName) { p in
                        Circle()
                            .fill(chartColor(for: p.loanName))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 選択日の詳細

    private func selectedDateDetail(date: Date, items: [PaymentItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fullDateString(date))
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                let total = items.reduce(0) { $0 + $1.amount }
                Text("合計 \(total.formatted())円")
                    .font(Theme.numericMedium(16))
                    .foregroundStyle(Theme.negative)
            }

            ForEach(items, id: \.loanName) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(chartColor(for: item.loanName))
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.loanName)
                            .font(.system(size: 13, weight: .semibold))
                        Text("元金 \(item.principal.formatted())円 / 利息 \(item.interest.formatted())円")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                    }

                    Spacer()

                    Text(item.amount.formatted() + "円")
                        .font(Theme.numericSmall(14))

                    // ステータスバッジ
                    if item.isPaid {
                        BadgeView(text: "済", color: Theme.positive)
                    } else if item.isOverdue {
                        BadgeView(text: "延滞", color: Theme.negative)
                    }
                }
                .padding(10)
                .background(Theme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .cardStyle()
    }

    // MARK: - 月間サマリー

    private var monthlySummary: some View {
        let items = paymentsForMonth(displayedMonth)
        let total = items.reduce(0) { $0 + $1.amount }
        let paid = items.filter(\.isPaid).reduce(0) { $0 + $1.amount }
        let remaining = total - paid

        return VStack(alignment: .leading, spacing: 10) {
            Text("今月の返済予定")
                .font(.system(size: 14, weight: .bold))

            HStack(spacing: 0) {
                summaryItem("支払い予定", value: "\(total.formatted())円", color: Theme.textPrimary)
                Divider().frame(height: 30)
                summaryItem("支払い済み", value: "\(paid.formatted())円", color: Theme.positive)
                Divider().frame(height: 30)
                summaryItem("残り", value: "\(remaining.formatted())円", color: remaining > 0 ? Theme.negative : Theme.positive)
            }

            // ローン別内訳
            let grouped = Dictionary(grouping: items, by: \.loanName)
            ForEach(Array(grouped.keys.sorted()), id: \.self) { name in
                let loanItems = grouped[name]!
                let loanTotal = loanItems.reduce(0) { $0 + $1.amount }
                HStack {
                    Circle()
                        .fill(chartColor(for: name))
                        .frame(width: 8, height: 8)
                    Text(name)
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(loanTotal.formatted())円")
                        .font(Theme.numericSmall(12))
                }
            }
        }
        .cardStyle()
    }

    private func summaryItem(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(Theme.numericSmall(13))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    struct PaymentItem {
        let loanName: String
        let amount: Int
        let principal: Int
        let interest: Int
        let isPaid: Bool
        let isOverdue: Bool
    }

    private func paymentsFor(date: Date) -> [PaymentItem] {
        var items: [PaymentItem] = []
        for loan in portfolio.loans {
            // 支払済み
            for p in loan.payments where calendar.isDate(p.dueDate, inSameDayAs: date) {
                items.append(PaymentItem(
                    loanName: loan.name, amount: p.amount,
                    principal: p.principalPart, interest: p.interestPart,
                    isPaid: p.status == .paid, isOverdue: p.status == .overdue
                ))
            }
            // 未払いスケジュール
            for s in loan.schedule where !s.isPaid && calendar.isDate(s.dueDate, inSameDayAs: date) {
                // 既に payments に記録済みならスキップ
                let alreadyRecorded = loan.payments.contains { $0.month == s.month }
                if !alreadyRecorded {
                    items.append(PaymentItem(
                        loanName: loan.name, amount: s.payment,
                        principal: s.principalPart, interest: s.interestPart,
                        isPaid: false, isOverdue: false
                    ))
                }
            }
        }
        return items
    }

    private func paymentsForMonth(_ date: Date) -> [PaymentItem] {
        let range = calendar.range(of: .day, in: .month, for: date)!
        let comps = calendar.dateComponents([.year, .month], from: date)
        var items: [PaymentItem] = []
        for day in range {
            var dc = comps
            dc.day = day
            if let d = calendar.date(from: dc) {
                items.append(contentsOf: paymentsFor(date: d))
            }
        }
        return items
    }

    // MARK: - Calendar Helpers

    private func daysInMonth() -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstDay = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDay) - 1 // 0=Sunday
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)

        for day in range {
            var dc = comps
            dc.day = day
            days.append(calendar.date(from: dc))
        }

        // 末尾を7の倍数に
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }

    private func moveMonth(_ offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = newDate
                selectedDate = nil
            }
        }
    }

    private func monthYearString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年 M月"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }

    private func fullDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日（E）"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }

    private func shortAmount(_ amount: Int) -> String {
        if amount >= 10_000 {
            return String(format: "%.0f万", Double(amount) / 10_000)
        }
        return "\(amount / 1000)千"
    }

    private let colorPalette: [Color] = [
        Theme.accent, Theme.info, Theme.warning, Theme.negative,
        .purple, .cyan, .mint, .indigo
    ]

    private func chartColor(for name: String) -> Color {
        let index = portfolio.loans.firstIndex(where: { $0.name == name }) ?? 0
        return colorPalette[index % colorPalette.count]
    }
}
