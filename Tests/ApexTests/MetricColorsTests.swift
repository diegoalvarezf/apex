import Testing
import SwiftUI
@testable import Apex

// Los colores de las métricas estaban copiados en cuatro sitios —la app, las dos
// vistas del widget y el reloj— y no coincidían: el Body Battery usaba 80/60/40 en
// la app y 75/50/25 en el widget pequeño y en el reloj. Un 78 salía CIAN en la app
// y VERDE en el reloj, a la vez, en la misma muñeca.
//
// Ahora hay una sola fuente compartida por los tres objetivos. Estos tests fijan
// los cortes: si alguien mueve un umbral, se entera aquí y no viendo dos colores
// distintos para el mismo número.
struct MetricColorsTests {

    @Test func elBodyBatteryCambiaEn80_60_40() {
        #expect(MetricColors.bodyBattery(85) == .green)
        #expect(MetricColors.bodyBattery(80) == .green)
        #expect(MetricColors.bodyBattery(79) == .cyan)
        #expect(MetricColors.bodyBattery(60) == .cyan)
        #expect(MetricColors.bodyBattery(59) == .orange)
        #expect(MetricColors.bodyBattery(40) == .orange)
        #expect(MetricColors.bodyBattery(39) == .red)
    }

    // El caso concreto que delataba la discrepancia: 78 tenía dos colores según
    // dónde se mirara.
    @Test func el78EsElMismoColorEnTodasPartes() {
        #expect(MetricColors.bodyBattery(78) == .cyan)
    }

    // La recuperación tiene un tramo más (naranja) porque acompaña a una palabra
    // —"Baja", "Muy baja"— y el color no puede decir algo distinto que el texto.
    @Test func laRecuperacionTieneCincoTramos() {
        #expect(MetricColors.recovery(90) == .green)
        #expect(MetricColors.recovery(70) == .cyan)
        #expect(MetricColors.recovery(50) == .yellow)
        #expect(MetricColors.recovery(30) == .orange)
        #expect(MetricColors.recovery(10) == .red)
    }

    // En esfuerzo, más no es mejor: la escala va al revés que las demás.
    @Test func elEsfuerzoVaAlReves() {
        #expect(MetricColors.effort(20) == .blue)    // poco esfuerzo: tranquilo
        #expect(MetricColors.effort(85) == .red)     // mucho: aviso
    }

    @Test func elSuenoVaDeIndigoARojo() {
        #expect(MetricColors.sleep(85) == .indigo)
        #expect(MetricColors.sleep(65) == .purple)
        #expect(MetricColors.sleep(20) == .red)
    }

    // Ningún valor posible puede quedarse sin color, incluido el 0 y un valor
    // corrupto por encima de 100.
    @Test func ningunValorSeQuedaSinColor() {
        for v in [-5, 0, 1, 100, 150] {
            #expect(MetricColors.bodyBattery(v) != .clear)
            #expect(MetricColors.recovery(v) != .clear)
            #expect(MetricColors.effort(v) != .clear)
            #expect(MetricColors.sleep(v) != .clear)
        }
    }
}
