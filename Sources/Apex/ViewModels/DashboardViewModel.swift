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
            // 6 meses para que el CTL (42d) converja correctamente. Paginado: si hay
            // >200 actividades en la ventana, sin esto se perderían y el CTL/ATL bajaría.
            let sixMonthsAgo = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
            let fetched = try await StravaAPI.shared.fetchAllActivities(token: token, after: sixMonthsAgo)
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
        let ftpEstimate = TrainingMetrics.estimateFTP(from: activities)
        let rhr = UserProfile.restingHR
        let maxHR = UserProfile.effectiveMaxHR
        let isMale = UserProfile.isMale

        // Carga diaria acumulada: TSS (ciclismo con potencia) o TRIMP de Banister
        var dailyTrimp: [Date: Double] = [:]
        for act in activities {
            let day = cal.startOfDay(for: act.startDate)
            dailyTrimp[day, default: 0] += TrainingMetrics.sessionLoad(
                act, ftp: ftpEstimate, restingHR: rhr, maxHR: maxHR, isMale: isMale)
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
            // TSB real = CTL − ATL (forma/frescura), no el ACWR
            history.append(LoadSample(date: day, atl: atl, ctl: ctl, tsb: ctl - atl))
        }

        let finalATL = history.last?.atl ?? 0
        let finalCTL = history.last?.ctl ?? 0
        return (TrainingLoad(atl: finalATL, ctl: finalCTL), history)
    }
}
