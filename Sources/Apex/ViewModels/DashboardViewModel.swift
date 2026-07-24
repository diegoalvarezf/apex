import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var activities: [StravaActivity] = []
    @Published var trainingLoad: TrainingLoad?
    @Published var loadHistory: [LoadSample] = []
    @Published var insights: [AIInsight] = []
    @Published var insightsGeneratedAt: Date?
    @Published var weeklySummary: String?
    @Published var weeklySummaryAt: Date?
    @Published var isLoadingActivities = false
    @Published var isLoadingInsights = false
    @Published var isLoadingWeekly = false
    @Published var error: String?

    @Published var aiAlerts: [AIAlert] = []
    @Published var aiAlertsAt: Date?
    @Published var isLoadingAlerts = false

    private let insightsKey = "apex_ai_insights_v1"
    private let insightsDateKey = "apex_ai_insights_date_v1"
    private let alertsKey = "apex_ai_alerts_v4"
    private let alertsDateKey = "apex_ai_alerts_date_v4"
    private let weeklyKey = "apex_ai_weekly_v1"
    private let weeklyDateKey = "apex_ai_weekly_date_v1"

    init() { loadCachedInsights() }

    struct LoadSample: Identifiable {
        let id = UUID()
        let date: Date
        let atl: Double
        let ctl: Double
        let tsb: Double
    }

    // MARK: - Caché de insights (evita re-llamar a la IA en cada visita)

    private func loadCachedInsights() {
        if let data = UserDefaults.standard.data(forKey: insightsKey),
           let decoded = try? JSONDecoder().decode([AIInsight].self, from: data) {
            insights = decoded
        }
        insightsGeneratedAt = UserDefaults.standard.object(forKey: insightsDateKey) as? Date
        weeklySummary = UserDefaults.standard.string(forKey: weeklyKey)
        weeklySummaryAt = UserDefaults.standard.object(forKey: weeklyDateKey) as? Date
        if let data = UserDefaults.standard.data(forKey: alertsKey),
           let decoded = try? JSONDecoder().decode([AIAlert].self, from: data) {
            aiAlerts = decoded
        }
        aiAlertsAt = UserDefaults.standard.object(forKey: alertsDateKey) as? Date
    }

    // MARK: - Alertas del día escritas por la IA (1×/día, cacheadas)

    private struct AlertsWrapper: Decodable { let alerts: [AIAlert] }

    func loadAlertsIfStale(health: HealthKitManager, strengthSummary: String? = nil) async {
        // Solo una vez al día: el resto se sirve de caché
        if let at = aiAlertsAt, Calendar.current.isDateInToday(at), !aiAlerts.isEmpty { return }
        guard !activities.isEmpty || health.recoveryScore != nil else { return }
        guard !isLoadingAlerts else { return }
        isLoadingAlerts = true
        defer { isLoadingAlerts = false }

        let context = buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
        do {
            let text = try await AIService.shared.rawCompletion(
                prompt: context.buildAlertsPrompt(), maxTokens: 700)
            guard let json = AIService.extractJSON(from: text),
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(AlertsWrapper.self, from: data),
                  !parsed.alerts.isEmpty else { return }
            aiAlerts = parsed.alerts
            aiAlertsAt = Date()
            if let enc = try? JSONEncoder().encode(aiAlerts) {
                UserDefaults.standard.set(enc, forKey: alertsKey)
            }
            UserDefaults.standard.set(aiAlertsAt, forKey: alertsDateKey)
        } catch {
            // Sin red o fallo de la API: se mantienen las reglas locales
        }
    }

    private func saveCachedInsights() {
        if let data = try? JSONEncoder().encode(insights) {
            UserDefaults.standard.set(data, forKey: insightsKey)
        }
        UserDefaults.standard.set(insightsGeneratedAt, forKey: insightsDateKey)
    }

    // MARK: - Resumen semanal IA (1×/semana, cacheado)

    // Contexto para el chat del coach (público)
    func coachContext(health: HealthKitManager, strengthSummary: String?) -> AICoachContext {
        buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
    }

    private func buildContext(health: HealthKitManager, strengthSummary: String?, localAlerts: String?) -> AICoachContext {
        AICoachContext(
            recentActivities: Array(activities.prefix(15)),
            sleepLast7Days: health.sleepHistory,
            latestHRV: health.hrvHistory.first,
            restingHR: health.todaySummary?.restingHR,
            vo2Max: health.todaySummary?.vo2Max,
            trainingLoad: trainingLoad,
            recoveryScore: health.recoveryScore,
            strengthSummary: strengthSummary,
            localAlerts: localAlerts
        )
    }

    // Genera el resumen solo si no hay uno de la SEMANA actual
    func loadWeeklySummaryIfStale(health: HealthKitManager, strengthSummary: String? = nil) async {
        let cal = Calendar.current
        let sameWeek = weeklySummaryAt.map {
            cal.isDate($0, equalTo: Date(), toGranularity: .weekOfYear)
        } ?? false
        if sameWeek, weeklySummary != nil { return }
        guard !activities.isEmpty || health.recoveryScore != nil else { return }
        guard !isLoadingWeekly else { return }
        isLoadingWeekly = true
        defer { isLoadingWeekly = false }

        let context = buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
        do {
            let text = try await AIService.shared.rawCompletion(
                prompt: context.buildWeeklySummaryPrompt(),
                model: ClaudeConfig.opusModel, maxTokens: 600)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            weeklySummary = clean
            weeklySummaryAt = Date()
            UserDefaults.standard.set(clean, forKey: weeklyKey)
            UserDefaults.standard.set(weeklySummaryAt, forKey: weeklyDateKey)
        } catch {
            // silencioso: el resumen semanal es secundario, no molesta al usuario con errores
        }
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

    func loadInsights(health: HealthKitManager, strengthSummary: String? = nil, localAlerts: String? = nil) async {
        guard !isLoadingInsights else { return }
        isLoadingInsights = true
        defer { isLoadingInsights = false }

        let context = AICoachContext(
            recentActivities: Array(activities.prefix(15)),
            sleepLast7Days: health.sleepHistory,
            latestHRV: health.hrvHistory.first,
            restingHR: health.todaySummary?.restingHR,
            vo2Max: health.todaySummary?.vo2Max,
            trainingLoad: trainingLoad,
            recoveryScore: health.recoveryScore,
            strengthSummary: strengthSummary,
            localAlerts: localAlerts
        )

        do {
            insights = try await AIService.shared.generateInsights(context: context)
            insightsGeneratedAt = Date()
            saveCachedInsights()
        } catch {
            self.error = "No se pudieron cargar los insights: \(error.localizedDescription)"
        }
    }

    // Ejecuta el análisis IA solo si no hay uno de hoy (auto 1×/día). El botón
    // "Actualizar análisis" sigue forzando una llamada nueva con loadInsights.
    func loadInsightsIfStale(health: HealthKitManager, strengthSummary: String? = nil, localAlerts: String? = nil) async {
        let hasToday = insightsGeneratedAt.map { Calendar.current.isDateInToday($0) } ?? false
        if hasToday && !insights.isEmpty { return }
        // No gastar en la IA si aún no hay datos que analizar
        guard !activities.isEmpty || health.recoveryScore != nil else { return }
        await loadInsights(health: health, strengthSummary: strengthSummary, localAlerts: localAlerts)
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
