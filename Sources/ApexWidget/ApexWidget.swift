import WidgetKit
import SwiftUI

private let appGroup = "group.com.diegoalvarezfrancos.apex"

// MARK: - Entry

struct ApexEntry: TimelineEntry {
    let date: Date
    let battery: Int
    let recovery: Int
    let effort: Int
    let sleep: Int
    let recoveryLabel: String
    let updated: Date?

    var hasData: Bool { recovery > 0 || battery > 0 }

    static let placeholder = ApexEntry(
        date: Date(), battery: 78, recovery: 74,
        effort: 52, sleep: 81, recoveryLabel: "Buena", updated: nil
    )
}

// MARK: - Provider

struct ApexProvider: TimelineProvider {
    func placeholder(in context: Context) -> ApexEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ApexEntry) -> Void) {
        let entry = readEntry()
        completion(context.isPreview || !entry.hasData ? .placeholder : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ApexEntry>) -> Void) {
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> ApexEntry {
        let d = UserDefaults(suiteName: appGroup)
        return ApexEntry(
            date: Date(),
            battery:       d?.integer(forKey: "widget_battery")  ?? 0,
            recovery:      d?.integer(forKey: "widget_recovery") ?? 0,
            effort:        d?.integer(forKey: "widget_effort")   ?? 0,
            sleep:         d?.integer(forKey: "widget_sleep")    ?? 0,
            recoveryLabel: d?.string(forKey: "widget_label")     ?? "--",
            updated:       d?.object(forKey: "widget_updated") as? Date
        )
    }
}

// MARK: - Metric bar row

private struct MetricBar: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color
    // Mientras la app no haya escrito nada, un 0 no significa "cero": significa
    // que no se sabe. Se muestra "--", como en el dashboard.
    var hasData: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                Spacer()
                Text(hasData ? "\(value)" : "--")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(hasData ? color : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.18))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(value, 100)) / 100.0, height: 5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Medium 4-bar widget

struct QuadMediumView: View {
    let entry: ApexEntry

    private var recoveryColor: Color {
        entry.recovery >= 80 ? .green : entry.recovery >= 60 ? .cyan : entry.recovery >= 40 ? .yellow : .red
    }
    private var batteryColor: Color {
        entry.battery >= 80 ? .green : entry.battery >= 60 ? .cyan : entry.battery >= 40 ? .yellow : .red
    }
    private var effortColor: Color {
        entry.effort < 40 ? .blue : entry.effort < 70 ? .orange : .red
    }
    private var sleepColor: Color {
        entry.sleep >= 80 ? .indigo : entry.sleep >= 60 ? .purple : entry.sleep >= 40 ? .purple.opacity(0.7) : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cabecera
            HStack {
                Text("APEX")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.primary)
                    .tracking(1.5)
                Spacer()
                if let updated = entry.updated {
                    Text(updated, style: .relative)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 8)

            // 4 barras
            VStack(spacing: 8) {
                MetricBar(icon: "bolt.heart.fill",       label: "Body Battery",  value: entry.battery, color: batteryColor, hasData: entry.hasData)
                MetricBar(icon: "arrow.up.heart.fill",   label: "Recuperación",  value: entry.recovery, color: recoveryColor, hasData: entry.hasData)
                MetricBar(icon: "bolt.fill",             label: "Esfuerzo",      value: entry.effort, color: effortColor, hasData: entry.hasData)
                MetricBar(icon: "moon.stars.fill",       label: "Sueño",         value: entry.sleep, color: sleepColor, hasData: entry.hasData)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            Color.black
        }
    }
}

// MARK: - Large 4-bar widget (barras más anchas y valores grandes)

struct QuadLargeView: View {
    let entry: ApexEntry

    private var recoveryColor: Color {
        entry.recovery >= 80 ? .green : entry.recovery >= 60 ? .cyan : entry.recovery >= 40 ? .yellow : .red
    }
    private var batteryColor: Color {
        entry.battery >= 80 ? .green : entry.battery >= 60 ? .cyan : entry.battery >= 40 ? .yellow : .red
    }
    private var effortColor: Color {
        entry.effort < 40 ? .blue : entry.effort < 70 ? .orange : .red
    }
    private var sleepColor: Color {
        entry.sleep >= 80 ? .indigo : entry.sleep >= 60 ? .purple : entry.sleep >= 40 ? .purple.opacity(0.7) : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("APEX")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.primary)
                    .tracking(2)
                Spacer()
                if let updated = entry.updated {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Actualizado")
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                        Text(updated, style: .relative)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }

            largebar(icon: "bolt.heart.fill",     label: "Body Battery", value: entry.battery,  color: batteryColor)
            largebar(icon: "arrow.up.heart.fill",  label: "Recuperación", value: entry.recovery, color: recoveryColor,
                     sublabel: entry.recoveryLabel)
            largebar(icon: "bolt.fill",            label: "Esfuerzo",     value: entry.effort,   color: effortColor)
            largebar(icon: "moon.stars.fill",       label: "Sueño",        value: entry.sleep,    color: sleepColor)
        }
        .padding(18)
        .containerBackground(for: .widget) {
            Color.black
        }
    }

    @ViewBuilder
    private func largebar(icon: String, label: String, value: Int, color: Color, sublabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                if let sub = sublabel {
                    Text("· \(sub)")
                        .font(.system(size: 10))
                        .foregroundStyle(color.opacity(0.7))
                }
                Spacer()
                Text(entry.hasData ? "\(value)" : "--")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.hasData ? color : .secondary)
                Text("/ 100")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .offset(y: -2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [color.opacity(0.7), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(value, 100)) / 100.0, height: 7)
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Widget definitions

struct ApexQuadMediumWidget: Widget {
    let kind = "ApexQuadMedium"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ApexProvider()) { entry in
            QuadMediumView(entry: entry)
        }
        .configurationDisplayName("Apex · Resumen")
        .description("Body Battery, Recuperación, Esfuerzo y Sueño.")
        .supportedFamilies([.systemMedium])
    }
}

struct ApexQuadLargeWidget: Widget {
    let kind = "ApexQuadLarge"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ApexProvider()) { entry in
            QuadLargeView(entry: entry)
        }
        .configurationDisplayName("Apex · Detalle")
        .description("Body Battery, Recuperación, Esfuerzo y Sueño con barras completas.")
        .supportedFamilies([.systemLarge])
    }
}

// Widget antiguo (small) para compatibilidad
struct ApexBodyBatteryWidget: Widget {
    let kind = "ApexBodyBattery"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ApexProvider()) { entry in
            SmallBatteryView(entry: entry)
        }
        .configurationDisplayName("Body Battery")
        .description("Tu nivel de energía actual.")
        .supportedFamilies([.systemSmall])
    }
}

private struct SmallBatteryView: View {
    let entry: ApexEntry
    private var color: Color {
        switch entry.battery {
        case 75...: return .green
        case 50..<75: return .cyan
        case 25..<50: return .yellow
        default: return .red
        }
    }
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(1, CGFloat(entry.battery) / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(entry.hasData ? "\(entry.battery)" : "--")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(entry.hasData ? color : .secondary)
                    Text("BODY BATTERY")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                }
            }
            .frame(width: 80, height: 80)
            Text(entry.recoveryLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color.black }
    }
}

@main
struct ApexWidgetBundle: WidgetBundle {
    var body: some Widget {
        ApexBodyBatteryWidget()
        ApexQuadMediumWidget()
        ApexQuadLargeWidget()
    }
}
