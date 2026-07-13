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

    // Trae TODAS las actividades desde `after` recorriendo páginas hasta agotarlas.
    // Strava topa per_page en 200; sin paginación se perderían actividades y el
    // ATL/CTL quedaría infravalorado. `maxPages` es un tope de seguridad.
    func fetchAllActivities(token: String, after: Date, perPage: Int = 200, maxPages: Int = 20) async throws -> [StravaActivity] {
        var all: [StravaActivity] = []
        var page = 1
        while page <= maxPages {
            let batch = try await fetchActivities(token: token, page: page, perPage: perPage, after: after)
            all.append(contentsOf: batch)
            if batch.count < perPage { break }   // última página
            page += 1
        }
        return all
    }

    func fetchActivity(id: Int, token: String) async throws -> StravaActivity {
        try await get("/activities/\(id)", token: token)
    }

    // Series temporales de la actividad (para análisis IA de la curva de FC/ritmo)
    func fetchStreams(id: Int, token: String) async throws -> ActivityStreams {
        try await get("/activities/\(id)/streams?keys=time,heartrate,velocity_smooth,distance,altitude,watts&key_by_type=true", token: token)
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

struct ActivityStreams: Decodable {
    struct Stream: Decodable { let data: [Double] }
    let time: Stream?
    let heartrate: Stream?
    let velocitySmooth: Stream?   // m/s
    let distance: Stream?
    let altitude: Stream?
    let watts: Stream?
    enum CodingKeys: String, CodingKey {
        case time, heartrate, distance, altitude, watts
        case velocitySmooth = "velocity_smooth"
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
