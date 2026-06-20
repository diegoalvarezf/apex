import Foundation

struct StravaActivity: Identifiable, Codable {
    let id: Int
    let name: String
    let type: String
    let sportType: String
    let startDate: Date
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let averageSpeed: Double
    let maxSpeed: Double
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let averageWatts: Double?
    let weightedAverageWatts: Int?
    let kilojoules: Double?
    let sufferScore: Int?
    let kudosCount: Int
    let hasHeartrate: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case sportType = "sport_type"
        case startDate = "start_date"
        case distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case averageWatts = "average_watts"
        case weightedAverageWatts = "weighted_average_watts"
        case kilojoules
        case sufferScore = "suffer_score"
        case kudosCount = "kudos_count"
        case hasHeartrate = "has_heartrate"
    }

    var formattedDistance: String {
        if distance >= 1000 {
            return String(format: "%.2f km", distance / 1000)
        }
        return String(format: "%.0f m", distance)
    }

    var formattedDuration: String {
        let hours = movingTime / 3600
        let minutes = (movingTime % 3600) / 60
        let seconds = movingTime % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedPace: String {
        guard distance > 0 else { return "--" }
        let paceSecondsPerKm = Double(movingTime) / (distance / 1000)
        let paceMin = Int(paceSecondsPerKm) / 60
        let paceSec = Int(paceSecondsPerKm) % 60
        return String(format: "%d:%02d /km", paceMin, paceSec)
    }

    var sportEmoji: String {
        switch sportType.lowercased() {
        case "run", "virtualrun": return "🏃"
        case "ride", "virtualride": return "🚴"
        case "swim": return "🏊"
        case "hike": return "🥾"
        case "walk": return "🚶"
        case "weighttraining": return "🏋️"
        case "yoga": return "🧘"
        default: return "⚡️"
        }
    }
}

struct StravaAthlete: Codable {
    let id: Int
    let firstname: String
    let lastname: String
    let profile: String
    let city: String?
    let country: String?
    let followerCount: Int
    let friendCount: Int

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, profile, city, country
        case followerCount = "follower_count"
        case friendCount = "friend_count"
    }

    var fullName: String { "\(firstname) \(lastname)" }
}

struct TrainingLoad {
    let atl: Double  // Acute Training Load (7 days)
    let ctl: Double  // Chronic Training Load (42 days)
    var tsb: Double { ctl - atl }  // Training Stress Balance (form)

    var formStatus: FormStatus {
        switch tsb {
        case 25...: return .fresh
        case 5..<25: return .optimal
        case -10..<5: return .neutral
        case -30 ..< -10: return .tired
        default: return .overreached
        }
    }

    enum FormStatus: String {
        case fresh = "Fresco"
        case optimal = "Óptimo"
        case neutral = "Neutral"
        case tired = "Cansado"
        case overreached = "Sobreentrenado"

        var color: String {
            switch self {
            case .fresh: return "blue"
            case .optimal: return "green"
            case .neutral: return "yellow"
            case .tired: return "orange"
            case .overreached: return "red"
            }
        }
    }
}
