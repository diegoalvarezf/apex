import Foundation

// Valores diarios que alimentan el calendario mensual.
//
// Cada métrica tiene un historial distinto porque depende de datos distintos, y eso
// se declara aquí en vez de dejar que el calendario aparente más de lo que hay:
//
// - Body Battery: los cierres de día que el propio store va guardando (30 días).
// - Recuperación: el histórico ya calculado a partir de sueño y HRV.
// - Estrés: se recalcula por día desde la FC horaria, igual que el tile del inicio.
enum MetricCalendarData {

    // @MainActor porque lee las propiedades publicadas de HealthKitManager.
    @MainActor
    static func values(
        for metric: MetricCalendarView.Metric,
        healthKit: HealthKitManager,
        activities: [StravaActivity]
    ) -> [Date: Int] {
        switch metric {
        case .battery:  return battery()
        case .recovery: return recovery(healthKit.recoveryHistory)
        case .stress:   return stress(hourlyHR: healthKit.recentHourlyHR,
                                      hrvHistory: healthKit.hrvHistory,
                                      restingHR: healthKit.todaySummary?.restingHR)
        }
    }

    static func disponibilidad(_ metric: MetricCalendarView.Metric) -> String {
        switch metric {
        case .battery:  return "Se guarda el cierre de cada día, hasta 30 días atrás."
        case .recovery: return "Necesita sueño y HRV de esa noche: últimos 30 días."
        case .stress:   return "Se calcula con la frecuencia cardíaca del día: últimos 30 días."
        }
    }

    // MARK: - Por métrica

    private static func battery() -> [Date: Int] {
        BodyBatteryStore.shared.storedDailyValues().mapValues { Int($0.rounded()) }
    }

    private static func recovery(_ history: [MetricSample]) -> [Date: Int] {
        let cal = Calendar.current
        var out: [Date: Int] = [:]
        for s in history {
            out[cal.startOfDay(for: s.date)] = Int(s.value.rounded())
        }
        return out
    }

    // Media diaria del estrés horario, con la misma fórmula que el tile del inicio:
    // base autonómica por HRV + empuje por la FC de cada hora.
    private static func stress(
        hourlyHR: [MetricSample],
        hrvHistory: [HRVData],
        restingHR: Double?
    ) -> [Date: Int] {
        guard !hourlyHR.isEmpty else { return [:] }
        let cal = Calendar.current
        let rhr = restingHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)

        // Agrupar la FC por día en una pasada; con 30 días son ~720 muestras.
        var porDia: [Date: [Double]] = [:]
        for s in hourlyHR {
            porDia[cal.startOfDay(for: s.date), default: []].append(s.value)
        }

        var out: [Date: Int] = [:]
        for (dia, valores) in porDia where !valores.isEmpty {
            // Baseline de HRV con las noches ANTERIORES a ese día, para no usar
            // información que aquel día todavía no existía.
            let previas = hrvHistory.filter { $0.date < dia }.map(\.sdnn)
            let deEseDia = hrvHistory.first { cal.isDate($0.date, inSameDayAs: dia) }?.sdnn
            let base = TrainingMetrics.hrvBaseStress(todaySDNN: deEseDia, baseline: previas)

            let estres = valores.map {
                TrainingMetrics.physiologicalStress(hr: $0, restingHR: rhr, maxHR: maxHR, hrvBase: base)
            }
            let media = estres.reduce(0, +) / Double(estres.count)
            out[dia] = Int(media.rounded())
        }
        return out
    }
}
