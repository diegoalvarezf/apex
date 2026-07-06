import SwiftUI

struct BiologicalAgeDetailView: View {
    let result: BiologicalAgeResult

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero
                VStack(spacing: 12) {
                    // Edad real vs biológica
                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text("\(result.chronologicalAge)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("Edad real").font(.caption).foregroundColor(.secondary)
                        }

                        // Flecha central
                        Image(systemName: result.delta < 0 ? "arrow.left" : "arrow.right")
                            .font(.title2).foregroundColor(result.deltaColor)

                        VStack(spacing: 4) {
                            Text(String(format: "%.1f", result.biologicalAge))
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundColor(result.deltaColor)
                            Text("Edad biológica").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // Badge
                    Text(result.deltaLabel.capitalized)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(result.deltaColor)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(result.deltaColor.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal)

                // Factores
                VStack(alignment: .leading, spacing: 0) {
                    Text("Factores analizados")
                        .font(.headline)
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

                    ForEach(result.factors) { factor in
                        FactorRow(factor: factor)
                        if factor.id != result.factors.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Qué es la edad biológica
                VStack(alignment: .leading, spacing: 8) {
                    Text("Qué es la edad biológica").font(.headline)
                    Text("La edad biológica mide cómo funciona tu cuerpo comparado con la media de tu grupo de edad. Una edad biológica menor a la real indica que tu cuerpo está en mejor forma que la media de personas de tu edad.\n\nSe calcula combinando marcadores fisiológicos clave: capacidad aeróbica (VO2Max), salud cardiovascular (FC y HRV), calidad del sueño y composición corporal.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                // Cómo mejorarla
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cómo reducir tu edad biológica").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        TipRow(icon: "figure.run", text: "Entrena en zona 2 (aeróbico suave) 3-4 días/semana — es el mayor impulsor del VO2Max")
                        TipRow(icon: "moon.fill", text: "Duerme 7-9h con horarios regulares para mejorar HRV y sueño profundo")
                        TipRow(icon: "scalemass", text: "Mantén un IMC entre 18.5-24.9 con dieta antiinflamatoria")
                        TipRow(icon: "heart.fill", text: "El descanso activo y la meditación reducen la FC en reposo")
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Edad biológica")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FactorRow: View {
    let factor: BiologicalAgeResult.BiologicalAgeFactor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(factor.color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: factor.icon).foregroundColor(factor.color).font(.system(size: 15))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(factor.name).font(.subheadline).fontWeight(.medium)
                    Text(factor.valueLabel).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                // Contribución en años
                VStack(alignment: .trailing, spacing: 1) {
                    let absD = abs(factor.ageDelta)
                    let sign = factor.ageDelta < -0.05 ? "" : factor.ageDelta > 0.05 ? "+" : "±"
                    Text(absD < 0.05 ? "±0 años" : "\(sign)\(String(format: "%.1f", factor.ageDelta)) años")
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                        .foregroundColor(factor.ageDelta <= 0 ? .green : .red)
                    Text(factor.ageDelta < -0.05 ? "más joven" : factor.ageDelta > 0.05 ? "más mayor" : "neutral")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            // Barra de contribución
            GeometryReader { geo in
                ZStack(alignment: factor.ageDelta <= 0 ? .trailing : .leading) {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 4)
                    let maxDelta = 8.0
                    let pct = min(abs(factor.ageDelta) / maxDelta, 1.0)
                    Rectangle()
                        .fill(factor.ageDelta <= 0 ? Color.green : Color.red)
                        .frame(width: geo.size.width * CGFloat(pct), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 52)
            .padding(.bottom, 8)
        }
    }
}

private struct TipRow: View {
    let icon: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.caption).foregroundColor(.accentColor)
                .frame(width: 16, height: 16)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
    }
}
