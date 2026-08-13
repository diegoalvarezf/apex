import Testing
import Foundation
@testable import Apex

// Tests del VO2max estimado a partir de carreras.
// Los valores esperados salen de aplicar a mano las dos ecuaciones publicadas
// (ACSM para el coste de oxígeno, Swain & Leutholtz para la extrapolación).
struct VO2MaxEstimatorTests {

    static let rest = 50.0
    static let max = 190.0

    // Corriendo a 12 km/h = 200 m/min:
    // VO2 = 0,2 · 200 + 3,5 = 43,5 ml/kg/min
    @Test func costeDeOxigenoSigueLaEcuacionDelACSM() {
        #expect(abs(VO2MaxEstimator.vo2AtPace(metersPerMinute: 200) - 43.5) < 0.0001)
        // En reposo (velocidad 0) queda el VO2 basal de 1 MET
        #expect(abs(VO2MaxEstimator.vo2AtPace(metersPerMinute: 0) - 3.5) < 0.0001)
    }

    // La pendiente encarece la carrera: +0,9 · velocidad · pendiente
    @Test func laPendienteEncareceElCosteDeOxigeno() {
        let llano = VO2MaxEstimator.vo2AtPace(metersPerMinute: 200)
        let cuesta = VO2MaxEstimator.vo2AtPace(metersPerMinute: 200, grade: 0.05)
        #expect(cuesta > llano)
        #expect(abs(cuesta - (llano + 0.9 * 200 * 0.05)) < 0.0001)
    }

    // 10 km en 50 min (200 m/min) a 150 lpm, con reposo 50 y máx 190:
    //   VO2 al ritmo = 43,5
    //   HRr = (150−50)/140 = 0,714286
    //   VO2max = 3,5 + (43,5 − 3,5)/0,714286 = 3,5 + 56 = 59,5
    @Test func extrapolaAlMaximoSegunLaReservaDeFC() {
        let carrera = StravaActivityFixture.make(
            sportType: "run", movingTime: 3000, averageHeartrate: 150
        )
        let vo2 = VO2MaxEstimator.estimate(from: carrera, restingHR: Self.rest, maxHR: Self.max)
        #expect(vo2 != nil)
        #expect(abs(vo2! - 59.5) < 0.01)
    }

