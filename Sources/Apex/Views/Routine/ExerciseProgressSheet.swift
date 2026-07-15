import SwiftUI
import Charts

// Hoja para registrar el peso semanal de un ejercicio de la rutina y ver su progresión.
struct ExerciseProgressSheet: View {
    let exercise: GymExercise
    var accent: Color = .purple

    @StateObject private var store = RoutineProgressStore.shared
    @EnvironmentObject private var routineVM: RoutineViewModel
    @Environment(\.dismiss) private var dismiss

    // Ejercicio vivo del VM (refleja ediciones al instante); id estable para el store
    private var live: GymExercise {
        for r in routineVM.routines {
            for d in r.days {
                if let e = d.exercises.first(where: { $0.id == exercise.id }) { return e }
            }
        }
        return exercise
    }

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var secondsText = ""
    @State private var entryDate = Date()
    @State private var showAdd = false
    @State private var showEdit = false
    @State private var editingEntry: LiftEntry? = nil   // nil = alta nueva

    private var entries: [LiftEntry] { store.entries(for: exercise.id) }

    // Qué métrica progresa este ejercicio: peso (con carga), tiempo (plancha,
    // isometría) o reps a peso corporal (elevaciones, dominadas…). Se deduce de
    // lo que se va registrando.
    private enum TrackMode { case weight, reps, time }
    private var trackMode: TrackMode {
        if entries.contains(where: { $0.weight > 0 }) { return .weight }
        if entries.contains(where: { ($0.seconds ?? 0) > 0 }) { return .time }
        if entries.contains(where: { ($0.reps ?? 0) > 0 }) { return .reps }
        return .weight
    }
    private func metricValue(_ e: LiftEntry) -> Double {
        switch trackMode {
        case .weight: return e.weight
        case .time:   return Double(e.seconds ?? 0)
        case .reps:   return Double(e.reps ?? 0)
        }
    }
    private func metricLabel(_ v: Double) -> String {
        switch trackMode {
        case .weight: return formatKg(v)
        case .time:   return "\(Int(v)) s"
        case .reps:   return "\(Int(v)) reps"
        }
    }
    private var chartTitle: String {
        switch trackMode {
        case .weight: return "Progresión de peso"
        case .time:   return "Progresión (segundos)"
        case .reps:   return "Progresión (reps)"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    prescriptionCard
                    if entries.isEmpty {
                        emptyState
                    } else {
                        chartCard
                        if entries.count >= 3 {
                            AITextCard(
                                title: "¿Cómo progreso?",
                                subtitle: "Claude analiza tu serie de pesos y te dice si progresas, te estancas o conviene descargar, y el siguiente paso.",
                                cacheKey: "apex_strength_ai_\(exercise.id.uuidString)_\(entries.count)",
                                generate: { try await analyzeProgress() }
                            )
                        }
                        historyCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(live.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                    Button {
                        editingEntry = nil
                        prefillFromLast()
                        showAdd = true
                    } label: { Image(systemName: "plus") }
                        .tint(accent)
                }
            }
            .sheet(isPresented: $showAdd) { addSheet }
            .sheet(isPresented: $showEdit) { EditExerciseSheet(exercise: live) }
        }
    }

    // MARK: - Cabecera con la prescripción de la rutina

