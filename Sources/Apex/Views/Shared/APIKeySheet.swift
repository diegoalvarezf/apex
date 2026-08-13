import SwiftUI

// Pantalla para que el usuario introduzca su propia clave de Anthropic.
//
// Cada uno usa la suya: la clave se guarda en el Keychain del dispositivo y el
// consumo va a su cuenta. La app no la envía a ningún sitio que no sea la propia
// API de Anthropic.
struct APIKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var isVerifying = false
    @State private var error: String?
    @State private var saved = APIKeyStore.hasKey

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if saved, let actual = APIKeyStore.key {
                        HStack {
                            Label(APIKeyStore.masked(actual), systemImage: "key.fill")
                                .font(.callout.monospaced())
                            Spacer()
                            Text("Activa").font(.caption).foregroundStyle(.green)
                        }
                    } else {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout.monospaced())
                    }
                } header: {
                    Text("Clave de Anthropic")
                } footer: {
                    Text("El coach de IA y los análisis usan la API de Anthropic. Necesitas tu propia clave: el consumo se factura a tu cuenta.\n\nSe guarda en el Keychain de este dispositivo y solo se envía a la API de Anthropic.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.red)
                    }
                }

                Section {
                    if saved {
                        Button(role: .destructive) {
                            APIKeyStore.delete()
                            saved = false
                            key = ""
                        } label: {
                            Label("Quitar la clave", systemImage: "trash")
                        }
                    } else {
                        Button {
                            Task { await verificarYGuardar() }
                        } label: {
                            HStack {
                                if isVerifying { ProgressView().padding(.trailing, 4) }
                                Text(isVerifying ? "Comprobando…" : "Comprobar y guardar")
                            }
                        }
                        .disabled(key.isEmpty || isVerifying)
                    }
                } footer: {
                    if !saved {
                        Text("Se hace una llamada mínima a la API para comprobar que la clave funciona antes de guardarla.")
                    }
                }

                Section {
                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                        Label("Crear una clave en console.anthropic.com", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("Sin clave, el resto de la app funciona igual: solo se desactivan los análisis y el coach de IA.")
                }
            }
            .navigationTitle("Apex IA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func verificarYGuardar() async {
        isVerifying = true
        error = nil
        defer { isVerifying = false }
        do {
            try await AIService.shared.verifyKey(key)
            guard APIKeyStore.save(key) else {
                error = "No se pudo guardar en el Keychain."
                return
            }
            saved = true
            key = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
