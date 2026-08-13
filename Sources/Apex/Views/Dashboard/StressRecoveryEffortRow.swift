import SwiftUI

// MARK: - Grid 2×2: Estrés · Recuperación · Esfuerzo · Batería

struct StressRecoveryEffortRow: View {
    let recoveryScore: RecoveryScore?
    let recoveryHistory: [MetricSample]
    let activities: [StravaActivity]
    let hrvHistory: [HRVData]
    let rhrHistory: [MetricSample]
    let todayRHR: Double?
    let hourlyHR: [MetricSample]
    let todayActiveKcal: Double
    var trainingLoad: TrainingLoad? = nil
    var sleep: SleepData? = nil
    var sleepHistory: [SleepData] = []

    // Estrés fisiológico estilo Firstbeat: base autonómica por HRV (con suelo en
    // reposo) + empuje por la FC del momento. El valor diario es la MEDIA de las
    // muestras horarias, igual que la gráfica horaria interior.
    private var stressValue: Int {
        let s = todayHourlyStress
        guard !s.isEmpty else { return Int(hrvBaseStress.rounded()) }
        return Int((s.map(\.value).reduce(0, +) / Double(s.count)).rounded())
    }

    // Base autonómica de estrés (HRV de hoy vs baseline personal de 60 días)
    private var hrvBaseStress: Double {
        let sorted = hrvHistory.sorted { $0.date > $1.date }
        let today = sorted.first?.sdnn
        let baseline = Array(sorted.dropFirst().map(\.sdnn))
        return TrainingMetrics.hrvBaseStress(todaySDNN: today, baseline: baseline)
    }

    private func hourlyStress(samples: [MetricSample]) -> [MetricSample] {
        let rhr: Double = todayRHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        let base = hrvBaseStress
        return samples.map { s in
            let stress = TrainingMetrics.physiologicalStress(hr: s.value, restingHR: rhr, maxHR: maxHR, hrvBase: base)
            return MetricSample(date: s.date, value: stress)
        }.sorted { $0.date < $1.date }
    }

    // Estrés horario de HOY — lo mismo que se ve dentro al pulsar
    private var todayHourlyStress: [MetricSample] {
        let today = Calendar.current.startOfDay(for: Date())
        return hourlyStress(samples: hourlyHR.filter { $0.date >= today })
    }

    // Media diaria de estrés de los últimos 7 días (para tendencia y páginas de detalle)
    private var stressTrendHistory: [MetricSample] {
        let cal = Calendar.current
        return (0...6).compactMap { offset -> MetricSample? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { return nil }
            let daySamples = hourlyStress(samples: hourlyHR.filter { cal.isDate($0.date, inSameDayAs: day) })
            guard !daySamples.isEmpty else { return nil }
            return MetricSample(date: day, value: daySamples.map(\.value).reduce(0, +) / Double(daySamples.count))
        }.sorted { $0.date < $1.date }
    }
    private var stressTrend: MetricTrend { computeTrend(samples: stressTrendHistory) }

