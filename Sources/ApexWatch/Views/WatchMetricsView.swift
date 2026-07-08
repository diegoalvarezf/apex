import SwiftUI

struct WatchMetricsView: View {
    let data: WatchDashboardData

    private func metricRow(_ icon: String, _ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    // TSB = CTL − ATL en unidades de carga (zonas TrainingPeaks):
    // ≥25 muy fresco · 5..25 fresco · −10..5 neutro · −30..−10 cargando · <−30 sobrecarga
    private var tsbColor: Color {
        data.tsb >= 25 ? .cyan : data.tsb >= 5 ? .green : data.tsb >= -10 ? .gray : data.tsb >= -30 ? .orange : .red
    }

    var body: some View {
        List {
            Section("Salud") {
                metricRow("moon.fill", "Sueño", data.sleepHours > 0 ? String(format: "%.1fh", data.sleepHours) : "--", color: .indigo)
                metricRow("waveform.path.ecg", "HRV", data.hrv > 0 ? String(format: "%.0f ms", data.hrv) : "--", color: .green)
                metricRow("heart.fill", "FC reposo", data.rhr > 0 ? String(format: "%.0f bpm", data.rhr) : "--", color: .red)
                metricRow("flame.fill", "Kcal", data.kcal > 0 ? String(format: "%.0f", data.kcal) : "--", color: .orange)
            }
            if data.ctl > 0 {
                Section("Carga") {
                    metricRow("chart.line.uptrend.xyaxis", "CTL", String(format: "%.0f", data.ctl), color: .blue)
                    metricRow("bolt.fill", "ATL", String(format: "%.0f", data.atl), color: .orange)
                    metricRow("gauge.medium", "TSB", String(format: "%+.0f", data.tsb), color: tsbColor)
                }
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Métricas")
    }
}
