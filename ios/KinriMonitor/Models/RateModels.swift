import Foundation

// MARK: - API Response Models

struct APIResponse<T: Decodable>: Decodable {
    let status: String
    let data: T?
    let message: String?
}

// MARK: - Rate Models

struct LatestRate: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let unit: String
    let lastUpdate: String
    let latest: RatePoint?
    let previous: RatePoint?
    let change: Double?

    struct RatePoint: Decodable {
        let date: String
        let value: Double
    }
}

struct RateHistory: Decodable {
    let key: String
    let label: String
    let unit: String
    let frequency: String
    let lastUpdate: String
    let data: [DataPoint]

    struct DataPoint: Decodable, Identifiable {
        var id: String { date }
        let date: String
        let value: Double?
    }
}

struct SeriesInfo: Decodable, Identifiable {
    var id: String { key }
    let key: String
    let db: String
    let code: String
    let label: String
}
