import SwiftUI
import Charts

struct BodyBatteryCard: View {
    let score: RecoveryScore?
    let recentHourlyHR: [MetricSample]
    let restingHR: Double?
    let sleep: SleepData?

    private var hourlyBattery: [MetricSample] {
        BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: score, sleep: sleep,
            hourlyHR: recentHourlyHR, restingHR: restingHR)
    }

    private var currentBattery: Int {
        BodyBatteryStore.shared.currentBattery(
            recoveryScore: score, sleep: sleep,
            hourlyHR: recentHourlyHR, restingHR: restingHR)
    }

    private var batteryColor: Color {
        currentBattery >= 80 ? .green : currentBattery >= 60 ? .cyan : currentBattery >= 40 ? .yellow : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body Battery").font(.headline)
                    Text(score?.label ?? "--")
                        .font(.subheadline)
                        .foregroundColor(batteryColor)
                        .fontWeight(.medium)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(currentBattery)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(batteryColor)
                        .contentTransition(.numericText())
                    Text("/ 100").font(.caption2).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)

            // Curva horaria de hoy — igual que el interior
            if hourlyBattery.count >= 2 {
                Chart {
                    // Zona sueño sombreada
                    if let sl = sleep {
                        RectangleMark(
                            xStart: .value("S", sl.sleepStart),
                            xEnd:   .value("E", sl.sleepEnd),
                            yStart: .value("Y0", 0), yEnd: .value("Y1", 100)
                        )
                        .foregroundStyle(Color.indigo.opacity(0.07))
                    }
                    ForEach(hourlyBattery) { s in
                        AreaMark(x: .value("H", s.date, unit: .hour), y: .value("B", s.value))
                            .foregroundStyle(LinearGradient(
                                colors: [batteryColor.opacity(0.25), batteryColor.opacity(0)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("H", s.date, unit: .hour), y: .value("B", s.value))
                            .foregroundStyle(batteryColor)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...100)
                .frame(height: 80)
                .padding(.horizontal, 16)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 80).padding(.horizontal, 16)
                    .overlay(Text("Sin datos de FC hoy").font(.caption).foregroundColor(.secondary))
            }

            Divider().padding(.horizontal, 16).padding(.top, 12)

            HStack(spacing: 0) {
                SegmentPill(icon: "moon.fill",         label: "Sueño",  value: score?.sleepScore ?? 0,        color: .indigo)
                Divider().frame(height: 36)
                SegmentPill(icon: "waveform.path.ecg", label: "HRV",   value: score?.hrvScore ?? 0,           color: .green)
                Divider().frame(height: 36)
                SegmentPill(icon: "heart.fill",        label: "FC",     value: score?.restingHRScore ?? 0,    color: .red)
                Divider().frame(height: 36)
                SegmentPill(icon: "figure.run",        label: "Carga",  value: score?.trainingLoadScore ?? 0, color: .orange)
            }
            .padding(.vertical, 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

private struct SegmentPill: View {
    let icon: String; let label: String; let value: Int; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundColor(color)
            Text("\(value)").font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
