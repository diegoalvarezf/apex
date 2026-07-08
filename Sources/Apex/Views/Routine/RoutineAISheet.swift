import SwiftUI

struct RoutineAISheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var mode: Mode = .maquetar

    enum Mode: String, CaseIterable, Identifiable {
        case maquetar = "Maquetar"
        case crear = "Crear con IA"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8).padding(.bottom, 4)

                if mode == .maquetar {
                    MaquetarSection(onDone: { dismiss() })
                } else {
                    CrearSection(onDone: { dismiss() })
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nueva rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Sección 1: Maquetar (pegar texto → la IA lo estructura)

private struct MaquetarSection: View {
    @EnvironmentObject var routineVM: RoutineViewModel
    let onDone: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private let placeholder = "Ej: Día A pecho y tríceps: press banca 4x8-10, aperturas con mancuernas 3x12, press inclinado 3x10, fondos 3x al fallo, press francés 4x10. Día B espalda y bíceps: dominadas 4x6-8, remo con barra 4x8, jalón al pecho 3x12, curl barra 3x10..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Maquetar rutina", systemImage: "text.badge.checkmark")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.purple)
                    Text("¿Ya tienes una rutina?")
                        .font(.title3).fontWeight(.bold)
                    Text("Pega tu rutina con días, ejercicios, series y repeticiones. La IA la estructura y la guarda para consultarla en el gym.")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.body).foregroundColor(Color(.placeholderText))
                            .padding(14).allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.body).scrollContentBackground(.hidden).padding(10)
                        .focused($focused)
                }
                .frame(minHeight: 200)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Plantillas de ejemplo").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                    ForEach(templates, id: \.name) { t in
                        Button { text = t.description } label: {
                            HStack {
                                Image(systemName: t.icon).foregroundColor(.purple).frame(width: 20)
                                Text(t.name).font(.subheadline)
                                Spacer()
                                Image(systemName: "arrow.up.left").font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .foregroundColor(.primary)
                    }
                }

                if let err = routineVM.aiError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.red)
                        .padding(12).background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    focused = false
                    Task {
                        await routineVM.parseRoutineWithAI(description: text)
                        if routineVM.aiError == nil { onDone() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if routineVM.isParsingAI { ProgressView().tint(.white) }
                        else { Image(systemName: "sparkles") }
                        Text(routineVM.isParsingAI ? "Estructurando rutina..." : "Estructurar rutina").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.purple)
                    .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routineVM.isParsingAI)
            }
            .padding()
        }
    }

    private struct Template { let name: String; let icon: String; let description: String }
    private let templates: [Template] = [
        Template(name: "Push / Pull / Legs", icon: "arrow.triangle.2.circlepath",
                 description: "Día A Push – Pecho, Hombros, Tríceps: press banca 4x8-10, press inclinado 3x10, aperturas 3x12, press militar 4x8-10, elevaciones laterales 3x15, fondos 3x al fallo, press francés 3x10.\nDía B Pull – Espalda, Bíceps: dominadas 4x6-8, remo con barra 4x8, jalón al pecho 3x12, remo en polea 3x12, curl barra 4x10, curl martillo 3x12.\nDía C Piernas: sentadilla 4x8-10, prensa 4x10-12, extensión de cuádriceps 3x12, curl femoral 3x12, peso muerto rumano 4x10, elevación de gemelos 4x15."),
        Template(name: "Torso / Pierna", icon: "figure.strengthtraining.traditional",
                 description: "Día A Torso: press banca 4x8, remo con barra 4x8, press militar 3x10, jalón al pecho 3x10, fondos 3x al fallo, curl barra 3x10, press francés 3x10.\nDía B Pierna: sentadilla 4x8-10, peso muerto 4x6-8, prensa 3x12, curl femoral 3x12, zancadas 3x10 por pierna, elevación de gemelos 4x15."),
        Template(name: "Full Body 3 días", icon: "calendar.badge.checkmark",
                 description: "Lunes Full Body A: sentadilla 4x8, press banca 4x8, remo con mancuerna 3x10 por lado, press militar 3x10, curl bíceps 3x12, extensión tríceps 3x12.\nMiércoles Full Body B: peso muerto 4x6, dominadas 3x6-8, press inclinado 3x10, zancadas 3x10, elevaciones laterales 3x15, plancha 3x45s.\nViernes Full Body C: prensa 4x10, remo en polea 4x10, aperturas 3x12, sentadilla búlgara 3x10, curl martillo 3x12, fondos 3x10."),
    ]
}

