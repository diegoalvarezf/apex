import Testing
import Foundation
@testable import Apex

// Tests de la edad de fitness y del VO2max estimado.
struct FitnessAgeTests {

    // MARK: - VO2max estimado (Uth et al. 2004)

    // VO2max ≈ 15,3 · (FCmáx / FCreposo). Con 190/50 → 15,3 · 3,8 = 58,14
    @Test func estimadoCoincideConLaEcuacionDeUth() {
        let vo2 = FitnessAgeNorms.estimatedVO2max(maxHR: 190, restingHR: 50)
        #expect(vo2 != nil)
        #expect(abs(vo2! - 58.14) < 0.0001)
    }

    // Bajar la FC en reposo (mejor forma) sube el VO2max estimado.
    @Test func estimadoSubeAlBajarLaFCEnReposo() {
        let enForma = FitnessAgeNorms.estimatedVO2max(maxHR: 190, restingHR: 45)!
        let peorForma = FitnessAgeNorms.estimatedVO2max(maxHR: 190, restingHR: 70)!
        #expect(enForma > peorForma)
    }

    // Fuera de rangos fisiológicos no estima: prefiere "sin dato" a inventar.
    @Test(arguments: [
        (190.0, 20.0),   // FC reposo imposible
        (190.0, 120.0),  // FC reposo demasiado alta
        (100.0, 50.0),   // FCmáx demasiado baja
        (250.0, 50.0),   // FCmáx imposible
        (50.0, 190.0),   // invertidas
        (0.0, 0.0)       // sin datos
    ])
    func noEstimaFueraDeRango(maxHR: Double, restingHR: Double) {
        #expect(FitnessAgeNorms.estimatedVO2max(maxHR: maxHR, restingHR: restingHR) == nil)
    }

    // MARK: - Edad de fitness

    // Un VO2max igual a la media de tu edad devuelve tu propia edad.
    @Test(arguments: [30.0, 40.0, 50.0])
    func laMediaDeTuEdadDevuelveTuEdad(edad: Double) {
        let medio = FitnessAgeNorms.expectedVO2max(age: edad, male: true)
        let fitness = FitnessAgeNorms.fitnessAge(vo2Max: medio, male: true)
        #expect(abs(fitness - edad) < 0.5)
    }

    // Más VO2max → menos edad de fitness (la curva es decreciente con la edad).
    @Test func masVO2maxDaMenosEdad() {
        let joven = FitnessAgeNorms.fitnessAge(vo2Max: 55, male: true)
        let mayor = FitnessAgeNorms.fitnessAge(vo2Max: 35, male: true)
        #expect(joven < mayor)
    }

    // La edad de fitness queda acotada por los extremos de la tabla HUNT.
    @Test func laEdadDeFitnessEstaAcotada() {
        #expect(FitnessAgeNorms.fitnessAge(vo2Max: 200, male: true) >= 18)
        #expect(FitnessAgeNorms.fitnessAge(vo2Max: 1, male: true) == 90)
    }

    // Hombres y mujeres tienen tablas normativas distintas.
    @Test func lasTablasDistinguenSexo() {
        let h = FitnessAgeNorms.expectedVO2max(age: 40, male: true)
        let m = FitnessAgeNorms.expectedVO2max(age: 40, male: false)
        #expect(h != m)
    }

    // MARK: - Integración con la edad biológica

    // Sin VO2max medido pero con FC válidas, usa el estimado y lo dice en la etiqueta.
    @Test func sinMedidoUsaElEstimadoYLoIndica() {
        let r = BiologicalAgeResult.compute(
            chronologicalAge: 40, isMale: true, vo2Max: nil,
            restingHR: 50, hrv: nil, sleepScore: nil, bmi: nil, maxHR: 190
        )
        let factor = r.factors.first { $0.name.contains("VO₂Max") }
        #expect(factor != nil)
        #expect(factor!.name.contains("estimado"))
    }

    // Con VO2max medido no se estima nada: manda el dato real.
    @Test func conMedidoNoEstima() {
        let r = BiologicalAgeResult.compute(
            chronologicalAge: 40, isMale: true, vo2Max: 50,
            restingHR: 50, hrv: nil, sleepScore: nil, bmi: nil, maxHR: 190
        )
        let factor = r.factors.first { $0.name.contains("VO₂Max") }
        #expect(factor != nil)
        #expect(!factor!.name.contains("estimado"))
    }

    // Sin VO2max y sin FC utilizables no se inventa una edad de fitness.
    @Test func sinDatosNoHayFactorDeVO2max() {
        let r = BiologicalAgeResult.compute(
            chronologicalAge: 40, isMale: true, vo2Max: nil,
            restingHR: nil, hrv: nil, sleepScore: nil, bmi: nil, maxHR: nil
        )
        #expect(!r.factors.contains { $0.name.contains("VO₂Max") })
    }
}