    private var prescriptionCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(live.muscleGroup.isEmpty ? "Ejercicio" : live.muscleGroup)
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(live.sets) series × \(live.reps)")
                    .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                if !live.weight.isEmpty {
                    Text("Objetivo rutina: \(live.weight)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let latest = store.latest(for: exercise.id) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Último").font(.caption2).foregroundStyle(.secondary)
                    Text(metricLabel(metricValue(latest)))
                        .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                        .foregroundStyle(accent)
                    if trackMode == .weight, let d = store.lastDelta(for: exercise.id), d != 0 {
                        deltaLabel(d)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Gráfica de progresión

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chartTitle).font(.headline)
            Chart(entries) { e in
                AreaMark(x: .value("Fecha", e.date, unit: .day),
                         y: .value("Valor", metricValue(e)))
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Fecha", e.date, unit: .day),
                         y: .value("Valor", metricValue(e)))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Fecha", e.date, unit: .day),
                          y: .value("Valor", metricValue(e)))
                    .foregroundStyle(accent)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                        .foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.caption2).foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 180)

            if let first = entries.first, let last = entries.last, entries.count >= 2 {
                let total = metricValue(last) - metricValue(first)
                HStack(spacing: 6) {
                    Image(systemName: total >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                    Text("\(total >= 0 ? "+" : "")\(metricLabel(total)) desde el inicio")
                        .font(.caption)
                }
                .foregroundStyle(total >= 0 ? .green : .orange)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Historial

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Historial").font(.headline)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            ForEach(entries.reversed()) { e in
                Button { startEditing(e) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                            if let sub = entrySubtitle(e) {
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(metricLabel(metricValue(e)))
                            .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if e.id != entries.first?.id { Divider().padding(.leading, 16) }
            }
            .padding(.bottom, 6)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34)).foregroundStyle(accent.opacity(0.6))
            Text("Sin registros todavía").font(.headline)
            Text("Pulsa + para apuntar el peso, las reps o los segundos de esta semana y ver tu progresión.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                prefillFromLast(); showAdd = true
            } label: {
                Label("Registrar", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(accent, in: Capsule()).foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: - Sheet de alta

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                        Text("kg").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Peso (opcional — vacío = peso corporal)")
                }
                Section("Repeticiones (opcional)") {
                    TextField("ej. 8", text: $repsText)
                        .keyboardType(.numberPad)
                }
                Section("Segundos (opcional — plancha, isometrías)") {
                    TextField("ej. 60", text: $secondsText)
                        .keyboardType(.numberPad)
                }
                Section {
                    DatePicker("Fecha", selection: $entryDate, displayedComponents: .date)
                }
                if let editing = editingEntry {
                    Section {
                        Button(role: .destructive) {
                            store.remove(editing, for: exercise.id)
                            showAdd = false; editingEntry = nil
                        } label: {
                            Label("Borrar este registro", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(editingEntry == nil ? "Registrar" : "Editar registro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showAdd = false; editingEntry = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { saveEntry() }
                        .fontWeight(.semibold)
                        .disabled(!hasAnyInput)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Lógica

    private var parsedWeight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: "."))
    }
    private var parsedSeconds: Int? { Int(secondsText) }
    // Se puede guardar si hay al menos un dato (peso, reps o segundos)
    private var hasAnyInput: Bool {
        (parsedWeight ?? 0) > 0 || Int(repsText) != nil || parsedSeconds != nil
    }

    private func prefillFromLast() {
        if let last = store.latest(for: exercise.id) {
            weightText = last.weight > 0 ? formatNumber(last.weight) : ""
            repsText = last.reps.map(String.init) ?? ""
            secondsText = last.seconds.map(String.init) ?? ""
        } else {
            weightText = ""; repsText = ""; secondsText = ""
        }
        entryDate = Date()
    }

    private func startEditing(_ e: LiftEntry) {
        editingEntry = e
        weightText = e.weight > 0 ? formatNumber(e.weight) : ""
        repsText = e.reps.map(String.init) ?? ""
        secondsText = e.seconds.map(String.init) ?? ""
        entryDate = e.date
        showAdd = true
    }

    private func saveEntry() {
        guard hasAnyInput else { return }
        let w = parsedWeight ?? 0
        if var updated = editingEntry {
            updated.weight = w
            updated.reps = Int(repsText)
            updated.seconds = parsedSeconds
            updated.date = entryDate
            store.update(updated, for: exercise.id)
        } else {
            store.add(weight: w, reps: Int(repsText), seconds: parsedSeconds, date: entryDate, for: exercise.id)
        }
        showAdd = false
        editingEntry = nil
    }

    @ViewBuilder private func deltaLabel(_ d: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: d > 0 ? "arrow.up" : "arrow.down").font(.system(size: 9, weight: .bold))
            Text("\(d > 0 ? "+" : "")\(formatNumber(d)) kg").font(.caption2).fontWeight(.medium)
        }
        .foregroundStyle(d > 0 ? .green : .orange)
    }

    // Info secundaria de cada registro del historial según el modo
    private func entrySubtitle(_ e: LiftEntry) -> String? {
        switch trackMode {
        case .weight:
            guard let reps = e.reps else { return nil }
            return "\(reps) reps\(e.oneRepMax.map { " · 1RM ~\(formatKg($0))" } ?? "")"
        case .time, .reps:
            return e.weight > 0 ? "+\(formatKg(e.weight)) lastre" : nil
        }
    }

    private func formatKg(_ w: Double) -> String { "\(formatNumber(w)) kg" }
    private func formatNumber(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w))" : String(format: "%.1f", w)
    }

    // MARK: - Análisis IA de la progresión

    private func analyzeProgress() async throws -> String {
        let ex = live
        var lines: [String] = [
            "Ejercicio: \(ex.name)\(ex.muscleGroup.isEmpty ? "" : " (\(ex.muscleGroup))")",
            "Prescripción de la rutina: \(ex.sets) series × \(ex.reps)\(ex.weight.isEmpty ? "" : ", objetivo \(ex.weight)")",
            "Registros (fecha · peso · reps), de más antiguo a reciente:"
        ]
        let df = DateFormatter(); df.dateFormat = "d MMM"
        for e in entries {
            var parts: [String] = []
            if e.weight > 0 { parts.append(formatKg(e.weight)) }
            if let r = e.reps { parts.append("\(r) reps") }
            if let s = e.seconds { parts.append("\(s) s") }
            if let orm = e.oneRepMax { parts.append("1RM est. ~\(formatKg(orm))") }
            let desc = parts.isEmpty ? "—" : parts.joined(separator: " · ")
            lines.append("  \(df.string(from: e.date)) · \(desc)")
        }
        let system = "Eres un entrenador de fuerza. Analizas la progresión de un ejercicio frente a su prescripción. LEE EL NOMBRE del ejercicio para entender qué es y cómo progresa (no es lo mismo un femoral sentado que tumbado, ni una plancha que un press). Los ejercicios pueden medirse por PESO (con carga), por SEGUNDOS (isometrías como plancha: más tiempo = progreso) o por REPS a peso corporal (elevaciones, dominadas: más reps = progreso). Responde en español, TEXTO PLANO (sin markdown ni listas), 2-3 frases: ¿progresa, se estanca o conviene descargar? Con peso y reps variables, valora la FUERZA REAL por el 1RM estimado (Epley), no solo el peso (80×10 puede ser más fuerte que 85×5). Ten en cuenta la sobrecarga progresiva y que 2-3 sesiones estancadas piden un cambio. Usa solo las cifras dadas; nunca inventes valores. TERMINA SIEMPRE con una línea aparte que empiece por 'Conclusión: ' y resuma en una frase el SIGUIENTE paso concreto (subir peso/reps/segundos, mantener o descargar) acorde al TIPO de ejercicio."
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }
}
