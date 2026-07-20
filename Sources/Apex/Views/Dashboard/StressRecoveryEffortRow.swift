import Foundation
import SwiftUI
import Charts

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
                               value: currentBattery, statusLabel: batteryStatusLabel, statusColor: batteryColor) {
                    TrendSparkline(samples: batteryHourlySamples, color: batteryColor, height: 40)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(destination: RecoveryDetailView(
                score: recoveryScore, history: recoveryHistory,
                color: recoveryColor, hrvHistory: hrvHistory, rhrHistory: rhrHistory, todayRHR: todayRHR
            )) {
                PeakMetricTile(title: "Recuperación", icon: "arrow.up.heart.fill",
                               value: recoveryValue, statusLabel: recoveryScore?.label ?? "--", statusColor: recoveryColor) {
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
                               value: stressValue, statusLabel: stressStatusLabel, statusColor: stressColor) {
                    MetricGauge(value: stressValue, gradient: stressGradient)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(destination: EffortDetailView(
                value: effortValue, todayKcal: todayKcal, todayActiveKcal: todayActiveKcal,
                hourlyHR: hourlyHR, restingHR: todayRHR, history: effortHistory, color: effortColor, activities: activities
            )) {
                PeakMetricTile(title: "Esfuerzo", icon: "bolt.fill",
                               value: effortValue, statusLabel: effortStatusLabel, statusColor: effortColor) {
                    MetricGradientBar(value: effortValue, gradient: effortGradient, showTicks: true)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Stress Detail

struct StressDetailView: View {
    let value: Int
    let history: [MetricSample]
    let color: Color
    let activities: [StravaActivity]
    let recentHourlyHR: [MetricSample]   // últimos 7 días
    let restingHR: Double?
    var hrvBase: Double = 30

    private let cal = Calendar.current

    private var availableDays: [Date] {
        (0...6).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
    }

    @State private var selectedPage: Int = 6

    var body: some View {
        VStack(spacing: 0) {
            // Navegación de día
            HStack {
                Button { if selectedPage > 0 { withAnimation { selectedPage -= 1 } } } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(selectedPage > 0 ? .primary : .secondary)
                }
                Spacer()
                Text(availableDays[selectedPage], format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).fontWeight(.semibold)
                    .contentTransition(.numericText())
                Spacer()
                Button { if selectedPage < 6 { withAnimation { selectedPage += 1 } } } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(selectedPage < 6 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            TabView(selection: $selectedPage) {
                ForEach(availableDays.indices, id: \.self) { i in
                    DayStressPage(
                        day: availableDays[i],
                        todayValue: i == 6 ? value : dayStress(for: availableDays[i]),
                        hourlyHR: recentHourlyHR.filter { cal.isDate($0.date, inSameDayAs: availableDays[i]) },
                        restingHR: restingHR,
                        hrvBase: hrvBase,
                        color: color
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Estrés").navigationBarTitleDisplayMode(.inline)
    }

    private func dayStress(for day: Date) -> Int {
        let s = history.first { cal.isDate($0.date, inSameDayAs: day) }
        return Int(s?.value ?? Double(value))
    }
}

private struct DayStressPage: View {
    let day: Date
    let todayValue: Int
    let hourlyHR: [MetricSample]
    let restingHR: Double?
    var hrvBase: Double = 30
    let color: Color

    // Consejo IA con los datos reales de estrés
    private func stressAdvice() async throws -> String {
        var lines = [
            "Estrés fisiológico hoy: \(todayValue)/100.",
            "Base autonómica por HRV: \(Int(hrvBase.rounded()))/100 (más alta = HRV bajo frente a su media)."
        ]
        if let rhr = restingHR { lines.append("FC en reposo: \(Int(rhr)) bpm.") }
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        if let peak = hourlyHR.map(\.value).max() {
            lines.append("FC máxima del día: \(Int(peak)) bpm (FCmáx de referencia \(Int(maxHR))).")
        }
        let system = "Eres un entrenador experto en recuperación y sistema nervioso autónomo. Con los datos de estrés fisiológico del usuario, dale acciones CONCRETAS para bajar el estrés HOY (respiración, paseo suave en Z1, sueño, mover o suavizar el entreno). Español, TEXTO PLANO sin markdown ni listas, 2-3 frases. Usa solo las cifras dadas; nunca inventes valores. TERMINA con una línea aparte que empiece por 'Conclusión: ' con la acción más importante de hoy."
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private var stressLabel: String {
        todayValue < 30 ? "Bajo — sistema descansado"
            : todayValue < 60 ? "Moderado" : "Elevado — prioriza descanso"
    }

    private var hourlyStress: [MetricSample] {
        let rhr = restingHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        return hourlyHR.map { s in
            let stress = TrainingMetrics.physiologicalStress(hr: s.value, restingHR: rhr, maxHR: maxHR, hrvBase: hrvBase)
            return MetricSample(date: s.date, value: stress)
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: todayValue, label: "Estrés", icon: "brain.head.profile",
                         color: color, subtitle: stressLabel)

                HourlyInteractiveChart(
                    samples: hourlyStress,
                    color: color,
                    unit: "",
                    higherIsBetter: false,
                    emptyText: "Sin datos de FC para este día.",
                    useBarMarks: true,
                    barColorFn: { v in v < 30 ? .green : v < 60 ? .orange : .red }
                )

                AITextCard(
                    title: "Cómo bajar tu estrés hoy",
                    subtitle: "Claude mira tu estrés, HRV y FC y te dice qué hacer hoy.",
                    cacheKey: "apex_stress_tips_\(aiDayKey(day))_\(todayValue)",
                    generate: { try await stressAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
    }
}

// MARK: - Recovery Detail

struct RecoveryDetailView: View {
    let score: RecoveryScore?
    let history: [MetricSample]
    let color: Color
    let hrvHistory: [HRVData]
    let rhrHistory: [MetricSample]
    let todayRHR: Double?

    // Consejo IA con los datos reales de recuperación
    private func recoveryAdvice() async throws -> String {
        var lines: [String] = []
        if let s = score {
            lines.append("Recuperación hoy: \(s.value)/100 (sub-puntuaciones sobre 100, NO son bpm ni ms — HRV: \(s.hrvScore)/100, FC reposo: \(s.restingHRScore)/100, sueño: \(s.sleepScore)/100, carga: \(s.trainingLoadScore)/100).")
        }
        if let hrv = hrvHistory.first { lines.append("HRV hoy: \(Int(hrv.sdnn)) ms.") }
        let hrvVals = hrvHistory.prefix(14).map(\.sdnn)
        if hrvVals.count >= 3 {
            let mean = hrvVals.reduce(0, +) / Double(hrvVals.count)
            lines.append("HRV media 14 días: \(Int(mean.rounded())) ms.")
        }
        if let rhr = todayRHR { lines.append("FC en reposo hoy: \(Int(rhr)) bpm.") }
        let rhrVals = rhrHistory.prefix(14).map(\.value)
        if rhrVals.count >= 3 {
            let mean = rhrVals.reduce(0, +) / Double(rhrVals.count)
            lines.append("FC reposo media 14 días: \(Int(mean.rounded())) bpm.")
        }
        if history.count >= 3 {
            let recent = history.suffix(7).map { String(Int($0.value)) }
            lines.append("Recuperación últimos días: \(recent.joined(separator: "→")).")
        }
        let system = "Eres un entrenador de élite experto en recuperación. Con los datos del usuario (HRV y FC en reposo frente a su media, sueño y carga), dile qué hacer para mejorar su recuperación. Interpreta la TENDENCIA, no solo el valor de hoy. Español, TEXTO PLANO sin markdown ni listas, 2-3 frases. Usa solo las cifras dadas; nunca inventes valores. TERMINA con una línea aparte que empiece por 'Conclusión: ' con el siguiente paso concreto."
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private var todayHRV: Double? { hrvHistory.first?.sdnn }
    private var hrvBaseline: Double? {
        guard hrvHistory.count >= 3 else { return nil }
        let vals = hrvHistory.map(\.sdnn)
        return vals.reduce(0, +) / Double(vals.count)
    }
    private var rhrBaseline: Double? {
        guard rhrHistory.count >= 3 else { return nil }
        let vals = rhrHistory.map(\.value)
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var hrvPct: Int {
        guard let t = todayHRV, let b = hrvBaseline, b > 0 else { return 50 }
        return max(0, min(100, Int((t / b) * 100)))
    }
    private var rhrPct: Int {
        // Invertido: RHR más baja = mejor = más porcentaje
        guard let t = todayRHR, let b = rhrBaseline, b > 0 else { return 50 }
        let ratio = b / t  // >1 si FC hoy < baseline (bien)
        return max(0, min(100, Int(ratio * 100)))
    }

    private var hrvSamples: [MetricSample] {
        hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: score?.value ?? 0, label: "Recuperación",
                         icon: "arrow.up.heart.fill", color: color,
                         subtitle: score?.label ?? "--")

                // HRV block
                MetricProgressBlock(
                    title: "Variabilidad FC (HRV)",
                    icon: "waveform.path.ecg", color: .green,
                    todayValue: todayHRV.map { "\(Int($0)) ms" } ?? "--",
                    baselineValue: hrvBaseline.map { "media \(Int($0)) ms" } ?? "",
                    pct: hrvPct,
                    higherBetter: true,
                    samples: hrvSamples,
                    unit: "ms"
                )

                // RHR block
                MetricProgressBlock(
                    title: "FC en reposo",
                    icon: "heart.fill", color: .red,
                    todayValue: todayRHR.map { "\(Int($0)) ppm" } ?? "--",
                    baselineValue: rhrBaseline.map { "media \(Int($0)) ppm" } ?? "",
                    pct: rhrPct,
                    higherBetter: false,
                    samples: rhrHistory.sorted { $0.date < $1.date },
                    unit: "ppm"
                )

                // Factores — pesos reales del score (HRV 70% + FC reposo 30%,
                // metodología PeakWatch). Sueño y carga se muestran como contexto:
                // alimentan Body Battery y las alertas, no este score.
                if let s = score {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Composición del score").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                        FactorBarRow(label: "HRV", icon: "waveform.path.ecg", color: .green,
                                     value: s.hrvScore, weight: "70%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "FC reposo", icon: "heart.fill", color: .red,
                                     value: s.restingHRScore, weight: "30%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Sueño", icon: "moon.fill", color: .indigo,
                                     value: s.sleepScore, weight: "contexto")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Carga", icon: "figure.run", color: .orange,
                                     value: s.trainingLoadScore, weight: "contexto")
                        Text("El score compara HRV y FC en reposo de hoy contra tu baseline de 60 días. Sueño y carga influyen en Body Battery, no en este número.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                AITextCard(
                    title: "Cómo mejorar tu recuperación",
                    subtitle: "Claude lee tu HRV, FC en reposo y su tendencia y te da el siguiente paso.",
                    cacheKey: "apex_recovery_tips_\(aiDayKey(Date()))_\(score?.value ?? 0)",
                    generate: { try await recoveryAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recuperación").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Effort Detail

struct EffortDetailView: View {
    let value: Int             // TRIMP score 0-100
    let todayKcal: Double
    let todayActiveKcal: Double
    let hourlyHR: [MetricSample]
    let restingHR: Double?
    let history: [MetricSample]
    let color: Color
    let activities: [StravaActivity]

    // Consejo IA con el esfuerzo real del usuario
    private func effortAdvice() async throws -> String {
        let cal = Calendar.current
        var lines = ["Esfuerzo de hoy: \(value)/100 (TRIMP diario normalizado)."]
        if history.count >= 2 {
            let recent = history.suffix(7).map { String(Int($0.value)) }
            lines.append("Esfuerzo últimos días: \(recent.joined(separator: "→")).")
        }
        let today = cal.startOfDay(for: Date())
        let todayActs = activities.filter { $0.startDate >= today }
        if todayActs.isEmpty {
            lines.append("Hoy no hay sesiones registradas.")
        } else {
            lines.append("Sesiones de hoy:")
            for a in todayActs {
                let hr = a.averageHeartrate.map { " · FC \(Int($0))" } ?? ""
                lines.append("  \(a.name) · \(a.formattedDuration)\(hr)")
            }
        }
        if let from = cal.date(byAdding: .day, value: -7, to: Date()) {
            let week = activities.filter { $0.startDate >= from }
            let h = week.reduce(0.0) { $0 + Double($1.movingTime) } / 3600.0
            lines.append(String(format: "Últimos 7 días: %d sesiones, %.1f h.", week.count, h))
        }
        let system = "Eres un entrenador de élite. Con el esfuerzo diario del usuario (TRIMP) y sus sesiones, dile si hoy toca empujar, mantener o descansar, y cómo enfocar los próximos días. Ten en cuenta que la supercompensación ocurre en el descanso y que conviene alternar días de carga alta y baja. Español, TEXTO PLANO sin markdown ni listas, 2-3 frases. Usa solo las cifras dadas; nunca inventes valores. TERMINA con una línea aparte que empiece por 'Conclusión: ' con la recomendación principal."
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private let zoneNames  = ["Z1 Muy suave", "Z2 Aeróbico", "Z3 Umbral", "Z4 Anaeróbico", "Z5 Máximo"]
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    private var rhr: Double { restingHR ?? UserProfile.restingHR }
    private var maxHR: Double { TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR) }

    // Tiempo en cada zona: prioriza actividades Strava (FC exacta × minutos), fallback horario
    private var zoneHours: [Int] {
        let cal = Calendar.current
        var counts = [0, 0, 0, 0, 0]
        let todayActs = activities.filter { cal.isDateInToday($0.startDate) && $0.averageHeartrate != nil }

        if !todayActs.isEmpty {
            for act in todayActs {
                let avgHR = act.averageHeartrate ?? 0.0
                let hours = Int(Double(act.movingTime) / 3600.0 * 4) // cuartos de hora
                let hrr = max(0, min(1, (avgHR - rhr) / (maxHR - rhr)))
                let z: Int
                if hrr < 0.5 { z = 0 } else if hrr < 0.6 { z = 1 } else if hrr < 0.7 { z = 2 } else if hrr < 0.8 { z = 3 } else { z = 4 }
                counts[z] += max(1, hours)
            }
        } else {
            let today = hourlyHR.filter { cal.isDateInToday($0.date) }
            for s in today {
                let hrr = max(0, min(1, (s.value - rhr) / (maxHR - rhr)))
                let z: Int
                if hrr < 0.5 { z = 0 } else if hrr < 0.6 { z = 1 } else if hrr < 0.7 { z = 2 } else if hrr < 0.8 { z = 3 } else { z = 4 }
                counts[z] += 1
            }
        }
        return counts
    }

    private var todayActivities: [StravaActivity] {
        let today = Calendar.current.startOfDay(for: Date())
        return activities.filter { $0.startDate >= today }
    }

    private var effortLabel: String {
        if value >= 80 { return "Día muy exigente — prioriza recuperación" }
        if value >= 55 { return "Carga alta — bien si estás entrenado" }
        if value >= 30 { return "Carga moderada" }
        if value >= 10 { return "Actividad ligera" }
        return "Día de descanso"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: value, label: "Carga cardiovascular",
                         icon: "bolt.fill", color: color, subtitle: effortLabel)

                // Anillo TRIMP + stats
                VStack(alignment: .leading, spacing: 16) {
                    Text("Esfuerzo cardiovascular (TRIMP)").font(.headline)
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(color.opacity(0.15), lineWidth: 14)
                            Circle()
                                .trim(from: 0, to: CGFloat(Double(value) / 100))
                                .stroke(color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.6), value: value)
                            VStack(spacing: 2) {
                                Text("\(value)")
                                    .font(.system(.title2, design: .rounded)).fontWeight(.bold).foregroundColor(color)
                                Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 110, height: 110)

                        VStack(alignment: .leading, spacing: 10) {
                            statRow("Activas hoy", "\(Int(todayActiveKcal)) kcal", color)
                            statRow("Horas con datos FC", "\(hourlyHR.filter { Calendar.current.isDateInToday($0.date) }.count)h", .secondary)
                            if !todayActivities.isEmpty {
                                statRow("Actividades", "\(todayActivities.count)", .secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Zonas cardíacas de hoy
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tiempo por zona").font(.headline)
                    ForEach(0..<5) { z in
                        HStack(spacing: 12) {
                            Circle().fill(zoneColors[z]).frame(width: 10, height: 10)
                            Text(zoneNames[z]).font(.subheadline).frame(width: 120, alignment: .leading)
                            GeometryReader { geo in
                                let maxH = zoneHours.max() ?? 1
                                let w = maxH > 0 ? CGFloat(zoneHours[z]) / CGFloat(maxH) * geo.size.width : 0
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(zoneColors[z].opacity(0.25))
                                    .frame(width: geo.size.width, height: 20)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(zoneColors[z])
                                            .frame(width: max(4, w), height: 20)
                                            .animation(.easeOut(duration: 0.5), value: zoneHours[z])
                                    }
                            }
                            .frame(height: 20)
                            Text("\(zoneHours[z])h").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Actividades del día
                if !todayActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Actividades de hoy").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                        ForEach(Array(todayActivities.enumerated()), id: \.element.id) { idx, act in
                            TodayActivityRow(act: act, color: color)
                            if idx < todayActivities.count - 1 { Divider().padding(.leading, 60) }
                        }
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                // Sparkline semanal
                if history.count >= 2 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Carga esta semana").font(.headline)
                        Chart(history) { s in
                            BarMark(x: .value("Día", s.date, unit: .day), y: .value("TRIMP", s.value))
                                .foregroundStyle(Calendar.current.isDateInToday(s.date)
                                    ? color.gradient : Color.secondary.opacity(0.4).gradient)
                                .cornerRadius(6)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.short)).font(.caption2).foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Color.primary.opacity(0.07))
                                AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(height: 120)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                AITextCard(
                    title: "Cómo enfocar tu carga",
                    subtitle: "Claude analiza tu esfuerzo de hoy y de la semana y te dice si empujar o descansar.",
                    cacheKey: "apex_effort_tips_\(aiDayKey(Date()))_\(value)",
                    generate: { try await effortAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Esfuerzo").navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ val: String, _ c: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(val).font(.system(.caption, design: .rounded)).fontWeight(.semibold).foregroundColor(c)
        }
    }
}

private struct TodayActivityRow: View {
    let act: StravaActivity
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sportIcon(act.sportType))
                .font(.system(size: 18)).foregroundColor(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(act.name).font(.subheadline).fontWeight(.medium)
                Text(act.startDate, format: .dateTime.hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if act.distance > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(act.formattedDistance)
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                    Text(act.formattedDuration).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func sportIcon(_ s: String) -> String {
        switch s.lowercased() {
        case "run", "virtualrun": return "figure.run"
        case "ride", "virtualride": return "figure.outdoor.cycle"
        case "swim": return "figure.pool.swim"
        case "hike": return "figure.hiking"
        case "walk": return "figure.walk"
        case "weighttraining": return "dumbbell.fill"
        case "yoga": return "figure.mind.and.body"
        default: return "bolt.fill"
        }
    }
}

// MARK: - Shared components

private struct HeroCard: View {
    let value: Int; let label: String; let icon: String; let color: Color; let subtitle: String
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: icon).font(.system(size: 26)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(color)
                    Text("/ 100").font(.subheadline).foregroundColor(.secondary).offset(y: -4)
                }
                Text(subtitle).font(.caption).foregroundColor(color).fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct MetricProgressBlock: View {
    let title: String; let icon: String; let color: Color
    let todayValue: String; let baselineValue: String; let pct: Int
    let higherBetter: Bool
    let samples: [MetricSample]; let unit: String

    private var pctColor: Color {
        if higherBetter { return pct >= 100 ? .green : pct >= 80 ? .orange : .red }
        else { return pct >= 100 ? .green : pct >= 80 ? .orange : .red }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundColor(color)
                Spacer()
                Text(todayValue)
                    .font(.system(.title3, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            }

            // Barra de progreso con porcentaje
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)).frame(height: 10)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(min(pct, 100)) / 100.0, height: 10)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(baselineValue).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)% de tu baseline")
                        .font(.caption2).fontWeight(.medium).foregroundColor(pctColor)
                }
            }

            // Sparkline tendencia 30 días
            if samples.count >= 3 {
                TrendSparkline(samples: samples, color: color, height: 40)
                Text("Tendencia 30 días").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FactorBarRow: View {
    let label: String; let icon: String; let color: Color; let value: Int; let weight: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.caption).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.subheadline)
                    Text(weight).font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(color)
                            .frame(width: geo.size.width * CGFloat(value) / 100.0, height: 6)
                    }
                }.frame(height: 6)
            }
            Text("\(value)").font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                .foregroundColor(color).frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// Clave de día para cachear los consejos IA (se regeneran al cambiar de día o de valor)
fileprivate func aiDayKey(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
