import SwiftUI
import Charts

// MARK: - Effort Detail

struct EffortDetailView: View {
    let value: Int             // TRIMP score 0-100
    let todayKcal: Double
    let todayActiveKcal: Double
    let hourlyHR: [MetricSample]
    let restingHR: Double?
    let history: [MetricSample]
    let color: Color
    let activities: [StravaActivity]

    // Consejo IA con el esfuerzo real del usuario
    private func effortAdvice() async throws -> String {
        let cal = Calendar.current
        var lines = ["Esfuerzo de hoy: \(value)/100 (TRIMP diario normalizado)."]
        if history.count >= 2 {
            let recent = history.suffix(7).map { String(Int($0.value)) }
            lines.append("Esfuerzo últimos días: \(recent.joined(separator: "→")).")
        }
        let today = cal.startOfDay(for: Date())
        let todayActs = activities.filter { $0.startDate >= today }
        if todayActs.isEmpty {
            lines.append("Hoy no hay sesiones registradas.")
        } else {
            lines.append("Sesiones de hoy:")
            for a in todayActs {
                let hr = a.averageHeartrate.map { " · FC \(Int($0))" } ?? ""
                lines.append("  \(a.name) · \(a.formattedDuration)\(hr)")
            }
        }
        if let from = cal.date(byAdding: .day, value: -7, to: Date()) {
            let week = activities.filter { $0.startDate >= from }
            let h = week.reduce(0.0) { $0 + Double($1.movingTime) } / 3600.0
            lines.append(String(format: "Últimos 7 días: %d sesiones, %.1f h.", week.count, h))
        }
        let system = AIPrompts.effort
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private let zoneNames  = ["Z1 Muy suave", "Z2 Aeróbico", "Z3 Umbral", "Z4 Anaeróbico", "Z5 Máximo"]
    private let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    private var rhr: Double { restingHR ?? UserProfile.restingHR }
    private var maxHR: Double { TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR) }

    // Tiempo en cada zona: prioriza actividades Strava (FC exacta × minutos), fallback horario
    private var zoneHours: [Int] {
        let cal = Calendar.current
        var counts = [0, 0, 0, 0, 0]
        let todayActs = activities.filter { cal.isDateInToday($0.startDate) && $0.averageHeartrate != nil }

        if !todayActs.isEmpty {
            for act in todayActs {
                let avgHR = act.averageHeartrate ?? 0.0
                let hours = Int(Double(act.movingTime) / 3600.0 * 4) // cuartos de hora
                let hrr = max(0, min(1, (avgHR - rhr) / (maxHR - rhr)))
                let z: Int
                if hrr < 0.5 { z = 0 } else if hrr < 0.6 { z = 1 } else if hrr < 0.7 { z = 2 } else if hrr < 0.8 { z = 3 } else { z = 4 }
                counts[z] += max(1, hours)
            }
        } else {
            let today = hourlyHR.filter { cal.isDateInToday($0.date) }
            for s in today {
                let hrr = max(0, min(1, (s.value - rhr) / (maxHR - rhr)))
                let z: Int
                if hrr < 0.5 { z = 0 } else if hrr < 0.6 { z = 1 } else if hrr < 0.7 { z = 2 } else if hrr < 0.8 { z = 3 } else { z = 4 }
                counts[z] += 1
            }
        }
        return counts
    }

    private var todayActivities: [StravaActivity] {
        let today = Calendar.current.startOfDay(for: Date())
        return activities.filter { $0.startDate >= today }
    }

    private var effortLabel: String {
        if value >= 80 { return "Día muy exigente — prioriza recuperación" }
        if value >= 55 { return "Carga alta — bien si estás entrenado" }
        if value >= 30 { return "Carga moderada" }
        if value >= 10 { return "Actividad ligera" }
        return "Día de descanso"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: value, label: "Carga cardiovascular",
                         icon: "bolt.fill", color: color, subtitle: effortLabel)

