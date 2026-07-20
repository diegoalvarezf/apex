import SwiftUI

// Tarjeta compacta de métricas corporales: una columna por métrica con su icono,
// una barra de rango vertical con la posición del valor y la cifra debajo.
struct QuickMetricsGrid: View {
    let summary: DailyHealthSummary?
    let hrvHistory: [HRVData]
    let vo2MaxData: VO2MaxData?
    let respiratoryData: RespiratoryData?
    let wristTempData: WristTempData?
    let daylightData: DaylightData?
    var bloodOxygen: Double? = nil

    @ObservedObject private var layout = HealthLayoutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Métricas corporales").font(.headline)
                Spacer()
                Image(systemName: "circle.dotted")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 6) {
                if layout.isVisible(.hrv) {
                    NavigationLink(destination: metricDetail(
                        title: "HRV", icon: "waveform.path.ecg", color: .green,
                        value: hrvValue.map { String(format: "%.0f", $0) } ?? "--", unit: "ms",
                        samples: hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) },
                        higherIsBetter: true, normalRange: 20...80,
                        explanation: "La variabilidad de la frecuencia cardíaca es el mejor indicador de recuperación del sistema nervioso autónomo."
                    )) {
                        MetricColumn(icon: "heart.text.square.fill", color: .red,
                                     value: hrvValue, unit: "ms", decimals: 0,
                                     display: 10...100, normal: 20...80)
                    }.buttonStyle(.plain)
                }

                if layout.isVisible(.restingHR) {
                    NavigationLink(destination: metricDetail(
                        title: "FC en reposo", icon: "heart.fill", color: .red,
                        value: summary?.restingHR.map { String(format: "%.0f", $0) } ?? "--", unit: "bpm",
                        samples: [], higherIsBetter: false, normalRange: 40...70,
                        explanation: "Una frecuencia cardíaca en reposo baja indica un corazón eficiente."
                    )) {
                        MetricColumn(icon: "heart.fill", color: .red,
                                     value: summary?.restingHR, unit: "bpm", decimals: 0,
                                     display: 40...90, normal: 40...70)
                    }.buttonStyle(.plain)
                }

                if layout.isVisible(.vo2max) {
                    NavigationLink(destination: metricDetail(
                        title: "VO₂Max", icon: "lungs.fill", color: .blue,
                        value: vo2MaxData.map { String(format: "%.1f", $0.current) } ?? "--", unit: "ml/kg/min",
                        samples: vo2MaxData?.samples ?? [], higherIsBetter: true, normalRange: 35...60,
                        explanation: "El VO₂Max es el predictor más potente de rendimiento aeróbico y longevidad."
                    )) {
                        MetricColumn(icon: "figure.run", color: .mint,
                                     value: vo2MaxData?.current, unit: "VO₂", decimals: 1,
                                     display: 25...65, normal: 35...60)
                    }.buttonStyle(.plain)
                }

                if layout.isVisible(.respiratory) {
                    NavigationLink(destination: metricDetail(
                        title: "Frec. respiratoria", icon: "wind", color: .cyan,
                        value: respiratoryData.map { String(format: "%.1f", $0.current) } ?? "--", unit: "resp/min",
                        samples: respiratoryData?.samples ?? [], higherIsBetter: false, normalRange: 12...20,
                        explanation: "La frecuencia respiratoria nocturna es sensible a enfermedad, estrés y sobreentrenamiento."
                    )) {
                        MetricColumn(icon: "lungs.fill", color: .blue,
                                     value: respiratoryData?.current, unit: "BrPM", decimals: 1,
                                     display: 8...25, normal: 12...20)
                    }.buttonStyle(.plain)
                }

                if layout.isVisible(.spo2) {
                    NavigationLink(destination: metricDetail(
                        title: "Oxígeno en sangre", icon: "drop.fill", color: .pink,
                        value: bloodOxygen.map { String(format: "%.0f", $0) } ?? "--", unit: "%",
                        samples: [], higherIsBetter: true, normalRange: 95...100,
                        explanation: "La saturación de oxígeno en sangre (SpO2) indica cuánto oxígeno transportan tus glóbulos rojos. Un valor ≥95% es normal en adultos sanos."
                    )) {
                        MetricColumn(icon: "drop.fill", color: .pink,
                                     value: bloodOxygen, unit: "%", decimals: 0,
                                     display: 90...100, normal: 95...100)
                    }.buttonStyle(.plain)
                }

                if layout.isVisible(.wristTemp) {
                    NavigationLink(destination: metricDetail(
                        title: "Temp. muñeca", icon: "thermometer.medium", color: .orange,
                        value: wristTempData.map { String(format: "%+.1f", $0.deviation) } ?? "--", unit: "°C desv.",
                        samples: wristTempData?.samples ?? [], higherIsBetter: false,
                        explanation: "La temperatura de la muñeca durante el sueño varía con enfermedades y recuperación."
                    )) {
                        MetricColumn(icon: "thermometer.medium", color: .orange,
                                     value: wristTempData?.deviation, unit: "°C", decimals: 1,
                                     display: -1.5...1.5, normal: -0.5...0.5, showsSign: true)
                    }.buttonStyle(.plain)
                }

            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }

    private var hrvValue: Double? { hrvHistory.first?.sdnn }

    private func metricDetail(
        title: String, icon: String, color: Color,
        value: String, unit: String,
        samples: [MetricSample],
        higherIsBetter: Bool = true,
        normalRange: ClosedRange<Double>? = nil,
        explanation: String = ""
    ) -> MetricDetailView {
        MetricDetailView(config: MetricConfig(
            title: title, icon: icon, color: color,
            unit: unit, value: value, samples: samples,
            higherIsBetter: higherIsBetter,
            normalRange: normalRange,
            explanation: explanation
        ))
    }
}

// MARK: - Columna de una métrica

private struct MetricColumn: View {
    let icon: String
    let color: Color
    let value: Double?
    let unit: String
    var decimals: Int = 0
    let display: ClosedRange<Double>   // rango que abarca la barra
    let normal: ClosedRange<Double>    // rango sano (dot verde dentro, naranja fuera)
    var showsSign: Bool = false

    private var normalized: Double? {
        guard let v = value else { return nil }
        let span = display.upperBound - display.lowerBound
        guard span > 0 else { return nil }
        return min(1, max(0, (v - display.lowerBound) / span))
    }
    private var inRange: Bool {
        guard let v = value else { return false }
        return normal.contains(v)
    }
    private var text: String {
        guard let v = value else { return "--" }
        let fmt = showsSign ? "%+.\(decimals)f" : "%.\(decimals)f"
        return String(format: fmt, v)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(color)
                .frame(height: 20)

            RangeBar(normalized: normalized, inRange: inRange)

            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(value == nil ? .secondary : .primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// Barra vertical de rango con un punto en la posición del valor
private struct RangeBar: View {
    let normalized: Double?
    let inRange: Bool
    private let trackH: CGFloat = 94
    private let dot: CGFloat = 11

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 3) {
                seg(16); seg(56); seg(16)
            }
            if let n = normalized {
                Circle()
                    .strokeBorder(inRange ? Color.green : Color.orange, lineWidth: 3)
                    .frame(width: dot, height: dot)
                    .offset(y: -(CGFloat(n) * (trackH - dot)))
            }
        }
        .frame(height: trackH)
    }

    private func seg(_ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(height: h)
    }
}
