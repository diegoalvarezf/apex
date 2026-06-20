import SwiftUI

struct HealthView: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !healthKit.isAuthorized {
                        HealthAuthCard()
                            .padding(.horizontal)
                    } else {
                        if let summary = healthKit.todaySummary {
                            TodayHealthCard(summary: summary)
                                .padding(.horizontal)
                        }

                        if !healthKit.sleepHistory.isEmpty {
                            SleepHistoryCard(sleepData: healthKit.sleepHistory)
                                .padding(.horizontal)
                        }

                        if !healthKit.hrvHistory.isEmpty {
                            HRVCard(data: healthKit.hrvHistory)
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.top)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Salud")
            .refreshable {
                await healthKit.loadAll()
            }
        }
    }
}

private struct HealthAuthCard: View {
    @EnvironmentObject var healthKit: HealthKitManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            VStack(spacing: 6) {
                Text("Conectar Apple Health")
                    .font(.headline)
                Text("Autoriza el acceso para ver sueño, HRV y recuperación")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Autorizar acceso") {
                Task { await healthKit.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct TodayHealthCard: View {
    let summary: DailyHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hoy")
                .font(.headline)

            HStack(spacing: 16) {
                if let rhr = summary.restingHR {
                    HealthMetric(
                        icon: "heart.fill", color: .red,
                        value: String(format: "%.0f", rhr), unit: "bpm",
                        label: "FC reposo"
                    )
                }
                if let vo2 = summary.vo2Max {
                    HealthMetric(
                        icon: "lungs.fill", color: .blue,
                        value: String(format: "%.1f", vo2), unit: "ml/kg/min",
                        label: "VO₂Max"
                    )
                }
                if let hrv = summary.hrv {
                    HealthMetric(
                        icon: "waveform.path.ecg", color: .green,
                        value: String(format: "%.0f", hrv.sdnn), unit: "ms",
                        label: "HRV"
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct HealthMetric: View {
    let icon: String
    let color: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SleepHistoryCard: View {
    let sleepData: [SleepData]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sueño — últimos 7 días")
                .font(.headline)

            if let latest = sleepData.first {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.formattedTotal)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                        Text("anoche")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    CircleScore(value: latest.score, color: .purple)
                }

                SleepPhasesBar(sleep: latest)
                    .frame(height: 12)

                HStack {
                    PhaseDot(color: .indigo, label: "Profundo", value: latest.deepSleep)
                    PhaseDot(color: .blue, label: "REM", value: latest.remSleep)
                    PhaseDot(color: .cyan, label: "Ligero", value: latest.coreSleep)
                    PhaseDot(color: .gray, label: "Despierto", value: latest.awake)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SleepPhasesBar: View {
    let sleep: SleepData

    var body: some View {
        GeometryReader { geo in
            let total = max(sleep.totalSleep + sleep.awake, 1)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.indigo)
                    .frame(width: geo.size.width * CGFloat(sleep.deepSleep / total))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: geo.size.width * CGFloat(sleep.remSleep / total))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.cyan)
                    .frame(width: geo.size.width * CGFloat(sleep.coreSleep / total))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: geo.size.width * CGFloat(sleep.awake / total))
            }
        }
    }
}

private struct PhaseDot: View {
    let color: Color
    let label: String
    let value: TimeInterval

    var formattedValue: String {
        let min = Int(value / 60)
        let hours = min / 60
        let minutes = min % 60
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text(formattedValue).font(.caption2).fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CircleScore: View {
    let value: Int
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(value) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(value)")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(width: 52, height: 52)
    }
}

private struct HRVCard: View {
    let data: [HRVData]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("HRV — 30 días")
                    .font(.headline)
                Spacer()
                if let latest = data.first {
                    Text(String(format: "%.0f ms", latest.sdnn))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }

            HRVSparkline(data: data)
                .frame(height: 60)

            Text("El HRV más alto indica mejor recuperación del sistema nervioso autónomo.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct HRVSparkline: View {
    let data: [HRVData]

    var body: some View {
        GeometryReader { geo in
            let values = data.reversed().map { $0.sdnn }
            let minV = values.min() ?? 0
            let maxV = max(values.max() ?? 1, minV + 1)
            let range = maxV - minV
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))

            Path { path in
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geo.size.height - (CGFloat(value - minV) / CGFloat(range)) * geo.size.height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
