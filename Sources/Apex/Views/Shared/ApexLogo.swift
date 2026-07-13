import SwiftUI

// Marca de Apex: el kanji 山 (montaña / cima) en trazo redondeado con degradado.
// Se dibuja en el espacio 1024×1024 del AppIcon para que coincida exactamente con
// el icono, y se escala al tamaño que se le pida.

// Solo la marca (los cuatro trazos), sin fondo. Tíntala sobre cualquier superficie.
struct ApexMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 1024.0
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
            }
            var p = Path()
            p.addPath(bar(350, 648, 324, 56, 28))   // base
            p.addPath(bar(372, 436, 54, 236, 27))   // trazo izquierdo
            p.addPath(bar(485, 300, 58, 372, 29))   // trazo central (el pico)
            p.addPath(bar(600, 396, 54, 276, 27))   // trazo derecho
            ctx.fill(p, with: .linearGradient(
                Gradient(colors: [Color(red: 0.243, green: 0.773, blue: 0.961),
                                  Color(red: 0.145, green: 0.388, blue: 0.922)]),
                startPoint: CGPoint(x: size.width * 0.2, y: 0),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)))
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
