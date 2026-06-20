import SwiftUI
import Charts

struct TrainingLoadDetailView: View {
    let load: TrainingLoad
    let activities: [StravaActivity]

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

                // ATL / CTL / TSB
                HStack(spacing: 0) {
                    LoadStat(label: "ATL", subtitle: "Fatiga", value: load.atl, color: .red)
                    Divider().frame(height: 50)
                    LoadStat(label: "CTL", subtitle: "Fitness", value: load.ctl, color: .blue)
                    Divider().frame(height: 50)
                    LoadStat(label: "TSB", subtitle: "Forma", value: load.tsb,
                             color: load.tsb >= 5 ? .green : load.tsb >= -10 ? .orange : .red)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Actividades recientes con suffer score
                if !activities.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Esfuerzo por actividad")
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                        ForEach(Array(activities.prefix(10).enumerated()), id: \.element.id) { i, act in
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

                // Explicación
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cómo funciona")
                        .font(.headline)
                    Text("**ATL** (Carga aguda, 7 días) mide la fatiga reciente. **CTL** (Carga crónica, 42 días) mide tu nivel de fitness. **TSB** = CTL - ATL y representa tu forma actual.\n\nTSB positivo alto → fresco pero posiblemente desentrenado. TSB muy negativo → sobreentrenado, alto riesgo de lesión.")
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
        case .fresh: return "Descansado y listo. Buen momento para una competición o test."
        case .optimal: return "En tu punto óptimo. El entrenamiento está dando frutos."
        case .neutral: return "Balance equilibrado entre carga y recuperación."
        case .tired: return "Acumulando fatiga. Considera una sesión de recuperación."
        case .overreached: return "Sobrecarga alta. Prioriza el descanso para evitar lesiones."
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

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(String(format: "%.0f", value))
                .font(.system(.title2, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
