import SwiftUI

// Pedir a la IA que sustituya un ejercicio, diciendo por qué no encaja.
//
// El motivo es texto libre a propósito: "me molesta el hombro", "no tengo barra
// Z", "me aburre". Es lo que permite proponer algo que de verdad sirva en vez de
// otro ejercicio del mismo grupo elegido al azar.
struct SwapExerciseSheet: View {
    let exercise: GymExercise
    let day: GymDay

    @EnvironmentObject var routineVM: RoutineViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var motivo = ""
    @FocusState private var escribiendo: Bool

    // Motivos frecuentes, para no obligar a escribir cuando es uno de los de siempre.
    private let sugerencias = [
        "Me molesta al hacerlo",
        "No tengo el material",
        "No me gusta / me aburre",
        "Es demasiado difícil",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name).font(.headline)
                        Text("\(exercise.sets)×\(exercise.reps)"
                             + (exercise.muscleGroup.isEmpty ? "" : " · \(exercise.muscleGroup)"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Ejercicio a cambiar")
                }

                Section {
                    TextField("Ej.: me molesta el hombro al bajar", text: $motivo, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($escribiendo)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sugerencias, id: \.self) { s in
                                Button(s) { motivo = s; escribiendo = false }
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(.primary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 0))
                } header: {
                    Text("¿Por qué no te encaja?")
                } footer: {
                    Text("Se buscará un sustituto del mismo grupo muscular que encaje en el día y respete el motivo. No gasta cuota de rutinas.")
                }

                if let error = routineVM.aiError {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Cambiar ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if routineVM.isParsingAI {
                        ProgressView()
                    } else {
                        Button("Cambiar") { cambiar() }
                            .disabled(motivo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(routineVM.isParsingAI)
        }
    }

    private func cambiar() {
        Task {
            await routineVM.swapExercise(exercise, in: day, reason: motivo)
            // Solo se cierra si ha funcionado; si no, el error queda a la vista.
            if routineVM.aiError == nil { dismiss() }
        }
    }
}
