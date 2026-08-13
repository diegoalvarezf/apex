import SwiftUI

// MARK: - Root: lista de rutinas guardadas

struct RoutineView: View {
    @EnvironmentObject var routineVM: RoutineViewModel
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if routineVM.routines.isEmpty {
                    EmptyRoutineView { showImport = true }
                } else {
                    RoutineListView(showImport: $showImport)
                }
            }
            .navigationTitle("Mis rutinas")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: {
                        Image(systemName: "plus")
                    }
                    .tint(.purple)
                }
            }
            .sheet(isPresented: $showImport) {
                RoutineAISheet()
            }
        }
    }
}

// MARK: - Lista de rutinas

private struct RoutineListView: View {
    @EnvironmentObject var routineVM: RoutineViewModel
    @Binding var showImport: Bool

    // La rutina más reciente (por fecha) se resalta en otro color
    private var newestID: UUID? {
        routineVM.routines.max(by: { $0.updatedAt < $1.updatedAt })?.id
    }

    var body: some View {
        List {
            ForEach(routineVM.routines) { routine in
                NavigationLink(destination: RoutineDetailView(routine: routine)) {
                    RoutineRowCard(routine: routine,
                                   isNewest: routine.id == newestID,
                                   isActive: routineVM.isActive(routine))
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading) {
                    if !routineVM.isActive(routine) {
                        Button {
                            routineVM.setActive(routine)
                        } label: {
                            Label("Activar", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
            }
            .onDelete { idx in
                idx.forEach { routineVM.delete(routineVM.routines[$0]) }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemGroupedBackground))
    }
}

private struct RoutineRowCard: View {
    let routine: GymRoutine
    var isNewest: Bool = false
    // La que se está siguiendo: es la que alimenta a la IA. Antes el distintivo
    // marcaba solo la más reciente por fecha, que no es lo mismo.
    var isActive: Bool = false
    @State private var exportURL: ExportFile?

    private var accent: Color { isActive ? .green : .purple }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(routine.name).font(.headline)
                        if isActive {
                            Text("Activa").font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundColor(.green)
                        } else if isNewest {
                            Text("Nueva").font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundColor(.purple)
                        }
                    }
                    Text(routine.updatedAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                // Exportar la rutina a JSON
                Button { exportURL = ExportFile(routine: routine) } label: {
                    Image(systemName: "square.and.arrow.up").font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(accent).font(.title3)
            }

            if !routine.aiSummary.isEmpty {
                Text(routine.aiSummary)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Pills con los días
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(routine.days) { day in
                        Text(day.shortName)
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(accent.opacity(0.12), in: Capsule())
                            .foregroundColor(accent)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isNewest ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .sheet(item: $exportURL) { file in
            ShareSheet(items: [file.url])
        }
    }
}

// Escribe la rutina en un JSON temporal para compartir/descargar
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL

    init(routine: GymRoutine) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        let data = (try? enc.encode(routine)) ?? Data()
        let safe = routine.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).json")
        try? data.write(to: url)
        self.url = url
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Detalle de una rutina (selector de día + ejercicios)

struct RoutineDetailView: View {
    let routine: GymRoutine
    @EnvironmentObject var routineVM: RoutineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedDayIndex = 0
    @State private var showDeleteConfirm = false

    // Copia viva del VM para que las ediciones se reflejen al instante
    private var live: GymRoutine { routineVM.routines.first { $0.id == routine.id } ?? routine }

    var body: some View {
        VStack(spacing: 0) {
            // Selector de día
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(live.days.indices, id: \.self) { i in
                        let day = live.days[i]
                        let sel = i == selectedDayIndex
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedDayIndex = i }
                        } label: {
                            VStack(spacing: 3) {
                                Text("Día \(i + 1)")
                                    .font(.caption2).fontWeight(.medium)
                                    .foregroundColor(sel ? .white : .secondary)
                                Text(day.shortName)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(sel ? .white : .primary)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(
                                sel ? Color.purple : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))

            if live.days.indices.contains(selectedDayIndex) {
                DayDetailView(day: live.days[selectedDayIndex])
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
            }
        }
        .confirmationDialog("Eliminar \"\(routine.name)\"", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Eliminar rutina", role: .destructive) {
                routineVM.delete(routine)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Detalle de un día

private struct DayDetailView: View {
    let day: GymDay

    @State private var showWorkout = false
    @State private var workoutSession = WorkoutLogSession()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    // Cabecera
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.name).font(.headline)
                            Text("\(day.exercises.count) ejercicios · \(day.totalSets) series")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(day.muscleGroups.prefix(3), id: \.self) { mg in
                                Text(mg)
                                    .font(.caption2).fontWeight(.medium)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.1), in: Capsule())
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !day.notes.isEmpty {
                        HStack {
                            Image(systemName: "note.text").foregroundColor(.secondary).font(.caption)
                            Text(day.notes).font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    VStack(spacing: 1) {
                        ForEach(Array(day.exercises.enumerated()), id: \.element.id) { idx, ex in
                            ExerciseRow(exercise: ex, index: idx + 1,
                                        supersetColor: supersetColor(ex.supersetGroup))
                            if idx < day.exercises.count - 1 {
                                Divider().padding(.leading, 56)
                            }
                        }
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Conclusión IA de cómo va este día de entreno
                    if dayEntriesCount > 0 {
                        AITextCard(
                            title: "¿Cómo voy en este día?",
                            subtitle: "Claude revisa la progresión de los ejercicios de este día y te da una conclusión.",
                            cacheKey: "apex_routine_day_ai_\(day.name)_\(dayEntriesCount)",
                            generate: { try await analyzeDay() }
                        )
                    }
                }
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 16)
            }

            // — Botón sticky "Entrenar este día"
            VStack(spacing: 0) {
                Button {
                    workoutSession = WorkoutLogSession()
                    for ex in day.exercises {
                        let exercise = Exercise(name: ex.name, category: categoryFor(ex.muscleGroup))
                        workoutSession.addExercise(exercise)
                    }
                    showWorkout = true
                } label: {
                    Label("Entrenar este día", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
        }
        .fullScreenCover(isPresented: $showWorkout) {
            LiveActivityView(sport: .weightTraining, preloadedSession: workoutSession)
        }
    }

    private func categoryFor(_ muscleGroup: String) -> ExerciseCategory {
        switch muscleGroup.lowercased() {
        case "pecho":                                        return .chest
        case "espalda":                                      return .back
        case "hombros":                                      return .shoulders
        case "bíceps", "biceps", "tríceps", "triceps", "brazos": return .arms
        case "piernas", "glúteos", "gluteos":               return .legs
        case "core", "abdominales":                          return .core
        default:                                             return .other
        }
    }

    // MARK: - Conclusión IA del día

    // Total de registros del día (sirve de firma para la caché: al añadir uno nuevo,
    // se recalcula el análisis).
    private var dayEntriesCount: Int {
        day.exercises.reduce(0) { $0 + RoutineProgressStore.shared.entries(for: $1.id).count }
    }

    private func analyzeDay() async throws -> String {
        let df = DateFormatter(); df.dateFormat = "d MMM"
        func fmt(_ w: Double) -> String { w == w.rounded() ? "\(Int(w))" : String(format: "%.1f", w) }

        var lines: [String] = [
            "Día de entreno: \(AICoachContext.safeText(day.name)) — \(day.exercises.count) ejercicios.",
            "Ejercicios y su progresión registrada (de más antiguo a reciente):"
        ]
        for ex in day.exercises {
            let entries = RoutineProgressStore.shared.entries(for: ex.id)
            var head = "- \(AICoachContext.safeText(ex.name))\(ex.muscleGroup.isEmpty ? "" : " (\(ex.muscleGroup))") [\(ex.sets)×\(ex.reps)\(ex.weight.isEmpty ? "" : ", obj \(ex.weight)")]"
            if entries.isEmpty { head += ": sin registros aún" }
            lines.append(head)
            for e in entries.suffix(6) {
                var parts: [String] = []
                if e.weight > 0 { parts.append("\(fmt(e.weight)) kg") }
                if let r = e.reps { parts.append("\(r) reps") }
                if let s = e.seconds { parts.append("\(s) s") }
                if let m = e.meters { parts.append("\(m) m") }
                lines.append("    \(df.string(from: e.date)) · \(parts.isEmpty ? "—" : parts.joined(separator: " · "))")
            }
        }

        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: AIPrompts.routineDay, maxTokens: 350)
    }
}

// MARK: - Color superserie

private func supersetColor(_ group: String?) -> Color? {
    guard let g = group else { return nil }
    switch g.uppercased() {
    case "A": return .orange
    case "B": return .blue
    case "C": return .indigo
    case "D": return .green
    case "E": return .pink
    default:  return .purple
    }
}

// MARK: - Fila ejercicio

private struct ExerciseRow: View {
    let exercise: GymExercise
    let index: Int
    var supersetColor: Color? = nil   // no nil → es parte de superserie
    @ObservedObject private var progress = RoutineProgressStore.shared
    @State private var showProgress = false
    @State private var showEdit = false

    private var accentColor: Color { supersetColor ?? muscleColor }
    private var latest: LiftEntry? { progress.latest(for: exercise.id) }

    var body: some View {
        Button {
            showProgress = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    // Línea de conexión superserie + badge
                    ZStack {
                        Circle().fill(accentColor.opacity(0.13)).frame(width: 36, height: 36)
                        if let group = exercise.supersetGroup {
                            VStack(spacing: 0) {
                                Text("SS").font(.system(size: 8, weight: .bold)).foregroundColor(accentColor)
                                Text(group).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(accentColor)
                            }
                        } else {
                            Text("\(index)")
                                .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                                .foregroundColor(accentColor)
                        }
                    }
                    .frame(width: 50)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                        Text(exercise.muscleGroup)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(exercise.sets) × \(exercise.reps)")
                            .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
                            .foregroundColor(supersetColor != nil ? accentColor : .primary)
                        // Último peso registrado (o el objetivo de la rutina si no hay)
                        if let latest {
                            loggedBadge(latest)
                        } else if !exercise.weight.isEmpty {
                            Text(exercise.weight).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.leading, 12)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)

                if !exercise.notes.isEmpty {
                    HStack(spacing: 8) {
                        Rectangle().fill(accentColor.opacity(0.5)).frame(width: 3).cornerRadius(2)
                        Text(exercise.notes).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 50).padding(.trailing, 14).padding(.bottom, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProgress) {
            ExerciseProgressSheet(exercise: exercise, accent: accentColor)
        }
        .sheet(isPresented: $showEdit) {
            EditExerciseSheet(exercise: exercise)
        }
        .contextMenu {
            Button { showProgress = true } label: {
                Label("Ver progresión", systemImage: "chart.line.uptrend.xyaxis")
            }
            Button { showEdit = true } label: {
                Label("Editar ejercicio", systemImage: "pencil")
            }
        }
    }

    // Capsula con el último registro + variación. Elige la métrica real del
    // ejercicio: peso si lo hay, si no segundos (plancha/isometría) o reps (peso
    // corporal). Así no muestra "0 kg" en ejercicios sin carga.
    @ViewBuilder private func loggedBadge(_ latest: LiftEntry) -> some View {
        let all = progress.entries(for: exercise.id)
        let prev = all.count >= 2 ? all[all.count - 2] : nil
        let badge = metricBadge(latest: latest, prev: prev)
        HStack(spacing: 3) {
            if let d = badge.delta, d != 0 {
                Image(systemName: d > 0 ? "arrow.up" : "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(d > 0 ? .green : .orange)
            }
            Text(badge.label)
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(accentColor.opacity(0.12), in: Capsule())
    }

    private func metricBadge(latest: LiftEntry, prev: LiftEntry?) -> (label: String, delta: Double?) {
        if latest.weight > 0 {
            return (fmtKg(latest.weight), prev.map { latest.weight - $0.weight })
        }
        if let s = latest.seconds {
            return ("\(s) s", prev?.seconds.map { Double(s - $0) })
        }
        if let m = latest.meters {
            return ("\(m) m", prev?.meters.map { Double(m - $0) })
        }
        if let r = latest.reps {
            return ("\(r) reps", prev?.reps.map { Double(r - $0) })
        }
        return (fmtKg(latest.weight), nil)
    }

    private func fmtKg(_ w: Double) -> String {
        (w == w.rounded() ? "\(Int(w))" : String(format: "%.1f", w)) + " kg"
    }

    private var muscleColor: Color {
        switch exercise.muscleGroup.lowercased() {
        case "pecho":              return .blue
        case "espalda":            return .green
        case "hombros":            return .orange
        case "bíceps", "biceps":   return .cyan
        case "tríceps", "triceps": return .red
        case "piernas":            return .purple
        case "core":               return .yellow
        case "glúteos", "gluteos": return .pink
        default:                   return .secondary
        }
    }
}

// MARK: - Empty state

private struct EmptyRoutineView: View {
    let onTap: () -> Void
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color.purple.opacity(0.1)).frame(width: 88, height: 88)
                Image(systemName: "dumbbell.fill").font(.system(size: 36)).foregroundColor(.purple)
            }
            VStack(spacing: 6) {
                Text("Sin rutinas todavía").font(.title2).fontWeight(.bold)
                Text("Pega el texto de tu rutina y la IA la organiza para consultarla en el gym")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Button(action: onTap) {
                Label("Importar rutina", systemImage: "sparkles")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .background(Color.purple).foregroundColor(.white).clipShape(Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
