import Foundation
import SwiftUI

// MARK: - Claude-powered insights (InsightsView)

struct AIInsight: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let category: Category
    let title: String
    let body: String
    let recommendations: [String]
    let priority: Priority

    init(category: Category, title: String, body: String, recommendations: [String], priority: Priority = .medium) {
        self.id = UUID()
        self.createdAt = Date()
        self.category = category
        self.title = title
        self.body = body
        self.recommendations = recommendations
        self.priority = priority
    }

    enum Category: String, Codable {
        // rawValues match exactly what Claude returns (lowercase English)
        case recovery, training, sleep, nutrition, performance

        var displayName: String {
            switch self {
            case .recovery:    return "Recuperación"
            case .training:    return "Entrenamiento"
            case .sleep:       return "Sueño"
            case .nutrition:   return "Nutrición"
            case .performance: return "Rendimiento"
            }
        }

        var icon: String {
            switch self {
            case .recovery:    return "bolt.heart.fill"
            case .training:    return "figure.run"
            case .sleep:       return "moon.stars.fill"
            case .nutrition:   return "fork.knife"
            case .performance: return "chart.line.uptrend.xyaxis"
            }
        }

        var color: Color {
            switch self {
            case .recovery:    return .green
            case .training:    return .blue
            case .sleep:       return .purple
            case .nutrition:   return .orange
            case .performance: return .cyan
            }
        }
    }

    enum Priority: String, Codable {
        case high, medium, low
    }
}

// MARK: - Smart contextual tips (computed locally, no API)

struct SmartTip: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let urgency: Urgency

    enum Urgency: Int { case info = 0, warn = 1, alert = 2 }
}

