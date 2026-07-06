import SwiftUI
import Charts

// MARK: - Sparkline compacto (tiles, sin ejes ni interacción)

struct TrendSparkline: View {
    let samples: [MetricSample]
    let color: Color
    var height: CGFloat = 28

    var body: some View {
        if samples.isEmpty {
            Color.clear.frame(height: height)
        } else {
            Chart(samples) { s in
                AreaMark(x: .value("t", s.date), y: .value("v", s.value))
                    .foregroundStyle(LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", s.date), y: .value("v", s.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: height)
        }
    }
}

// MARK: - Gráfica interactiva completa

struct InteractiveChart: View {
    let samples: [MetricSample]
    let color: Color
    let unit: String
    var higherIsBetter: Bool = true

    // Swift Charts iOS 17 selection API — se actualiza automáticamente al tocar/deslizar
    @State private var selectedDate: Date? = nil

    private var sorted: [MetricSample] { samples.sorted { $0.date < $1.date } }

    private var selectedSample: MetricSample? {
        guard let sel = selectedDate else { return sorted.last }
        return sorted.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    private var yDomain: ClosedRange<Double> {
        let vals = sorted.map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), lo < hi else { return 0...100 }
        let pad = (hi - lo) * 0.2
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Tooltip ────────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 12) {
                if let s = selectedSample {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.date, format: .dateTime.weekday(.short).day().month(.abbreviated))
                            .font(.caption2).foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: unit.contains(".") || unit.isEmpty ? "%.1f" : "%.0f", s.value))
                                .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(color)
                            if !unit.isEmpty {
                                Text(unit).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                // Mín / Máx
                if let lo = sorted.map(\.value).min(), let hi = sorted.map(\.value).max() {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up").font(.system(size: 9))
                            Text(String(format: "%.1f", hi))
                        }
                        .foregroundColor(higherIsBetter ? .green : .red)
                        .font(.caption2)

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down").font(.system(size: 9))
                            Text(String(format: "%.1f", lo))
                        }
                        .foregroundColor(higherIsBetter ? .red : .green)
                        .font(.caption2)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            // ── Gráfica ────────────────────────────────────────────────────
            Chart(sorted) { s in
                AreaMark(
                    x: .value("Fecha", s.date, unit: .day),
                    y: .value("Valor", s.value)
                )
                .foregroundStyle(LinearGradient(
                    colors: [color.opacity(0.2), color.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Fecha", s.date, unit: .day),
                    y: .value("Valor", s.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                // Marcador del punto seleccionado
                if let sel = selectedSample, Calendar.current.isDate(s.date, inSameDayAs: sel.date) {
                    PointMark(
                        x: .value("Fecha", s.date, unit: .day),
                        y: .value("Valor", s.value)
                    )
                    .foregroundStyle(color)
                    .symbolSize(72)

                    RuleMark(x: .value("Fecha", s.date, unit: .day))
                        .foregroundStyle(color.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: strideDays)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.secondary)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary)
                        .font(.caption2)
                }
            }
            // Scroll horizontal mostrando los últimos 14 días por defecto
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: 60 * 60 * 24 * 14)          // 14 días visibles
            .chartScrollPosition(initialX: sorted.last?.date ?? Date()) // empieza al final
            // API nativa de selección — no pierde el cursor al hacer scroll
            .chartXSelection(value: $selectedDate)
            .frame(height: 200)
            .animation(.easeInOut(duration: 0.15), value: selectedDate)
        }
    }

    private var strideDays: Int {
        sorted.count > 20 ? 7 : sorted.count > 10 ? 3 : 1
    }
}

// MARK: - Gráfica horaria interactiva (para Body Battery y Estrés)

struct HourlyInteractiveChart: View {
    let samples: [MetricSample]   // un punto por hora
    let color: Color
    let unit: String
    var higherIsBetter: Bool = true
    var emptyText: String = "Sin datos"
    var useBarMarks: Bool = false  // true = barras (estrés), false = línea (battery)
    var barColorFn: ((Double) -> Color)? = nil  // si nil usa color fijo

    @State private var selectedDate: Date? = nil

    private var sorted: [MetricSample] { samples.sorted { $0.date < $1.date } }
    private var selected: MetricSample? {
        guard let sel = selectedDate else { return sorted.last }
        return sorted.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tooltip
            HStack(alignment: .bottom) {
                if let s = selected {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.date, format: .dateTime.hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.0f", s.value))
                                .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(barColorFn?(s.value) ?? color)
                            if !unit.isEmpty {
                                Text(unit).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
                if let lo = sorted.map(\.value).min(), let hi = sorted.map(\.value).max() {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up").font(.system(size: 9))
                            Text(String(format: "%.0f", hi))
                        }.foregroundColor(higherIsBetter ? .green : .red).font(.caption2)
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down").font(.system(size: 9))
                            Text(String(format: "%.0f", lo))
                        }.foregroundColor(higherIsBetter ? .red : .green).font(.caption2)
                    }
                }
            }
            .padding(.horizontal, 4)

            if sorted.isEmpty {
                Text(emptyText)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(sorted) { s in
                    if useBarMarks {
                        BarMark(
                            x: .value("Hora", s.date, unit: .hour),
                            y: .value("Valor", s.value)
                        )
                        .foregroundStyle((barColorFn?(s.value) ?? color).gradient)
                        .cornerRadius(3)
                        .opacity(selectedDate == nil || Calendar.current.isDate(s.date, equalTo: selected?.date ?? s.date, toGranularity: .hour) ? 1 : 0.35)
                    } else {
                        AreaMark(
                            x: .value("Hora", s.date, unit: .hour),
                            y: .value("Valor", s.value)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Hora", s.date, unit: .hour),
                            y: .value("Valor", s.value)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)

                        if let sel = selected, Calendar.current.isDate(s.date, equalTo: sel.date, toGranularity: .hour) {
                            PointMark(x: .value("Hora", s.date, unit: .hour), y: .value("Valor", s.value))
                                .foregroundStyle(color).symbolSize(64)
                            RuleMark(x: .value("Hora", s.date, unit: .hour))
                                .foregroundStyle(color.opacity(0.3))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.caption2).foregroundStyle(Color.secondary)
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(Color.primary.opacity(0.07))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                            .foregroundStyle(Color.primary.opacity(0.07))
                        AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 190)
                .animation(.easeInOut(duration: 0.1), value: selectedDate)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
