import SwiftUI

struct HealthView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var dashVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !healthKit.isAuthorized {
                    ScrollView { HealthAuthCard().padding() }
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            bioAgeSection()
                            vitalsSection()
                            activitySection()
                            bodySection()
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Salud")
            .refreshable { await healthKit.loadAll() }
        }
    }

    // MARK: - Secciones

    @ViewBuilder
    private func bioAgeSection() -> some View {
        if let bioAge = healthKit.biologicalAge {
            NavigationLink(destination: BiologicalAgeDetailView(result: bioAge)) {
                BioAgeHeroCard(result: bioAge)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func vitalsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Métricas corporales", icon: "waveform.path.ecg")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let hrv = healthKit.hrvHistory.first {
                    let samples = healthKit.hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "HRV", icon: "waveform.path.ecg", color: .green,
                        unit: "ms", value: String(format: "%.0f", hrv.sdnn),
                        samples: samples, higherIsBetter: true, normalRange: 20...80,
                        explanation: "La variabilidad de la frecuencia cardíaca es el mejor indicador de recuperación del sistema nervioso autónomo."
                    ))) {
                        PWMetricCard(icon: "waveform.path.ecg", color: .green,
                                     title: "HRV", value: String(format: "%.0f", hrv.sdnn), unit: "ms",
                                     status: hrvStatus(hrv.sdnn), samples: samples)
                    }.buttonStyle(.plain)
                }

                if let rhr = healthKit.todaySummary?.restingHR {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "FC en reposo", icon: "heart.fill", color: .red,
                        unit: "bpm", value: String(format: "%.0f", rhr),
                        samples: healthKit.restingHRHistory, higherIsBetter: false, normalRange: 40...80,
                        explanation: "Una frecuencia cardíaca en reposo baja indica un corazón eficiente."
                    ))) {
                        PWMetricCard(icon: "heart.fill", color: .red,
                                     title: "FC en reposo", value: String(format: "%.0f", rhr), unit: "bpm",
                                     status: rhrStatus(rhr), samples: healthKit.restingHRHistory)
                    }.buttonStyle(.plain)
                }

                if let vo2 = healthKit.vo2MaxData {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "VO₂Max", icon: "lungs.fill", color: .blue,
                        unit: "ml/kg/min", value: String(format: "%.1f", vo2.current),
                        samples: vo2.samples, higherIsBetter: true, normalRange: 35...60,
                        explanation: "El VO₂Max es el predictor más potente de rendimiento aeróbico y longevidad."
                    ))) {
                        PWMetricCard(icon: "lungs.fill", color: .blue,
                                     title: "VO₂Max", value: String(format: "%.1f", vo2.current), unit: "ml/kg/min",
                                     status: vo2Status(vo2.current), samples: vo2.samples)
                    }.buttonStyle(.plain)
                }

                if let resp = healthKit.respiratoryData {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "Frec. respiratoria", icon: "wind", color: .cyan,
                        unit: "resp/min", value: String(format: "%.0f", resp.current),
                        samples: resp.samples, higherIsBetter: false, normalRange: 12...20,
                        explanation: "La frecuencia respiratoria nocturna es sensible a enfermedad, estrés y sobreentrenamiento."
                    ))) {
                        PWMetricCard(icon: "wind", color: .cyan,
                                     title: "Frec. respiratoria", value: String(format: "%.0f", resp.current), unit: "resp/min",
                                     status: respStatus(resp.current), samples: resp.samples)
                    }.buttonStyle(.plain)
                }

                if let spo2 = healthKit.bloodOxygen {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "Oxígeno en sangre", icon: "drop.fill", color: .pink,
                        unit: "%", value: String(format: "%.0f", spo2),
                        samples: [], higherIsBetter: true, normalRange: 95...100,
                        explanation: "La saturación de oxígeno en sangre (SpO2) indica cuánto oxígeno transportan tus glóbulos rojos. Un valor ≥95% es normal en adultos sanos."
                    ))) {
                        PWMetricCard(icon: "drop.fill", color: .pink,
                                     title: "Oxígeno en sangre", value: String(format: "%.0f", spo2), unit: "%",
                                     status: spo2Status(spo2), samples: [])
                    }.buttonStyle(.plain)
                }

                if let wrist = healthKit.wristTempData {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "Temp. muñeca", icon: "thermometer.medium", color: .purple,
                        unit: "°C desv.", value: String(format: "%+.1f°", wrist.deviation),
                        samples: wrist.samples, higherIsBetter: false,
                        explanation: "La temperatura de la muñeca durante el sueño varía con enfermedades y recuperación."
                    ))) {
                        PWMetricCard(icon: "thermometer.medium", color: .purple,
                                     title: "Temp. muñeca", value: String(format: "%+.1f°", wrist.deviation), unit: "desviación",
                                     status: wristTempStatus(wrist.deviation), samples: wrist.samples)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func activitySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Actividad", icon: "figure.run")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink(destination: HeartRateZonesView()) {
                    ActivityStatCard(title: "Zona 1–3 / sem.", value: "\(weeklyZone13)", unit: "min",
                                     level: zone13Level)
                }.buttonStyle(.plain)

                NavigationLink(destination: HeartRateZonesView()) {
                    ActivityStatCard(title: "Zona 4–5 / sem.", value: "\(weeklyZone45)", unit: "min",
                                     level: zone45Level)
                }.buttonStyle(.plain)

                ActivityStatCard(title: "Fuerza / sem.", value: "\(weeklyStrength)", unit: "min",
                                 level: strengthLevel)

                ActivityStatCard(title: "Pasos", value: "\(healthKit.todaySummary?.steps ?? 0)", unit: "",
                                 level: stepsLevel)

                ActivityStatCard(title: "Pisos subidos", value: "\(healthKit.todayFlights)", unit: "",
                                 level: flightsLevel)
            }
        }
    }

    // MARK: - Cálculo de la sección Actividad

    private var weekActivities: [StravaActivity] {
        let from = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return dashVM.activities.filter { $0.startDate >= from }
    }

    // Clasifica cada sesión por su FC media respecto a la FCmáx: Z1-3 <80%, Z4-5 ≥80%
    private func weeklyMinutes(highIntensity: Bool) -> Int {
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: healthKit.recentHourlyHR)
        guard maxHR > 0 else { return 0 }
        let mins = weekActivities.reduce(0.0) { acc, a in
            guard let hr = a.averageHeartrate else { return acc }
            let pct = hr / maxHR
            let isHigh = pct >= 0.80
            guard isHigh == highIntensity else { return acc }
            return acc + Double(a.movingTime) / 60.0
        }
        return Int(mins.rounded())
    }
    private var weeklyZone13: Int { weeklyMinutes(highIntensity: false) }
    private var weeklyZone45: Int { weeklyMinutes(highIntensity: true) }

    private var weeklyStrength: Int {
        let mins = weekActivities
            .filter { TrainingMetrics.strengthTypes.contains($0.sportType.lowercased()) }
            .reduce(0.0) { $0 + Double($1.movingTime) / 60.0 }
        return Int(mins.rounded())
    }

    // Niveles: 0 bajo · 1 medio · 2 bueno · 3 excelente
    // Referencias OMS: 150 min/sem moderado (Z1-3), 75 min/sem vigoroso (Z4-5),
    // 2 sesiones de fuerza/sem, 10.000 pasos/día.
    private var zone13Level: Int {
        switch weeklyZone13 { case ..<60: 0; case ..<120: 1; case ..<180: 2; default: 3 }
    }
    private var zone45Level: Int {
        switch weeklyZone45 { case ..<15: 0; case ..<30: 1; case ..<75: 2; default: 3 }
    }
    private var strengthLevel: Int {
        switch weeklyStrength { case ..<30: 0; case ..<60: 1; case ..<100: 2; default: 3 }
    }
    private var stepsLevel: Int {
        switch healthKit.todaySummary?.steps ?? 0 { case ..<5000: 0; case ..<7500: 1; case ..<10000: 2; default: 3 }
    }
    private var flightsLevel: Int {
        switch healthKit.todayFlights { case ..<5: 0; case ..<10: 1; case ..<15: 2; default: 3 }
    }

    @ViewBuilder
    private func bodySection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Composición corporal", icon: "figure.stand")

            NavigationLink(destination: BodyCompositionView()) {
                BodyCompositionRow(composition: healthKit.bodyComposition)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Status helpers

    private func rhrStatus(_ v: Double) -> HealthMetricStatus {
        switch v {
        case ..<50: return .excellent
        case 50..<60: return .good
        case 60..<70: return .normal
        default: return .low
        }
    }

    private func hrvStatus(_ v: Double) -> HealthMetricStatus {
        switch v {
        case 65...: return .excellent
        case 45..<65: return .good
        case 25..<45: return .normal
        default: return .low
        }
    }

    private func vo2Status(_ v: Double) -> HealthMetricStatus {
        switch v {
        case 52...: return .excellent
        case 44..<52: return .good
        case 36..<44: return .normal
        default: return .low
        }
    }

    private func respStatus(_ v: Double) -> HealthMetricStatus {
        switch v {
        case 12..<16: return .excellent
        case 16..<18: return .good
        case 18..<20: return .normal
        default: return .low
        }
    }

    private func spo2Status(_ v: Double) -> HealthMetricStatus {
        switch v {
        case 97...: return .excellent
        case 95..<97: return .good
        case 92..<95: return .normal
        default: return .low
        }
    }

    private func wristTempStatus(_ v: Double) -> HealthMetricStatus {
        let a = abs(v)
        switch a {
        case ..<0.2: return .excellent
        case 0.2..<0.5: return .good
        case 0.5..<1.0: return .normal
        default: return .low
        }
    }

}

