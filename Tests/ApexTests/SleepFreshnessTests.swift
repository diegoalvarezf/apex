import Testing
import Foundation
@testable import Apex

// La app llamaba "anoche" a la última noche que tuviera, viniera de cuando viniera.
// Con el reloj sin sincronizar, esa noche puede ser de hace dos días, y presentarla
// como "anoche" enseña un dato viejo como si fuera fresco. Diego lo pilló en directo:
// Apex seguía diciendo "anoche" con una noche del 15-16 mientras la de verdad (16-17)
// no había llegado todavía.
struct SleepFreshnessTests {

    private func noche(hace dias: Int) -> SleepData {
        let fecha = Calendar.current.date(byAdding: .day, value: -dias, to: Date())!
        return SleepData(
            date: Calendar.current.startOfDay(for: fecha),
            sleepStart: fecha.addingTimeInterval(-6 * 3600), sleepEnd: fecha,
            totalSleep: 6 * 3600, deepSleep: 3600, remSleep: 3600, coreSleep: 3600, awake: 0
        )
    }

    @Test func laDeHoySeLlamaAnoche() {
        #expect(noche(hace: 0).etiqueta() == "anoche")
    }

    // El caso que falló de verdad: dos noches de retraso.
    @Test func unaNocheVieajaLlevaSuFecha() {
        let vieja = noche(hace: 2)
        let etiqueta = vieja.etiqueta()
        #expect(etiqueta != "anoche")
        #expect(etiqueta.contains("noche del"))
    }

    @Test func laDeAyerTampocoSeLlamaAnoche() {
        // Solo "hoy" es "anoche": decir lo mismo para ayer sería la misma mentira
        // en pequeño.
        #expect(noche(hace: 1).etiqueta() != "anoche")
    }

    // La referencia inyectable es lo que permite fijar el "hoy" del test sin que
    // dependa de la hora real a la que se ejecute.
    @Test func laReferenciaMandaSobreElRelojDelSistema() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let n = SleepData(
            date: Calendar.current.startOfDay(for: base),
            sleepStart: base, sleepEnd: base, totalSleep: 3600, deepSleep: 0, remSleep: 0,
            coreSleep: 3600, awake: 0
        )
        #expect(n.etiqueta(referencia: base) == "anoche")
        let dosDiasDespues = base.addingTimeInterval(2 * 86_400)
        #expect(n.etiqueta(referencia: dosDiasDespues) != "anoche")
    }
}
