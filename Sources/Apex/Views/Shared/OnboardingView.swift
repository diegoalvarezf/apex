import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                VStack(spacing: 6) {
                    Text("Apex")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Entrena con inteligencia")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(spacing: 0) {
                FeatureRow(
                    icon: "figure.run",
                    title: "Actividades Strava",
                    description: "Análisis detallado de rendimiento y carga de entrenamiento"
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    icon: "moon.fill",
                    title: "Sueño y recuperación",
                    description: "Fases de sueño, HRV y puntuación de recuperación diaria"
                )
                Divider().padding(.leading, 56)
                FeatureRow(
                    icon: "sparkles",
                    title: "Coach de IA",
                    description: "Recomendaciones personalizadas basadas en todos tus datos"
                )
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: stravaAuth.authorize) {
                    Text("Conectar con Strava")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("Al continuar aceptas los Términos de Uso y la Política de Privacidad.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 14)

            Spacer()
        }
    }
}
