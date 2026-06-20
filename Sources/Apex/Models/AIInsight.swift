import Foundation

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
        case recovery = "Recuperación"
        case training = "Entrenamiento"
        case sleep = "Sueño"
        case nutrition = "Nutrición"
        case performance = "Rendimiento"

        var icon: String {
            switch self {
            case .recovery: return "bolt.heart.fill"
            case .training: return "figure.run"
            case .sleep: return "moon.stars.fill"
            case .nutrition: return "fork.knife"
            case .performance: return "chart.line.uptrend.xyaxis"
            }
        }

        var color: String {
            switch self {
            case .recovery: return "#00C853"
            case .training: return "#2979FF"
            case .sleep: return "#7C4DFF"
            case .nutrition: return "#FF6D00"
            case .performance: return "#00BCD4"
            }
        }
    }

    enum Priority: String, Codable {
        case high, medium, low
    }
}

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
        parts.append("Eres un entrenador deportivo de élite y experto en ciencias del deporte. Analiza los siguientes datos del atleta y proporciona insights concisos y accionables en español.")
        parts.append("")

        if let recovery = recoveryScore {
            parts.append("RECUPERACIÓN ACTUAL: \(recovery.value)/100 (\(recovery.label))")
            parts.append("- Sueño: \(recovery.sleepScore)/100")
            parts.append("- HRV: \(recovery.hrvScore)/100")
            parts.append("- Carga de entrenamiento: \(recovery.trainingLoadScore)/100")
        }

        if let load = trainingLoad {
            parts.append("")
            parts.append("CARGA DE ENTRENAMIENTO:")
            parts.append("- ATL (7 días): \(String(format: "%.0f", load.atl))")
            parts.append("- CTL (42 días): \(String(format: "%.0f", load.ctl))")
            parts.append("- Forma (TSB): \(String(format: "%.0f", load.tsb)) → \(load.formStatus.rawValue)")
        }

        if let hrv = latestHRV {
            parts.append("")
            parts.append("HRV ÚLTIMA MEDICIÓN: \(String(format: "%.0f", hrv.sdnn)) ms")
        }

        if let rhr = restingHR {
            parts.append("FC EN REPOSO: \(String(format: "%.0f", rhr)) bpm")
        }

        if let vo2 = vo2Max {
            parts.append("VO2MAX: \(String(format: "%.1f", vo2)) ml/kg/min")
        }

        if !sleepLast7Days.isEmpty {
            parts.append("")
            parts.append("SUEÑO (últimos 7 días):")
            for sleep in sleepLast7Days.prefix(7) {
                parts.append("- \(sleep.formattedTotal) | Profundo: \(String(format: "%.0f", sleep.deepSleep / 3600 * 60))min | Score: \(sleep.score)/100")
            }
        }

        if !recentActivities.isEmpty {
            parts.append("")
            parts.append("ACTIVIDADES RECIENTES:")
            for act in recentActivities.prefix(5) {
                var actLine = "- \(act.sportEmoji) \(act.name): \(act.formattedDistance), \(act.formattedDuration)"
                if let hr = act.averageHeartrate {
                    actLine += ", FC avg \(String(format: "%.0f", hr))bpm"
                }
                if let watts = act.averageWatts {
                    actLine += ", \(String(format: "%.0f", watts))W avg"
                }
                parts.append(actLine)
            }
        }

        parts.append("")
        parts.append("Responde con un JSON con este formato exacto:")
        parts.append("""
{
  "insights": [
    {
      "category": "recovery|training|sleep|nutrition|performance",
      "title": "Título corto (máx 8 palabras)",
      "body": "Análisis de 2-3 frases concisas",
      "recommendations": ["Acción concreta 1", "Acción concreta 2"],
      "priority": "high|medium|low"
    }
  ]
}
""")
        parts.append("Genera 2-3 insights relevantes y accionables basados estrictamente en los datos.")

        return parts.joined(separator: "\n")
    }
}
