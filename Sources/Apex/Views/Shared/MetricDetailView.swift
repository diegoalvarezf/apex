import SwiftUI
import Charts

struct MetricConfig {
    let title: String
    let icon: String
    let color: Color
    let unit: String
    let value: String
    let samples: [MetricSample]
    var higherIsBetter: Bool = true
    var normalRange: ClosedRange<Double>?
    var explanation: String = ""
}

struct MetricDetailView: View {
    let config: MetricConfig
    @State private var selectedRange: ChartRange = .month

    enum ChartRange: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }

    var filteredSamples: [MetricSample] {
        let days: Int
        switch selectedRange {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return config.samples.filter { $0.date >= cutoff }
    }

    var trend: MetricTrend { computeTrend(samples: config.samples) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero value
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(config.value)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(config.unit)
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .offset(y: -4)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: trend.systemImage)
                        Text(trendLabel)
                    }
                    .font(.subheadline)
                    .foregroundColor(trend.color(higherIsBetter: config.higherIsBetter))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)

                // Chart
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Rango", selection: $selectedRange) {
                        ForEach(ChartRange.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    if filteredSamples.count >= 2 {
                        Chart(filteredSamples) { sample in
                            LineMark(
                                x: .value("Fecha", sample.date),
                                y: .value(config.title, sample.value)
                            )
                            .foregroundStyle(config.color)
                            .interpolationMethod(.catmullRom)

                            AreaMark(
                                x: .value("Fecha", sample.date),
                                y: .value(config.title, sample.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [config.color.opacity(0.3), config.color.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            if let range = config.normalRange {
                                RuleMark(y: .value("Mín", range.lowerBound))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                    .lineStyle(StrokeStyle(dash: [4]))
                                RuleMark(y: .value("Máx", range.upperBound))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                    .lineStyle(StrokeStyle(dash: [4]))
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: strideCount)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                AxisValueLabel()
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(height: 180)
                    } else {
                        ContentUnavailableView("Sin datos", systemImage: "chart.line.downtrend.xyaxis")
                            .frame(height: 180)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Stats
                if !filteredSamples.isEmpty {
                    StatsRow(samples: filteredSamples, unit: config.unit, color: config.color)
                        .padding(.horizontal)
                }

                // Explanation
                if !config.explanation.isEmpty {
                    Text(config.explanation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                }
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trendLabel: String {
        switch trend {
        case .up: return config.higherIsBetter ? "Mejorando" : "En aumento"
        case .down: return config.higherIsBetter ? "Bajando" : "Mejorando"
        case .flat: return "Estable"
        }
    }

    private var strideCount: Int {
        switch selectedRange {
        case .week: return 2
        case .month: return 7
        case .quarter: return 21
        }
    }
}

private struct StatsRow: View {
    let samples: [MetricSample]
    let unit: String
    let color: Color

    var avg: Double { samples.map(\.value).reduce(0, +) / Double(samples.count) }
    var min: Double { samples.map(\.value).min() ?? 0 }
    var max: Double { samples.map(\.value).max() ?? 0 }

    var body: some View {
        HStack(spacing: 0) {
            StatPill(label: "Mín", value: String(format: "%.0f", min), unit: unit, color: color)
            Divider().frame(height: 36)
            StatPill(label: "Media", value: String(format: "%.0f", avg), unit: unit, color: color)
            Divider().frame(height: 36)
            StatPill(label: "Máx", value: String(format: "%.0f", max), unit: unit, color: color)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StatPill: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.system(.headline, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
