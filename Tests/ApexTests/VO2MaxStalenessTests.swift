import Testing
import Foundation
@testable import Apex

// HealthKit conserva lecturas de relojes que ya no se usan, así que el último
// VO2max disponible puede ser de hace meses. Estos tests fijan cuándo deja de
// tratarse como una medida vigente.
struct VO2MaxStalenessTests {

    private func data(daysAgo: Int, value: Double = 45) -> VO2MaxData {
        let fecha = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return VO2MaxData(current: value, samples: [MetricSample(date: fecha, value: value)])
    }

    @Test func unaLecturaRecienteSigueVigente() {
        let vo2 = data(daysAgo: 3)
        #expect(!vo2.isStale)
        #expect(vo2.currentIfFresh == 45)
    }

    @Test func unaLecturaDeHaceMesesCaduca() {
        let vo2 = data(daysAgo: 120)
        #expect(vo2.isStale)
        #expect(vo2.currentIfFresh == nil)
        // El valor se conserva: la tarjeta lo sigue mostrando, pero avisando.
        #expect(vo2.current == 45)
    }

    // El umbral son 60 días: justo antes vigente, justo después caducado.
    @Test func elUmbralSonSesentaDias() {
        #expect(!data(daysAgo: 59).isStale)
        #expect(data(daysAgo: 61).isStale)
    }

    @Test func cuentaLosDiasDesdeLaMedicion() {
        #expect(data(daysAgo: 45).daysSinceMeasured == 45)
    }

    @Test func sinMuestrasNoHayFecha() {
        let vacio = VO2MaxData(current: 45, samples: [])
        #expect(vacio.lastMeasured == nil)
        #expect(vacio.daysSinceMeasured == nil)
        #expect(vacio.isStale)          // sin fecha no se puede considerar vigente
        #expect(vacio.currentIfFresh == nil)
    }

    // Un VO2max caducado no debe alimentar la edad de fitness: se prefiere el
    // estimado, que al menos sale de datos de hoy y va etiquetado.
    @Test func laEdadDeFitnessPrefiereElEstimadoAlDatoCaducado() {
        let caducado = data(daysAgo: 200, value: 44.9)
        let r = BiologicalAgeResult.compute(
            chronologicalAge: 40, isMale: true, vo2Max: caducado.currentIfFresh,
            restingHR: 50, hrv: nil, sleepScore: nil, bmi: nil, maxHR: 190
        )
        let factor = r.factors.first { $0.name.contains("VO₂Max") }
        #expect(factor != nil)
        #expect(factor!.name.contains("estimado"))
    }
}