enum SmartTipsEngine {
    static func compute(
        recovery: RecoveryScore?,
        sleep: SleepData?,
        sleepHistory: [SleepData],
        hourlyHR: [MetricSample],
        rhr: Double?,
        rhrHistory: [MetricSample],
        hrvHistory: [HRVData],
        activities: [StravaActivity]
    ) -> [SmartTip] {
        var tips: [SmartTip] = []

        // ── Recuperación ───────────────────────────────────────────────
        if let r = recovery {
            if r.value < 35 {
                tips.append(SmartTip(
                    icon: "exclamationmark.triangle.fill", color: .red,
                    title: "Recuperación muy baja (\(r.value)/100)",
                    detail: "Hoy no es día de entrenar. Camina, estira o descansa.",
                    urgency: .alert
                ))
            } else if r.value < 60 {
                tips.append(SmartTip(
                    icon: "arrow.down.heart.fill", color: .orange,
                    title: "Recuperación moderada (\(r.value)/100)",
                    detail: "Mantén la intensidad baja — zona 1-2 máximo.",
                    urgency: .warn
                ))
            } else if r.value >= 85 {
                tips.append(SmartTip(
                    icon: "bolt.fill", color: .green,
                    title: "Cuerpo listo para rendir (\(r.value)/100)",
                    detail: "Indicadores en verde — buen momento para sesión de calidad.",
                    urgency: .info
                ))
            }
        }

        // ── Sueño ──────────────────────────────────────────────────────
        if let s = sleep {
            let hours = s.totalSleep / 3600
            if hours < 6 {
                tips.append(SmartTip(
                    icon: "moon.zzz.fill", color: .purple,
                    title: "Sueño insuficiente (\(String(format: "%.1f", hours))h)",
                    detail: "Menos de 6h afecta al rendimiento y a la recuperación muscular.",
                    urgency: .alert
                ))
            } else if hours < 7 {
                tips.append(SmartTip(
                    icon: "moon.fill", color: .indigo,
                    title: "Sueño por debajo de tu óptimo",
                    detail: "Intenta acostarte 30 min antes esta noche.",
                    urgency: .warn
                ))
            }
            if s.deepSleep / s.totalSleep < 0.12 && s.totalSleep > 3600 {
                tips.append(SmartTip(
                    icon: "waveform.path", color: .purple,
                    title: "Sueño profundo escaso",
                    detail: "Evita alcohol y pantallas 1h antes de dormir para más sueño profundo.",
                    urgency: .warn
                ))
            }
        }

        // Déficit sueño acumulado (últimas 3 noches)
        let last3 = Array(sleepHistory.prefix(3))
        if last3.count == 3 {
            let totalH: Double = last3.reduce(0.0) { $0 + $1.totalSleep / 3600.0 }
            let avgH: Double = totalH / 3.0
            if avgH < 6.5 {
                tips.append(SmartTip(
                    icon: "bed.double.fill", color: .purple,
                    title: "Déficit de sueño acumulado",
                    detail: "Media de \(String(format: "%.1f", avgH))h en 3 noches — deuda de sueño activa.",
                    urgency: .warn
                ))
            }
        }

        // ── HRV ───────────────────────────────────────────────────────
        if hrvHistory.count >= 7 {
            let recent: Double = hrvHistory.first.map { $0.sdnn } ?? 0.0
            let sdnnVals: [Double] = hrvHistory.prefix(7).map { $0.sdnn }
            let baseline: Double = sdnnVals.reduce(0.0, +) / 7.0
            let drop: Double = baseline > 0.0 ? (baseline - recent) / baseline : 0.0
            if drop > 0.2 {
                tips.append(SmartTip(
                    icon: "waveform.path.ecg", color: .red,
                    title: "HRV \(Int(drop * 100))% por debajo de tu media",
                    detail: "Señal de estrés acumulado. Prioriza descanso y alimentación.",
                    urgency: .alert
                ))
            } else if drop > 0.1 {
                tips.append(SmartTip(
                    icon: "waveform.path.ecg", color: .orange,
                    title: "HRV ligeramente deprimida",
                    detail: "El sistema nervioso señala algo de fatiga. Día suave recomendado.",
                    urgency: .warn
                ))
            }
        }

        // ── Esfuerzo acumulado (Edwards TRIMP últimos 2 días) ─────────
        let rhrVal = rhr ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        let cal = Calendar.current

        func effortForDay(_ day: Date) -> Int {
            let trimp = TrainingMetrics.dailyEffortTRIMP(day: day, activities: activities,
                hourlyHR: hourlyHR, restingHR: rhrVal, maxHR: maxHR, isMale: UserProfile.isMale)
            return TrainingMetrics.effortScore(dailyTRIMP: trimp)
        }

        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let dayBefore = cal.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        // Alerta si dos días seguidos con esfuerzo alto (score ≥70 cada uno)
        if effortForDay(yesterday) >= 70 && effortForDay(dayBefore) >= 70 {
            tips.append(SmartTip(
                icon: "flame.fill", color: .orange,
                title: "Carga alta acumulada (2 días)",
                detail: "Llevas 2 días de entrenamiento intenso. Hoy considera recuperación activa.",
                urgency: .warn
            ))
        }

        // ── Actividad reciente ─────────────────────────────────────────
        let lastAct = activities.first
        if let act = lastAct, let elapsed = cal.dateComponents([.hour], from: act.startDate, to: Date()).hour {
            if elapsed < 24, let hr = act.averageHeartrate, hr > 165 {
                tips.append(SmartTip(
                    icon: "heart.fill", color: .red,
                    title: "Sesión intensa reciente",
                    detail: "FC media de \(Int(hr))bpm en \(act.name). Espera 48h antes de otra sesión dura.",
                    urgency: .warn
                ))
            }
        }

        // ── Racha sin actividad ────────────────────────────────────────
        if let last = activities.first {
            let daysSince = cal.dateComponents([.day], from: last.startDate, to: Date()).day ?? 0
            if daysSince >= 5 {
                tips.append(SmartTip(
                    icon: "figure.walk", color: .blue,
                    title: "Sin actividad en \(daysSince) días",
                    detail: "Una salida suave reactiva el metabolismo aeróbico.",
                    urgency: .info
                ))
            }
        }

        // Sort: alert > warn > info
        return tips.sorted { $0.urgency.rawValue > $1.urgency.rawValue }
    }
}

