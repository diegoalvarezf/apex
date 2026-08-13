import SwiftUI

// MARK: - Shared components

struct HeroCard: View {
    let value: Int; let label: String; let icon: String; let color: Color; let subtitle: String
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 64, height: 64)
                Image(systemName: icon).font(.system(size: 26)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.subheadline).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(value)")
                        .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(color)
                    Text("/ 100").font(.subheadline).foregroundColor(.secondary).offset(y: -4)
                }
                Text(subtitle).font(.caption).foregroundColor(color).fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MetricProgressBlock: View {
    let title: String; let icon: String; let color: Color
    let todayValue: String; let baselineValue: String; let pct: Int
    let higherBetter: Bool
    let samples: [MetricSample]; let unit: String

    private var pctColor: Color {
        if higherBetter { return pct >= 100 ? .green : pct >= 80 ? .orange : .red }
        else { return pct >= 100 ? .green : pct >= 80 ? .orange : .red }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundColor(color)
                Spacer()
                Text(todayValue)
                    .font(.system(.title3, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            }

            // Barra de progreso con porcentaje
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.1)).frame(height: 10)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.gradient)
                            .frame(width: geo.size.width * CGFloat(min(pct, 100)) / 100.0, height: 10)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text(baselineValue).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(pct)% de tu baseline")
                        .font(.caption2).fontWeight(.medium).foregroundColor(pctColor)
                }
            }

            // Sparkline tendencia 30 días
            if samples.count >= 3 {
                TrendSparkline(samples: samples, color: color, height: 40)
                Text("Tendencia 30 días").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FactorBarRow: View {
    let label: String; let icon: String; let color: Color; let value: Int; let weight: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.caption).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label).font(.subheadline)
                    Text(weight).font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(color)
                            .frame(width: geo.size.width * CGFloat(value) / 100.0, height: 6)
                    }
                }.frame(height: 6)
            }
            Text("\(value)").font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                .foregroundColor(color).frame(width: 30, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}

// Clave de día para cachear los consejos IA (se regeneran al cambiar de día o de valor)
func aiDayKey(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}
