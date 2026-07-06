import SwiftUI

struct WeightTrainingView: View {
    @ObservedObject var session: WorkoutLogSession
    let elapsedSeconds: Int

    @State private var showExercisePicker = false
    @State private var activeEntry: ExerciseEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Timer compacto
            Text(formatDuration(elapsedSeconds))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.vertical, 12)

            // Lista de ejercicios
            if session.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(session.entries) { entry in
                            ExerciseCard(entry: entry, session: session)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            // Botón añadir ejercicio
            Button {
                showExercisePicker = true
            } label: {
                Label("Añadir ejercicio", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { exercise in
                session.addExercise(exercise)
                showExercisePicker = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.3))
            Text("Añade tu primer ejercicio")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatDuration(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Tarjeta de ejercicio

private struct ExerciseCard: View {
    let entry: ExerciseEntry
    @ObservedObject var session: WorkoutLogSession
    @State private var weight: Double = 0
    @State private var reps: Int = 10
    @State private var showSetInput = false

    private var lastLog: WorkoutSet? { WorkoutLogStore.shared.lastLog(for: entry.exerciseName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cabecera
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.exerciseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    if let last = lastLog {
                        Text("Último: \(formatWeight(last.weight)) × \(last.reps)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer()
                Button {
                    session.removeExercise(entry.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            // Series registradas
            if !entry.sets.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { i, set in
                        HStack {
                            Text("Serie \(i + 1)")
                                .font(.caption2).foregroundStyle(.white.opacity(0.5))
                                .frame(width: 50, alignment: .leading)
                            Text(formatWeight(set.weight))
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .frame(width: 60)
                            Text("×")
                                .font(.caption2).foregroundStyle(.white.opacity(0.4))
                            Text("\(set.reps) reps")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("1RM ~\(formatWeight(set.oneRepMax))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Añadir serie
            if showSetInput {
                AddSetRow(weight: $weight, reps: $reps) {
                    session.addSet(to: entry.id, weight: weight, reps: reps)
                    showSetInput = false
                }
            } else {
                Button {
                    weight = lastLog?.weight ?? 0
                    reps = lastLog?.reps ?? 10
                    showSetInput = true
                } label: {
                    Label("Añadir serie", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func formatWeight(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w)) kg" : String(format: "%.1f kg", w)
    }
}

// MARK: - Fila de entrada de serie

private struct AddSetRow: View {
    @Binding var weight: Double
    @Binding var reps: Int
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Peso
            HStack(spacing: 4) {
                Button { weight = max(0, weight - 2.5) } label: {
                    Image(systemName: "minus").font(.caption).foregroundStyle(.white)
                }
                Text(weight == weight.rounded() ? "\(Int(weight))kg" : String(format: "%.1fkg", weight))
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(minWidth: 48)
                Button { weight += 2.5 } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            // Reps
            HStack(spacing: 4) {
                Button { reps = max(1, reps - 1) } label: {
                    Image(systemName: "minus").font(.caption).foregroundStyle(.white)
                }
                Text("\(reps) reps")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(minWidth: 48)
                Button { reps += 1 } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button(action: onSave) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Selector de ejercicio

struct ExercisePickerSheet: View {
    let onSelect: (Exercise) -> Void
    @StateObject private var store = WorkoutLogStore.shared
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory? = nil
    @State private var showAddCustom = false
    @State private var customName = ""

    private var filtered: [Exercise] {
        store.library.filter { ex in
            (selectedCategory == nil || ex.category == selectedCategory) &&
            (searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Categorías
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(label: "Todos", selected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                            CategoryChip(label: cat.rawValue, selected: selectedCategory == cat) {
                                selectedCategory = selectedCategory == cat ? nil : cat
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(filtered) { exercise in
                    Button {
                        onSelect(exercise)
                    } label: {
                        HStack {
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(exercise.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Añadir personalizado
                if showAddCustom {
                    HStack {
                        TextField("Nombre del ejercicio", text: $customName)
                        Button("Añadir") {
                            guard !customName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let ex = Exercise(name: customName, category: selectedCategory ?? .other, isCustom: true)
                            store.addExercise(ex)
                            onSelect(ex)
                        }
                        .disabled(customName.isEmpty)
                    }
                } else {
                    Button {
                        showAddCustom = true
                    } label: {
                        Label("Añadir ejercicio personalizado", systemImage: "plus.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Buscar ejercicio")
            .navigationTitle("Ejercicios")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CategoryChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                            in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