// MARK: - Status enum

enum HealthMetricStatus {
    case excellent, good, normal, low, info

    var label: String {
        switch self {
        case .excellent: return "Excelente"
        case .good:      return "Bueno"
        case .normal:    return "Normal"
        case .low:       return "Mejorable"
        case .info:      return "Ver"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good:      return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .normal:    return .orange
        case .low:       return .red
        case .info:      return .secondary
        }
    }
}

// MARK: - Componentes de UI

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.5)
        }
        .padding(.leading, 2)
    }
}

private struct BioAgeHeroCard: View {
    let result: BiologicalAgeResult

    // Escala de la barra: de 18 a un techo por encima de tu edad real
    private var minAge: Double { 18 }
    private var maxAge: Double { Swift.max(Double(result.chronologicalAge) + 12, 45) }
    private func pos(_ age: Double) -> Double {
        Swift.max(0, Swift.min(1, (age - minAge) / (maxAge - minAge)))
    }

    private var deltaText: (label: String, value: String) {
        let abs = Swift.abs(result.delta)
        if abs < 0.5 { return ("En tu edad real", "") }
        return (result.delta < 0 ? "Más joven" : "Mayor", String(format: "%.1f años", abs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Cabecera
            HStack {
                Text("Edad biológica").font(.headline)
                Spacer()
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }

            // Barra de ticks con marcador de edad real
            AgeTickBar(bioPos: pos(result.biologicalAge), chronoPos: pos(Double(result.chronologicalAge)))
                .frame(height: 30)

            // Número grande
            Text(String(format: "%.1f", result.biologicalAge))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Stats: delta (izq) · edad real (der)
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(deltaText.label).foregroundStyle(.secondary)
                    if !deltaText.value.isEmpty {
                        Text(deltaText.value).foregroundColor(result.deltaColor).fontWeight(.semibold)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Edad real").foregroundStyle(.secondary)
                    Text("\(result.chronologicalAge)").foregroundColor(.primary).fontWeight(.semibold)
                }
            }
            .font(.subheadline)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// Barra segmentada de edad: ticks con degradado teal→verde hasta la edad biológica
// y una línea marcadora en la edad real (a la derecha del relleno = más joven).
private struct AgeTickBar: View {
    let bioPos: Double
    let chronoPos: Double

    private func tickColor(_ t: Double) -> Color {
        let tt = Swift.max(0, Swift.min(1, t))
        return Color(red: 0.10 + 0.20 * tt, green: 0.78 + 0.07 * tt, blue: 0.70 - 0.25 * tt)
    }

    var body: some View {
        Canvas { ctx, size in
            let n = 44
            let gap: CGFloat = 3
            let tickW = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            for i in 0..<n {
                let frac = Double(i) / Double(n - 1)
                let x = CGFloat(i) * (tickW + gap)
                let filled = frac <= bioPos
                let h: CGFloat = filled ? size.height : size.height * 0.62
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: tickW, height: h)
                let path = Path(roundedRect: rect, cornerRadius: tickW / 2)
                let shade: GraphicsContext.Shading = filled
                    ? .color(tickColor(bioPos > 0 ? frac / bioPos : 0))
                    : .color(.primary.opacity(0.13))
                ctx.fill(path, with: shade)
            }
            // Marcador de edad real
            let mx = size.width * chronoPos
            let marker = Path(roundedRect: CGRect(x: mx - 1.5, y: 0, width: 3, height: size.height), cornerRadius: 1.5)
            ctx.fill(marker, with: .color(.primary))
        }
    }
}

// Tarjeta de actividad: título + chevron, valor grande, estado y barra de nivel vertical
private struct ActivityStatCard: View {
    let title: String
    let value: String
    let unit: String
    let level: Int          // 0 bajo · 1 medio · 2 bueno · 3 excelente

    private var status: (label: String, icon: String, color: Color) {
        switch level {
        case 0:  return ("Bajo", "chevron.down.circle.fill", .red)
        case 1:  return ("Medio", "minus.circle.fill", .yellow)
        case 2:  return ("Bueno", "checkmark.circle.fill", .green)
        default: return ("Excelente", "hand.thumbsup.circle.fill", .blue)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 14)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: status.icon).font(.caption)
                    Text(status.label).font(.subheadline).fontWeight(.medium)
                }
                .foregroundStyle(status.color)
            }
            Spacer(minLength: 0)
            LevelBar(level: level)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// Barra vertical de 4 niveles; el activo se muestra alto y en color
private struct LevelBar: View {
    let level: Int
    private let colors: [Color] = [.red, .yellow, .green, .blue]   // 0 abajo → 3 arriba

