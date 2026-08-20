import SwiftUI

// Colores de las métricas, en un solo sitio.
//
// Estaban copiados en cuatro —la app, las dos vistas del widget, el reloj— y no
// coincidían entre sí. El Body Battery se pintaba con tres criterios distintos
// (80/60/40 en la app, los mismos cortes con otro tono en el widget mediano, y
// 75/50/25 en el widget pequeño y en el reloj), así que un 78 salía VERDE en el
// reloj y CIAN en el widget de al lado. Con la app abierta y el widget en la
// pantalla de inicio, el mismo número con dos colores no se lee como un matiz: se
// lee como que uno de los dos está roto.
//
// Manda el criterio de la app, que es donde el usuario ve la métrica explicada.
// Este fichero lo comparten los tres objetivos de compilación, que es lo que
// impide que vuelvan a separarse.
enum MetricColors {

    // Body Battery: energía disponible ahora.
    static func bodyBattery(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 60..<80: return .cyan
        case 40..<60: return .orange
        default:      return .red
        }
    }

    // Recuperación: los mismos tramos que `RecoveryScore.label`, para que el color
    // y la palabra ("Buena", "Baja"…) no puedan contradecirse.
    static func recovery(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default:      return .red
        }
    }

    // Esfuerzo: aquí más NO es mejor, así que la escala va al revés.
    static func effort(_ value: Int) -> Color {
        switch value {
        case ..<40:   return .blue
        case 40..<70: return .orange
        default:      return .red
        }
    }

    static func sleep(_ value: Int) -> Color {
        switch value {
        case 80...:   return .indigo
        case 60..<80: return .purple
        case 40..<60: return .purple.opacity(0.7)
        default:      return .red
        }
    }
}
