import Foundation

enum ExerciseCategory: String, Codable, CaseIterable {
    case chest = "Pecho"
    case back = "Espalda"
    case shoulders = "Hombros"
    case arms = "Brazos"
    case legs = "Piernas"
    case core = "Core"
    case other = "Otro"

    var icon: String {
        switch self {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .legs: return "figure.run"
        case .core: return "figure.core.training"
        case .other: return "star.fill"
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: ExerciseCategory
    var isCustom: Bool = false
}

struct WorkoutSet: Codable, Identifiable {
    var id: UUID = UUID()
    var weight: Double   // kg
    var reps: Int
    var timestamp: Date = Date()

    var oneRepMax: Double { reps > 0 ? weight * (1.0 + Double(reps) / 30.0) : weight }
}

struct ExerciseEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseId: UUID
    var exerciseName: String
    var category: ExerciseCategory
    var sets: [WorkoutSet] = []

    var totalVolume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var bestSet: WorkoutSet? { sets.max(by: { $0.oneRepMax < $1.oneRepMax }) }
}

struct WorkoutLog: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var duration: TimeInterval
    var exercises: [ExerciseEntry] = []

    var totalVolume: Double { exercises.reduce(0) { $0 + $1.totalVolume } }
    var exerciseCount: Int { exercises.count }
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

extension Exercise {
    static let defaultLibrary: [Exercise] = [
        // Pecho
        Exercise(name: "Press banca", category: .chest),
        Exercise(name: "Press inclinado", category: .chest),
        Exercise(name: "Aperturas", category: .chest),
        Exercise(name: "Fondos", category: .chest),
        // Espalda
        Exercise(name: "Dominadas", category: .back),
        Exercise(name: "Remo con barra", category: .back),
        Exercise(name: "Remo con mancuerna", category: .back),
        Exercise(name: "Jalón al pecho", category: .back),
        Exercise(name: "Peso muerto", category: .back),
        // Hombros
        Exercise(name: "Press militar", category: .shoulders),
        Exercise(name: "Elevaciones laterales", category: .shoulders),
        Exercise(name: "Pájaro", category: .shoulders),
        // Brazos
        Exercise(name: "Curl de bíceps", category: .arms),
        Exercise(name: "Curl martillo", category: .arms),
        Exercise(name: "Extensión tríceps polea", category: .arms),
        Exercise(name: "Press francés", category: .arms),
        // Piernas
        Exercise(name: "Sentadilla", category: .legs),
        Exercise(name: "Prensa", category: .legs),
        Exercise(name: "Zancadas", category: .legs),
        Exercise(name: "Curl de pierna", category: .legs),
        Exercise(name: "Extensión de cuádriceps", category: .legs),
        Exercise(name: "Hip thrust", category: .legs),
        Exercise(name: "Gemelos de pie", category: .legs),
        // Core
        Exercise(name: "Plancha", category: .core),
        Exercise(name: "Crunch", category: .core),
        Exercise(name: "Rueda abdominal", category: .core),
    ]
}
