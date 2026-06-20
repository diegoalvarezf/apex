import Foundation

final class StravaAPI {
    static let shared = StravaAPI()
    private let base = "https://www.strava.com/api/v3"
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fetchAthlete(token: String) async throws -> StravaAthlete {
        try await get("/athlete", token: token)
    }

    func fetchActivities(token: String, page: Int = 1, perPage: Int = 30, after: Date? = nil) async throws -> [StravaActivity] {
        var params = "page=\(page)&per_page=\(perPage)"
        if let after {
            params += "&after=\(Int(after.timeIntervalSince1970))"
        }
        return try await get("/athlete/activities?\(params)", token: token)
    }

    func fetchActivity(id: Int, token: String) async throws -> StravaActivity {
        try await get("/activities/\(id)", token: token)
    }

    func fetchAthleteZones(token: String) async throws -> AthleteZones {
        try await get("/athlete/zones", token: token)
    }

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StravaError.httpError(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct AthleteZones: Codable {
    let heartRate: ZoneRanges?
    let power: ZoneRanges?
    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case power
    }
}

struct ZoneRanges: Codable {
    let zones: [Zone]
    struct Zone: Codable {
        let min: Int
        let max: Int
    }
}

enum StravaError: Error {
    case httpError(Int)
    case notAuthenticated
}
