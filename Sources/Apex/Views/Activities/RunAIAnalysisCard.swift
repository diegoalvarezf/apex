import SwiftUI

// Análisis IA de una sesión de resistencia (carrera o ciclismo): baja los streams
// de FC/ritmo/potencia de Strava y deja que Claude interprete la curva real
// (estructura de intervalos, control del esfuerzo, deriva/fade…). Bajo demanda y
// cacheado por actividad para no repetir la llamada.
struct ActivityAIAnalysisCard: View {
    let activity: StravaActivity
    @EnvironmentObject var stravaAuth: StravaAuthManager

    @State private var analysis: String?
    @State private var isLoading = false
    @State private var error: String?

    private var cacheKey: String { "apex_run_ai_\(activity.id)" }

    private var isRide: Bool {
        ["ride", "virtualride", "ebikeride", "mountainbikeride", "gravelride"].contains(activity.sportType.lowercased())
    }
    private var title: String { isRide ? "Análisis de la salida" : "Análisis de la carrera" }
    private var subtitle: String {
        isRide
            ? "Claude analiza la potencia y la FC tramo a tramo: detecta bloques/intervalos, cómo dosificaste y dónde flojeaste."
            : "Claude analiza el ritmo y la FC tramo a tramo: detecta si fueron series, cómo controlaste el esfuerzo y dónde flojeaste."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(title).font(.headline)
                Spacer()
                if analysis != nil && !isLoading {
                    Button { Task { await analyze() } } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                }
            }

            if let analysis {
                AIAnalysisBody(text: analysis)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Leyendo tu curva de esfuerzo…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear {
            analysis = UserDefaults.standard.string(forKey: cacheKey)
            // Automático: si no hay análisis cacheado, lánzalo al abrir la actividad
            if analysis == nil { Task { await analyze() } }
        }
    }

    // MARK: - Lógica

    private func analyze() async {
        guard let token = stravaAuth.accessToken else { error = "Reconecta con Strava."; return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let streams = try await StravaAPI.shared.fetchStreams(id: activity.id, token: token)
            let prompt = buildPrompt(streams: streams)
            let text = try await AIService.shared.analyze(.run, input: prompt)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { error = "La IA no devolvió análisis."; return }
            analysis = clean
            UserDefaults.standard.set(clean, forKey: cacheKey)
        } catch {
            self.error = "No pude analizar la sesión: \(error.localizedDescription)"
        }
    }

    private func buildPrompt(streams: ActivityStreams) -> String {
        var lines: [String] = [
            "\(isRide ? "Salida en bici" : "Carrera"): \(activity.name) · \(activity.formattedDistance) · \(activity.formattedDuration) · ritmo/vel media \(activity.formattedPace)"
        ]
        if let hr = activity.averageHeartrate { lines.append("FC media \(Int(hr))" + (activity.maxHeartrate.map { " · máx \(Int($0))" } ?? "")) }
        if let w = activity.averageWatts { lines.append("Potencia media \(Int(w))W") }
        if activity.isStructuredWorkout { lines.append("Marcada en Strava como sesión estructurada (intervalos/workout).") }

        let t = streams.time?.data ?? []
        let hr = streams.heartrate?.data
        let watts = streams.watts?.data
        let vel = streams.velocitySmooth?.data
        let n = t.count
        if n > 4 && (hr != nil || watts != nil || vel != nil) {
            // Columnas según lo disponible: bici prioriza potencia; carrera, ritmo
            let usePower = isRide && (watts?.count ?? 0) >= n
            let header = usePower ? "min · potencia W · FC" : "min · ritmo min/km · FC"
            lines.append("Curva por tramos (\(header)):")
            let step = max(1, n / 34)
            var i = 0
            while i < n {
                let minute = t[i] / 60.0
                let mid: String
                if usePower, let w = watts, i < w.count {
                    mid = "\(Int(w[i]))W"
                } else if let v = vel, i < v.count {
                    mid = v[i] > 0.4 ? formatPace(secPerKm: 1000.0 / v[i]) : "parado"
                } else {
                    mid = "-"
                }
                let hrStr = (hr.flatMap { i < $0.count ? "\(Int($0[i]))" : nil }) ?? "-"
                lines.append("  \(String(format: "%.0f", minute)) · \(mid) · \(hrStr)")
                i += step
            }
        } else {
            lines.append("(No hay streams; analiza con los promedios.)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatPace(secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
