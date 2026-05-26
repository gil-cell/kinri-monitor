import Foundation

// MARK: - Loan Condition (端末内保存)

struct LoanCondition: Codable {
    var totalAmount: Int        // 総額（円）
    var downPayment: Int        // 頭金（円）
    var annualRate: Double      // 年利（%）
    var termYears: Int          // 返済期間（年）
    var bankType: BankType      // 比較対象の金融機関タイプ

    /// 実際の借入額（総額 − 頭金）
    var principal: Int {
        max(totalAmount - downPayment, 0)
    }

    /// 頭金の割合（%）
    var downPaymentRatio: Double {
        guard totalAmount > 0 else { return 0 }
        return Double(downPayment) / Double(totalAmount) * 100
    }

    enum BankType: String, Codable, CaseIterable {
        case domestic = "LENDING_NEW_TOTAL_DOMESTIC"
        case city = "LENDING_NEW_TOTAL_CITY"
        case regional = "LENDING_NEW_TOTAL_REGIONAL"
        case shinkin = "LENDING_NEW_TOTAL_SHINKIN"

        var label: String {
            switch self {
            case .domestic: return "国内銀行"
            case .city:     return "都市銀行"
            case .regional: return "地方銀行"
            case .shinkin:  return "信用金庫"
            }
        }
    }

    static let `default` = LoanCondition(
        totalAmount: 30_000_000,
        downPayment: 0,
        annualRate: 1.5,
        termYears: 15,
        bankType: .domestic
    )
}

// MARK: - Calculation Results

struct RepaymentResult: Decodable {
    let method: String
    let monthlyFirst: Int
    let monthlyLast: Int
    let totalPayment: Int
    let totalInterest: Int
    let annualPayment: Int
}

struct RepaymentResponse: Decodable {
    let equalPayment: RepaymentResult
    let equalPrincipal: RepaymentResult
}

struct DeviationResult: Decodable {
    let userRate: Double
    let marketRate: Double
    let deviation: Double
    let deviationBps: Int
    let verdict: String
    let annualDifference: Int
    let comment: String
}

struct SimulationScenario: Decodable, Identifiable {
    var id: Double { rateIncrease }
    let rateIncrease: Double
    let newRate: Double
    let equalPayment: RepaymentResult
    let equalPrincipal: RepaymentResult
    let monthlyIncrease: Int
    let annualIncrease: Int
}

// MARK: - 返済明細（ローカル計算）

struct MonthlyBreakdown: Identifiable {
    let id: Int          // 回数（1始まり）
    let payment: Int     // 返済額
    let principal: Int   // 元金部分
    let interest: Int    // 利息部分
    let balance: Int     // 残高
}

enum RepaymentScheduleCalculator {

    /// 元利均等返済の返済明細
    static func equalPaymentSchedule(principal: Int, annualRate: Double, termYears: Int) -> [MonthlyBreakdown] {
        let P = Double(principal)
        let r = annualRate / 100.0 / 12.0
        let n = termYears * 12

        guard r > 0 else {
            let monthly = Int(round(P / Double(n)))
            return (1...n).map { i in
                MonthlyBreakdown(
                    id: i, payment: monthly, principal: monthly,
                    interest: 0, balance: max(0, principal - monthly * i)
                )
            }
        }

        let rn = pow(1 + r, Double(n))
        let monthlyPayment = P * r * rn / (rn - 1)

        var balance = P
        var result: [MonthlyBreakdown] = []
        for i in 1...n {
            let interestPart = balance * r
            let principalPart = monthlyPayment - interestPart
            balance -= principalPart
            if balance < 0 { balance = 0 }

            result.append(MonthlyBreakdown(
                id: i,
                payment: Int(round(monthlyPayment)),
                principal: Int(round(principalPart)),
                interest: Int(round(interestPart)),
                balance: Int(round(balance))
            ))
        }
        return result
    }

    /// 元金均等返済の返済明細
    static func equalPrincipalSchedule(principal: Int, annualRate: Double, termYears: Int) -> [MonthlyBreakdown] {
        let P = Double(principal)
        let r = annualRate / 100.0 / 12.0
        let n = termYears * 12
        let monthlyPrincipal = P / Double(n)

        var balance = P
        var result: [MonthlyBreakdown] = []
        for i in 1...n {
            let interestPart = balance * r
            let payment = monthlyPrincipal + interestPart
            balance -= monthlyPrincipal
            if balance < 0 { balance = 0 }

            result.append(MonthlyBreakdown(
                id: i,
                payment: Int(round(payment)),
                principal: Int(round(monthlyPrincipal)),
                interest: Int(round(interestPart)),
                balance: Int(round(balance))
            ))
        }
        return result
    }
}
