import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var stravaAuth: StravaAuthManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    Image(systemName: "bolt.heart.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    VStack(spacing: 8) {
                        Text("Apex")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(.white)

                        Text("Entrena con inteligencia")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Spacer()

                VStack(spacing: 16) {
                    FeatureRow(icon: "figure.run", color: .orange, title: "Actividades Strava", desc: "Análisis completo de tu rendimiento")
                    FeatureRow(icon: "moon.stars.fill", color: .purple, title: "Sueño y recuperación", desc: "HRV, fases de sueño y body battery")
                    FeatureRow(icon: "sparkles", color: .blue, title: "IA Coach personal", desc: "Recomendaciones basadas en tus datos")
                }
                .padding(.horizontal, 32)

                Spacer()

                Button(action: stravaAuth.authorize) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                        Text("Conectar con Strava")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
    }
}
