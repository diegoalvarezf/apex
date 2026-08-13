import Testing
import Foundation
@testable import Apex

// La foto diaria es lo que hace que mirar un día pasado devuelva lo que se vio
// aquel día y no un recálculo. Estos tests fijan ese contrato.
@MainActor
struct DailySnapshotStoreTests {

    private func diaDePrueba(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    @Test func guardaYRecuperaLoQueSeCalculo() {
        let dia = diaDePrueba(-3)
        DailySnapshotStore.shared.save(day: dia, battery: 82, recovery: 71, stress: 28, effort: 45)

        let leido = DailySnapshotStore.shared.snapshot(for: dia)
        #expect(leido?.battery == 82)
        #expect(leido?.recovery == 71)
        #expect(leido?.stress == 28)
        #expect(leido?.effort == 45)
    }

    // El dashboard va completando el día según cargan las fuentes: HealthKit trae
    // recuperación y estrés, y Strava después el esfuerzo. Guardar lo segundo no
    // puede borrar lo primero.
    @Test func guardarPorPartesNoPisaLoAnterior() {
        let dia = diaDePrueba(-4)
        DailySnapshotStore.shared.save(day: dia, battery: 60, recovery: 55)
        DailySnapshotStore.shared.save(day: dia, effort: 70)

        let leido = DailySnapshotStore.shared.snapshot(for: dia)
        #expect(leido?.battery == 60)
        #expect(leido?.recovery == 55)
        #expect(leido?.effort == 70)
    }

    // Un día sin foto devuelve nil, no ceros: el detalle lo usa para avisar de que
    // ese día es anterior al registro en lugar de enseñar valores inventados.
    @Test func unDiaSinFotoNoDevuelveNada() {
        let lejano = diaDePrueba(-85)
        // Nadie ha guardado ese día en estos tests
        let leido = DailySnapshotStore.shared.snapshot(for: lejano)
        #expect(leido == nil || leido?.isEmpty == true)
    }

    @Test func laCurvaSeGuardaConSusHoras() {
        let dia = diaDePrueba(-5)
        let inicio = Calendar.current.startOfDay(for: dia)
        let curva = (0..<6).map { MetricSample(date: inicio.addingTimeInterval(Double($0) * 3600),
                                              value: Double(90 - $0 * 5)) }
        DailySnapshotStore.shared.save(day: dia, batteryCurve: curva)

        let leido = DailySnapshotStore.shared.snapshot(for: dia)
        #expect(leido?.batteryCurve.count == 6)
        #expect(leido?.batteryCurve.first?.value == 90)
        #expect(leido?.batteryCurve.last?.value == 65)
    }

    // Los parámetros usados se guardan para poder explicar el número después.
    @Test func guardaLosParametrosDelCalculo() {
        let dia = diaDePrueba(-6)
        DailySnapshotStore.shared.save(day: dia, battery: 70, restingHR: 52, maxHR: 191)
        let leido = DailySnapshotStore.shared.snapshot(for: dia)
        #expect(leido?.restingHR == 52)
        #expect(leido?.maxHR == 191)
    }

    // Dos guardados del mismo día son el mismo registro, no dos.
    @Test func elMismoDiaEsUnaSolaFoto() {
        let dia = diaDePrueba(-7)
        DailySnapshotStore.shared.save(day: dia, battery: 40)
        DailySnapshotStore.shared.save(day: dia, battery: 45)
        #expect(DailySnapshotStore.shared.snapshot(for: dia)?.battery == 45)

        let mismoDiaOtraHora = dia.addingTimeInterval(5 * 3600)
        #expect(DailySnapshotStore.shared.snapshot(for: mismoDiaOtraHora)?.battery == 45)
    }
}
