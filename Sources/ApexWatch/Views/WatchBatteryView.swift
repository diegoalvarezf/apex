import SwiftUI

struct WatchBatteryView: View {
    let data: WatchDashboardData

    // Sin datos, gris: el rojo del caso por defecto hacía leer "--" como si fuera
    // un valor crítico, cuando lo que pasa es que aún no ha llegado nada del iPhone.
    private var batteryColor: Color {
        guard data.hasData else { return .secondary }
        switch data.battery {
        case 75...: return .green
        case 50..<75: return .cyan
        case 25..<50: return .yellow
        default: return .red
        }
    }

    private var recoveryColor: Color {
        guard data.hasData else { return .secondary }
        switch data.recovery {
        case 80...: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(batteryColor.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(data.battery) / 100)
                        .stroke(batteryColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(data.hasData ? "\(data.battery)" : "--")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(batteryColor)
                        Text("BODY BATTERY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }
                }
                .frame(width: 100, height: 100)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recuperación")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(data.hasData ? "\(data.recovery)" : "--")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(recoveryColor)
                            Text("/ 100")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(data.recoveryLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(recoveryColor)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Apex")
    }
}
