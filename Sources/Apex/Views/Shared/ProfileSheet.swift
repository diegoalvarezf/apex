import SwiftUI

struct ProfileSheet: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var profileManager: UserProfileManager
    @Environment(\.dismiss) var dismiss

    @State private var customMaxHRText: String = ""
    @State private var showMaxHRReset = false

    // Cuotas del servidor. Se enseñan aquí porque es donde el usuario mira qué
    // tiene contratado; antes esta fila decía si había puesto su clave, que ya no
    // existe.
    @State private var cuotas: AllQuotas?

    private var cuotaTexto: String {
        guard let c = cuotas else { return "Incluida" }
        if c.isPro { return "Pro · \(c.routine.remaining) rutinas este mes" }
        return "Gratis · \(c.standard.remaining) análisis hoy"
    }

    var body: some View {
        NavigationStack {
            List {

                // ── Cabecera atleta ─────────────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: stravaAuth.athlete?.profile ?? "")) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40)).foregroundColor(.secondary)
                        }
                        .frame(width: 60, height: 60).clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stravaAuth.athlete?.fullName ?? "Atleta")
                                .font(.headline)
                            // Strava devuelve cadenas vacías, no nil, cuando el atleta
                            // no rellena la ciudad: comprobar solo `!= nil` dejaba una
                            // coma suelta delante del país.
                            let ubicacion = [stravaAuth.athlete?.city, stravaAuth.athlete?.country]
                                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                                .joined(separator: ", ")
                            if !ubicacion.isEmpty {
                                Text(ubicacion)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // ── Perfil físico ────────────────────────────────────────────
                Section("Perfil físico") {
                    LabeledContent("Peso") {
                        Text(profileManager.weightKg > 0
                             ? String(format: "%.1f kg", profileManager.weightKg)
                             : "--")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Edad") {
                        Text(profileManager.age > 0 ? "\(profileManager.age) años" : "--")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("FC Máxima")
                        Spacer()
                        if profileManager.customMaxHR != nil {
                            TextField("Auto", text: $customMaxHRText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .foregroundStyle(.primary)
                                .onSubmit { applyCustomMaxHR() }
                            Text("bpm").foregroundStyle(.secondary).font(.subheadline)
                            Button { profileManager.saveCustomMaxHR(nil) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("\(profileManager.maxHR) bpm (auto)")
                                .foregroundStyle(.secondary)
                            Button("Editar") {
                                customMaxHRText = "\(profileManager.maxHR)"
                                profileManager.saveCustomMaxHR(profileManager.maxHR)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .onAppear {
                    if let hr = profileManager.customMaxHR {
                        customMaxHRText = "\(hr)"
                    }
                }

                // ── Apps conectadas ──────────────────────────────────────────
                Section("Apps conectadas") {
                    ConnectedAppRow(
                        icon: "figure.run.circle.fill",
                        iconColor: Color(red: 0.98, green: 0.35, blue: 0.1),
                        name: "Strava",
                        status: stravaAuth.isAuthenticated ? "Conectado" : "Desconectado",
                        connected: stravaAuth.isAuthenticated
                    )

                    ConnectedAppRow(
                        icon: "heart.fill",
                        iconColor: .pink,
                        name: "Apple Health",
                        status: "Conectado",
                        connected: true
                    )

                    ConnectedAppRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        name: "Apex IA",
                        status: cuotaTexto,
                        connected: true
                    )
                }

                // ── Strava ───────────────────────────────────────────────────
                Section {
                    Button {
                        stravaAuth.authorize()
                    } label: {
                        Label("Reconectar Strava", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if stravaAuth.isAuthenticated {
                        Button(role: .destructive) {
                            stravaAuth.signOut()
                            dismiss()
                        } label: {
                            Label("Desconectar Strava", systemImage: "link.slash")
                        }
                    }
                } footer: {
                    // El error se enseña aquí y no en una alerta: la reconexión
                    // vuelve de Safari, y una alerta al reaparecer se pierde con
                    // facilidad. Aquí queda a la vista junto al botón que falló.
                    if let error = stravaAuth.connectError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Si dejaste de ver tus actividades, reconecta para renovar el acceso a Strava.")
                    }
                }

                // ── Info app ─────────────────────────────────────────────────
                Section("Sobre la app") {
                    LabeledContent("Versión") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Build") {
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .task { cuotas = try? await BackendClient.shared.quotas() }
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func applyCustomMaxHR() {
        guard let val = Int(customMaxHRText), val > 100, val < 250 else { return }
        profileManager.saveCustomMaxHR(val)
    }
}

private struct ConnectedAppRow: View {
    let icon: String
    let iconColor: Color
    let name: String
    let status: String
    let connected: Bool

    // Cuotas del servidor. Se enseñan aquí porque es donde el usuario mira qué
    // tiene contratado; antes esta fila decía si había puesto su clave, que ya no
    // existe.
    @State private var cuotas: AllQuotas?

    private var cuotaTexto: String {
        guard let c = cuotas else { return "Incluida" }
        if c.isPro { return "Pro · \(c.routine.remaining) rutinas este mes" }
        return "Gratis · \(c.standard.remaining) análisis hoy"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2).foregroundColor(iconColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(connected ? .green : .secondary)
        }
        .padding(.vertical, 4)
    }
}
