import Testing
import Foundation
@testable import Apex

// Tests de la carga por sesión y del esfuerzo diario: las funciones que deciden
// QUÉ fórmula se aplica a cada actividad y cómo se agregan a lo largo del día.
struct SessionLoadTests {

    static let rest = 50.0
    static let max = 190.0

    // MARK: - FC efectiva

    // El cardio continuo usa su FC media tal cual: Banister asume estado estacionario
    // y ahí el promedio sí representa el esfuerzo.
    @Test func cardioContinuoUsaLaFCMediaSinTocar() {
        let carrera = StravaActivityFixture.make(sportType: "run", averageHeartrate: 150, maxHeartrate: 180)
        let hr = TrainingMetrics.effectiveHR(for: carrera, restingHR: Self.rest, maxHR: Self.max)
        #expect(hr == 150)
    }

    // En fuerza los descansos entre series diluyen la media, así que se desplaza un
    // 35% hacia el pico: 150 + 0.35·(180−150) = 160.5
    @Test func laFuerzaDesplazaLaFCHaciaElPico() {
        let pesas = StravaActivityFixture.make(sportType: "weighttraining", averageHeartrate: 150, maxHeartrate: 180)
        let hr = TrainingMetrics.effectiveHR(for: pesas, restingHR: Self.rest, maxHR: Self.max)
        #expect(abs(hr - 160.5) < 0.0001)
    }

    // Las series también son intermitentes, se detecten por workout_type o por el nombre.
    @Test func lasSeriesTambienSeCorrigen() {
        let porTipo = StravaActivityFixture.make(sportType: "run", averageHeartrate: 150, maxHeartrate: 180, workoutType: 3)
        #expect(TrainingMetrics.effectiveHR(for: porTipo, restingHR: Self.rest, maxHR: Self.max) > 150)

        let porNombre = StravaActivityFixture.make(name: "10x400 series", sportType: "run", averageHeartrate: 150, maxHeartrate: 180)
        #expect(TrainingMetrics.effectiveHR(for: porNombre, restingHR: Self.rest, maxHR: Self.max) > 150)
    }

    // Sin FC máxima registrada no hay pico al que desplazarse: se queda en la media.
    @Test func sinPicoNoHayCorreccion() {
        let sinMax = StravaActivityFixture.make(sportType: "weighttraining", averageHeartrate: 150, maxHeartrate: nil)
        #expect(TrainingMetrics.effectiveHR(for: sinMax, restingHR: Self.rest, maxHR: Self.max) == 150)

        // Pico por debajo de la media (dato incoherente): tampoco corrige.
        let picoAbsurdo = StravaActivityFixture.make(sportType: "weighttraining", averageHeartrate: 150, maxHeartrate: 140)
        #expect(TrainingMetrics.effectiveHR(for: picoAbsurdo, restingHR: Self.rest, maxHR: Self.max) == 150)
    }

    // Sin pulsómetro cae a la estimación por deporte (0.75 de reserva en carrera).
    @Test func sinFCUsaLaEstimacionPorDeporte() {
        let sinFC = StravaActivityFixture.make(sportType: "run", averageHeartrate: nil, maxHeartrate: nil)
        let hr = TrainingMetrics.effectiveHR(for: sinFC, restingHR: Self.rest, maxHR: Self.max)
        #expect(abs(hr - 155) < 0.0001)
    }

    // MARK: - FTP estimado

    // FTP ≈ 95% de la mejor potencia normalizada en salidas de 20 min o más.
    @Test func ftpEsElNoventaYCincoPorCientoDeLaMejorPotencia() {
        let salidas = [
            StravaActivityFixture.make(id: 1, sportType: "ride", movingTime: 3600, weightedAverageWatts: 200),
            StravaActivityFixture.make(id: 2, sportType: "ride", movingTime: 3600, weightedAverageWatts: 250),
            StravaActivityFixture.make(id: 3, sportType: "ride", movingTime: 3600, weightedAverageWatts: 180)
        ]
        let ftp = TrainingMetrics.estimateFTP(from: salidas)
        #expect(ftp != nil)
        #expect(abs(ftp! - 237.5) < 0.0001)   // 250 × 0.95
    }

    // Solo cuentan salidas en bici: un potenciómetro de carrera mide otra cosa.
    @Test func ftpIgnoraLoQueNoSeaCiclismo() {
        let carreraConPotencia = [
            StravaActivityFixture.make(sportType: "run", movingTime: 3600, weightedAverageWatts: 300)
        ]
        #expect(TrainingMetrics.estimateFTP(from: carreraConPotencia) == nil)
    }