    // El mismo ritmo a menos pulsaciones implica estar más en forma.
    @Test func mismoRitmoAMenosPulsacionesDaMasVO2max() {
        let enForma = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 140)
        let cansado = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 170)
        let a = VO2MaxEstimator.estimate(from: enForma, restingHR: Self.rest, maxHR: Self.max)!
        let b = VO2MaxEstimator.estimate(from: cansado, restingHR: Self.rest, maxHR: Self.max)!
        #expect(a > b)
    }

    // MARK: - Qué actividades se descartan

    @Test func descartaLoQueNoSeaCorrer() {
        let bici = StravaActivityFixture.make(sportType: "ride", movingTime: 3000, averageHeartrate: 150)
        #expect(VO2MaxEstimator.estimate(from: bici, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    // Las series no valen: la extrapolación asume ritmo y FC estables.
    @Test func descartaLasSeries() {
        let porTipo = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 150, workoutType: 3)
        #expect(VO2MaxEstimator.estimate(from: porTipo, restingHR: Self.rest, maxHR: Self.max) == nil)

        let porNombre = StravaActivityFixture.make(name: "12x400 series", sportType: "run", movingTime: 3000, averageHeartrate: 150)
        #expect(VO2MaxEstimator.estimate(from: porNombre, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    @Test func descartaSesionesCortas() {
        let corta = StravaActivityFixture.make(sportType: "run", movingTime: 14 * 60, averageHeartrate: 150)
        #expect(VO2MaxEstimator.estimate(from: corta, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    @Test func descartaSinPulsometro() {
        let sinFC = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: nil)
        #expect(VO2MaxEstimator.estimate(from: sinFC, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    // Intensidades extremas: muy suave multiplica el error, y casi a tope no deja
    // margen que extrapolar.
    @Test func descartaIntensidadesExtremas() {
        let muySuave = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 110)  // HRr 0,43
        #expect(VO2MaxEstimator.estimate(from: muySuave, restingHR: Self.rest, maxHR: Self.max) == nil)

        let aTope = StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 187)     // HRr 0,98
        #expect(VO2MaxEstimator.estimate(from: aTope, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    // MARK: - Agregado

    // Con varias carreras devuelve la mediana, no la media ni el máximo.
    @Test func usaLaMedianaDeLasCarrerasValidas() {
        // Tres carreras al mismo ritmo con FC 140, 150 y 160 → la mediana es la de 150
        let fcs = [140.0, 150.0, 160.0]
        let carreras = fcs.enumerated().map { i, fc in
            StravaActivityFixture.make(id: i, sportType: "run", startDate: Date(), movingTime: 3000, averageHeartrate: fc)
        }
        let mediana = VO2MaxEstimator.estimate(from: carreras, restingHR: Self.rest, maxHR: Self.max)
        let laDe150 = VO2MaxEstimator.estimate(
            from: StravaActivityFixture.make(sportType: "run", movingTime: 3000, averageHeartrate: 150),
            restingHR: Self.rest, maxHR: Self.max
        )
        #expect(mediana != nil)
        #expect(abs(mediana! - laDe150!) < 0.01)
    }

    // Un dato disparatado (GPS que se va) no arrastra la estimación.
    @Test func laMedianaAguantaUnDatoAnomalo() {
        var carreras = (0..<4).map { i in
            StravaActivityFixture.make(id: i, sportType: "run", movingTime: 3000, averageHeartrate: 150)
        }
        let limpio = VO2MaxEstimator.estimate(from: carreras, restingHR: Self.rest, maxHR: Self.max)!
        // Carrera con el GPS disparado: mismo tiempo, FC baja → VO2max altísimo
        carreras.append(StravaActivityFixture.make(id: 99, sportType: "run", movingTime: 3000, averageHeartrate: 125))
        let conRuido = VO2MaxEstimator.estimate(from: carreras, restingHR: Self.rest, maxHR: Self.max)!
        #expect(abs(conRuido - limpio) < 3)
    }

    // Con menos de tres carreras no se da cifra: la mediana no filtraría nada.
    @Test func exigeUnMinimoDeCarreras() {
        let dos = (0..<2).map { i in
            StravaActivityFixture.make(id: i, sportType: "run", movingTime: 3000, averageHeartrate: 150)
        }
        #expect(VO2MaxEstimator.estimate(from: dos, restingHR: Self.rest, maxHR: Self.max) == nil)
        #expect(VO2MaxEstimator.estimate(from: [], restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    // Las carreras viejas no cuentan: la estimación debe describir tu forma de ahora.
    @Test func ignoraCarrerasFueraDeVentana() {
        let viejas = (0..<4).map { i in
            StravaActivityFixture.make(
                id: i, sportType: "run",
                startDate: Calendar.current.date(byAdding: .day, value: -200, to: Date())!,
                movingTime: 3000, averageHeartrate: 150
            )
        }
        #expect(VO2MaxEstimator.estimate(from: viejas, restingHR: Self.rest, maxHR: Self.max) == nil)
    }

    // MARK: - Integración

    // Con carreras suficientes, la edad de fitness usa esa estimación y no el
    // cociente FCmáx/FCreposo, que es más grueso.
    @Test func laEdadDeFitnessPrefiereLasCarrerasAlCociente() {
        let porCarreras = 59.5
        let r = BiologicalAgeResult.compute(
            chronologicalAge: 40, isMale: true, vo2Max: nil,
            restingHR: 50, hrv: nil, sleepScore: nil, bmi: nil,
            maxHR: 190, runBasedVO2Max: porCarreras
        )
        let factor = r.factors.first { $0.name.contains("VO₂Max") }
        #expect(factor != nil)
        #expect(factor!.explanation.contains("carreras"))
        // La edad sale de 59,5, no del 58,14 que daría el cociente
        let esperada = FitnessAgeNorms.fitnessAge(vo2Max: porCarreras, male: true)
        #expect(abs(r.biologicalAge - esperada) < 0.5)
    }
}
