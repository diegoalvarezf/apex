import SwiftUI

struct HealthView: View {
    @EnvironmentObject var healthKit: HealthKitManager

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
                if let dl = healthKit.daylightData {
                    NavigationLink(destination: MetricDetailView(config: MetricConfig(
                        title: "Luz diurna", icon: "sun.max.fill", color: .yellow,
                        unit: "min hoy", value: "\(dl.todayMinutes)",
                        samples: dl.samples, higherIsBetter: true, normalRange: 20...120,
                        explanation: "La exposición a la luz natural sincroniza el ritmo circadiano y mejora el sueño. Mínimo 20-30 min diarios."
                    ))) {
                        PWMetricCard(icon: "sun.max.fill", color: .yellow,
                                     title: "Luz diurna", value: "\(dl.todayMinutes)", unit: "min hoy",
                                     status: daylightStatus(dl.todayMinutes), samples: dl.samples)
                    }.buttonStyle(.plain)
                }

                NavigationLink(destination: HeartRateZonesView()) {
                    PWMetricCard(icon: "waveform.path.ecg.rectangle.fill", color: .orange,
                                 title: "Zonas FC", value: "Ver", unit: "detalle",
                                 status: .info, samples: [])
                }.buttonStyle(.plain)
            }
        }
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

    private func daylightStatus(_ v: Int) -> HealthMetricStatus {
        switch v {
        case 45...: return .excellent
        case 20..<45: return .good
        case 10..<20: return .normal
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

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Edad biológica", systemImage: "figure.walk.motion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", result.biologicalAge))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(result.deltaColor)
                    Text("años")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text(result.deltaLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(result.deltaColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(result.deltaColor.opacity(0.12), in: Capsule())
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 7)
                    .frame(width: 76, height: 76)
                Circle()
                    .trim(from: 0, to: min(1, CGFloat(result.biologicalAge) / CGFloat(max(result.chronologicalAge + 10, 50))))
                    .stroke(result.deltaColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 76, height: 76)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(result.chronologicalAge)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("real").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