    // Menos de 20 min no aproxima el test de FTP.
    @Test func ftpIgnoraSalidasCortas() {
        let corta = [
            StravaActivityFixture.make(sportType: "ride", movingTime: 19 * 60, weightedAverageWatts: 300)
        ]
        #expect(TrainingMetrics.estimateFTP(from: corta) == nil)

        let justa = [
            StravaActivityFixture.make(sportType: "ride", movingTime: 20 * 60, weightedAverageWatts: 300)
        ]
        #expect(TrainingMetrics.estimateFTP(from: justa) != nil)
    }

    @Test func ftpEsNilSinDatosDePotencia() {
        let sinPotencia = [StravaActivityFixture.make(sportType: "ride", movingTime: 3600)]
        #expect(TrainingMetrics.estimateFTP(from: sinPotencia) == nil)
        #expect(TrainingMetrics.estimateFTP(from: []) == nil)
    }

    // MARK: - Elección de fórmula por sesión

    // Bici con potencia y FTP → TSS. Una hora al FTP son 100.
    @Test func ciclismoConPotenciaUsaTSS() {
        let salida = StravaActivityFixture.make(sportType: "ride", movingTime: 3600, weightedAverageWatts: 250)
        let carga = TrainingMetrics.sessionLoad(salida, ftp: 250, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(abs(carga - 100) < 0.0001)
    }

    // Sin FTP no se puede calcular TSS: cae a Banister, que da un valor distinto.
    @Test func ciclismoSinFTPCaeATRIMP() {
        let salida = StravaActivityFixture.make(sportType: "ride", movingTime: 3600,
                                                averageHeartrate: 150, weightedAverageWatts: 250)
        let carga = TrainingMetrics.sessionLoad(salida, ftp: nil, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(abs(carga - 108.0954) < 0.001)
    }

    // Correr con potenciómetro NO usa TSS: la escala de Coggan es de ciclismo.
    @Test func correrConPotenciaSigueUsandoTRIMP() {
        let carrera = StravaActivityFixture.make(sportType: "run", movingTime: 3600,
                                                 averageHeartrate: 150, weightedAverageWatts: 300)
        let carga = TrainingMetrics.sessionLoad(carrera, ftp: 250, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(abs(carga - 108.0954) < 0.001)
    }

    // MARK: - Esfuerzo diario

    // Solo suma lo del día pedido: la actividad de ayer no infla el esfuerzo de hoy.
    @Test func elEsfuerzoDiarioIgnoraOtrosDias() {
        let hoy = Date()
        let ayer = Calendar.current.date(byAdding: .day, value: -1, to: hoy)!
        let actividades = [
            StravaActivityFixture.make(id: 1, sportType: "run", startDate: hoy, movingTime: 3600, averageHeartrate: 150),
            StravaActivityFixture.make(id: 2, sportType: "run", startDate: ayer, movingTime: 3600, averageHeartrate: 150)
        ]
        let soloHoy = TrainingMetrics.dailyEffortTRIMP(
            day: hoy, activities: actividades, hourlyHR: [],
            restingHR: Self.rest, maxHR: Self.max, isMale: true
        )
        #expect(abs(soloHoy - 108.0954) < 0.001)
    }

    // La FC de fondo en reposo (HRr ≤ 0.20) no cuenta: si contase, estar sentado
    // todo el día sumaría carga y el tile de Esfuerzo nunca marcaría un día tranquilo.
    @Test func elEsfuerzoDiarioIgnoraLaFCDeReposo() {
        let hoy = Date()
        // HRr de 0.20 con reserva 140 son 78 lpm: por debajo no suma.
        let enReposo = (0..<12).map { h in
            MetricSample(date: Calendar.current.date(byAdding: .hour, value: -h, to: hoy)!, value: 70)
        }
        let total = TrainingMetrics.dailyEffortTRIMP(
            day: hoy, activities: [], hourlyHR: enReposo,
            restingHR: Self.rest, maxHR: Self.max, isMale: true
        )
        #expect(total == 0)
    }

    // Con la FC de fondo elevada sí suma (actividad no registrada en Strava).
    @Test func elEsfuerzoDiarioSumaLaFCDeFondoElevada() {
        let hoy = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
        let activo = [MetricSample(date: hoy, value: 130)]
        let total = TrainingMetrics.dailyEffortTRIMP(
            day: hoy, activities: [], hourlyHR: activo,
            restingHR: Self.rest, maxHR: Self.max, isMale: true
        )
        #expect(total > 0)
    }
}
