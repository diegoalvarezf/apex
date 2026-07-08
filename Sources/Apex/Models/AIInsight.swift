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

    func buildPrompt() -> String {
        var parts: [String] = []
        parts.append("Eres un entrenador deportivo de élite. Analiza los datos y da insights concisos y accionables en español.")
        parts.append("")

        if let recovery = recoveryScore {
            parts.append("RECUPERACIÓN: \(recovery.value)/100 — Sueño:\(recovery.sleepScore) HRV:\(recovery.hrvScore) Carga:\(recovery.trainingLoadScore)")
        }
        if let load = trainingLoad {
            let acwrLabel: String
            switch load.acwr {
            case ..<0.8:    acwrLabel = "subentrenado (poca carga)"
            case 0.8..<1.3: acwrLabel = "óptimo"
            case 1.3..<1.5: acwrLabel = "elevado (fatiga acumulada)"
            default:        acwrLabel = "riesgo (sobreentrenamiento)"
            }
            parts.append("CARGA — ATL:\(String(format: "%.1f", load.atl)) CTL:\(String(format: "%.1f", load.ctl)) ACWR:\(String(format: "%.2f", load.acwr)) Estado:\(acwrLabel)")
        }
        if let hrv = latestHRV { parts.append("HRV: \(String(format: "%.0f", hrv.sdnn))ms") }
        if let rhr = restingHR { parts.append("FC reposo: \(String(format: "%.0f", rhr))bpm") }
        if let vo2 = vo2Max { parts.append("VO2max: \(String(format: "%.1f", vo2))ml/kg/min") }

        if !sleepLast7Days.isEmpty {
            parts.append("SUEÑO 7 días:")
            for s in sleepLast7Days.prefix(5) {
                parts.append("  \(s.formattedTotal) profundo:\(String(format: "%.0f", s.deepSleep/60))min score:\(s.score)")
            }
        }
        if !recentActivities.isEmpty {
            parts.append("ACTIVIDADES:")
            for a in recentActivities.prefix(5) {
                var line = "  \(a.sportEmoji) \(a.name): \(a.formattedDistance) \(a.formattedDuration)"
                if let hr = a.averageHeartrate { line += " FC:\(Int(hr))bpm" }
                parts.append(line)
            }
        }

        parts.append("""

Responde SOLO con este JSON exacto (sin markdown):
{
  "insights": [
    {
      "category": "recovery|training|sleep|nutrition|performance",
      "title": "Título corto (max 8 palabras)",
      "body": "Análisis de 2-3 frases",
      "recommendations": ["Acción 1", "Acción 2"],
      "priority": "high|medium|low"
    }
  ]
}
Genera 3-4 insights relevantes y accionables.
""")
        return parts.joined(separator: "\n")
    }
}
