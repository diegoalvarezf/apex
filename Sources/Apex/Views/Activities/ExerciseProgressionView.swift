import SwiftUI
import Charts

struct ExerciseProgressionView: View {
    let exerciseName: String
    @StateObject private var store = WorkoutLogStore.shared

    private var history: [(date: Date, bestSet: WorkoutSet, volume: Double)] {
        store.history(for: exerciseName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if history.isEmpty {
                    ContentUnavailableView("Sin historial", systemImage: "dumbbell",
                        description: Text("Registra un entrenamiento para ver tu progresión"))
                } else {
                    // 1RM estimado
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1RM estimado").font(.headline).padding(.horizontal)
                        Chart(history, id: \.date) { item in
                            LineMark(x: .value("Fecha", item.date),
                                     y: .value("1RM", item.bestSet.oneRepMax))
                                .foregroundStyle(Color.accentColor)
                                .interpolationMethod(.catmullRom)
                            AreaMark(x: .value("Fecha", item.date),
                                     y: .value("1RM", item.bestSet.oneRepMax))
                                .foregroundStyle(Color.accentColor.opacity(0.1))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Fecha", item.date),
                                      y: .value("1RM", item.bestSet.oneRepMax))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 160)
                        .padding(.horizontal)
                        .chartYAxisLabel("kg")
                    }
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // Volumen total por sesión
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Volumen total").font(.headline).padding(.horizontal)
                        Chart(history, id: \.date) { item in
                            BarMark(x: .value("Fecha", item.date),
                                    y: .value("Volumen", item.volume))
                                .foregroundStyle(Color.blue.gradient)
                                .cornerRadius(4)
                        }
                        .frame(height: 120)
                        .padding(.horizontal)
                        .chartYAxisLabel("kg totales")
                    }
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    // Últimas 5 sesiones
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Últimas sesiones").font(.headline).padding()
                        ForEach(Array(history.reversed().prefix(5)), id: \.date) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.date, style: .date).font(.subheadline)
                                    Text("Mejor serie: \(formatWeight(item.bestSet.weight)) × \(item.bestSet.reps) reps")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("1RM ~\(formatWeight(item.bestSet.oneRepMax))")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Vol: \(formatWeight(item.volume))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            Divider().padding(.leading)
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(exerciseName)
        .background(Color(.systemGroupedBackground))
    }

    private func formatWeight(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w)) kg" : String(format: "%.1f kg", w)
    }
}
