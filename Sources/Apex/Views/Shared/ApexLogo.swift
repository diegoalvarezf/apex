import SwiftUI

// Marca de Apex: cumbre de dos picos con un sendero en negativo (referencias:
// AllTrails / Strava / PeakWatch). Se dibuja en el espacio 1024×1024 del AppIcon
// para que coincida exactamente con el icono, y se escala al tamaño que se le pida.

// Colores del degradado teal→azul de la marca
private let apexTeal = Color(red: 0.176, green: 0.831, blue: 0.749)   // #2dd4bf
private let apexBlue = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3b82f6
private let apexDark = Color(red: 0.043, green: 0.063, blue: 0.125)   // #0b1020 (sendero)

// Solo la marca (montaña + sendero), sin fondo. Pensada para el tile oscuro.
struct ApexMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 1024.0
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Silueta de dos picos
            var peaks = Path()
            peaks.move(to: P(205, 724))
            peaks.addLine(to: P(389, 270))
            peaks.addLine(to: P(518, 497))
            peaks.addLine(to: P(637, 356))
            peaks.addLine(to: P(821, 724))
            peaks.closeSubpath()

            let grad = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [apexTeal, apexBlue]),
                startPoint: P(205, 724), endPoint: P(821, 300))
            ctx.fill(peaks, with: grad)
            // Esquinas redondeadas (trazo del mismo color con unión redonda)
            ctx.stroke(peaks, with: grad, style: StrokeStyle(lineWidth: 24 * s, lineJoin: .round))

            // Sendero en negativo subiendo al pico principal
            var trail = Path()
            trail.move(to: P(313, 724))
            trail.addQuadCurve(to: P(389, 300), control: P(335, 518))
            ctx.stroke(trail, with: .color(apexDark),
                       style: StrokeStyle(lineWidth: 26 * s, lineCap: .round))
        }
        .accessibilityLabel("Apex")
    }
}

// Icono completo: la marca sobre el tile oscuro redondeado, igual que el AppIcon.
struct ApexIcon: View {
    var size: CGFloat = 100
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.055, green: 0.078, blue: 0.188),   // #0e1430
                             Color(red: 0.031, green: 0.043, blue: 0.094)],  // #080b18
                    startPoint: .top, endPoint: .bottom))
            ApexMark()
        }
        .frame(width: size, height: size)
    }
}