// MARK: - Claude prompt builder

struct AICoachContext {
    let recentActivities: [StravaActivity]
    let sleepLast7Days: [SleepData]
    let latestHRV: HRVData?
    let restingHR: Double?
    let vo2Max: Double?
    let trainingLoad: TrainingLoad?
    let recoveryScore: RecoveryScore?
    var strengthSummary: String? = nil   // progresión de pesos del gimnasio
    var localAlerts: String? = nil        // alertas que el usuario ya ve (para no repetirlas)

    // Bloque de datos compartido por insights y resumen semanal
    private func metricsBlock() -> [String] {
        let cal = Calendar.current
        let now = Date()
        var parts: [String] = []

        if let recovery = recoveryScore {
            parts.append("RECUPERACIÓN: \(recovery.value)/100 — HRV:\(recovery.hrvScore) FCreposo:\(recovery.restingHRScore)")
        }
        if let load = trainingLoad {
            let acwrLabel: String
            switch load.acwr {
            case ..<0.8:    acwrLabel = "subentrenado (poca carga)"
            case 0.8..<1.3: acwrLabel = "óptimo"
            case 1.3..<1.5: acwrLabel = "elevado (fatiga acumulada)"
            default:        acwrLabel = "riesgo (sobreentrenamiento)"
            }
            parts.append("CARGA — Fitness(CTL):\(String(format: "%.0f", load.ctl)) Fatiga(ATL):\(String(format: "%.0f", load.atl)) ACWR:\(String(format: "%.2f", load.acwr)) [\(acwrLabel)] Forma(TSB):\(String(format: "%+.0f", load.tsb))")
        }
        if let hrv = latestHRV { parts.append("HRV: \(String(format: "%.0f", hrv.sdnn))ms") }
        if let rhr = restingHR { parts.append("FC reposo: \(String(format: "%.0f", rhr))bpm") }
        if let vo2 = vo2Max { parts.append("VO2max: \(String(format: "%.1f", vo2))ml/kg/min") }

        // ── Resumen semanal de entrenamiento (esta semana vs la anterior) ──
        func window(_ from: Int, _ to: Int) -> [StravaActivity] {
            let lo = cal.date(byAdding: .day, value: -from, to: now)!
            let hi = cal.date(byAdding: .day, value: -to, to: now)!
            return recentActivities.filter { $0.startDate >= lo && $0.startDate < hi }
        }
        func summ(_ acts: [StravaActivity]) -> String {
            let h = acts.reduce(0.0) { $0 + Double($1.movingTime) } / 3600.0
            let elev = acts.reduce(0.0) { $0 + $1.totalElevationGain }
            return String(format: "%d sesiones, %.1fh, %.0fm desnivel", acts.count, h, elev)
        }
        parts.append("VOLUMEN — Últimos 7d: \(summ(window(7, 0))) · 7d previos: \(summ(window(14, 7)))")

        // ── Sesiones recientes con detalle ────────────────────────────────
        if !recentActivities.isEmpty {
            parts.append("SESIONES RECIENTES:")
            for a in recentActivities.prefix(8) {
                let daysAgo = cal.dateComponents([.day], from: a.startDate, to: now).day ?? 0
                var line = "  hace \(daysAgo)d \(a.sportEmoji) \(a.name): \(a.formattedDistance) \(a.formattedDuration)"
                if a.distance > 0 { line += " ritmo_medio:\(a.formattedPace)" }
                if let hr = a.averageHeartrate { line += " FCmedia:\(Int(hr))" }
                if a.totalElevationGain > 50 { line += " +\(Int(a.totalElevationGain))m" }
                if let np = a.averageWatts { line += " \(Int(np))W" }
                if let ss = a.sufferScore { line += " esfuerzo:\(ss)" }
                if a.isStructuredWorkout { line += " [INTERVALOS/serie: ritmo variable por diseño]" }
                parts.append(line)
            }
            parts.append("  (Nota: estos son PROMEDIOS de sesión. En sesiones marcadas como intervalos, un ritmo medio lento con FC alta es NORMAL — son las recuperaciones las que bajan el promedio; NO lo interpretes como mala economía o ritmo irregular.)")
        }

        // ── Progresión de fuerza (gimnasio) ───────────────────────────────
        if let strength = strengthSummary, !strength.isEmpty {
            parts.append("PROGRESIÓN DE FUERZA (peso por ejercicio, de más antiguo a reciente):")
            parts.append(strength)
        }

        if !sleepLast7Days.isEmpty {
            parts.append("SUEÑO 7 días:")
            for s in sleepLast7Days.prefix(5) {
                parts.append("  \(s.formattedTotal) profundo:\(String(format: "%.0f", s.deepSleep/60))min score:\(s.score)")
            }
        }

        if let alerts = localAlerts, !alerts.isEmpty {
            parts.append("")
            parts.append("ALERTAS AUTOMÁTICAS QUE EL USUARIO YA VE (NO las repitas):")
            parts.append(alerts)
        }
        return parts
    }

