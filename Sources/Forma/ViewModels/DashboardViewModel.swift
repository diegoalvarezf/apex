import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var trainingLoad: TrainingLoad?
    @Published var insights: [AIInsight] = []
    @Published var isLoadingActivities = false
    @Published var isLoadingInsights = false
    @Published var error: String?

    func loadActivities(token: String) async {
        isLoadingActivities = true
        defer { isLoadingActivities = false }
        do {
            let sixWeeksAgo = Calendar.current.date(byAdding: .day, value: -42, to: Date())!
            activities = try await StravaAPI.shared.fetchActivities(token: token, perPage: 50, after: sixWeeksAgo)
            trainingLoad = computeTrainingLoad(from: activities)
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

    private func computeTrainingLoad(from activities: [StravaActivity]) -> TrainingLoad {
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let sixWeeksAgo = Calendar.current.date(byAdding: .day, value: -42, to: now)!

        func sufferScore(_ a: StravaActivity) -> Double {
            Double(a.sufferScore ?? 0)
        }

        let recentActivities = activities.filter { $0.startDate > sixWeeksAgo }
        let weekActivities = recentActivities.filter { $0.startDate > oneWeekAgo }

        let atl = weekActivities.reduce(0.0) { $0 + sufferScore($1) } / 7.0
        let ctl = recentActivities.reduce(0.0) { $0 + sufferScore($1) } / 42.0

        return TrainingLoad(atl: atl * 10, ctl: ctl * 10)
    }
}
