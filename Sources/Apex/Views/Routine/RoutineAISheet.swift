import SwiftUI

struct RoutineAISheet: View {
    @EnvironmentObject var routineVM: RoutineViewModel
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private let placeholder = "Ej: Día A pecho y tríceps: press banca 4x8-10, aperturas con mancuernas 3x12, press inclinado 3x10, fondos 3x al fallo, press francés 4x10. Día B espalda y bíceps: dominadas 4x6-8, remo con barra 4x8, jalón al pecho 3x12, curl barra 3x10..."

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Cabecera
                    VStack(alignment: .leading, spacing: 6) {
                        Label("IA Coach", systemImage: "sparkles")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.purple)
                        Text("Describe tu rutina de gym")
                            .font(.title3).fontWeight(.bold)
                        Text("Escribe todos tus días con los ejercicios, series y repeticiones. La IA lo estructura y lo guarda para que lo consultes en el gym.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    // Editor
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.body).foregroundColor(Color(.placeholderText))
                                .padding(14).allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .focused($focused)
                    }
                    .frame(minHeight: 200)

                    // Plantillas rápidas
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plantillas de ejemplo").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                        VStack(spacing: 6) {
                            ForEach(templates, id: \.name) { t in
                                Button {
                                    text = t.description
                                } label: {
                                    HStack {
                                        Image(systemName: t.icon).foregroundColor(.purple).frame(width: 20)
                                        Text(t.name).font(.subheadline)
                                        Spacer()
                                        Image(systemName: "arrow.up.left").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .padding(12)
                                    .background(Color(.secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }

                    // Error
                    if let err = routineVM.aiError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                            .padding(12)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Botón
                    Button {
                        focused = false
                        Task {
                            await routineVM.parseRoutineWithAI(description: text)
                            if routineVM.aiError == nil { dismiss() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if routineVM.isParsingAI {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(routineVM.isParsingAI ? "Estructurando rutina..." : "Generar rutina")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.purple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || routineVM.isParsingAI)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nueva rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private struct Template {
        let name: String; let icon: String; let description: String
    }

    private let templates: [Template] = [
        Template(name: "Push / Pull / Legs", icon: "arrow.triangle.2.circlepath",
                 description: "Día A Push – Pecho, Hombros, Tríceps: press banca 4x8-10, press inclinado 3x10, aperturas 3x12, press militar 4x8-10, elevaciones laterales 3x15, fondos 3x al fallo, press francés 3x10.\nDía B Pull – Espalda, Bíceps: dominadas 4x6-8, remo con barra 4x8, jalón al pecho 3x12, remo en polea 3x12, curl barra 4x10, curl martillo 3x12.\nDía C Piernas: sentadilla 4x8-10, prensa 4x10-12, extensión de cuádriceps 3x12, curl femoral 3x12, peso muerto rumano 4x10, elevación de gemelos 4x15."),
        Template(name: "Torso / Pierna", icon: "figure.strengthtraining.traditional",
                 description: "Día A Torso: press banca 4x8, remo con barra 4x8, press militar 3x10, jalón al pecho 3x10, fondos 3x al fallo, curl barra 3x10, press francés 3x10.\nDía B Pierna: sentadilla 4x8-10, peso muerto 4x6-8, prensa 3x12, curl femoral 3x12, zancadas 3x10 por pierna, elevación de gemelos 4x15."),
        Template(name: "Full Body 3 días", icon: "calendar.badge.checkmark",
                 description: "Lunes Full Body A: sentadilla 4x8, press banca 4x8, remo con mancuerna 3x10 por lado, press militar 3x10, curl bíceps 3x12, extensión tríceps 3x12.\nMiércoles Full Body B: peso muerto 4x6, dominadas 3x6-8, press inclinado 3x10, zancadas 3x10, elevaciones laterales 3x15, plancha 3x45s.\nViernes Full Body C: prensa 4x10, remo en polea 4x10, aperturas 3x12, sentadilla búlgara 3x10, curl martillo 3x12, fondos 3x10."),
    ]
}