    // Contexto en texto plano para el chat del coach (reutiliza el mismo bloque
    // de métricas que los insights).
    func contextText() -> String { metricsBlock().joined(separator: "\n") }

    // Regla común: la IA interpreta, pero NO inventa cifras.
    private static let noInventarCifras = "REGLA IMPORTANTE: usa SOLO las cifras que aparecen explícitamente en los datos de arriba. Nunca inventes ni estimes números, porcentajes, pesos, ritmos o valores que no te hayan dado. Si no tienes un dato, habla de la tendencia sin poner una cifra."

    func buildPrompt() -> String {
        var parts = ["Eres un entrenador deportivo de élite. Analiza SOBRE TODO los entrenamientos del usuario (sesiones recientes, carga, intensidad y progresión) junto con su recuperación, y da insights concisos y accionables en español.", ""]
        parts += metricsBlock()
        parts.append("""

NO repitas las alertas automáticas de arriba: el usuario ya las ve. Tu valor es ir MÁS ALLÁ — conecta varias señales entre sí (p.ej. carga + sueño + HRV), analiza la PROGRESIÓN (fuerza y fitness/CTL) y la PLANIFICACIÓN a días/semanas vista. Concretamente: ¿progresa la fuerza y el fitness? ¿la carga es adecuada o hay riesgo/estancamiento? ¿toca empujar, mantener o descargar? Sugiere ajustes concretos de la próxima sesión y de la progresión.

\(AICoachContext.noInventarCifras)

Responde SOLO con este JSON exacto (sin markdown):
{
  "insights": [
    {
      "category": "recovery|training|sleep|nutrition|performance",
      "title": "Título corto (max 8 palabras)",
      "body": "Análisis de 2-3 frases basado en SUS datos concretos",
      "recommendations": ["Acción 1", "Acción 2"],
      "priority": "high|medium|low"
    }
  ]
}
Genera 3-5 insights, priorizando los de entrenamiento (training/performance).
""")
        return parts.joined(separator: "\n")
    }

    // Resumen semanal en prosa (no JSON) para la tarjeta y la notificación
    func buildWeeklySummaryPrompt() -> String {
        var parts = ["Eres un entrenador deportivo de élite. Escribe el RESUMEN SEMANAL del usuario en español: qué tal ha ido la semana de entrenamiento, cómo evolucionan su carga/fitness y su progresión de fuerza, y qué enfocar la semana que viene.", ""]
        parts += metricsBlock()
        parts.append("""

Escribe 2 párrafos cortos (máx. 90 palabras en total), tono directo de coach, en TEXTO PLANO (sin markdown, sin listas, sin JSON). Párrafo 1: balance de la semana (volumen, carga, progresión). Párrafo 2: foco y ajuste concreto para la semana que viene.

\(AICoachContext.noInventarCifras)
""")
        return parts.joined(separator: "\n")
    }
}
