import SwiftUI

struct GaugeRing: View {
    let value: Double        // 0-100
    let colors: [Color]
    var lineWidth: CGFloat = 20
    var size: CGFloat = 200
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: CGFloat(animated / 100))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: colors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: colors.first?.opacity(0.4) ?? .clear, radius: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { animated = value }
        }
        .onChange(of: value) { _, new in
            withAnimation(.easeOut(duration: 0.8)) { animated = new }
        }
    }
}
