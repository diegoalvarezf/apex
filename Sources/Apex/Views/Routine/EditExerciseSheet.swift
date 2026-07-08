import SwiftUI

// Edición de un ejercicio de la rutina (corregir el parseo de la IA o ajustar objetivos).
// Mantiene el mismo id, así que la progresión de peso registrada se conserva.
struct EditExerciseSheet: View {
    let exercise: GymExercise
    @EnvironmentObject var routineVM: RoutineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var muscleGroup: String
    @State private var setsText: String
    @State private var reps: String
    @State private var weight: String
    @State private var notes: String

    init(exercise: GymExercise) {
        self.exercise = exercise
        _name        = State(initialValue: exercise.name)
        _muscleGroup = State(initialValue: exercise.muscleGroup)
        _setsText    = State(initialValue: "\(exercise.sets)")
        _reps        = State(initialValue: exercise.reps)
        _weight      = State(initialValue: exercise.weight)
        _notes       = State(initialValue: exercise.notes)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ejercicio") {
                    TextField("Nombre", text: $name)
                    TextField("Grupo muscular", text: $muscleGroup)
                }
                Section("Prescripción") {
                    fieldRow("Series") {
                        TextField("3", text: $setsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    fieldRow("Reps") {
                        TextField("8-12", text: $reps)
                            .multilineTextAlignment(.trailing)
                    }
                    fieldRow("Peso objetivo") {
                        TextField("ej. 70kg", text: $weight)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Notas") {
                    TextField("Técnica, tempo, descanso…", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("Editar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder private func fieldRow<Content: View>(_ label: String, @ViewBuilder _ field: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            field().frame(maxWidth: 130)
        }
    }

    private func save() {
        var updated = exercise
        updated.name        = name.trimmingCharacters(in: .whitespaces)
        updated.muscleGroup = muscleGroup.trimmingCharacters(in: .whitespaces)
        updated.sets        = Int(setsText) ?? exercise.sets
        updated.reps        = reps.trimmingCharacters(in: .whitespaces).isEmpty ? exercise.reps : reps
        updated.weight      = weight.trimmingCharacters(in: .whitespaces)
        updated.notes       = notes
        routineVM.updateExercise(updated)
        dismiss()
    }
}
