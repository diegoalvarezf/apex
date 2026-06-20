import SwiftUI

struct BodyBatteryCard: View {
    let score: RecoveryScore?
    let summary: DailyHealthSummary?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Battery")
                        .font(.headline)
                    Text(Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "bolt.heart.fill")
                    .foregroundColor(score?.systemColor ?? .secondary)
                    .font(.title3)
            }

            ZStack {
                GaugeRing(
                    value: Double(score?.value ?? 0),
                    colors: score?.gradientColors ?? [.gray],
                    lineWidth: 22,
                    size: 200
                )

                VStack(spacing: 4) {
                    Text("\(score?.value ?? 0)")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                    Text(score?.label ?? "--")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 210)

            // Segmentos estrés / recuperación / esfuerzo
            HStack(spacing: 0) {
                SegmentPill(
                    icon: "moon.fill",
                    label: "Sueño",
                    value: score?.sleepScore ?? 0,
                    color: .indigo
                )
                Divider().frame(height: 44)
                SegmentPill(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: score?.hrvScore ?? 0,
                    color: .green
                )
                Divider().frame(height: 44)
                SegmentPill(
                    icon: "heart.fill",
                    label: "FC",
                    value: score?.restingHRScore ?? 0,
                    color: .red
                )
                Divider().frame(height: 44)
                SegmentPill(
                    icon: "figure.run",
                    label: "Carga",
                    value: score?.trainingLoadScore ?? 0,
                    color: .orange
                )
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

private struct SegmentPill: View {
    let icon: String
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
