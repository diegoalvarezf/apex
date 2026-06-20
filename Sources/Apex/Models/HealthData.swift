import Foundation
import SwiftUI

// MARK: - Generic time series

struct MetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum MetricTrend {
    case up, down, flat

    var systemImage: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    func color(higherIsBetter: Bool) -> Color {
        switch self {
        case .up: return higherIsBetter ? .green : .red
        case .down: return higherIsBetter ? .red : .green
        case .flat: return .secondary
        }
    }
}

func computeTrend(samples: [MetricSample]) -> MetricTrend {
    guard samples.count >= 14 else { return .flat }
    let sorted = samples.sorted { $0.date < $1.date }
    let mid = sorted.count / 2
    let recent = sorted.suffix(mid).map(\.value)
    let previous = sorted.prefix(mid).map(\.value)
    let recentAvg = recent.reduce(0, +) / Double(recent.count)
    let prevAvg = previous.reduce(0, +) / Double(previous.count)
    guard prevAvg > 0 else { return .flat }
    let change = (recentAvg - prevAvg) / prevAvg
    if change > 0.05 { return .up }
    if change < -0.05 { return .down }
    return .flat
}

// MARK: - Sleep

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

// MARK: - HRV

struct HRVData: Identifiable {
    let id = UUID()
    let date: Date
    let sdnn: Double  // ms
}

// MARK: - Recovery / Body Battery

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

    var systemColor: Color {
        switch value {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }

    var gradientColors: [Color] {
        switch value {
        case 80...100: return [.green, .mint]
        case 60..<80: return [.cyan, .blue]
        case 40..<60: return [.yellow, .orange]
        case 20..<40: return [.orange, .red]
        default: return [.red, .pink]
        }
    }
}

// MARK: - New health metrics

struct VO2MaxData {
    let current: Double
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }
}

struct RespiratoryData {
    let current: Double  // breaths/min
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }
}

struct WristTempData {
    let baseline: Double   // °C
    let deviation: Double  // latest - baseline
    let samples: [MetricSample]
}

struct DaylightData {
    let todayMinutes: Int
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }
}

struct BodyCompositionData {
    let weightKg: Double?
    let bmi: Double?
    let samples: [MetricSample]  // weight history
    var trend: MetricTrend { computeTrend(samples: samples) }

    static func computeBMI(weightKg: Double, heightM: Double) -> Double {
        guard heightM > 0 else { return 0 }
        return weightKg / (heightM * heightM)
    }
}

struct HeartRateZone: Identifiable {
    let id = UUID()
    let zone: Int
    let name: String
    let minBPM: Int
    let maxBPM: Int
    let timeInZone: TimeInterval

    var color: Color {
        switch zone {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }

    var formattedTime: String {
        let h = Int(timeInZone) / 3600
        let m = (Int(timeInZone) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Daily summary

struct DailyHealthSummary {
    let date: Date
    let sleep: SleepData?
    let hrv: HRVData?
    let restingHR: Double?
    let vo2Max: Double?
    let steps: Int
    let activeCalories: Double
    let recovery: RecoveryScore?
    let respiratoryRate: Double?
    let wristTempDeviation: Double?
    let daylightMinutes: Int?
    let weightKg: Double?
    let bmi: Double?
}
