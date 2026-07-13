import Foundation
import SwiftUI
import CoreLocation

// Nested map object from Strava response
private struct ActivityMap: Codable {
    let summaryPolyline: String?
    enum CodingKeys: String, CodingKey { case summaryPolyline = "summary_polyline" }
}

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
    let calories: Double?        // calorías estimadas (disponible para todos los deportes)
    let sufferScore: Int?
    let kudosCount: Int
    let hasHeartrate: Bool
    let workoutType: Int?        // Strava: run 1=carrera, 2=tirada larga, 3=workout/intervalos
    private let map: ActivityMap?

    // Sesión de ritmo variable (intervalos/series/fartlek/tempo): las métricas de
    // economía y desacoplamiento NO aplican porque comparan un promedio contra continuo.
    var isStructuredWorkout: Bool {
        if workoutType == 3 { return true }
        let n = name.lowercased()
        return ["interval", "serie", "series", "fartlek", "tempo", "x400", "x800", "x1000", "cuestas"].contains { n.contains($0) }
    }

    var summaryPolyline: String? { map?.summaryPolyline }
    // Usa calories si está disponible (todos los deportes), si no kilojoules * 0.239 (ciclismo con potenciómetro)
    var kcal: Double? { calories ?? kilojoules.map { $0 * 0.239 } }

    // kcal garantizadas: medidas > Keytel HR-ajustada > MET × 70kg
    var displayKcal: Double {
        if let k = kcal, k > 1 { return k }
        let hours = Double(movingTime) / 3600.0
        let durationMin = hours * 60.0

        // Fórmula Keytel 2005 (hombre 70kg): más precisa que MET cuando hay FC
        // kcal/min = (-55.0969 + 0.6309×HR + 0.1988×70) / 4.184
        if let hr = averageHeartrate, hr > 80 {
            let kcalPerMin = max(0, (-41.18 + 0.6309 * hr)) / 4.184
            if kcalPerMin > 0 { return kcalPerMin * durationMin }
        }

        // Fallback: MET × peso × h
        let weight = UserProfile.weightKg
        let met: Double
        switch sportType.lowercased() {
        case "run", "trail_run", "virtualrun":
            let kmh = averageSpeed * 3.6
            met = max(7.0, min(18.0, kmh * 1.05))
        case "ride", "virtualride":
            let kmh = averageSpeed * 3.6
            met = max(5.0, min(15.0, kmh * 0.45))
        case "ebikeride":             met = 4.0
        case "swim":                  met = 7.0
        case "hike":                  met = 6.0
        case "walk":                  met = 3.8
        case "weighttraining", "crossfit", "workout": met = 5.0
        case "yoga", "pilates":       met = 2.5
        default:                      met = 6.0
        }
        return met * weight * hours
    }
    var kcalIsEstimated: Bool { kcal == nil || (kcal ?? 0) <= 1 }

    enum CodingKeys: String, CodingKey {
        case id, name, type, map
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
        case calories
        case sufferScore = "suffer_score"
        case kudosCount = "kudos_count"
        case hasHeartrate = "has_heartrate"
        case workoutType = "workout_type"
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
        case "trail_run": return "🏃"
        case "ride", "virtualride": return "🚴"
        case "swim": return "🏊"
        case "hike": return "🥾"
        case "walk": return "🚶"
        case "weighttraining": return "🏋️"
        case "yoga": return "🧘"
        default: return "⚡️"
        }
    }

    var sportLabel: String {
        switch sportType.lowercased() {
        case "run", "virtualrun":   return "Carrera"
        case "trail_run":           return "Trail"
        case "ride", "virtualride": return "Ciclismo"
        case "swim":                return "Natación"
        case "walk":                return "Caminata"
        case "hike":                return "Senderismo"
        case "weighttraining":      return "Fuerza"
        case "yoga":                return "Yoga"
        default:                    return sportType.capitalized
        }
    }

    var sportIcon: String {
        switch sportType.lowercased() {
        case "run", "virtualrun":                       return "figure.run"
        case "trail_run":                               return "figure.run"
        case "ride", "virtualride", "ebikeride",
             "mountainbikeride", "gravelride":          return "figure.outdoor.cycle"
        case "swim":                                    return "figure.pool.swim"
        case "walk":                                    return "figure.walk"
        case "hike":                                    return "figure.hiking"
        case "weighttraining", "crossfit", "workout":   return "dumbbell.fill"
        case "yoga", "pilates":                         return "figure.yoga"
        default:                                        return "bolt.fill"
        }
    }

    var sportColor: Color {
        switch sportType.lowercased() {
        case "run", "virtualrun", "trail_run":          return .orange
        case "ride", "virtualride", "ebikeride",
             "mountainbikeride", "gravelride":          return .green
        case "swim":                                    return .cyan
        case "walk":                                    return .teal
        case "hike":                                    return .brown
        case "weighttraining", "crossfit", "workout":   return .purple
        case "yoga", "pilates":                         return .pink
        default:                                        return .blue
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

struct TrainingLoad: Equatable {
    let atl: Double  // Acute Training Load  (7-day EMA)
    let ctl: Double  // Chronic Training Load (42-day EMA)

    // ACWR = ATL/CTL (Gabbett 2016) — indicador de RIESGO DE LESIÓN.
    // Óptimo: 0.8-1.3 · Elevado: 1.3-1.5 · Riesgo: >1.5 · Subentrenado: <0.8
    var acwr: Double { ctl > 0 ? atl / ctl : 1.0 }

    // TSB = CTL − ATL (Training Stress Balance / "Form", Coggan-Banister) — indicador
    // de FRESCURA. En unidades de carga (TSS/TRIMP): positivo = fresco, negativo = fatigado.
    // No confundir con ACWR: miden cosas distintas (frescura vs riesgo de lesión).
    var tsb: Double { ctl - atl }

    // Estado de riesgo (barra de carga) — basado en ACWR
    var formStatus: FormStatus {
        switch acwr {
        case ..<0.8:       return .undertrained
        case 0.8..<1.3:    return .optimal
        case 1.3..<1.5:    return .elevated
        default:            return .overreached
        }
    }

    // Zona de forma/frescura — basada en TSB (zonas TrainingPeaks)
    var formZone: FormZone {
        switch tsb {
        case 25...:        return .transition   // muy fresco / desentrenando
        case 5..<25:       return .fresh        // frescura de competición
        case -10..<5:      return .neutral      // zona neutra
        case -30..<(-10):  return .productive   // entrenamiento productivo (fatiga útil)
        default:           return .overreached  // sobrecarga
        }
    }

    enum FormZone: String {
        case transition  = "Muy fresco"
        case fresh       = "Fresco"
        case neutral     = "Neutro"
        case productive  = "Cargando"
        case overreached = "Sobrecarga"

        var color: Color {
            switch self {
            case .transition:  return .cyan
            case .fresh:       return .green
            case .neutral:     return .gray
            case .productive:  return .orange
            case .overreached: return .red
            }
        }

        var detail: String {
            switch self {
            case .transition:  return "Muy descansado. Ideal para competir, pero mantenido en el tiempo pierdes fitness."
            case .fresh:       return "Frescura de competición: fitness alto y fatiga baja. Buen momento para rendir."
            case .neutral:     return "Carga y recuperación equilibradas. Mantenimiento."
            case .productive:  return "Fatiga útil: estás construyendo fitness. Normal en bloques de carga."
            case .overreached: return "Fatiga muy alta. Reduce la carga para no caer en sobreentrenamiento."
            }
        }
    }

    enum FormStatus: String {
        case undertrained = "Subentrenado"
        case optimal      = "Óptimo"
        case elevated     = "Elevado"
        case overreached  = "Riesgo"

        var color: Color {
            switch self {
            case .undertrained: return .blue
            case .optimal:      return .green
            case .elevated:     return .yellow
            case .overreached:  return .red
            }
        }

        var systemImage: String {
            switch self {
            case .undertrained: return "arrow.down.circle.fill"
            case .optimal:      return "checkmark.circle.fill"
            case .elevated:     return "exclamationmark.circle.fill"
            case .overreached:  return "xmark.circle.fill"
            }
        }
    }
}
