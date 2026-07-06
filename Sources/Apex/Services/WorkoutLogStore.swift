import Foundation

@MainActor
final class WorkoutLogStore: ObservableObject {
    static let shared = WorkoutLogStore()

    @Published var logs: [WorkoutLog] = []
    @Published var library: [Exercise] = []

    private let logsKey = "apex_workout_logs"
    private let libraryKey = "apex_exercise_library"

    private init() {
        loadLogs()
        loadLibrary()
    }

    // MARK: - Logs

    func save(_ log: WorkoutLog) {
        if let idx = logs.firstIndex(where: { $0.id == log.id }) {
            logs[idx] = log
        } else {
            logs.insert(log, at: 0)
        }
        persistLogs()
    }

    func delete(_ log: WorkoutLog) {
        logs.removeAll { $0.id == log.id }
        persistLogs()
    }

    // Historial de sets para un ejercicio concreto (por nombre, para gráfica de progresión)
    func history(for exerciseName: String) -> [(date: Date, bestSet: WorkoutSet, volume: Double)] {
        logs.compactMap { log -> (date: Date, bestSet: WorkoutSet, volume: Double)? in
            guard let entry = log.exercises.first(where: { $0.exerciseName == exerciseName }),
                  let best = entry.bestSet else { return nil }
            return (log.date, best, entry.totalVolume)
        }.sorted { $0.date < $1.date }
    }

    // Último log de un ejercicio (para sugerir peso al usuario)
    func lastLog(for exerciseName: String) -> WorkoutSet? {
        for log in logs {
            if let entry = log.exercises.first(where: { $0.exerciseName == exerciseName }),
               let last = entry.sets.last {
                return last
            }
        }
        return nil
    }

    // MARK: - Library

    func addExercise(_ exercise: Exercise) {
        library.append(exercise)
        persistLibrary()
    }

    func deleteExercise(_ exercise: Exercise) {
        library.removeAll { $0.id == exercise.id && $0.isCustom }
        persistLibrary()
    }

    // MARK: - Persistence

    private func loadLogs() {
        guard let data = UserDefaults.standard.data(forKey: logsKey),
              let decoded = try? JSONDecoder().decode([WorkoutLog].self, from: data) else { return }
        logs = decoded
    }

    private func persistLogs() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        UserDefaults.standard.set(data, forKey: logsKey)
    }

    private func loadLibrary() {
        if let data = UserDefaults.standard.data(forKey: libraryKey),
           let custom = try? JSONDecoder().decode([Exercise].self, from: data) {
            library = Exercise.defaultLibrary + custom.filter { $0.isCustom }
        } else {
            library = Exercise.defaultLibrary
        }
    }

    private func persistLibrary() {
        let custom = library.filter { $0.isCustom }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        UserDefaults.standard.set(data, forKey: libraryKey)
    }
}