    var body: some View {
        VStack(spacing: 5) {
            ForEach((0..<4).reversed(), id: \.self) { i in
                if i == level {
                    Capsule().fill(colors[i])
                        .frame(width: 9, height: 44)
                        .overlay(
                            Circle().fill(.white.opacity(0.95)).frame(width: 5, height: 5)
                        )
                } else {
                    Capsule().fill(colors[i].opacity(0.22))
                        .frame(width: 9, height: 9)
                }
            }
        }
    }
}

// Tarjeta estilo PeakWatch: barra de color en el borde izquierdo, valor grande, sparkline pequeño
struct PWMetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String
    let status: HealthMetricStatus
    var samples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Borde izquierdo de color (estilo PeakWatch)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    // Icono + status
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(color)
                        Spacer()
                        Text(status.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(status.color)
                    }

                    // Valor
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(.system(.title2, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(unit)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    // Sparkline si hay datos
                    if samples.count >= 4 {
                        TrendSparkline(samples: Array(samples.suffix(12)), color: color, height: 20)
                    }

                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 12)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct BodyCompositionRow: View {
    let composition: BodyCompositionData?

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.pink)
                .frame(width: 3, height: 44)

            Image(systemName: "figure.stand")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.pink)

            VStack(alignment: .leading, spacing: 2) {
                Text("Peso e IMC").font(.subheadline).fontWeight(.medium)
                if let b = composition, let w = b.weightKg, let bmi = b.bmi {
                    Text(String(format: "%.1f kg · IMC %.1f", w, bmi))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Toca para registrar").font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HealthAuthCard: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill").font(.system(size: 52)).foregroundColor(.red)
            VStack(spacing: 6) {
                Text("Conectar Apple Health").font(.title3).fontWeight(.semibold)
                Text("Autoriza el acceso para ver sueño, HRV, recuperación y mucho más.")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button("Autorizar acceso") { Task { await healthKit.requestAuthorization() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
