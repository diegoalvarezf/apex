import SwiftUI

// Plan de Apex IA y activación de Pro.
//
// Pro se activa con un código y no con una compra dentro de la app: eso exige
// cuenta de desarrollador de pago, que no existe todavía. El código concede el
// mismo plan que concedería la suscripción, así que la funcionalidad es real —no
// una simulación— y el día que haya IAP solo cambia cómo se concede, no qué.
struct ApexProSheet: View {
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var cuotas: AllQuotas?
    @State private var codigo = ""
    @State private var canjeando = false
    @State private var error: String?
    @State private var exito = false
    @FocusState private var escribiendo: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    planActual
                } header: {
                    Text("Tu plan")
                }

                Section {
                    comparativa
                } header: {
                    Text("Qué incluye cada uno")
                }

                if cuotas?.isPro != true {
                    Section {
                        TextField("XXXX-XXXX-XXXX", text: $codigo)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .focused($escribiendo)

                        Button {
                            canjear()
                        } label: {
                            HStack {
                                Spacer()
                                if canjeando { ProgressView() } else { Text("Activar Pro").fontWeight(.semibold) }
                                Spacer()
                            }
                        }
                        .disabled(codigo.trimmingCharacters(in: .whitespaces).isEmpty || canjeando)
                    } header: {
                        Text("Tengo un código")
                    } footer: {
                        if let error {
                            Text(error).foregroundStyle(.red)
                        } else {
                            Text("Apex Pro todavía no se vende: se activa con un código de invitación.")
                        }
                    }
                }
            }
            .navigationTitle("Apex IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task { await cargar() }
            .overlay { if exito { activado } }
        }
    }

    // MARK: - Piezas

    @ViewBuilder private var planActual: some View {
        if let c = cuotas {
            HStack(spacing: 14) {
                Image(systemName: c.isPro ? "crown.fill" : "sparkles")
                    .font(.title2)
                    .foregroundStyle(c.isPro ? Color.orange : Color.purple)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.isPro ? "Apex Pro" : "Plan gratuito").font(.headline)
                    Text("\(c.standard.remaining) análisis hoy · \(c.routine.remaining) rutinas este mes")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack { ProgressView().controlSize(.small); Text("Consultando…").foregroundStyle(.secondary) }
        }
    }

    private var comparativa: some View {
        VStack(spacing: 10) {
            filaComparativa("Análisis al día", gratis: "20", pro: "100")
            Divider()
            filaComparativa("Rutinas al mes", gratis: "1", pro: "4")
            Divider()
            filaComparativa("Cambios de ejercicio", gratis: "5", pro: "30")
        }
        .padding(.vertical, 4)
    }

    private func filaComparativa(_ titulo: String, gratis: String, pro: String) -> some View {
        HStack {
            Text(titulo).font(.subheadline)
            Spacer()
            Text(gratis).font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(pro).font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var activado: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill").font(.system(size: 44)).foregroundStyle(.orange)
            Text("Apex Pro activado").font(.title3).fontWeight(.semibold)
            Text("Ya tienes las cuotas ampliadas.").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Acciones

    private func cargar() async {
        cuotas = try? await BackendClient.shared.quotas()
    }

    private func canjear() {
        escribiendo = false
        canjeando = true
        error = nil
        Task {
            defer { canjeando = false }
            do {
                _ = try await BackendClient.shared.redeemPro(code: codigo)
                await cargar()
                onChange()
                withAnimation { exito = true }
                // Se deja ver la confirmación un momento antes de cerrar: si la
                // hoja desapareciera al instante, no quedaría claro qué ha pasado.
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
