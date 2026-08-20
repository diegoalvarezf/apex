import Testing
import Foundation
@testable import Apex

// La notificación de "racha de carga alta" decía "3 días seguidos" el primer día
// que el ACWR de hoy superaba 1,3 —un número inventado con apariencia de contado—.
// `loadHistory` ya trae el ATL/CTL de cada día, así que la racha real sale de ahí
// sin ningún dato nuevo. Estos tests fijan el conteo.
@MainActor
struct HighLoadStreakTests {

    // ctl>0 y atl/ctl > 1.3 ⇒ ese día cuenta. Construye una muestra con el ACWR
    // exacto que se pide, dejando ctl fijo.
    private func muestra(diasAtras: Int, acwr: Double) -> DashboardViewModel.LoadSample {
        let fecha = Calendar.current.date(byAdding: .day, value: -diasAtras, to: Date())!
        let ctl = 50.0
        return DashboardViewModel.LoadSample(date: fecha, atl: ctl * acwr, ctl: ctl, tsb: 0)
    }

    @Test func sinHistorialNoHayRacha() {
        #expect(HealthKitManager.highLoadStreak(history: []) == 0)
    }

    @Test func unSoloDiaAltoCuentaUno() {
        let historial = [muestra(diasAtras: 0, acwr: 1.5)]
        #expect(HealthKitManager.highLoadStreak(history: historial) == 1)
    }

    // El caso que fallaba: no todos los días de carga alta valen "3".
    @Test func cuentaLosDiasDeVerdad() {
        let historial = [
            muestra(diasAtras: 4, acwr: 1.5),
            muestra(diasAtras: 3, acwr: 1.5),
            muestra(diasAtras: 2, acwr: 1.4),
            muestra(diasAtras: 1, acwr: 1.35),
            muestra(diasAtras: 0, acwr: 1.31),
        ]
        #expect(HealthKitManager.highLoadStreak(history: historial) == 5)
    }

    // La racha se corta en cuanto un día no llega a 1.3, aunque antes hubiera más
    // días altos: no se suman por separado.
    @Test func seCortaEnElPrimerDiaBajo() {
        let historial = [
            muestra(diasAtras: 4, acwr: 1.8),   // alto, pero antes del corte
            muestra(diasAtras: 3, acwr: 1.8),
            muestra(diasAtras: 2, acwr: 1.0),   // corte
            muestra(diasAtras: 1, acwr: 1.5),
            muestra(diasAtras: 0, acwr: 1.5),
        ]
        #expect(HealthKitManager.highLoadStreak(history: historial) == 2)
    }

    @Test func hoyBajoDaRachaCero() {
        let historial = [
            muestra(diasAtras: 3, acwr: 1.9),
            muestra(diasAtras: 2, acwr: 1.9),
            muestra(diasAtras: 1, acwr: 1.9),
            muestra(diasAtras: 0, acwr: 1.0),
        ]
        #expect(HealthKitManager.highLoadStreak(history: historial) == 0)
    }

    // El orden de entrada no importa: se ordena por fecha antes de contar.
    @Test func funcionaAunqueElHistorialVengaDesordenado() {
        let historial = [
            muestra(diasAtras: 0, acwr: 1.5),
            muestra(diasAtras: 2, acwr: 1.5),
            muestra(diasAtras: 1, acwr: 1.5),
        ]
        #expect(HealthKitManager.highLoadStreak(history: historial) == 3)
    }

    @Test func ctlCeroNoDivideCero() {
        let historial = [
            DashboardViewModel.LoadSample(date: Date(), atl: 10, ctl: 0, tsb: 0),
        ]
        // ctl=0 usa acwr=1.0 (sin carga de fondo, ni alta ni baja): no cuenta.
        #expect(HealthKitManager.highLoadStreak(history: historial) == 0)
    }
}
