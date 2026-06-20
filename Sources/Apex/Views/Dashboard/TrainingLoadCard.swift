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
                LoadPill(title: "ATL", subtitle: "Última semana", value: load.atl, color: .red)
                Divider().frame(height: 40)
                LoadPill(title: "CTL", subtitle: "6 semanas", value: load.ctl, color: .blue)
                Divider().frame(height: 40)
                LoadPill(
                    title: "TSB",
                    subtitle: "Forma",
                    value: load.tsb,
                    color: load.tsb >= 5 ? .green : load.tsb >= -10 ? .orange : .red
                )
            }

            LoadBar(atl: load.atl, ctl: load.ctl)
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

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.0f", value))
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

private struct LoadBar: View {
    let atl: Double
    let ctl: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 8)
                let maxVal = max(atl, ctl, 1)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.blue.opacity(0.4))
                    .frame(width: geo.size.width * CGFloat(min(ctl / maxVal, 1)), height: 8)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(min(atl / maxVal, 1)), height: 4)
                    .offset(y: 2)
            }
        }
        .frame(height: 8)
    }
}