// MARK: - Sección 2: Crear con IA (cuestionario + contexto de salud/historial)

private struct CrearSection: View {
    @EnvironmentObject var routineVM: RoutineViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var dashVM: DashboardViewModel
    let onDone: () -> Void

    enum Goal: String, CaseIterable, Identifiable { case hipertrofia = "Hipertrofia", fuerza = "Fuerza", perdida = "Pérdida de grasa", resistencia = "Resistencia", salud = "Salud general"; var id: String { rawValue } }
    enum Level: String, CaseIterable, Identifiable { case principiante = "Principiante", intermedio = "Intermedio", avanzado = "Avanzado"; var id: String { rawValue } }
    enum Equip: String, CaseIterable, Identifiable { case gym = "Gimnasio completo", barraMancuernas = "Barra y mancuernas", mancuernas = "Solo mancuernas", peso = "Peso corporal", casa = "Casa básico"; var id: String { rawValue } }

    @State private var goal: Goal = .hipertrofia
    @State private var level: Level = .intermedio
    @State private var days = 4
    @State private var minutes = 60
    @State private var equip: Equip = .gym
    @State private var focusGroups: Set<String> = []
    @State private var injuries = ""
    @State private var notes = ""
    @State private var useContext = true

    private let muscleOptions = ["Pecho", "Espalda", "Hombros", "Brazos", "Piernas", "Glúteos", "Core"]

