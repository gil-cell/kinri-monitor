import Foundation
import UIKit
import PDFKit

/// シミュレーション結果と返済明細のPDF/CSV出力
enum ExportService {

    // MARK: - CSV出力

    static func generateCSV(
        condition: LoanCondition,
        repayment: RepaymentResponse?,
        scenarios: [SimulationScenario],
        method: RepaymentScheduleView.ScheduleMethod = .equalPayment
    ) -> URL? {
        let schedule: [MonthlyBreakdown]
        switch method {
        case .equalPayment:
            schedule = RepaymentScheduleCalculator.equalPaymentSchedule(
                principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears
            )
        case .equalPrincipal:
            schedule = RepaymentScheduleCalculator.equalPrincipalSchedule(
                principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears
            )
        }

        var csv = "\u{FEFF}" // BOM for Excel
        csv += "借入金利モニター - シミュレーション結果\n"
        csv += "出力日,\(dateString())\n\n"

        // 借入条件
        csv += "【借入条件】\n"
        csv += "総額,\(condition.totalAmount)\n"
        csv += "頭金,\(condition.downPayment)\n"
        csv += "借入額,\(condition.principal)\n"
        csv += "金利（年利）,\(String(format: "%.3f%%", condition.annualRate))\n"
        csv += "返済期間,\(condition.termYears)年\n\n"

        // 返済結果
        if let r = repayment {
            csv += "【元利均等返済】\n"
            csv += "月額返済額,\(r.equalPayment.monthlyFirst)\n"
            csv += "年間返済額,\(r.equalPayment.annualPayment)\n"
            csv += "利息総額,\(r.equalPayment.totalInterest)\n"
            csv += "返済総額,\(r.equalPayment.totalPayment)\n\n"

            csv += "【元金均等返済】\n"
            csv += "初月返済額,\(r.equalPrincipal.monthlyFirst)\n"
            csv += "最終月返済額,\(r.equalPrincipal.monthlyLast)\n"
            csv += "利息総額,\(r.equalPrincipal.totalInterest)\n"
            csv += "返済総額,\(r.equalPrincipal.totalPayment)\n\n"
        }

        // 金利上昇シミュレーション
        if !scenarios.isEmpty {
            csv += "【金利上昇シミュレーション】\n"
            csv += "上昇幅,新金利,月額返済額,月額増加,年間増加,返済総額増加\n"
            for s in scenarios {
                let totalInc = repayment.map { s.equalPayment.totalPayment - $0.equalPayment.totalPayment } ?? 0
                csv += "+\(String(format: "%.2f%%", s.rateIncrease)),\(String(format: "%.2f%%", s.newRate)),"
                csv += "\(s.equalPayment.monthlyFirst),+\(s.monthlyIncrease),+\(s.annualIncrease),+\(totalInc)\n"
            }
            csv += "\n"
        }

        // 返済明細
        csv += "【返済明細一覧（\(method.rawValue)）】\n"
        csv += "回,返済額,元金部分,利息部分,残高\n"
        for row in schedule {
            csv += "\(row.id),\(row.payment),\(row.principal),\(row.interest),\(row.balance)\n"
        }

        csv += "\n※本資料は参考情報であり金融アドバイスではありません。重要な判断は専門家にご相談ください。\n"

        // ファイル書き出し
        let fileName = "kinri_simulation_\(fileTimestamp()).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - PDF出力

    static func generatePDF(
        condition: LoanCondition,
        repayment: RepaymentResponse?,
        scenarios: [SimulationScenario],
        deviation: DeviationResult?,
        method: RepaymentScheduleView.ScheduleMethod = .equalPayment
    ) -> URL? {
        let schedule: [MonthlyBreakdown]
        switch method {
        case .equalPayment:
            schedule = RepaymentScheduleCalculator.equalPaymentSchedule(
                principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears
            )
        case .equalPrincipal:
            schedule = RepaymentScheduleCalculator.equalPrincipalSchedule(
                principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears
            )
        }

        let pageWidth: CGFloat = 595.0  // A4
        let pageHeight: CGFloat = 842.0
        let margin: CGFloat = 40.0
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            func newPage() {
                context.beginPage()
                y = margin
            }

            func checkPageBreak(_ needed: CGFloat) {
                if y + needed > pageHeight - margin {
                    newPage()
                }
            }

            func drawText(_ text: String, x: CGFloat, font: UIFont, color: UIColor = .black, width: CGFloat? = nil) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let maxW = width ?? (contentWidth - (x - margin))
                let rect = CGRect(x: x, y: y, width: maxW, height: 1000)
                let drawn = (text as NSString).boundingRect(with: CGSize(width: maxW, height: 1000),
                                                            options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                (text as NSString).draw(in: rect, withAttributes: attrs)
                y += drawn.height + 4
            }

            func drawLine() {
                checkPageBreak(10)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                UIColor.lightGray.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 8
            }

            func drawRow(_ cols: [String], widths: [CGFloat], font: UIFont, color: UIColor = .black) {
                checkPageBreak(16)
                var x = margin
                for (i, col) in cols.enumerated() {
                    let w = widths[i]
                    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let rect = CGRect(x: x, y: y, width: w, height: 14)
                    (col as NSString).draw(in: rect, withAttributes: attrs)
                    x += w
                }
                y += 16
            }

            let titleFont = UIFont.boldSystemFont(ofSize: 16)
            let headFont = UIFont.boldSystemFont(ofSize: 11)
            let bodyFont = UIFont.systemFont(ofSize: 10)
            let smallFont = UIFont.systemFont(ofSize: 8)
            let accentColor = UIColor(red: 0.18, green: 0.74, blue: 0.56, alpha: 1)

            // === PAGE 1: サマリー ===
            newPage()

            drawText("借入金利モニター シミュレーション結果", x: margin, font: titleFont, color: accentColor)
            drawText("出力日：\(dateString())", x: margin, font: smallFont, color: .gray)
            y += 8
            drawLine()

            // 借入条件
            drawText("■ 借入条件", x: margin, font: headFont, color: accentColor)
            if condition.downPayment > 0 {
                drawText("総額：\(condition.totalAmount.formatted())円", x: margin + 10, font: bodyFont)
                drawText("頭金：\(condition.downPayment.formatted())円（\(String(format: "%.1f%%", condition.downPaymentRatio))）", x: margin + 10, font: bodyFont)
            }
            drawText("借入額：\(condition.principal.formatted())円", x: margin + 10, font: bodyFont)
            drawText("金利：\(String(format: "%.3f%%", condition.annualRate))（年利）", x: margin + 10, font: bodyFont)
            drawText("返済期間：\(condition.termYears)年（\(condition.termYears * 12)回）", x: margin + 10, font: bodyFont)
            y += 6
            drawLine()

            // 返済結果
            if let r = repayment {
                drawText("■ 元利均等返済", x: margin, font: headFont, color: accentColor)
                drawText("月額返済額：\(r.equalPayment.monthlyFirst.formatted())円　利息総額：\(r.equalPayment.totalInterest.formatted())円　返済総額：\(r.equalPayment.totalPayment.formatted())円", x: margin + 10, font: bodyFont)
                y += 4
                drawText("■ 元金均等返済", x: margin, font: headFont, color: accentColor)
                drawText("初月：\(r.equalPrincipal.monthlyFirst.formatted())円　最終月：\(r.equalPrincipal.monthlyLast.formatted())円　利息総額：\(r.equalPrincipal.totalInterest.formatted())円", x: margin + 10, font: bodyFont)
                y += 4
                drawLine()
            }

            // 乖離診断
            if let d = deviation {
                drawText("■ 市場平均との乖離診断", x: margin, font: headFont, color: accentColor)
                drawText("市場平均：\(String(format: "%.3f%%", d.marketRate))　自社金利：\(String(format: "%.3f%%", d.userRate))　乖離：\(String(format: "%+.3f%%", d.deviation))（\(d.deviationBps)bp）", x: margin + 10, font: bodyFont)
                if d.annualDifference > 0 {
                    drawText("年間差額：約\(d.annualDifference.formatted())円", x: margin + 10, font: bodyFont)
                }
                drawText(d.comment, x: margin + 10, font: smallFont, color: .darkGray, width: contentWidth - 20)
                y += 4
                drawLine()
            }

            // 金利上昇シミュレーション
            if !scenarios.isEmpty {
                drawText("■ 金利上昇シミュレーション", x: margin, font: headFont, color: accentColor)
                let colW: [CGFloat] = [80, 80, 100, 100, 100]
                drawRow(["上昇幅", "新金利", "月額返済額", "月額増加", "返済総額増加"], widths: colW, font: UIFont.boldSystemFont(ofSize: 9), color: .gray)
                for s in scenarios {
                    let totalInc = repayment.map { s.equalPayment.totalPayment - $0.equalPayment.totalPayment } ?? 0
                    drawRow([
                        "+\(String(format: "%.2f%%", s.rateIncrease))",
                        "\(String(format: "%.2f%%", s.newRate))",
                        "\(s.equalPayment.monthlyFirst.formatted())円",
                        "+\(s.monthlyIncrease.formatted())円",
                        "+\(totalInc.formatted())円"
                    ], widths: colW, font: bodyFont)
                }
                y += 4
                drawLine()
            }

            // === PAGE 2+: 返済明細 ===
            drawText("■ 返済明細一覧（\(method.rawValue)）", x: margin, font: headFont, color: accentColor)

            let schedW: [CGFloat] = [40, 90, 90, 90, contentWidth - 310]
            drawRow(["回", "返済額", "元金部分", "利息部分", "残高"], widths: schedW, font: UIFont.boldSystemFont(ofSize: 9), color: .gray)

            for row in schedule {
                checkPageBreak(16)
                drawRow([
                    "\(row.id)",
                    "\(row.payment.formatted())",
                    "\(row.principal.formatted())",
                    "\(row.interest.formatted())",
                    "\(row.balance.formatted())"
                ], widths: schedW, font: bodyFont)

                if row.id % 12 == 0 && row.id < schedule.count {
                    checkPageBreak(14)
                    drawText("── \(row.id / 12)年目終了 ──", x: margin, font: smallFont, color: accentColor)
                }
            }

            // フッター
            y += 12
            drawLine()
            drawText("※ 本資料は参考情報であり、投資助言・金融アドバイスではありません。重要な判断は専門家にご相談ください。", x: margin, font: smallFont, color: .gray, width: contentWidth)
            drawText("データ出典：日本銀行 時系列統計データ検索サイト　アプリ：借入金利モニター", x: margin, font: smallFont, color: .gray, width: contentWidth)
        }

        let fileName = "kinri_simulation_\(fileTimestamp()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日"
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: Date())
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
