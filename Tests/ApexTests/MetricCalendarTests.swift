import Testing
import Foundation
@testable import Apex

// El calendario mensual coloca cada día en su columna y colorea según el valor.
// Ambas cosas son fáciles de equivocar, y un fallo no rompe nada: solo pinta el
// mes torcido o con el color al revés.
@MainActor
struct MetricCalendarTests {

    // MARK: - Color

    // Con "más es mejor" (batería, recuperación) el verde es el valor alto.
    @Test func masEsMejorPintaVerdeLoAlto() {
        let vista = MetricCalendarView.Metric.battery
        #expect(vista.higherIsBetter)
    }

    // El estrés va al revés: 90 de estrés es malo, no bueno.
    @Test func elEstresSeInvierte() {
        #expect(!MetricCalendarView.Metric.stress.higherIsBetter)
        #expect(MetricCalendarView.Metric.recovery.higherIsBetter)
    }

    // MARK: - Disponibilidad declarada

    // Cada métrica declara de cuánto historial dispone; el texto no puede faltar
    // porque es lo que evita que el usuario crea que un mes vacío es un fallo.
    @Test(arguments: MetricCalendarView.Metric.allCases)
    func todasDeclaranSuDisponibilidad(metric: MetricCalendarView.Metric) {
        let texto = MetricCalendarData.disponibilidad(metric)
        #expect(!texto.isEmpty)
        #expect(texto.contains("días"))
    }

    @Test(arguments: MetricCalendarView.Metric.allCases)
    func todasTienenNombreEIcono(metric: MetricCalendarView.Metric) {
        #expect(!metric.rawValue.isEmpty)
        #expect(!metric.icon.isEmpty)
    }
}
