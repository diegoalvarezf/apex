import SwiftUI

struct ProfileSheet: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var profileManager: UserProfileManager
    @Environment(\.dismiss) var dismiss

    @State private var customMaxHRText: String = ""
    @State private var showMaxHRReset = false

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
                            if let city = stravaAuth.athlete?.city,
                               let country = stravaAuth.athlete?.country {
                                Text("\(city), \(country)")
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
                }

                // ── Strava ───────────────────────────────────────────────────
                if stravaAuth.isAuthenticated {
                    Section {
                        Button(role: .destructive) {
                            stravaAuth.signOut()
                            dismiss()
                        } label: {
                            Label("Desconectar Strava", systemImage: "link.slash")
                        }
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