                // Anillo TRIMP + stats
                VStack(alignment: .leading, spacing: 16) {
                    Text("Esfuerzo cardiovascular (TRIMP)").font(.headline)
                    HStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(color.opacity(0.15), lineWidth: 14)
                            Circle()
                                .trim(from: 0, to: CGFloat(Double(value) / 100))
                                .stroke(color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.6), value: value)
                            VStack(spacing: 2) {
                                Text("\(value)")
                                    .font(.system(.title2, design: .rounded)).fontWeight(.bold).foregroundColor(color)
                                Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 110, height: 110)

                        VStack(alignment: .leading, spacing: 10) {
                            statRow("Activas hoy", "\(Int(todayActiveKcal)) kcal", color)
                            statRow("Horas con datos FC", "\(hourlyHR.filter { Calendar.current.isDateInToday($0.date) }.count)h", .secondary)
                            if !todayActivities.isEmpty {
                                statRow("Actividades", "\(todayActivities.count)", .secondary)
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Zonas cardíacas de hoy
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tiempo por zona").font(.headline)
                    ForEach(0..<5) { z in
                        HStack(spacing: 12) {
                            Circle().fill(zoneColors[z]).frame(width: 10, height: 10)
                            Text(zoneNames[z]).font(.subheadline).frame(width: 120, alignment: .leading)
                            GeometryReader { geo in
                                let maxH = zoneHours.max() ?? 1
                                let w = maxH > 0 ? CGFloat(zoneHours[z]) / CGFloat(maxH) * geo.size.width : 0
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(zoneColors[z].opacity(0.25))
                                    .frame(width: geo.size.width, height: 20)
                                    .overlay(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(zoneColors[z])
                                            .frame(width: max(4, w), height: 20)
                                            .animation(.easeOut(duration: 0.5), value: zoneHours[z])
                                    }
                            }
                            .frame(height: 20)
                            Text("\(zoneHours[z])h").font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Actividades del día
                if !todayActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Actividades de hoy").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
                        ForEach(Array(todayActivities.enumerated()), id: \.element.id) { idx, act in
                            TodayActivityRow(act: act, color: color)
                            if idx < todayActivities.count - 1 { Divider().padding(.leading, 60) }
                        }
                        .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                // Sparkline semanal
                if history.count >= 2 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Carga esta semana").font(.headline)
                        Chart(history) { s in
                            BarMark(x: .value("Día", s.date, unit: .day), y: .value("TRIMP", s.value))
                                .foregroundStyle(Calendar.current.isDateInToday(s.date)
                                    ? color.gradient : Color.secondary.opacity(0.4).gradient)
                                .cornerRadius(6)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.short)).font(.caption2).foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Color.primary.opacity(0.07))
                                AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(height: 120)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                AITextCard(
                    title: "Cómo enfocar tu carga",
                    subtitle: "Claude analiza tu esfuerzo de hoy y de la semana y te dice si empujar o descansar.",
                    cacheKey: "apex_effort_tips_\(aiDayKey(Date()))_\(value)",
                    generate: { try await effortAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Esfuerzo").navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ label: String, _ val: String, _ c: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(val).font(.system(.caption, design: .rounded)).fontWeight(.semibold).foregroundColor(c)
        }
    }
}

private struct TodayActivityRow: View {
    let act: StravaActivity
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sportIcon(act.sportType))
                .font(.system(size: 18)).foregroundColor(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(act.name).font(.subheadline).fontWeight(.medium)
                Text(act.startDate, format: .dateTime.hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if act.distance > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(act.formattedDistance)
                        .font(.system(.subheadline, design: .rounded)).fontWeight(.bold)
                    Text(act.formattedDuration).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func sportIcon(_ s: String) -> String {
        switch s.lowercased() {
        case "run", "virtualrun": return "figure.run"
        case "ride", "virtualride": return "figure.outdoor.cycle"
        case "swim": return "figure.pool.swim"
        case "hike": return "figure.hiking"
        case "walk": return "figure.walk"
        case "weighttraining": return "dumbbell.fill"
        case "yoga": return "figure.mind.and.body"
        default: return "bolt.fill"
        }
    }
}

