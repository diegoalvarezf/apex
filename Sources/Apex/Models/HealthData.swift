import Foundation

struct SleepData: Identifiable {
    let id = UUID()
    let date: Date
    let totalSleep: TimeInterval
    let deepSleep: TimeInterval
    let remSleep: TimeInterval
    let coreSleep: TimeInterval
    let awake: TimeInterval

    var efficiency: Double {
        guard totalSleep > 0 else { return 0 }
        return (totalSleep - awake) / totalSleep * 100
    }

    var formattedTotal: String {
        let hours = Int(totalSleep) / 3600
        let minutes = (Int(totalSleep) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var score: Int {
        let baseDuration = min(totalSleep / (8 * 3600), 1.0) * 40
        let deepPct = totalSleep > 0 ? deepSleep / totalSleep : 0
        let deepScore = min(deepPct / 0.20, 1.0) * 30
        let effScore = efficiency / 100.0 * 30
        return Int(baseDuration + deepScore + effScore)
    }
}

struct HRVData: Identifiable {
    let id = UUID()
    let date: Date
    let sdnn: Double  // ms

    var trend: HRVTrend = .neutral

    enum HRVTrend {
        case up, neutral, down
    }
}

struct RecoveryScore {
    let value: Int  // 0-100
    let sleepScore: Int
    let hrvScore: Int
    let trainingLoadScore: Int
    let restingHRScore: Int

    var label: String {
        switch value {
        case 80...100: return "Excelente"
        case 60..<80: return "Buena"
        case 40..<60: return "Moderada"
        case 20..<40: return "Baja"
        default: return "Muy baja"
        }
    }

    var gradient: [String] {
        switch value {
        case 80...100: return ["#00C853", "#69F0AE"]
        case 60..<80: return ["#00BCD4", "#80DEEA"]
        case 40..<60: return ["#FFB300", "#FFD54F"]
        case 20..<40: return ["#FF6D00", "#FFAB40"]
        default: return ["#D50000", "#FF5252"]
        }
    }
}

struct DailyHealthSummary {
    let date: Date
    let sleep: SleepData?
    let hrv: HRVData?
    let restingHR: Double?
    let vo2Max: Double?
    let steps: Int
    let activeCalories: Double
    let recovery: RecoveryScore?
}
