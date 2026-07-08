import Foundation

// Registro ligero de peso por ejercicio de una rutina guardada. Es independiente
// del sistema de sesiones (WorkoutLog): aquí el usuario solo va apuntando el peso
// (y opcionalmente las reps) de cada semana para ver la progresión de ese ejercicio.
struct LiftEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var weight: Double      // kg
    var reps: Int?          // opcional

    // 1RM estimado (Epley) si hay reps
    var oneRepMax: Double? {
        guard let reps, reps > 0 else { return nil }
        return weight * (1.0 + Double(reps) / 30.0)
    }
}

@MainActor
final class RoutineProgressStore: ObservableObject {
    static let shared = RoutineProgressStore()

    // Clave = id del GymExercise (estable en una rutina guardada)
    @Published private var byExercise: [String: [LiftEntry]] = [:]

    private let storageKey = "apex_routine_progress_v1"

    private init() { load() }

    // MARK: - Consulta

    // Entradas de un ejercicio, ordenadas de más antigua a más reciente
    func entries(for exerciseID: UUID) -> [LiftEntry] {
        (byExercise[exerciseID.uuidString] ?? []).sorted { $0.date < $1.date }
    }

    func latest(for exerciseID: UUID) -> LiftEntry? {
        entries(for: exerciseID).last
    }

    // Variación (kg) de la última entrada respecto a la anterior
    func lastDelta(for exerciseID: UUID) -> Double? {
        let e = entries(for: exerciseID)
        guard e.count >= 2 else { return nil }
        return e[e.count - 1].weight - e[e.count - 2].weight
    }

    // MARK: - Mutación

    func add(weight: Double, reps: Int?, date: Date = Date(), for exerciseID: UUID) {
        var list = byExercise[exerciseID.uuidString] ?? []
        list.append(LiftEntry(date: date, weight: weight, reps: reps))
        byExercise[exerciseID.uuidString] = list
        persist()
    }

    func remove(_ entry: LiftEntry, for exerciseID: UUID) {
        byExercise[exerciseID.uuidString]?.removeAll { $0.id == entry.id }
        persist()
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [LiftEntry]].self, from: data) else { return }
        byExercise = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(byExercise) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
