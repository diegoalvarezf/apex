import SwiftUI
import Charts

struct TrainingLoadDetailView: View {
    let load: TrainingLoad
    let activities: [StravaActivity]
    let loadHistory: [DashboardViewModel.LoadSample]

    // Aplana el historial en puntos de serie para la gráfica
    private struct FitnessPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let series: String
    }

    private var chartPoints: [FitnessPoint] {
        loadHistory.flatMap { s in [
            FitnessPoint(date: s.date, value: s.ctl, series: "Fitness (CTL)"),
            FitnessPoint(date: s.date, value: s.atl, series: "Fatiga (ATL)")
        ]}
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // TSB status hero
                VStack(spacing: 8) {
                    Image(systemName: load.formStatus.systemImage)
                        .font(.system(size: 48))
                        .foregroundColor(load.formStatus.color)
                    Text(load.formStatus.rawValue)
                        .font(.title2).fontWeight(.bold)
                    Text(tsbDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)

                // ATL / CTL / ACWR
                HStack(spacing: 0) {
                    LoadStat(label: "ATL", subtitle: "Fatiga · 7d", value: load.atl, color: .orange)
                    Divider().frame(height: 50)
                    LoadStat(label: "CTL", subtitle: "Fitness · 42d", value: load.ctl, color: .blue)
                    Divider().frame(height: 50)
                    LoadStat(label: "ACWR", subtitle: "Riesgo", value: load.acwr,
                             color: load.formStatus.color, decimals: 2)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Forma / frescura (TSB = CTL − ATL)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Forma (TSB)", systemImage: "figure.run.circle.fill")
                            .font(.headline).foregroundColor(load.formZone.color)
                        Spacer()
                        Text(String(format: "%+.0f", load.tsb))
                            .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                            .foregroundColor(load.formZone.color)
                        Text(load.formZone.rawValue)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(load.formZone.color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(load.formZone.color.opacity(0.12), in: Capsule())
                    }
                    Text(load.formZone.detail)
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Fitness chart — historial ATL + CTL
                if !loadHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Evolución últimos 6 meses")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        Chart(chartPoints) { point in
                            LineMark(
                                x: .value("Fecha", point.date, unit: .day),
                                y: .value("Valor", point.value)
                            )
                            .foregroundStyle(by: .value("Serie", point.series))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartForegroundStyleScale([
                            "Fitness (CTL)": Color.blue,
                            "Fatiga (ATL)": Color.orange
                        ])
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                                AxisGridLine()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartLegend(position: .bottom, alignment: .center)
                        .frame(height: 200)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                }

                // Actividades recientes con suffer score
                if !activities.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Esfuerzo por actividad")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                        ForEach(Array(activities.suffix(10).reversed().enumerated()), id: \.element.id) { i, act in
                            HStack(spacing: 12) {
                                Text(act.sportEmoji).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(act.name).font(.subheadline).lineLimit(1)
                                    Text(act.startDate.formatted(.relative(presentation: .named)))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let ss = act.sufferScore {
                                    Text("\(ss)")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.bold)
                                        .foregroundColor(sufferColor(ss))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                            if i < min(activities.count, 10) - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                }

                // Explanation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cómo funciona")
                        .font(.headline)
                    Text("**ATL** (Carga aguda, 7 días) refleja la fatiga acumulada esta semana. **CTL** (Carga crónica, 42 días) refleja tu fitness general.\n\n**ACWR** = ATL / CTL (riesgo de lesión, Gabbett): <0.8 subentrenado · 0.8–1.3 óptimo · 1.3–1.5 elevado · >1.5 riesgo.\n\n**TSB** = CTL − ATL (forma/frescura, TrainingPeaks): positivo = fresco para competir, negativo = fatiga de entrenamiento productivo.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Carga de entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tsbDescription: String {
        switch load.formStatus {
        case .undertrained: return "Baja carga reciente. Puedes aumentar la intensidad o volumen."
        case .optimal:      return "Ratio óptimo. El entrenamiento y la recuperación están en equilibrio."
        case .elevated:     return "Carga elevada. Vigila señales de fatiga y prioriza el descanso."
        case .overreached:  return "Sobrecarga alta. Alto riesgo de lesión — reduce la carga esta semana."
        }
    }

    private func sufferColor(_ score: Int) -> Color {
        switch score {
        case 0..<50: return .blue
        case 50..<100: return .green
        case 100..<150: return .yellow
        case 150..<200: return .orange
        default: return .red
        }
    }
}

private struct LoadStat: View {
    let label: String
    let subtitle: String
    let value: Double
    let color: Color
    var decimals: Int = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(decimals == 0
                 ? String(format: "%.0f", value)
                 : String(format: "%.2f", value))
                .font(.system(.title2, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
