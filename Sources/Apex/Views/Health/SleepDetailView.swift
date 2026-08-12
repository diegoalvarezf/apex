import SwiftUI
import Charts

struct SleepDetailView: View {
    let history: [SleepData]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let latest = history.first {
                    // Hero noche pasada
                    VStack(spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(latest.formattedTotal)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text("anoche")
                                .font(.subheadline).foregroundColor(.secondary).offset(y: -8)
                            Spacer()
                            CircleScore(value: latest.score, color: .indigo)
                        }

                        SleepPhasesBar(sleep: latest).frame(height: 14)

                        HStack {
                            PhaseLegend(color: .indigo, label: "Profundo",
                                        value: formatDuration(latest.deepSleep))
                            PhaseLegend(color: .blue, label: "REM",
                                        value: formatDuration(latest.remSleep))
                            PhaseLegend(color: .cyan, label: "Ligero",
                                        value: formatDuration(latest.coreSleep))
                            PhaseLegend(color: .gray, label: "Despierto",
                                        value: formatDuration(latest.awake))
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal)

                    // Análisis IA de la arquitectura del sueño
                    AITextCard(
                        title: "Análisis del sueño",
                        subtitle: "Claude lee tu arquitectura (profundo, REM, despertares, horarios) y te da una lectura de la noche y una recomendación.",
                        cacheKey: "apex_sleep_ai_\(Int(latest.date.timeIntervalSince1970))",
                        generate: { try await Self.analyzeSleep(latest: latest, history: history) }
                    )
                    .padding(.horizontal)
                }

                // Historial 7 días
                if history.count > 1 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Últimos 7 días").font(.headline)

                        Chart(history.reversed()) { sleep in
                            BarMark(
                                x: .value("Día", sleep.date, unit: .day),
                                y: .value("Horas", sleep.totalSleep / 3600)
                            )
                            .foregroundStyle(Color.indigo.opacity(0.7))
                            .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks { v in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                AxisValueLabel("\(v.as(Double.self).map { Int($0) } ?? 0)h")
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .frame(height: 140)

                        // Stats medias
                        let avgTotal = history.map(\.totalSleep).reduce(0, +) / Double(history.count) / 3600
                        let avgScore = history.map(\.score).reduce(0, +) / history.count
                        HStack {
                            StatBadge(label: "Media", value: String(format: "%.1fh", avgTotal), color: .indigo)
                            StatBadge(label: "Score medio", value: "\(avgScore)", color: .indigo)
                            StatBadge(label: "Noches", value: "\(history.count)", color: .indigo)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                }

                // Explicación
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cómo se calcula el score").font(.headline)
                    Text("El score pondera la duración total (40%), el porcentaje de sueño profundo (30%) y la eficiencia del sueño — tiempo dormido vs tiempo en cama (30%).\n\nObjetivo: 7-9h totales, con al menos un 20% de sueño profundo.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
            }
            .padding(.top).padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sueño")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600; let m = (Int(t) % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }; return "\(m)m"
    }

    // MARK: - Análisis IA del sueño

    private static func analyzeSleep(latest: SleepData, history: [SleepData]) async throws -> String {
        func pct(_ part: TimeInterval, _ total: TimeInterval) -> Int { total > 0 ? Int((part / total * 100).rounded()) : 0 }
        let total = latest.totalSleep
        let f: (TimeInterval) -> String = { let h = Int($0)/3600, m = (Int($0)%3600)/60; return "\(h)h\(m)m" }
        let hhmm: (Date) -> String = { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0) }

        var lines: [String] = [
            "Anoche: \(f(total)) total, eficiencia \(Int(latest.efficiency))%, score \(latest.score)/100.",
            "Fases: profundo \(f(latest.deepSleep)) (\(pct(latest.deepSleep, total))%), REM \(f(latest.remSleep)) (\(pct(latest.remSleep, total))%), ligero \(f(latest.coreSleep)) (\(pct(latest.coreSleep, total))%), despierto \(f(latest.awake)).",
            "Horario: se durmió \(hhmm(latest.sleepStart)), despertó \(hhmm(latest.sleepEnd))."
        ]
        if history.count > 1 {
            lines.append("Últimas noches (horas · score · profundo%):")
            for s in history.prefix(7) {
                lines.append("  \(f(s.totalSleep)) · \(s.score) · \(pct(s.deepSleep, s.totalSleep))%")
            }
        }

        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: AIPrompts.sleep, maxTokens: 400)
    }
}

private struct SleepPhasesBar: View {
    let sleep: SleepData
    var body: some View {
        GeometryReader { geo in
            let total = max(sleep.totalSleep + sleep.awake, 1)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.indigo)
                    .frame(width: geo.size.width * CGFloat(sleep.deepSleep / total))
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.blue)
                    .frame(width: geo.size.width * CGFloat(sleep.remSleep / total))
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.cyan)
                    .frame(width: geo.size.width * CGFloat(sleep.coreSleep / total))
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.gray.opacity(0.4))
                    .frame(width: geo.size.width * CGFloat(sleep.awake / total))
            }
        }
    }
}

private struct PhaseLegend: View {
    let color: Color; let label: String; let value: String
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.caption2).foregroundColor(.secondary)
            }
            Text(value).font(.caption2).fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatBadge: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded)).fontWeight(.bold).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CircleScore: View {
    let value: Int; let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat(value) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)").font(.system(.headline, design: .rounded)).fontWeight(.bold).foregroundColor(color)
        }
        .frame(width: 52, height: 52)
    }
}
