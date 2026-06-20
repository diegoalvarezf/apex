import SwiftUI

struct RecoveryBatteryCard: View {
    let score: RecoveryScore?

    @State private var animatedValue: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recuperación")
                    .font(.headline)
                Spacer()
                Text(Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 20)
                    .frame(width: 180, height: 180)

                Circle()
                    .trim(from: 0, to: CGFloat(animatedValue) / 100)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: batteryColors),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    Text("\(score?.value ?? 0)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                    Text(score?.label ?? "--")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 24)

            Divider()

            HStack(spacing: 0) {
                ScorePillar(label: "Sueño", value: score?.sleepScore ?? 0, color: .purple)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                ScorePillar(label: "HRV", value: score?.hrvScore ?? 0, color: .blue)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                ScorePillar(label: "FC", value: score?.restingHRScore ?? 0, color: .red)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 40)
                ScorePillar(label: "Carga", value: score?.trainingLoadScore ?? 0, color: .orange)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                animatedValue = Double(score?.value ?? 0)
            }
        }
        .onChange(of: score?.value) { _, new in
            withAnimation(.easeOut(duration: 0.8)) {
                animatedValue = Double(new ?? 0)
            }
        }
    }

    private var batteryColors: [Color] {
        let v = score?.value ?? 0
        switch v {
        case 80...100: return [.green, .mint]
        case 60..<80: return [.cyan, .blue]
        case 40..<60: return [.yellow, .orange]
        default: return [.orange, .red]
        }
    }
}

private struct ScorePillar: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
