import Testing
import Foundation
@testable import Apex

// Todas las series van en orden cronológico: la más reciente al final.
//
// Es una convención, y las convenciones se rompen en silencio. Al unificarla se
// quedaron sitios pidiendo `.first`, que pasó a devolver la medida MÁS VIEJA: la app
// enseñaba como "anoche" una noche de hasta 30 días atrás, y el score de recuperación
// se calculaba con ella. Nada fallaba; simplemente el dato era de otro día.
//
// Estos tests fijan el extremo correcto para que romperlo cueste un test en rojo.
@MainActor
struct SeriesOrderTests {

    private func noche(_ diasAtras: Int, horas: Double) -> SleepData {
        let fecha = Calendar.current.date(byAdding: .day, value: -diasAtras, to: Date())!
        return SleepData(
            date: fecha,
            sleepStart: fecha.addingTimeInterval(-horas * 3600),
            sleepEnd: fecha,
            totalSleep: horas * 3600,
            deepSleep: 3600, remSleep: 3600, coreSleep: (horas - 2) * 3600, awake: 300
        )
    }

    @Test func laNocheMasRecienteEsLaDelFinal() {
        let health = HealthKitManager()
        health.sleepHistory = [noche(30, horas: 5), noche(7, horas: 6), noche(0, horas: 8)]

        // 8 h, la de anoche. Con `.first` salían las 5 h de hace un mes.
        // Literales en Double: `#expect` compara mal un `Double?` contra 8 * 3600,
        // que es aritmética entera.
        #expect(health.latestSleep?.totalSleep == 28800.0)   // 8 h
    }

    @Test func laHRVMasRecienteTambien() {
        let health = HealthKitManager()
        let hoy = Date()
        let hace20 = Calendar.current.date(byAdding: .day, value: -20, to: hoy)!
        health.hrvHistory = [HRVData(date: hace20, sdnn: 30), HRVData(date: hoy, sdnn: 65)]

        #expect(health.latestHRV?.sdnn == 65)
    }

    @Test func conUnaSolaNocheEsEsa() {
        let health = HealthKitManager()
        health.sleepHistory = [noche(0, horas: 7)]
        #expect(health.latestSleep?.totalSleep == 25200.0)   // 7 h
    }

    @Test func sinDatosNoHayNoche() {
        #expect(HealthKitManager().latestSleep == nil)
    }
}

// La tarjeta "Últimos 7 días" del detalle de sueño anunciaba una semana y pintaba
// el mes entero: la media salía de 30 noches y el gráfico apretaba un mes en el
// ancho de una semana. Como el corte es `suffix`, se prueba el extremo que coge.
@MainActor
struct UltimaSemanaTests {

    private func noches(_ cuantas: Int) -> [SleepData] {
        (0..<cuantas).reversed().map { diasAtras in
            let fecha = Calendar.current.date(byAdding: .day, value: -diasAtras, to: Date())!
            // Horas distintas por noche para distinguir cuáles se han cogido.
            let horas = Double(30 - diasAtras)
            return SleepData(
                date: fecha, sleepStart: fecha.addingTimeInterval(-horas * 3600), sleepEnd: fecha,
                totalSleep: horas * 3600, deepSleep: 3600, remSleep: 3600,
                coreSleep: (horas - 2) * 3600, awake: 300
            )
        }
    }

    @Test func cogeLasSieteUltimasYNoLasSieteViejas() {
        let semana = Array(noches(30).suffix(7))
        #expect(semana.count == 7)
        // La última es la de hoy: 30 h en la escala del fixture.
        #expect(semana.last?.totalSleep == 108000.0)
        // Y la primera de las siete es la de hace 6 días, no la de hace 29.
        #expect(semana.first?.totalSleep == 86400.0)
    }

    @Test func conMenosDeSieteNochesLasCogeTodas() {
        #expect(Array(noches(3).suffix(7)).count == 3)
    }
}
