import SwiftUI

struct WeightEntrySheet: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @Environment(\.dismiss) var dismiss
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var isSaving = false

    var weightKg: Double? { Double(weightText.replacingOccurrences(of: ",", with: ".")) }
    var heightM: Double? {
        guard let h = Double(heightText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return h > 3 ? h / 100 : h  // acepta cm o metros
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Peso") {
                    HStack {
                        TextField("0.0", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("kg").foregroundColor(.secondary)
                    }
                }

                Section("Altura (opcional, para calcular IMC)") {
                    HStack {
                        TextField("175", text: $heightText)
                            .keyboardType(.decimalPad)
                        Text("cm").foregroundColor(.secondary)
                    }
                }

                if let w = weightKg, let h = heightM {
                    Section {
                        let bmi = BodyCompositionData.computeBMI(weightKg: w, heightM: h)
                        HStack {
                            Text("IMC calculado")
                            Spacer()
                            Text(String(format: "%.1f", bmi))
                                .fontWeight(.semibold)
                                .foregroundColor(bmiColor(bmi))
                        }
                    }
                }
            }
            .navigationTitle("Registrar peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let kg = weightKg else { return }
                        isSaving = true
                        Task {
                            await healthKit.writeWeight(kg, heightM: heightM)
                            dismiss()
                        }
                    }
                    .disabled(weightKg == nil || isSaving)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func bmiColor(_ b: Double) -> Color {
        switch b {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}
