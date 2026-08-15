import Testing
import Foundation
@testable import Apex

// La serie de Body Battery se memoriza porque las vistas la piden varias veces por
// repintado. Estos tests fijan lo que la caché no debe romper: mismos datos, mismo
// resultado; y si cambian los datos, el resultado se rehace.
@MainActor
struct BodyBatteryCacheTests {

    // Noche que acaba a la hora indicada de hoy, para fijar la hora de despertar
    // y que la simulación no dependa de a qué hora se ejecute el test.
    private func despertarA(hora: Int) -> SleepData {
        let inicioDia = Calendar.current.startOfDay(for: Date())
        let fin = inicioDia.addingTimeInterval(Double(hora) * 3600)
        return SleepData(
            date: inicioDia,
            sleepStart: fin.addingTimeInterval(-7 * 3600),
            sleepEnd: fin,
            totalSleep: 7 * 3600,
            deepSleep: 5400,
            remSleep: 5400,
            coreSleep: 14400,
            awake: 0)
    }

    private func hourlyHR(hours: Int, value: Double = 70) -> [MetricSample] {
        let inicio = Calendar.current.startOfDay(for: Date())
        return (0..<hours).map { h in
            MetricSample(date: inicio.addingTimeInterval(Double(h) * 3600), value: value)
        }
    }

    private func recovery(_ v: Int) -> RecoveryScore {
        RecoveryScore(value: v, sleepScore: 70, hrvScore: 70, trainingLoadScore: 70, restingHRScore: 70)
    }

    @Test func dosLlamadasSeguidasDanLoMismo() {
        let hr = hourlyHR(hours: 10)
        let primera = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: [], hourlyHR: hr, restingHR: 55)
        let segunda = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: [], hourlyHR: hr, restingHR: 55)

        #expect(primera.count == segunda.count)
        #expect(zip(primera, segunda).allSatisfy { abs($0.value - $1.value) < 0.0001 })
    }

    // Si cambian los datos de entrada, la firma cambia y se recalcula: la caché no
    // puede seguir devolviendo la serie del estado anterior.
    //
    // No se comprueba con el recovery: la batería de partida es el valor persistido
    // del día anterior (el encadenado día a día que documenta el store), así que
    // cambiar el recovery de hoy no tiene por qué mover el primer punto.
    @Test func alCambiarLosDatosSeRecalcula() {
        // Se le da una noche que termina a medianoche para que TODAS las horas
        // simuladas cuenten como despierto. Sin esto el test dependía del reloj:
        // el store solo simula hasta la hora actual y, ejecutándolo de madrugada,
        // todas las horas caían antes de la hora de despertar por defecto (las 7),
        // donde no hay drenaje por FC y las dos series salían idénticas.
        let despiertoDesdeMedianoche = [despertarA(hora: 0)]

        // Con la FC de fondo muy por encima del reposo se drena bastante más que
        // cuando queda por debajo, así que las dos series no pueden coincidir.
        let activo = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: despiertoDesdeMedianoche,
            hourlyHR: hourlyHR(hours: 12, value: 130), restingHR: 50)
        let enReposo = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: despiertoDesdeMedianoche,
            hourlyHR: hourlyHR(hours: 12, value: 55), restingHR: 50)

        // Si la caché no se invalidara, la segunda llamada devolvería la primera serie.
        let iguales = zip(activo, enReposo).allSatisfy { abs($0.value - $1.value) < 0.0001 }
        #expect(!iguales)
    }

    @Test func masHorasDeDatosDanMasMuestras() {
        let corto = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: [], hourlyHR: hourlyHR(hours: 5), restingHR: 55)
        let largo = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(70), sleepHistory: [], hourlyHR: hourlyHR(hours: 20), restingHR: 55)
        #expect(largo.count >= corto.count)
    }

    // La batería vive acotada entre 5 y 100, como en Garmin: ningún encadenado de
    // días puede sacarla de ahí.
    @Test func laBateriaQuedaAcotada() {
        let serie = BodyBatteryStore.shared.hourlyBattery(
            recoveryScore: recovery(95), sleepHistory: [], hourlyHR: hourlyHR(hours: 24, value: 180), restingHR: 55)
        #expect(serie.allSatisfy { $0.value >= 5 && $0.value <= 100 })
    }
}
