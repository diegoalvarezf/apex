import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var trainingLoad: TrainingLoad?
    @Published var loadHistory: [LoadSample] = []
    @Published var insights: [AIInsight] = []
    @Published var isLoadingActivities = false
    @Published var isLoadingInsights = false
    @Published var error: String?
    @Published var todayEffortScore: Int = 0

    struct LoadSample: Identifiable {
        let id = UUID()
        let date: Date
        let atl: Double
        let ctl: Double
        let tsb: Double
    }

    func loadActivities(token: String) async {
        isLoadingActivities = true
        defer { isLoadingActivities = false }
        do {
            // 6 meses para que el CTL (42d) converja correctamente, igual que PeakWatch
            let sixMonthsAgo = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
            let fetched = try await StravaAPI.shared.fetchActivities(token: token, perPage: 200, after: sixMonthsAgo)
            activities = fetched.sorted { $0.startDate > $1.startDate }
            let (load, history) = computeTrainingLoad(from: activities)
            trainingLoad = load
            loadHistory = history
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadInsights(health: HealthKitManager) async {
        guard !isLoadingInsights else { return }
        isLoadingInsights = true
        defer { isLoadingInsights = false }

        let context = AICoachContext(
            recentActivities: Array(activities.prefix(10)),
            sleepLast7Days: health.sleepHistory,
            latestHRV: health.hrvHistory.first,
            restingHR: health.todaySummary?.restingHR,
            vo2Max: health.todaySummary?.vo2Max,
            trainingLoad: trainingLoad,
            recoveryScore: health.recoveryScore
        )

        do {
            insights = try await AIService.shared.generateInsights(context: context)
        } catch {
            self.error = "No se pudieron cargar los insights: \(error.localizedDescription)"
        }
    }

    private func computeTrainingLoad(from activities: [StravaActivity]) -> (TrainingLoad, [LoadSample]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let ftpEstimate = estimatedFTP(from: activities)

        // Daily TRIMP/TSS accumulated per day
        var dailyTrimp: [Date: Double] = [:]
        for act in activities {
            let day = cal.startOfDay(for: act.startDate)
            dailyTrimp[day, default: 0] += trimpForActivity(act, ftpEstimate: ftpEstimate)
        }

        // EMA standard PeakWatch/TrainingPeaks
        // ATL τ=7d: k = 1 - e^(-1/7) ≈ 0.133
        // CTL τ=42d: k = 1 - e^(-1/42) ≈ 0.0235
        let kATL = 1.0 - Foundation.exp(-1.0 / 7.0)
        let kCTL = 1.0 - Foundation.exp(-1.0 / 42.0)

        var atl = 0.0
        var ctl = 0.0
        var history: [LoadSample] = []

        // 180 días para que el CTL (τ=42d) converja completamente
        for offset in stride(from: -179, through: 0, by: 1) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let trimp = dailyTrimp[day] ?? 0.0
            atl = atl * (1 - kATL) + trimp * kATL
            ctl = ctl * (1 - kCTL) + trimp * kCTL
            let acwr = ctl > 0 ? atl / ctl : 1.0
            history.append(LoadSample(date: day, atl: atl, ctl: ctl, tsb: acwr))
        }

        let finalATL = history.last?.atl ?? 0
        let finalCTL = history.last?.ctl ?? 0
        // Esfuerzo de hoy: TRIMP del día escalado a 0-100
        let rawToday = dailyTrimp[today] ?? 0.0
        todayEffortScore = min(100, Int(rawToday))
        return (TrainingLoad(atl: finalATL, ctl: finalCTL), history)
    }

    // Estimate FTP from average power of the most recent 10 rides with power data
    private func estimatedFTP(from activities: [StravaActivity]) -> Double? {
        let rideTypes = ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"]
        let powerValues: [Double] = Array(
            activities
                .filter { rideTypes.contains($0.sportType.lowercased()) }
                .compactMap { act -> Double? in
                    if let w = act.weightedAverageWatts { return Double(w) }
                    return act.averageWatts
                }
                .prefix(10)
        )
        guard !powerValues.isEmpty else { return nil }
        return powerValues.reduce(0, +) / Double(powerValues.count)
    }

    // Banister TRIMP / TSS per activity
    private func trimpForActivity(_ act: StravaActivity, ftpEstimate: Double? = nil) -> Double {
        let rhr = 55.0
        let maxHR = Double(UserProfile.maxHR)

        // TSS for cycling rides that have power data
        let rideTypes = ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"]
        let np: Double? = act.weightedAverageWatts.map(Double.init) ?? act.averageWatts
        if rideTypes.contains(act.sportType.lowercased()),
           let ftp = ftpEstimate, ftp > 0,
           let npValue = np, npValue > 0 {
            let ifValue = npValue / ftp
            let seconds = Double(act.movingTime)
            var tss = (seconds * npValue * ifValue) / (ftp * 3600.0) * 100.0
            // +1% per 100m elevation gain
            let elevationFactor = 1.0 + (act.totalElevationGain / 10000.0)
            tss *= elevationFactor
            return tss
        }

        // Banister TRIMP for all other sports
        let durationH = Double(act.movingTime) / 3600.0
        let avgHR: Double
        if let hr = act.averageHeartrate {
            avgHR = hr
        } else {
            let frac: Double
            switch act.sportType.lowercased() {
            case "run", "trail_run", "virtualrun":        frac = 0.75
            case "ride", "virtualride", "ebikeride":      frac = 0.65
            case "swim":                                   frac = 0.70
            case "weighttraining", "crossfit", "workout": frac = 0.55
            case "walk", "hike":                          frac = 0.40
            case "yoga", "pilates":                       frac = 0.30
            default:                                       frac = 0.60
            }
            avgHR = rhr + frac * (maxHR - rhr)
        }
        let hrr = max(0, min(1, (avgHR - rhr) / (maxHR - rhr)))
        var trimp = durationH * hrr * Foundation.exp(1.92 * hrr)
        let elevationFactor = 1.0 + (act.totalElevationGain / 10000.0)
        trimp *= elevationFactor
        // Escalar a rango PeakWatch (ATL/CTL en unidades 20-50 para entrenos típicos)
        return trimp * 13.0
    }
}
