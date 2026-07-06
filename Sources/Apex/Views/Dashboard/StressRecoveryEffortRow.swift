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

    private var stressValue: Int { 100 - (recoveryScore?.value ?? 50) }

    // Estrés horario de HOY — lo mismo que se ve dentro al pulsar
    private var todayHourlyStress: [MetricSample] {
        let rhr: Double = todayRHR ?? 55.0
        let today = Calendar.current.startOfDay(for: Date())
        let filtered = hourlyHR.filter { $0.date >= today }
        let mapped: [MetricSample] = filtered.map { s in
            let stress: Double = max(0.0, min(100.0, (s.value - rhr) / (Double(UserProfile.maxHR) - rhr) * 100.0))
            return MetricSample(date: s.date, value: stress)
        }
        return mapped.sorted { $0.date < $1.date }
    }
    private var stressTrendHistory: [MetricSample] {
        recoveryHistory.map { MetricSample(date: $0.date, value: max(0, 100 - $0.value)) }
    }
    private var stressTrend: MetricTrend { computeTrend(samples: stressTrendHistory) }

    private var recoveryValue: Int { recoveryScore?.value ?? 0 }
    // HRV de las últimas 2 semanas — la métrica principal que muestra el interior
    private var hrvSamples: [MetricSample] {
        hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }
            .sorted { $0.date < $1.date }.suffix(14).map { $0 }
    }
    private var recoveryTrend: MetricTrend { computeTrend(samples: recoveryHistory) }

    // TRIMP — igual que PeakWatch: todo el día sin umbral, maxHR observado sin buffer
    // PeakWatch doc: "not only deliberate exercise but also all activities in daily life"
    // PeakWatch doc: "the highest recorded heart rate over the past 30 days" como maxHR
    private func trimpStrain(forDay day: Date) -> Double {
        let rhr    = todayRHR ?? 55.0
        let allHR  = hourlyHR.map(\.value)
        // maxHR = máximo observado en los datos disponibles, sin buffer artificial
        let maxHR  = max(Double(UserProfile.maxHR), allHR.max() ?? Double(UserProfile.maxHR))
        let cal    = Calendar.current

        let dayActs = activities.filter { cal.isDate($0.startDate, inSameDayAs: day) }
        var trimp = 0.0
        var coveredHours: Set<Int> = []

        for act in dayActs {
            let durationH = Double(act.movingTime) / 3600.0
            let avgHR: Double
            if let hr = act.averageHeartrate {
                avgHR = hr
            } else {
                let hrrFraction: Double
                switch act.sportType.lowercased() {
                case "run", "trail_run", "virtualrun":        hrrFraction = 0.75
                case "ride", "virtualride", "ebikeride":      hrrFraction = 0.65
                case "swim":                                   hrrFraction = 0.70
                case "weighttraining", "crossfit", "workout": hrrFraction = 0.55
                case "walk", "hike":                          hrrFraction = 0.40
                case "yoga", "pilates":                       hrrFraction = 0.30
                default:                                       hrrFraction = 0.60
                }
                avgHR = rhr + hrrFraction * (maxHR - rhr)
            }
            let hrr = max(0.0, min(1.0, (avgHR - rhr) / (maxHR - rhr)))
            trimp += durationH * hrr * Foundation.exp(1.92 * hrr)

            let startH = cal.component(.hour, from: act.startDate)
            let endH   = min(23, startH + Int(ceil(durationH)))
            for h in startH...endH { coveredHours.insert(h) }
        }

        // Toda la actividad de fondo del día — sin umbral mínimo, igual que PeakWatch
        // La fórmula TRIMP pondera de forma natural: reposo (HRR≈0.08) aporta ~0.09/h,
        // caminar (HRR≈0.24) aporta ~0.38/h, ejercicio real aporta 2-5/h
        let dayHR = hourlyHR.filter { cal.isDate($0.date, inSameDayAs: day) }
        for s in dayHR {
            let hour = cal.component(.hour, from: s.date)
            guard !coveredHours.contains(hour) else { continue }
            let hrr = max(0.0, min(1.0, (s.value - rhr) / (maxHR - rhr)))
            trimp += hrr * Foundation.exp(1.92 * hrr)
        }

        // Calibración: maratón completo (~9 TRIMP total) → ~100 puntos, igual que PeakWatch
        return min(100.0, trimp * 11.0)
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
            recoveryScore: recoveryScore, sleep: sleep,
            hourlyHR: hourlyHR, restingHR: todayRHR)
    }
    private var currentBattery: Int {
        Int(batteryHourlySamples.last?.value ?? Double(recoveryScore?.value ?? 0))
    }
    private var batteryColor: Color {
        currentBattery >= 80 ? .green : currentBattery >= 60 ? .cyan : currentBattery >= 40 ? .yellow : .red
    }
    private var batteryTrend: MetricTrend { computeTrend(samples: batteryHourlySamples) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            // Fila 1: Batería · Recuperación
            NavigationLink(destination: BodyBatteryDetailView(
                score: recoveryScore,
                recentHourlyHR: hourlyHR,
                restingHR: todayRHR,
                sleepHistory: sleepHistory,
                recoveryHistory: recoveryHistory,
                activities: activities
            )) {
                MetricTile(icon: "bolt.heart.fill", color: batteryColor,
                           title: "Body Battery", value: "\(currentBattery)", unit: "/ 100",
                           trend: batteryTrend, higherIsBetter: true, samples: batteryHourlySamples)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: RecoveryDetailView(
                score: recoveryScore, history: recoveryHistory,
                color: recoveryColor, hrvHistory: hrvHistory,
                rhrHistory: rhrHistory, todayRHR: todayRHR
            )) {
                MetricTile(icon: "arrow.up.heart.fill", color: recoveryColor,
                           title: "Recuperación", value: "\(recoveryValue)", unit: "/ 100",
                           trend: recoveryTrend, higherIsBetter: true, samples: hrvSamples)
            }
            .buttonStyle(.plain)

            // Fila 2: Estrés · Esfuerzo
            NavigationLink(destination: StressDetailView(
                value: stressValue, history: stressTrendHistory,
                color: stressColor, activities: activities,
                recentHourlyHR: hourlyHR, restingHR: todayRHR
            )) {
                MetricTile(icon: "brain.head.profile", color: stressColor,
                           title: "Estrés", value: "\(stressValue)", unit: "/ 100",
                           trend: stressTrend, higherIsBetter: false, samples: todayHourlyStress)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: EffortDetailView(
                value: effortValue,
                todayKcal: todayKcal, todayActiveKcal: todayActiveKcal,
                hourlyHR: hourlyHR, restingHR: todayRHR,
                history: effortHistory, color: effortColor, activities: activities
            )) {
                MetricTile(icon: "bolt.fill", color: effortColor,
                           title: "Esfuerzo", value: "\(effortValue)", unit: "/ 100",
                           trend: effortTrend, higherIsBetter: false, samples: effortHistory)
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
    let color: Color

    private var stressLabel: String {
        todayValue < 30 ? "Bajo — sistema descansado"
            : todayValue < 60 ? "Moderado" : "Elevado — prioriza descanso"
    }

    private var hourlyStress: [MetricSample] {
        let rhr = restingHR ?? 55.0
        return hourlyHR.map { s in
            let stress = max(0, min(100, (s.value - rhr) / (Double(UserProfile.maxHR) - rhr) * 100))
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

                TipsCard(title: "Reduce el estrés fisiológico", tips: [
                    ("moon.fill", "El sueño profundo es el mayor regenerador del sistema nervioso"),
                    ("figure.walk", "Caminar suave (Z1) reduce el cortisol en 20 minutos"),
                    ("leaf.fill", "La respiración 4-7-8 activa el nervio vago en minutos"),
                ])
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

                // Factores adicionales
                if let s = score {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Todos los factores").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                        FactorBarRow(label: "Sueño", icon: "moon.fill", color: .indigo,
                                     value: s.sleepScore, weight: "30%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "HRV", icon: "waveform.path.ecg", color: .green,
                                     value: s.hrvScore, weight: "40%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "FC reposo", icon: "heart.fill", color: .red,
                                     value: s.restingHRScore, weight: "20%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Carga", icon: "figure.run", color: .orange,
                                     value: s.trainingLoadScore, weight: "10%")
                            .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                TipsCard(title: "Mejora tu recuperación", tips: [
                    ("bed.double.fill", "Mantén un horario de sueño consistente para maximizar HRV"),
                    ("chart.line.uptrend.xyaxis", "Observa la tendencia semanal, no solo el valor de hoy"),
                    ("fork.knife", "Proteínas + carbohidratos post-entreno aceleran la recuperación"),
                ])
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

    private let zoneNames  = ["Z1 Muy suave", "Z2 Aeróbico", "Z3 Umbral", "Z4 Anaeróbico", "Z5 Máximo"]
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    private var rhr: Double { restingHR ?? 55.0 }
    private var maxHR: Double { max(Double(UserProfile.maxHR), (hourlyHR.map(\.value).max() ?? Double(UserProfile.maxHR)) * 1.05) }

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
                            TodayActivityRow(act: act, color: color, barColor: { k in k < 300 ? .blue : k < 600 ? .orange : .red })
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

                TipsCard(title: "Sobre el TRIMP", tips: [
                    ("bolt.fill", "El TRIMP pondera exponencialmente la intensidad: Z4/Z5 cuentan mucho más que Z1"),
                    ("arrow.up.arrow.down", "Alterna días de carga alta (>60) con días de recuperación (<25)"),
                    ("bed.double.fill", "La supercompensación ocurre en el descanso — no en el entreno"),
                ])
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
    let barColor: (Double) -> Color

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
            if let kj = act.kilojoules {
                let kcal = kj * 0.239
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(kcal))")
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                        .foregroundColor(barColor(kcal))
                    Text("kcal").font(.caption2).foregroundStyle(.secondary)
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

private struct TipsCard: View {
    let title: String; let tips: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Divider()
            ForEach(tips, id: \.0) { icon, text in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).font(.caption).foregroundColor(.accentColor).frame(width: 16)
                    Text(text).font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