    var body: some View {
        Form {
            Section {
                Text("Responde unas preguntas y la IA (Opus) diseña una rutina desde cero basándose en principios de entrenamiento y, si quieres, en tus métricas de salud y los pesos que ya registras.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Objetivo y nivel") {
                Picker("Objetivo", selection: $goal) { ForEach(Goal.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Nivel", selection: $level) { ForEach(Level.allCases) { Text($0.rawValue).tag($0) } }
            }

            Section("Estructura") {
                Stepper("Días por semana: \(days)", value: $days, in: 2...6)
                Picker("Duración por sesión", selection: $minutes) {
                    ForEach([45, 60, 75, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Material disponible", selection: $equip) { ForEach(Equip.allCases) { Text($0.rawValue).tag($0) } }
            }

            Section("Grupos a priorizar (opcional)") {
                ForEach(muscleOptions, id: \.self) { m in
                    Button {
                        if focusGroups.contains(m) { focusGroups.remove(m) } else { focusGroups.insert(m) }
                    } label: {
                        HStack {
                            Text(m).foregroundStyle(.primary)
                            Spacer()
                            if focusGroups.contains(m) { Image(systemName: "checkmark").foregroundStyle(.purple) }
                        }
                    }
                }
            }

            Section("Limitaciones y preferencias (opcional)") {
                TextField("Lesiones o limitaciones (ej. hombro, rodilla)", text: $injuries, axis: .vertical).lineLimit(1...3)
                TextField("Otras preferencias (ejercicios favoritos, a evitar…)", text: $notes, axis: .vertical).lineLimit(1...3)
            }

            Section {
                Toggle("Usar mis métricas e historial", isOn: $useContext)
            } footer: {
                Text("Incluye recuperación, carga de entrenamiento, VO₂max, sueño y los pesos que ya has registrado, para ajustar volumen y progresión.")
            }

            if let err = routineVM.aiError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.red)
                }
            }

            Section {
                Button {
                    Task {
                        await routineVM.createRoutineWithAI(brief: buildBrief(),
                                                            context: useContext ? buildContext() : "No proporcionado.")
                        if routineVM.aiError == nil { onDone() }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if routineVM.isParsingAI { ProgressView().tint(.white) }
                        else { Image(systemName: "sparkles") }
                        Text(routineVM.isParsingAI ? "Diseñando tu rutina..." : "Crear rutina con IA").fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(routineVM.isParsingAI ? Color.secondary : Color.purple)
                .foregroundStyle(.white)
                .disabled(routineVM.isParsingAI)
            }
        }
    }

    // MARK: - Construcción de prompts

    private func buildBrief() -> String {
        var parts: [String] = [
            "Objetivo: \(goal.rawValue)",
            "Nivel: \(level.rawValue)",
            "Días por semana: \(days)",
            "Duración por sesión: \(minutes) min",
            "Material: \(equip.rawValue)",
        ]
        if !focusGroups.isEmpty { parts.append("Grupos a priorizar: \(focusGroups.sorted().joined(separator: ", "))") }
        if !injuries.trimmingCharacters(in: .whitespaces).isEmpty { parts.append("Lesiones/limitaciones: \(injuries)") }
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty { parts.append("Preferencias: \(notes)") }
        return parts.joined(separator: "\n")
    }

    private func buildContext() -> String {
        var lines: [String] = []

        if let r = healthKit.recoveryScore { lines.append("Recuperación hoy: \(r.value)/100 (\(r.label))") }
        if let hrv = healthKit.hrvHistory.first?.sdnn { lines.append("HRV (SDNN): \(Int(hrv)) ms") }
        if let rhr = healthKit.todaySummary?.restingHR { lines.append("FC en reposo: \(Int(rhr)) bpm") }
        if let vo2 = healthKit.vo2MaxData?.current { lines.append(String(format: "VO₂max: %.1f ml/kg/min", vo2)) }
        if let sleep = healthKit.sleepHistory.first {
            lines.append(String(format: "Sueño reciente: %.1f h (score %d/100)", sleep.totalSleep / 3600, sleep.score))
        }
        if let load = dashVM.trainingLoad {
            lines.append(String(format: "Carga: ATL %.0f · CTL %.0f · ACWR %.2f (%@)",
                                load.atl, load.ctl, load.acwr, load.formStatus.rawValue))
        }

        // Volumen de actividad últimos 28 días
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recent = dashVM.activities.filter { $0.startDate >= cutoff }
        if !recent.isEmpty {
            let hours = recent.reduce(0.0) { $0 + Double($1.movingTime) } / 3600.0
            lines.append(String(format: "Actividad últimas 4 semanas: %d sesiones, %.1f h totales", recent.count, hours))
        }

        // Pesos ya registrados por ejercicio (de las rutinas guardadas)
        var lifts: [String] = []
        for routine in routineVM.routines {
            for day in routine.days {
                for ex in day.exercises {
                    if let latest = RoutineProgressStore.shared.latest(for: ex.id) {
                        let w = latest.weight == latest.weight.rounded() ? "\(Int(latest.weight))" : String(format: "%.1f", latest.weight)
                        lifts.append("\(ex.name): \(w) kg")
                    }
                }
            }
        }
        if !lifts.isEmpty {
            lines.append("Pesos recientes registrados — " + Array(Set(lifts)).sorted().prefix(25).joined(separator: "; "))
        }

        // Rutinas actuales (nombres) para no duplicar
        if !routineVM.routines.isEmpty {
            lines.append("Rutinas ya guardadas: " + routineVM.routines.map(\.name).joined(separator: ", "))
        }

        return lines.isEmpty ? "Sin datos de salud disponibles todavía." : lines.joined(separator: "\n")
    }
}
