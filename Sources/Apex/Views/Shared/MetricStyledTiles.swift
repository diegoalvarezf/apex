import SwiftUI

// Tiles estilo PeakWatch: cabecera (título + icono) · visual · % grande + etiqueta.
// Shell común para que los 4 tiles del dashboard tengan la misma anatomía y altura.

struct PeakMetricTile<Visual: View>: View {
    let title: String
    let icon: String
    let value: Int
    let statusLabel: String
    let statusColor: Color
    @ViewBuilder var visual: () -> Visual

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }

            visual().frame(height: 40)

            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(value)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(statusLabel)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(statusColor)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Barra de gradiente (Recuperación · Esfuerzo)

struct MetricGradientBar: View {
    let value: Int              // 0-100
    let gradient: [Color]
    var showTicks: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fill = CGFloat(max(0, min(100, value))) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(11, w * fill))
                    .animation(.easeOut(duration: 0.5), value: value)
                if showTicks {
                    HStack(spacing: 0) {
                        ForEach(1..<4) { _ in
                            Spacer()
                            Rectangle()
                                .fill(Color.primary.opacity(0.25))
                                .frame(width: 1.5, height: 7)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 11)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Arco / gauge (Estrés)

struct MetricGauge: View {
    let value: Int              // 0-100
    let gradient: [Color]

    var body: some View {
        ZStack {
            TopArc(progress: 1)
                .stroke(Color.primary.opacity(0.09),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
            TopArc(progress: CGFloat(max(0, min(100, value))) / 100)
                .stroke(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .animation(.easeOut(duration: 0.6), value: value)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Semicírculo superior dibujado por muestreo de puntos (geometría fiable,
// independiente de las convenciones de ángulos de SwiftUI).
private struct TopArc: Shape {
    var progress: CGFloat       // 0...1

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, cy = rect.maxY
        let r = min(rect.midX, rect.maxY) - 6
        guard r > 0 else { return p }
        let steps = 64
        let maxT = Double(max(0, min(1, progress)))
        for i in 0...steps {
            let t = Double(i) / Double(steps) * maxT
            let ang = Double.pi - t * Double.pi           // π (izq) → 0 (der), por arriba
            let x = cx + r * CGFloat(cos(ang))
            let y = cy - r * CGFloat(sin(ang))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
}
