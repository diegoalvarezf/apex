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
