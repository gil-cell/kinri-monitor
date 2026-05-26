import SwiftUI

// MARK: - 指標の解説データ

enum RateDescription {
    struct Info {
        let summary: String      // 一行の概要
        let detail: String       // 借入における意味
        let icon: String         // SF Symbol
        let relevance: String    // 借入との関連度（高/中/低）
    }

    static func info(for key: String) -> Info {
        switch key {
        case "LENDING_NEW_TOTAL_DOMESTIC":
            return Info(
                summary: "国内銀行が新規に実行した貸出の加重平均金利",
                detail: "自社の借入金利が「市場の相場」と比べて高いか低いかを判断するための最も基本的な指標です。この金利より大幅に高い場合、金融機関への交渉材料になる可能性があります。",
                icon: "building.columns.fill",
                relevance: "高"
            )
        case "LENDING_NEW_SHORT_DOMESTIC":
            return Info(
                summary: "期間1年未満の新規貸出の平均金利",
                detail: "運転資金や短期つなぎ融資の金利水準を示します。手形貸付や当座貸越の金利交渉時に参考になります。",
                icon: "clock.fill",
                relevance: "高"
            )
        case "LENDING_NEW_LONG_DOMESTIC":
            return Info(
                summary: "期間1年以上の新規貸出の平均金利",
                detail: "設備投資や長期運転資金の金利水準を示します。長期借入を検討中の場合、この水準が交渉の出発点になります。",
                icon: "calendar.badge.clock",
                relevance: "高"
            )
        case "LENDING_NEW_TOTAL_CITY":
            return Info(
                summary: "メガバンク（都市銀行）の新規貸出平均金利",
                detail: "三菱UFJ・三井住友・みずほなど大手行の貸出水準です。信用力の高い企業向けの金利の目安となり、地方銀行より低い傾向があります。",
                icon: "building.2.fill",
                relevance: "中"
            )
        case "LENDING_NEW_TOTAL_REGIONAL":
            return Info(
                summary: "地方銀行の新規貸出平均金利",
                detail: "地域の中小企業が最も利用する金融機関の金利水準です。地銀から借入している場合、この数値と自社金利を比較してみてください。",
                icon: "mappin.and.ellipse",
                relevance: "高"
            )
        case "LENDING_NEW_TOTAL_SHINKIN":
            return Info(
                summary: "信用金庫の新規貸出平均金利",
                detail: "小規模事業者が多く利用する信金の金利水準です。一般的に銀行より高めですが、審査の柔軟さとのトレードオフがあります。",
                icon: "person.2.fill",
                relevance: "高"
            )
        case "LENDING_STOCK_TOTAL":
            return Info(
                summary: "既存の全貸出残高に対する加重平均金利",
                detail: "「今まさに返済中のローン全体」の平均金利です。新規金利との差が大きい場合、借り換えで利息を削減できる可能性があります。",
                icon: "tray.full.fill",
                relevance: "高"
            )
        case "LENDING_STOCK_SHORT":
            return Info(
                summary: "短期の既存貸出残高に対する平均金利",
                detail: "短期借入の残高全体にかかっている金利水準です。金利上昇時に最も早く影響を受ける部分です。",
                icon: "gauge.with.needle",
                relevance: "中"
            )
        case "LENDING_STOCK_LONG":
            return Info(
                summary: "長期の既存貸出残高に対する平均金利",
                detail: "長期借入の残高にかかっている金利水準です。固定金利の場合は影響を受けにくいですが、変動金利の場合は注視が必要です。",
                icon: "gauge.with.needle.fill",
                relevance: "中"
            )
        case "BASE_RATE":
            return Info(
                summary: "日銀が金融機関に貸し出す際の基準金利",
                detail: "かつての「公定歩合」です。短期プライムレートの基準となり、変動金利型ローンの金利に間接的に影響します。この金利が上がると、数ヶ月後に借入金利も上がる可能性があります。",
                icon: "building.columns.circle.fill",
                relevance: "中"
            )
        case "CALL_RATE_ON_AVG":
            return Info(
                summary: "銀行間で翌日返済の資金を貸し借りする際の金利",
                detail: "日銀の金融政策が最も直接的に反映される金利です。この金利の動きは「金利上昇の先行シグナル」として重要。上昇トレンドが続く場合、数ヶ月後に貸出金利も追随する傾向があります。",
                icon: "antenna.radiowaves.left.and.right",
                relevance: "中"
            )
        case "PRIME_RATE_TOTAL":
            return Info(
                summary: "金融機関が最も信用力の高い企業に適用する最優遇金利",
                detail: "多くの変動金利型ローンが「短期プライムレート＋スプレッド」で決まるため、この変動は返済額に直結します。変動金利で借入している場合は必ずチェックしてください。",
                icon: "star.circle.fill",
                relevance: "高"
            )
        default:
            return Info(
                summary: "金融市場の指標金利",
                detail: "市場全体の金利動向を把握するための参考指標です。",
                icon: "chart.line.uptrend.xyaxis",
                relevance: "低"
            )
        }
    }
}

// MARK: - Rate Card View

struct RateCardView: View {
    let rate: LatestRate
    let isSelected: Bool
    let onTap: () -> Void

    @State private var showDetail = false

    private var info: RateDescription.Info {
        RateDescription.info(for: rate.key)
    }

    var body: some View {
        VStack(spacing: 0) {
            // メインカード
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // アイコン
                    Image(systemName: info.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // ラベル + 概要
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rate.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        if let latest = rate.latest {
                            Text(latest.date)
                                .font(Theme.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    Spacer()

                    // 値 + 変化
                    if let latest = rate.latest {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(String(format: "%.3f", latest.value))
                                .font(Theme.numericMedium(20))
                                .foregroundStyle(Theme.textPrimary)
                            + Text("%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textMuted)

                            if let change = rate.change {
                                HStack(spacing: 3) {
                                    Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "minus")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(String(format: "%+.3f", change))
                                        .font(Theme.numericSmall(11))
                                }
                                .foregroundStyle(change > 0 ? Theme.negative : change < 0 ? Theme.positive : Theme.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (change > 0 ? Theme.negative : change < 0 ? Theme.positive : Theme.textMuted)
                                        .opacity(0.1)
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // 説明展開トグル
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDetail.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(showDetail ? "閉じる" : "この指標について")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Image(systemName: showDetail ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.04))
            }
            .buttonStyle(.plain)

            // 展開コンテンツ
            if showDetail {
                VStack(alignment: .leading, spacing: 10) {
                    // 概要
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 16)
                        Text(info.summary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    Divider()

                    // 借入への影響
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("借入への影響")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                            Text(info.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // 関連度バッジ
                    HStack {
                        Spacer()
                        Text("借入との関連度：")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                        BadgeView(
                            text: info.relevance,
                            color: info.relevance == "高" ? Theme.negative
                                 : info.relevance == "中" ? Theme.warning
                                 : Theme.textMuted
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.bgPrimary.opacity(0.5))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 8 : 4, y: 2)
    }
}
