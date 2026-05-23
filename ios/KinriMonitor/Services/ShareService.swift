import Foundation

/// 銀行交渉用の比較サマリー生成
struct ShareService {
    static func generateSummary(
        condition: LoanCondition,
        deviation: DeviationResult,
        repayment: RepaymentResponse
    ) -> String {
        """
        ━━━━━━━━━━━━━━━━━━━━
        借入金利 比較サマリー
        ━━━━━━━━━━━━━━━━━━━━

        ■ 自社借入条件
        借入額: \(condition.principal.formatted())円
        金利: \(String(format: "%.3f", condition.annualRate))%
        期間: \(condition.termYears)年
        比較対象: \(condition.bankType.label)

        ■ 市場平均との比較
        自社金利: \(String(format: "%.3f", deviation.userRate))%
        市場平均: \(String(format: "%.3f", deviation.marketRate))%
        乖離: \(String(format: "%+.3f", deviation.deviation))%（\(String(format: "%+d", deviation.deviationBps))bp）
        年間差額: 約\(deviation.annualDifference.formatted())円

        ■ 返済額（元利均等）
        月額: \(repayment.equalPayment.monthlyFirst.formatted())円
        年間: \(repayment.equalPayment.annualPayment.formatted())円
        利息総額: \(repayment.equalPayment.totalInterest.formatted())円

        ━━━━━━━━━━━━━━━━━━━━
        データ出典: 日本銀行 時系列統計データ
        ※ 本資料は参考情報であり、金融アドバイスではありません。
        重要な判断は専門家にご相談ください。
        生成日: \(Date().formatted(date: .abbreviated, time: .omitted))
        """
    }
}
