import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    @EnvironmentObject var healthKit: HealthKitManager
    @State private var step = 0

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            switch step {
            case 0:  WelcomeStep  { withAnimation(.spring()) { step = 1 } }
            case 1:  HealthStep   { withAnimation(.spring()) { step = 2 } }
            default: StravaStep()
            }
        }
        .animation(.easeInOut, value: step)
    }
}

// MARK: - Paso 1: Bienvenida

private struct WelcomeStep: View {
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 100, height: 100)
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 48)).foregroundStyle(Color.accentColor)
                }
                VStack(spacing: 8) {
                    Text("Apex").font(.system(size: 38, weight: .bold))
                    Text("Entrena con inteligencia").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 0) {
                FeatureRow(icon: "waveform.path.ecg", color: .green,  title: "Recuperación real", desc: "HRV, FC en reposo y sueño con algoritmos de PeakWatch")
                Divider().padding(.leading, 64)
                FeatureRow(icon: "bolt.fill",         color: .orange, title: "Carga TRIMP",        desc: "ATL/CTL con media exponencial, como TrainingPeaks")
                Divider().padding(.leading, 64)
                FeatureRow(icon: "sparkles",          color: .purple, title: "Coach de IA",        desc: "Claude analiza tus datos y te da recomendaciones")
                Divider().padding(.leading, 64)
                FeatureRow(icon: "map.fill",          color: .blue,   title: "Rutas GPS",          desc: "Registra actividades con mapa en tiempo real")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            Spacer()
            Button(action: onContinue) {
                Text("Empezar").font(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal).padding(.bottom, 48)
        }
    }
}

// MARK: - Paso 2: HealthKit

private struct HealthStep: View {
    @EnvironmentObject var healthKit: HealthKitManager
    let onContinue: () -> Void
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.1)).frame(width: 100, height: 100)
                    Image(systemName: "heart.text.square.fill").font(.system(size: 48)).foregroundStyle(.red)
                }
                VStack(spacing: 8) {
                    Text("Apple Health").font(.title2).fontWeight(.bold)
                    Text("Apex necesita acceso a tus datos de salud para calcular recuperación, sueño y carga de entrenamiento.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }
            Spacer()
            VStack(spacing: 0) {
                PermRow(icon: "moon.fill",          color: .indigo, label: "Sueño y fases")
                Divider().padding(.leading, 56)
                PermRow(icon: "waveform.path.ecg",  color: .green,  label: "HRV (variabilidad FC)")
                Divider().padding(.leading, 56)
                PermRow(icon: "heart.fill",         color: .red,    label: "FC en reposo")
                Divider().padding(.leading, 56)
                PermRow(icon: "lungs.fill",         color: .cyan,   label: "VO2Max y FR")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    requesting = true
                    Task {
                        _ = await healthKit.requestAuthorization()
                        requesting = false
                        onContinue()
                    }
                } label: {
                    Group {
                        if requesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Permitir acceso a Salud")
                        }
                    }
                    .font(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button("Ahora no") { onContinue() }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.bottom, 48)
        }
    }
}

// MARK: - Paso 3: Strava

private struct StravaStep: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.12)).frame(width: 100, height: 100)
                    Image(systemName: "figure.run.circle.fill").font(.system(size: 48)).foregroundStyle(.orange)
                }
                VStack(spacing: 8) {
                    Text("Conecta Strava").font(.title2).fontWeight(.bold)
                    Text("Apex importa tus actividades de Strava para calcular TRIMP, carga y esfuerzo cardiovascular.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }
            Spacer()
            VStack(spacing: 0) {
                PermRow(icon: "bolt.fill",           color: .orange, label: "Actividades y esfuerzo TRIMP")
                Divider().padding(.leading, 56)
                PermRow(icon: "heart.fill",          color: .red,    label: "Frecuencia cardíaca por actividad")
                Divider().padding(.leading, 56)
                PermRow(icon: "map.fill",            color: .blue,   label: "Rutas GPS y polilíneas")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            Spacer()
            VStack(spacing: 8) {
                Button(action: stravaAuth.authorize) {
                    Label("Conectar con Strava", systemImage: "link")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("Al continuar aceptas los Términos de Uso y la Política de Privacidad.")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal).padding(.bottom, 48)
        }
    }
}

// MARK: - Subcomponentes

private struct FeatureRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color)
            }
            .padding(.leading, 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            Spacer()
        }
    }
}

private struct PermRow: View {
    let icon: String; let color: Color; let label: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.caption).foregroundStyle(color)
            }
            .padding(.leading, 16)
            Text(label).font(.subheadline).padding(.vertical, 14)
            Spacer()
            Image(systemName: "checkmark").font(.caption).foregroundStyle(color).padding(.trailing, 16)
        }
    }
}
