import SwiftUI

struct TrainingLoadCard: View {
    let load: TrainingLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Carga de entrenamiento")
                    .font(.headline)
                Spacer()
                Label(load.formStatus.rawValue, systemImage: formIcon)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(formColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(formColor.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 24) {
                LoadPill(
                    title: "ATL",
                    subtitle: "Última semana",
                    value: load.atl,
                    color: .red
                )
                LoadPill(
                    title: "CTL",
                    subtitle: "6 semanas",
                    value: load.ctl,
                    color: .blue
                )
                LoadPill(
                    title: "TSB",
                    subtitle: "Apex",
                    value: load.tsb,
                    color: load.tsb >= 0 ? .green : .orange
                )
            }

            LoadBar(atl: load.atl, ctl: load.ctl)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var formColor: Color {
        switch load.formStatus {
        case .fresh: return .blue
        case .optimal: return .green
        case .neutral: return .yellow
        case .tired: return .orange
        case .overreached: return .red
        }
    }

    private var formIcon: String {
        switch load.formStatus {
        case .fresh: return "arrow.up.circle.fill"
        case .optimal: return "checkmark.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .tired: return "exclamationmark.circle.fill"
        case .overreached: return "xmark.circle.fill"
        }
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(height: 8)

                let maxVal = max(atl, ctl, 100)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: geo.size.width * CGFloat(ctl / maxVal), height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red)
                    .frame(width: geo.size.width * CGFloat(atl / maxVal), height: 4)
                    .offset(y: 2)
            }
        }
        .frame(height: 8)
    }
}
