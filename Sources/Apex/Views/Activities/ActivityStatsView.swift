import SwiftUI
import Charts

struct ActivityStatsView: View {
    let activities: [StravaActivity]

    private struct SportStat: Identifiable {
        let id: String
        let label: String
        let emoji: String
        let km: Double
        let hours: Double
        let elevation: Double
        var color: Color {
            switch id.lowercased() {
            case let s where s.contains("run"):    return .red
            case let s where s.contains("ride"):   return .orange
            case let s where s.contains("swim"):   return .blue
            case let s where s.contains("walk"):   return .teal
            case let s where s.contains("hike"):   return .green
            case let s where s.contains("weight"): return .purple
            case let s where s.contains("yoga"):   return .pink
            default: return .indigo
            }
        }
    }

    private struct MonthStat: Identifiable {
        let id: Date
        let hours: Double
    }

    private var sportStats: [SportStat] {
        Dictionary(grouping: activities) { $0.sportType }
            .map { key, acts in
                SportStat(
                    id: key,
                    label: acts.first?.sportLabel ?? key,
                    emoji: acts.first?.sportEmoji ?? "⚡",
                    km: acts.reduce(0) { $0 + $1.distance } / 1000,
                    hours: acts.reduce(0) { $0 + Double($1.movingTime) } / 3600,
                    elevation: acts.reduce(0) { $0 + $1.totalElevationGain }
                )
            }
            .sorted { $0.hours > $1.hours }
    }

    private var monthlyStats: [MonthStat] {
        let cal = Calendar.current
        var totals: [Date: Double] = [:]
        for act in activities {
            let comps = cal.dateComponents([.year, .month], from: act.startDate)
            if let m = cal.date(from: comps) { totals[m, default: 0] += Double(act.movingTime) / 3600 }
        }
        return totals.map { MonthStat(id: $0.key, hours: $0.value) }.sorted { $0.id < $1.id }.suffix(12).map { $0 }
    }

    private var totalKm: Double { activities.reduce(0) { $0 + $1.distance } / 1000 }
    private var totalHours: Double { activities.reduce(0) { $0 + Double($1.movingTime) } / 3600 }
    private var totalElevation: Double { activities.reduce(0) { $0 + $1.totalElevationGain } }
    private var totalActivities: Int { activities.count }

    // Rango temporal cubierto por las actividades sincronizadas, para dejar claro
    // que las cifras son ACUMULADAS de todo el historial (no diarias ni mensuales).
    private var periodLabel: String {
        guard let earliest = activities.map(\.startDate).min() else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = "MMM yyyy"
        return "\(totalActivities) actividades · desde \(f.string(from: earliest))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Aclaración del periodo: todo el historial acumulado
                VStack(spacing: 2) {
                    Text("Totales acumulados").font(.headline)
                    Text(periodLabel).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                // — Totales en grid 2×2
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(icon: "map.fill", color: .blue, title: "Kilómetros", value: String(format: "%.0f", totalKm), unit: "km")
                    StatCard(icon: "clock.fill", color: .orange, title: "Tiempo", value: String(format: "%.0fh", totalHours), unit: "horas")
                    StatCard(icon: "mountain.2.fill", color: .green, title: "Desnivel", value: String(format: "%.0f", totalElevation), unit: "m")
                    StatCard(icon: "bolt.fill", color: .purple, title: "Actividades", value: "\(totalActivities)", unit: "sesiones")
                }
                .padding(.horizontal)

                // — Km por deporte (barras horizontales)
                let kmSports = sportStats.filter { $0.km > 0.5 }
                if !kmSports.isEmpty {
                    CardSection(title: "Kilómetros por deporte") {
                        VStack(spacing: 10) {
                            ForEach(kmSports) { stat in
                                VStack(spacing: 4) {
                                    HStack {
                                        Text(stat.emoji + " " + stat.label)
                                            .font(.subheadline).fontWeight(.medium)
                                        Spacer()
                                        Text(String(format: "%.0f km", stat.km))
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundStyle(stat.color)
                                    }
                                    GeometryReader { geo in
                                        let maxKm = kmSports.map(\.km).max() ?? 1
                                        let ratio = stat.km / maxKm
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color(.tertiarySystemFill))
                                                .frame(height: 8)
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(stat.color.gradient)
                                                .frame(width: geo.size.width * ratio, height: 8)
                                        }
                                    }
                                    .frame(height: 8)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }

                // — Distribución de tiempo por deporte (donut con leyenda custom)
                let timeSports = sportStats.filter { $0.hours > 0 }
                if timeSports.count > 1 {
                    CardSection(title: "Distribución de tiempo") {
                        HStack(alignment: .center, spacing: 16) {
                            // Donut
                            Chart(timeSports) { stat in
                                SectorMark(
                                    angle: .value("Horas", stat.hours),
                                    innerRadius: .ratio(0.60),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(stat.color)
                                .cornerRadius(4)
                            }
                            .chartLegend(.hidden)
                            .frame(width: 130, height: 130)

                            // Leyenda custom — nunca se sale
                            VStack(alignment: .leading, spacing: 8) {
                                let total = timeSports.reduce(0) { $0 + $1.hours }
                                ForEach(timeSports.prefix(5)) { stat in
                                    HStack(spacing: 8) {
                                        Circle().fill(stat.color).frame(width: 8, height: 8)
                                        Text(stat.emoji + " " + stat.label)
                                            .font(.caption).lineLimit(1)
                                        Spacer(minLength: 0)
                                        Text(String(format: "%.0f%%", stat.hours / total * 100))
                                            .font(.caption).fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }

                // — Horas por mes
                if monthlyStats.count > 1 {
                    CardSection(title: "Horas por mes") {
                        Chart(monthlyStats) { item in
                            BarMark(
                                x: .value("Mes", item.id, unit: .month),
                                y: .value("Horas", item.hours)
                            )
                            .foregroundStyle(Color.indigo.gradient)
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.narrow))
                            }
                        }
                        .chartYAxisLabel("h")
                        .frame(height: 160)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .padding(.top)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helpers

private struct StatCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
            content
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
