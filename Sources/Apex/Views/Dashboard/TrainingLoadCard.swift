import SwiftUI

struct TrainingLoadCard: View {
    let load: TrainingLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Carga de entrenamiento")
                    .font(.headline)
                Spacer()
                Label(load.formStatus.rawValue, systemImage: load.formStatus.systemImage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(load.formStatus.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            HStack(spacing: 0) {
                LoadPill(title: "ATL", subtitle: "7 días", value: load.atl, color: .orange)
                Divider().frame(height: 40)
                LoadPill(title: "CTL", subtitle: "42 días", value: load.ctl, color: .blue)
                Divider().frame(height: 40)
                LoadPill(
                    title: "ACWR",
                    subtitle: "Ratio",
                    value: load.acwr,
                    color: load.formStatus.color,
                    decimals: 2
                )
            }

            ACWRBar(acwr: load.acwr)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LoadPill: View {
    let title: String
    let subtitle: String
    let value: Double
    let color: Color
    var decimals: Int = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(decimals == 0
                 ? String(format: "%.0f", value)
                 : String(format: "%.2f", value))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Barra de 4 zonas igual que PeakWatch:
// Azul <0.8 | Verde 0.8–1.3 | Amarillo 1.3–1.5 | Rojo >1.5
private struct ACWRBar: View {
    let acwr: Double

    private let totalRange = 2.0  // eje de 0 a 2.0

    private let zones: [(color: Color, start: Double, end: Double, label: String)] = [
        (.blue,   0.0, 0.8, "Bajo"),
        (.green,  0.8, 1.3, "Óptimo"),
        (.yellow, 1.3, 1.5, "Elevado"),
        (.red,    1.5, 2.0, "Riesgo")
    ]

    var body: some View {
        GeometryReader { geo in
            let barH: CGFloat = 8
            let w = geo.size.width

            ZStack(alignment: .leading) {
                // Segmentos de color
                HStack(spacing: 1) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                        let segW = CGFloat((zone.end - zone.start) / totalRange) * w
                        Rectangle()
                            .fill(zone.color.opacity(0.75))
                            .frame(width: max(0, segW - 1), height: barH)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Marcador de posición actual
                let clampedACWR = min(max(acwr, 0), totalRange)
                let markerX = CGFloat(clampedACWR / totalRange) * w - 2
                Capsule()
                    .fill(Color.white)
                    .frame(width: 4, height: barH + 4)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: max(0, markerX))
            }

            // Etiquetas de zona
            HStack(spacing: 0) {
                ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                    let segW = CGFloat((zone.end - zone.start) / totalRange) * w
                    Text(zone.label)
                        .frame(width: segW)
                }
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .offset(y: barH + 4)
        }
        .frame(height: 30)
    }
}
