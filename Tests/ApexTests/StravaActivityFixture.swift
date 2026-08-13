import Foundation
@testable import Apex

// StravaActivity tiene un miembro privado (`map`), así que no expone init memberwise:
// los fixtures se construyen decodificando JSON con las mismas claves que devuelve la
// API de Strava. De paso, esto ejerce el decoder real en vez de esquivarlo.
enum StravaActivityFixture {

    static func make(
        id: Int = 1,
        name: String = "Sesión",
        sportType: String = "run",
        startDate: Date = Date(),
        movingTime: Int = 3600,
        averageHeartrate: Double? = 150,
        maxHeartrate: Double? = 180,
        averageWatts: Double? = nil,
        weightedAverageWatts: Int? = nil,
        workoutType: Int? = nil
    ) -> StravaActivity {
        var json: [String: Any] = [
            "id": id,
            "name": name,
            "type": sportType,
            "sport_type": sportType,
            "start_date": ISO8601DateFormatter().string(from: startDate),
            "distance": 10_000.0,
            "moving_time": movingTime,
            "elapsed_time": movingTime,
            "total_elevation_gain": 0.0,
            "average_speed": 3.0,
            "max_speed": 4.0,
            "kudos_count": 0,
            "has_heartrate": averageHeartrate != nil
        ]
        if let averageHeartrate { json["average_heartrate"] = averageHeartrate }
        if let maxHeartrate { json["max_heartrate"] = maxHeartrate }
        if let averageWatts { json["average_watts"] = averageWatts }
        if let weightedAverageWatts { json["weighted_average_watts"] = weightedAverageWatts }
        if let workoutType { json["workout_type"] = workoutType }

        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(StravaActivity.self, from: data)
    }
}
