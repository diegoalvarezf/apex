import Testing
import HealthKit
import Foundation
@testable import Apex

// Diego comparó su noche en Apex (6h34m) contra Apple Salud (8h23m) para la MISMA
// noche y la MISMA fuente ("Health Sync") detrás de las dos. La diferencia no podía
// estar en los datos —son los mismos—, así que estaba en cómo Apex los agrupaba.
//
// La sesión se partía en dos por el hueco de >4h que separa una noche de otra, y
// como las dos sesiones "amanecían" el mismo día, `history.last` se quedaba con la
// última y la primera desaparecía en silencio. Salud, en cambio, suma todo lo del
// día. Se reproduce con muestras de verdad porque el fallo estaba en cómo se
// procesan, no en un cálculo aparte que se pudiera probar sin ellas.
struct SleepSessionMergeTests {

    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

    private func muestra(_ valor: HKCategoryValueSleepAnalysis, _ inicio: Date, _ fin: Date) -> HKCategorySample {
        HKCategorySample(type: sleepType, value: valor.rawValue, start: inicio, end: fin)
    }

    // Dos sesiones de sueño reales, el mismo día, separadas por más de 4h: por
    // ejemplo una siesta o una noche partida por un hueco de sincronización.
    private func dosSesionesMismoDia() -> (primera: Date, segunda: Date, muestras: [HKCategorySample]) {
        let hoy = Calendar.current.startOfDay(for: Date())
        let inicioA = hoy.addingTimeInterval(1 * 3600)   // 01:00
        let finA    = hoy.addingTimeInterval(2 * 3600)   // 02:00 → 1h
        let inicioB = hoy.addingTimeInterval(7 * 3600)   // 07:00 (6h de hueco)
        let finB    = hoy.addingTimeInterval(8 * 3600)   // 08:00 → 1h
        return (inicioA, finB, [
            muestra(.asleepCore, inicioA, finA),
            muestra(.asleepCore, inicioB, finB),
        ])
    }

    @Test func dosSesionesDelMismoDiaSeFusionan() {
        let (_, _, muestras) = dosSesionesMismoDia()
        let resultado = HealthKitManager.processSleepSamples(muestras)

        // Una sola noche para el día, no dos compitiendo.
        #expect(resultado.count == 1)
        #expect(resultado.first?.totalSleep == 7200.0)   // 1h + 1h, no solo la última
    }

    @Test func laVentanaVaDelPrimerInicioAlUltimoFin() {
        let (primera, segunda, muestras) = dosSesionesMismoDia()
        let resultado = HealthKitManager.processSleepSamples(muestras)

        #expect(resultado.first?.sleepStart == primera)
        #expect(resultado.first?.sleepEnd == segunda)
    }

    // Sin fusión, una noche normal (una sola sesión) no debe duplicarse ni partirse.
    @Test func unaNocheNormalDaUnaSolaEntrada() {
        let hoy = Calendar.current.startOfDay(for: Date())
        let muestras = [
            muestra(.asleepCore, hoy.addingTimeInterval(1 * 3600), hoy.addingTimeInterval(3 * 3600)),
            muestra(.asleepDeep, hoy.addingTimeInterval(3 * 3600), hoy.addingTimeInterval(4 * 3600)),
        ]
        let resultado = HealthKitManager.processSleepSamples(muestras)
        #expect(resultado.count == 1)
        #expect(resultado.first?.totalSleep == 10800.0)
    }

    // Dos noches en DÍAS distintos siguen siendo dos entradas: la fusión es por
    // día, no una fusión general de todo el historial.
    @Test func nochesEnDiasDistintosNoSeTocan() {
        let hoy = Calendar.current.startOfDay(for: Date())
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: hoy)!
        // Más de 1h cada una: el guard descarta sesiones de 3600s o menos.
        let muestras = [
            muestra(.asleepCore, ayer.addingTimeInterval(1 * 3600), ayer.addingTimeInterval(2.5 * 3600)),
            muestra(.asleepCore, hoy.addingTimeInterval(1 * 3600), hoy.addingTimeInterval(2.5 * 3600)),
        ]
        let resultado = HealthKitManager.processSleepSamples(muestras)
        #expect(resultado.count == 2)
    }
}
