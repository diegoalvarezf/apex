import SwiftUI

struct WorkoutHistoryView: View {
    @StateObject private var store = WorkoutLogStore.shared

    var body: some View {
        Group {
            if store.logs.isEmpty {
                ContentUnavailableView("Sin entrenamientos",
                    systemImage: "dumbbell",
                    description: Text("Inicia una actividad de fuerza para registrar tus pesos"))
            } else {
                List {
                    ForEach(store.logs) { log in
                        NavigationLink(destination: WorkoutLogDetailView(log: log)) {
                            WorkoutLogRow(log: log)
                        }
                    }
                    .onDelete { idx in
                        idx.forEach { store.delete(store.logs[$0]) }
                    }
                }
            }
        }
        .navigationTitle("Historial de fuerza")
    }
}

struct WorkoutLogRow: View {
    let log: WorkoutLog
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(log.date, style: .date).font(.subheadline.weight(.semibold))
            HStack(spacing: 12) {
                Label("\(log.exerciseCount) ejercicios", systemImage: "dumbbell")
                Label("\(log.setCount) series", systemImage: "list.number")
                Label(formatVol(log.totalVolume), systemImage: "scalemass")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    private func formatVol(_ v: Double) -> String { String(format: "%.0f kg", v) }
}

struct WorkoutLogDetailView: View {
    let log: WorkoutLog
    var body: some View {
        List {
            ForEach(log.exercises) { entry in
                NavigationLink(destination: ExerciseProgressionView(exerciseName: entry.exerciseName)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.exerciseName).font(.subheadline.weight(.semibold))
                        ForEach(Array(entry.sets.enumerated()), id: \.element.id) { i, set in
                            Text("Serie \(i+1): \(formatW(set.weight)) × \(set.reps) reps  →  1RM ~\(formatW(set.oneRepMax))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(log.date.formatted(.dateTime.day().month().year()))
    }
    private func formatW(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w)) kg" : String(format: "%.1f kg", w)
    }
}