    private var recoveryValue: Int { recoveryScore?.value ?? 0 }
    // HRV de las últimas 2 semanas — la métrica principal que muestra el interior
    private var hrvSamples: [MetricSample] {
        hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }
            .sorted { $0.date < $1.date }.suffix(14).map { $0 }
    }
    private var recoveryTrend: MetricTrend { computeTrend(samples: recoveryHistory) }

    // Esfuerzo diario — TRIMP de Edwards (tiempo en zonas de FC), la misma
    // metodología que documenta PeakWatch para su Exertion Score: FCmáx = máxima
    // registrada y "accumulated time spent in different heart rate zones".
    // Incluye actividades Strava + toda la FC de fondo del día.
    private func trimpStrain(forDay day: Date) -> Double {
        let rhr = todayRHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        let trimp = TrainingMetrics.dailyEffortTRIMP(
            day: day, activities: activities, hourlyHR: hourlyHR,
            restingHR: rhr, maxHR: maxHR, isMale: UserProfile.isMale)
        return Double(TrainingMetrics.effortScore(dailyTRIMP: trimp))
    }

    private var todayKcal: Double {
        let stravaKcal: Double = {
            let today = Calendar.current.startOfDay(for: Date())
            return activities.filter { $0.startDate >= today }
                .compactMap { $0.kilojoules }.reduce(0, +) * 0.239
        }()
        return stravaKcal > 0 ? stravaKcal : todayActiveKcal
    }

    private var effortValue: Int { Int(trimpStrain(forDay: Date())) }

    // Historial TRIMP de los últimos 7 días para el sparkline
    private var effortHistory: [MetricSample] {
        let cal = Calendar.current
        return (0...6).compactMap { offset -> MetricSample? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { return nil }
            let strain = trimpStrain(forDay: day)
            return strain > 0 ? MetricSample(date: day, value: strain) : nil
        }.sorted { $0.date < $1.date }
    }
    private var effortTrend: MetricTrend { computeTrend(samples: effortHistory) }

    private var stressColor: Color {
        stressValue < 30 ? .green : stressValue < 60 ? .orange : .red
    }
    private var recoveryColor: Color {
        recoveryValue >= 80 ? .green : recoveryValue >= 60 ? .cyan : recoveryValue >= 40 ? .yellow : .red
    }
    private var effortColor: Color {
        effortValue < 40 ? .blue : effortValue < 70 ? .orange : .red
    }

    // MARK: Body Battery — usa BodyBatteryStore (acumulativo entre días, igual que PeakWatch)
    private var batteryHourlySamples: [MetricSample] {
        BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recoveryScore, sleepHistory: sleepHistory,
            hourlyHR: hourlyHR, restingHR: todayRHR,
            recoveryHistory: recoveryHistory, activities: activities,
            hrvHistory: hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) })
    }
    private var currentBattery: Int {
        Int(batteryHourlySamples.last?.value ?? Double(recoveryScore?.value ?? 0))
    }
    private var batteryColor: Color {
        currentBattery >= 80 ? .green : currentBattery >= 60 ? .cyan : currentBattery >= 40 ? .yellow : .red
    }
    private var batteryTrend: MetricTrend { computeTrend(samples: batteryHourlySamples) }

    // Sin FC horaria ni recuperación, la simulación arranca de un valor por defecto:
    // el número que sale no describe nada y no debe presentarse como medida.
    private var hasBatteryData: Bool { !hourlyHR.isEmpty || recoveryScore != nil }
    // El estrés parte de la base autonómica por HRV, que sin dato devuelve un valor
    // fijo. Hace falta al menos HRV o FC horaria para que signifique algo.
    private var hasStressData: Bool { !hrvHistory.isEmpty || !hourlyHR.isEmpty }
    // Un 0 de esfuerzo sin datos no significa "hoy no entrenaste", sino que no se
    // sabe: hace falta FC horaria o alguna actividad para poder afirmarlo.
    private var hasEffortData: Bool { !hourlyHR.isEmpty || !activities.isEmpty }

    // Etiquetas de estado (estilo PeakWatch)
    private var batteryStatusLabel: String {
        currentBattery >= 80 ? "Alta" : currentBattery >= 55 ? "Media" : currentBattery >= 30 ? "Baja" : "Muy baja"
    }
    private var stressStatusLabel: String {
        stressValue < 25 ? "Excelente" : stressValue < 45 ? "Normal" : stressValue < 65 ? "Moderado" : "Elevado"
    }
    private var effortStatusLabel: String {
        effortValue < 30 ? "Bajo" : effortValue < 55 ? "Moderado" : effortValue < 75 ? "Alto" : "Máximo"
    }

    // Gradientes por métrica
    private let recoveryGradient: [Color] = [.red, .orange, .yellow, .green, .mint]
    private let stressGradient:   [Color] = [.green, .yellow, .orange, .red]
    private let effortGradient:   [Color] = [.blue, .indigo, .purple]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Fila 1: Body Battery · Recuperación
            NavigationLink(destination: BodyBatteryDetailView(
                score: recoveryScore, recentHourlyHR: hourlyHR, restingHR: todayRHR,
                sleepHistory: sleepHistory, recoveryHistory: recoveryHistory, activities: activities,
                hrvHistory: hrvSamples
            )) {
                PeakMetricTile(title: "Body Battery", icon: "bolt.heart.fill",
                               value: currentBattery,
                               statusLabel: hasBatteryData ? batteryStatusLabel : "Sin datos",
                               statusColor: hasBatteryData ? batteryColor : .secondary,
                               hasData: hasBatteryData) {
                    TrendSparkline(samples: batteryHourlySamples, color: batteryColor, height: 40)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(destination: RecoveryDetailView(
                score: recoveryScore, history: recoveryHistory,
                color: recoveryColor, hrvHistory: hrvHistory, rhrHistory: rhrHistory, todayRHR: todayRHR
            )) {
                PeakMetricTile(title: "Recuperación", icon: "arrow.up.heart.fill",
                               value: recoveryValue,
                               statusLabel: recoveryScore?.label ?? "Sin datos",
                               statusColor: recoveryScore == nil ? .secondary : recoveryColor,
                               hasData: recoveryScore != nil) {
                    MetricGradientBar(value: recoveryValue, gradient: recoveryGradient)
                }
            }
            .buttonStyle(.plain)

            // Fila 2: Estrés · Esfuerzo
            NavigationLink(destination: StressDetailView(
                value: stressValue, history: stressTrendHistory,
                color: stressColor, activities: activities, recentHourlyHR: hourlyHR, restingHR: todayRHR,
                hrvBase: hrvBaseStress
            )) {
                PeakMetricTile(title: "Estrés", icon: "brain.head.profile",
                               value: stressValue,
                               statusLabel: hasStressData ? stressStatusLabel : "Sin datos",
                               statusColor: hasStressData ? stressColor : .secondary,
                               hasData: hasStressData) {
                    MetricGauge(value: stressValue, gradient: stressGradient)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(destination: EffortDetailView(
                value: effortValue, todayKcal: todayKcal, todayActiveKcal: todayActiveKcal,
                hourlyHR: hourlyHR, restingHR: todayRHR, history: effortHistory, color: effortColor, activities: activities
            )) {
                PeakMetricTile(title: "Esfuerzo", icon: "bolt.fill",
                               value: effortValue,
                               statusLabel: hasEffortData ? effortStatusLabel : "Sin datos",
                               statusColor: hasEffortData ? effortColor : .secondary,
                               hasData: hasEffortData) {
                    MetricGradientBar(value: effortValue, gradient: effortGradient, showTicks: true)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

