import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    // Cronológico, como el resto de series de la app: la más reciente al final.
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

    // ¿Ha terminado ya el primer intento de traer actividades?
    //
    // Al abrir la app, cargar Strava y pedir los análisis del día arrancan a la vez,
    // y Strava tarda más: pasa por renovar el token y por la red, mientras que
    // HealthKit responde al instante desde el dispositivo. Sin esperar, el análisis
    // se escribía sobre una lista de actividades todavía vacía —y como es de 1×/día,
    // esa foto equivocada se quedaba cacheada hasta el día siguiente—.
    //
    // Se marca también cuando no hay Strava conectado: entonces la lista vacía es la
    // respuesta correcta y no hay nada que esperar.
    @Published private(set) var activitiesSettled = false

    func markActivitiesSettled() { activitiesSettled = true }

    private let insightsKey = "apex_ai_insights_v1"
    private let insightsDateKey = "apex_ai_insights_date_v1"
    private let alertsKey = "apex_ai_alerts_v5"
    private let alertsDateKey = "apex_ai_alerts_date_v5"
    private let weeklyKey = "apex_ai_weekly_v1"
    private let weeklyDateKey = "apex_ai_weekly_date_v1"

    // El almacén se inyecta para que los tests no compartan el del dispositivo: si
    // no, un análisis cacheado por una prueba anterior contamina a la siguiente.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadCachedInsights()
    }

    struct LoadSample: Identifiable {
        let id = UUID()
        let date: Date
        let atl: Double
        let ctl: Double
        let tsb: Double
    }

    // MARK: - Caché de insights (evita re-llamar a la IA en cada visita)

    private func loadCachedInsights() {
        if let data = defaults.data(forKey: insightsKey),
           let decoded = try? JSONDecoder().decode([AIInsight].self, from: data) {
            insights = decoded
        }
        insightsGeneratedAt = defaults.object(forKey: insightsDateKey) as? Date
        weeklySummary = defaults.string(forKey: weeklyKey)
        weeklySummaryAt = defaults.object(forKey: weeklyDateKey) as? Date
        if let data = defaults.data(forKey: alertsKey),
           let decoded = try? JSONDecoder().decode([AIAlert].self, from: data) {
            aiAlerts = decoded
        }
        aiAlertsAt = defaults.object(forKey: alertsDateKey) as? Date
    }

    // MARK: - Alertas del día escritas por la IA (1×/día, cacheadas)

    private struct AlertsWrapper: Decodable { let alerts: [AIAlert] }

    // Forzar regeneración (botón manual), aunque ya haya alertas de hoy
    func reloadAlerts(health: HealthKitManager, strengthSummary: String? = nil) async {
        await loadAlertsIfStale(health: health, strengthSummary: strengthSummary, force: true)
    }

    func loadAlertsIfStale(health: HealthKitManager, strengthSummary: String? = nil, force: Bool = false) async {
        // Solo una vez al día (salvo forzado): el resto se sirve de caché
        if !force, let at = aiAlertsAt, Calendar.current.isDateInToday(at), !aiAlerts.isEmpty { return }
        // Esperar a que Strava haya contestado: escribir las alertas del día sobre
        // una lista de actividades a medio cargar deja "sin entrenar" a quien sí
        // entrenó, y cacheado hasta mañana.
        guard activitiesSettled else { return }
        guard !activities.isEmpty || health.recoveryScore != nil else { return }
        guard !isLoadingAlerts else { return }
        isLoadingAlerts = true
        defer { isLoadingAlerts = false }

        let context = buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
        do {
            let text = try await AIService.shared.analyze(
                .alerts, input: context.buildAlertsPrompt())
            guard let json = AIService.extractJSON(from: text),
                  let data = json.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(AlertsWrapper.self, from: data),
                  !parsed.alerts.isEmpty else { return }
            aiAlerts = parsed.alerts
            aiAlertsAt = Date()
            if let enc = try? JSONEncoder().encode(aiAlerts) {
                defaults.set(enc, forKey: alertsKey)
            }
            defaults.set(aiAlertsAt, forKey: alertsDateKey)
        } catch {
            // Sin red o fallo de la API: se mantienen las reglas locales
        }
    }

    // ¿Hay materia prima para un análisis? Se comparte entre insights y alertas.
    func hasDataToAnalyze(health: HealthKitManager) -> Bool {
        !activities.isEmpty || health.recoveryScore != nil
    }

    private func saveCachedInsights() {
        if let data = try? JSONEncoder().encode(insights) {
            defaults.set(data, forKey: insightsKey)
        }
        defaults.set(insightsGeneratedAt, forKey: insightsDateKey)
    }

    // MARK: - Resumen semanal IA (1×/semana, cacheado)

    // Contexto para el chat del coach (público)
    func coachContext(health: HealthKitManager, strengthSummary: String?) -> AICoachContext {
        buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
    }

    private func buildContext(health: HealthKitManager, strengthSummary: String?, localAlerts: String?) -> AICoachContext {
        AICoachContext(
            recentActivities: Array(activities.suffix(15)),
            sleepLast7Days: Array(health.sleepHistory.suffix(7)),
            latestHRV: health.hrvHistory.last,
            restingHR: health.todaySummary?.restingHR,
            vo2Max: health.displayVO2Max?.value,
            trainingLoad: trainingLoad,
            recoveryScore: health.recoveryScore,
            strengthSummary: strengthSummary,
            localAlerts: localAlerts
        )
    }

    // Forzar regeneración (botón manual), aunque ya haya uno de esta semana
    func reloadWeeklySummary(health: HealthKitManager, strengthSummary: String? = nil) async {
        await loadWeeklySummaryIfStale(health: health, strengthSummary: strengthSummary, force: true)
    }

    // Genera el resumen solo si no hay uno de la SEMANA actual (salvo forzado)
    func loadWeeklySummaryIfStale(health: HealthKitManager, strengthSummary: String? = nil, force: Bool = false) async {
        let cal = Calendar.current
        let sameWeek = weeklySummaryAt.map {
            cal.isDate($0, equalTo: Date(), toGranularity: .weekOfYear)
        } ?? false
        if !force, sameWeek, weeklySummary != nil { return }
        guard activitiesSettled else { return }
        guard !activities.isEmpty || health.recoveryScore != nil else { return }
        guard !isLoadingWeekly else { return }
        isLoadingWeekly = true
        defer { isLoadingWeekly = false }

        let context = buildContext(health: health, strengthSummary: strengthSummary, localAlerts: nil)
        do {
            // El modelo lo elige el servidor: Sonnet basta para cuatro viñetas
            // sobre métricas ya calculadas.
            let text = try await AIService.shared.analyze(
                .weekly, input: context.buildWeeklySummaryPrompt())
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            weeklySummary = clean
            weeklySummaryAt = Date()
            defaults.set(clean, forKey: weeklyKey)
            defaults.set(weeklySummaryAt, forKey: weeklyDateKey)
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
            activities = fetched.sorted { $0.startDate < $1.startDate }   // cronológico: la más reciente al final
            let (load, history) = computeTrainingLoad(from: activities)
            trainingLoad = load
            loadHistory = history
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadInsights(health: HealthKitManager, strengthSummary: String? = nil, localAlerts: String? = nil) async {
        // Sin actividades ni recuperación no hay nada que analizar, y pedírselo al
        // modelo igualmente le hace redactar conclusiones a partir del vacío
        // ("semana en blanco", "fitness en caída libre"). Mismo guard que las alertas.
        guard hasDataToAnalyze(health: health) else { return }
        guard !isLoadingInsights else { return }
        isLoadingInsights = true
        defer { isLoadingInsights = false }

        let context = AICoachContext(
            recentActivities: Array(activities.suffix(15)),
            sleepLast7Days: Array(health.sleepHistory.suffix(7)),
            latestHRV: health.hrvHistory.last,
            restingHR: health.todaySummary?.restingHR,
            vo2Max: health.displayVO2Max?.value,
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
        guard activitiesSettled else { return }
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
