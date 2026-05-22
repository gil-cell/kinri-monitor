import Foundation

// MARK: - Loan Condition (端末内保存)

struct LoanCondition: Codable {
    var principal: Int          // 借入元本（円）
    var annualRate: Double      // 年利（%）
    var termYears: Int          // 返済期間（年）
    var bankType: BankType      // 比較対象の金融機関タイプ

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
        principal: 30_000_000,
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
