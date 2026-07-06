import Foundation
import SwiftUI

@MainActor
final class WorkoutLogSession: ObservableObject {
    @Published var entries: [ExerciseEntry] = []

    func addExercise(_ exercise: Exercise) {
        guard !entries.contains(where: { $0.exerciseName == exercise.name }) else { return }
        entries.append(ExerciseEntry(exerciseId: exercise.id, exerciseName: exercise.name, category: exercise.category))
    }

    func addSet(to entryId: UUID, weight: Double, reps: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx].sets.append(WorkoutSet(weight: weight, reps: reps))
    }

    func removeSet(_ setId: UUID, from entryId: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[idx].sets.removeAll { $0.id == setId }
    }

    func removeExercise(_ entryId: UUID) {
        entries.removeAll { $0.id == entryId }
    }

    func buildLog(duration: TimeInterval) -> WorkoutLog {
        WorkoutLog(date: Date(), duration: duration, exercises: entries.filter { !$0.sets.isEmpty })
    }
}
