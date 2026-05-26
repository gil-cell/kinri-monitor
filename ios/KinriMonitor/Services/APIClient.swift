import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://kinri-monitor-api.kinritilyusyou.workers.dev"
    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // MARK: - GET

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - POST

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.serverError
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Public API

    func fetchLatestRates() async throws -> [LatestRate] {
        let resp: APIResponse<[LatestRate]> = try await get("/api/rates/latest")
        guard let data = resp.data else { throw APIError.noData }
        return data
    }

    func fetchHistory(key: String, months: Int = 24) async throws -> RateHistory {
        let resp: APIResponse<RateHistory> = try await get("/api/rates/history?key=\(key)&months=\(months)")
        guard let data = resp.data else { throw APIError.noData }
        return data
    }

    func calcRepayment(condition: LoanCondition) async throws -> RepaymentResponse {
        struct Body: Encodable {
            let principal: Int
            let annualRate: Double
            let termYears: Int
        }
        let body = Body(principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears)
        let resp: APIResponse<RepaymentResponse> = try await post("/api/calc/repayment", body: body)
        guard let data = resp.data else { throw APIError.noData }
        return data
    }

    func calcDeviation(userRate: Double, marketRate: Double, principal: Int, termYears: Int) async throws -> DeviationResult {
        struct Body: Encodable {
            let userRate: Double
            let marketRate: Double
            let principal: Int
            let termYears: Int
        }
        let body = Body(userRate: userRate, marketRate: marketRate, principal: principal, termYears: termYears)
        let resp: APIResponse<DeviationResult> = try await post("/api/calc/deviation", body: body)
        guard let data = resp.data else { throw APIError.noData }
        return data
    }

    func calcSimulation(condition: LoanCondition) async throws -> [SimulationScenario] {
        struct Body: Encodable {
            let principal: Int
            let annualRate: Double
            let termYears: Int
        }
        let body = Body(principal: condition.principal, annualRate: condition.annualRate, termYears: condition.termYears)
        let resp: APIResponse<[SimulationScenario]> = try await post("/api/calc/simulation", body: body)
        guard let data = resp.data else { throw APIError.noData }
        return data
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case serverError
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "無効なURL"
        case .serverError: return "サーバーエラー"
        case .noData: return "データが取得できませんでした"
        }
    }
}
