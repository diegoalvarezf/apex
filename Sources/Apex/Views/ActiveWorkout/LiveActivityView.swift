import SwiftUI
import MapKit

struct LiveActivityView: View {
    let sport: WorkoutSportType
    var preloadedSession: WorkoutLogSession? = nil

    @StateObject private var tracker = ActivityTracker()
    @StateObject private var logSession = WorkoutLogSession()
    @Environment(\.dismiss) var dismiss

    @State private var showStopConfirm = false
    @State private var showSaveResult  = false
    @State private var saveSuccess     = false
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if sport.isOutdoor {
                    liveMap
                } else if sport == .weightTraining {
                    WeightTrainingView(session: logSession, elapsedSeconds: tracker.elapsedSeconds)
                } else {
                    indoorHero
                }
                statsStrip
                controls.padding(.bottom, 36)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            tracker.requestLocation()
            tracker.start(sport: sport)
            if let preloaded = preloadedSession {
                for entry in preloaded.entries {
                    logSession.entries.append(entry)
                }
            }
        }
        .confirmationDialog(
            "¿Finalizar actividad?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Guardar en Apple Health") {
                Task {
                    saveSuccess = await tracker.finish()
                    // Guardar log de pesos si hay ejercicios registrados
                    if sport == .weightTraining && !logSession.entries.isEmpty {
                        let log = logSession.buildLog(duration: Double(tracker.elapsedSeconds))
                        await MainActor.run { WorkoutLogStore.shared.save(log) }
                    }
                    showSaveResult = true
                }
            }
            Button("Descartar", role: .destructive) {
                tracker.cancel()
                dismiss()
            }
            Button("Continuar", role: .cancel) {}
        } message: {
            let dist = sport.isOutdoor ? " · \(formatDistance(tracker.distanceMeters))" : ""
            Text("\(formatDuration(tracker.elapsedSeconds))\(dist)")
        }
        .alert(
            saveSuccess ? "Actividad guardada" : "Error al guardar",
            isPresented: $showSaveResult
        ) {
            Button("Aceptar") { dismiss() }
        } message: {
            Text(saveSuccess
                 ? "Guardado en Apple Health."
                 : "Revisa los permisos de Salud en Ajustes.")
        }
    }

    // MARK: - Mapa exterior

    private var liveMap: some View {
        Map(position: $mapPosition) {
            if tracker.coordinates.count > 1 {
                MapPolyline(coordinates: tracker.coordinates)
                    .stroke(sportColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { MapCompass(); MapScaleView() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero interior

    private var indoorHero: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(sport.emoji).font(.system(size: 64))
            Text(formatDuration(tracker.elapsedSeconds))
                .font(.system(size: 76, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(sport.label)
                .font(.title3).foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            StatBox(title: "TIEMPO", value: formatDuration(tracker.elapsedSeconds))
            if sport.isOutdoor {
                Divider().frame(height: 36).background(Color.white.opacity(0.15))
                StatBox(title: "DISTANCIA", value: formatDistance(tracker.distanceMeters))
                Divider().frame(height: 36).background(Color.white.opacity(0.15))
                StatBox(title: "RITMO", value: formatPace(tracker.currentPaceSecPerKm))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.systemGray6).opacity(0.12))
    }

    // MARK: - Controles

    private var controls: some View {
        HStack(spacing: 48) {
            // Parar
            Button { showStopConfirm = true } label: {
                Image(systemName: "stop.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.red.opacity(0.85), in: Circle())
            }

            // Pausa / Reanudar
            Button {
                if tracker.state == .active { tracker.pause() }
                else { tracker.resume() }
            } label: {
                Image(systemName: tracker.state == .active ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.black)
                    .frame(width: 72, height: 72)
                    .background(Color.white, in: Circle())
            }
            .animation(.spring(response: 0.25), value: tracker.state)
        }
        .padding(.top, 20)
    }

    // MARK: - Color por deporte

    private var sportColor: Color {
        switch sport {
        case .run, .trailRun: return .red
        case .ride:           return .orange
        case .walk:           return .teal
        case .hike:           return .green
        default:              return .blue
        }
    }

    // MARK: - Formato

    private func formatDuration(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    private func formatDistance(_ m: Double) -> String {
        m < 1000
            ? String(format: "%.0f m", m)
            : String(format: "%.2f km", m / 1000)
    }

    private func formatPace(_ secPerKm: Double) -> String {
        guard secPerKm > 0, secPerKm < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(secPerKm) / 60, Int(secPerKm) % 60)
    }
}

private struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(1)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}
