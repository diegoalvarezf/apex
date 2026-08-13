import Testing
import Foundation
@testable import Apex

// Tests de las calculadoras de carga de entrenamiento.
//
// El objetivo no es cubrir líneas, sino comprobar que las fórmulas publicadas se
// implementan fielmente: los valores esperados salen de aplicar a mano la ecuación
// original (Banister 1991, Coggan/TrainingPeaks), no de ejecutar el código y copiar
// lo que devolvía. Ver docs/METRICS_SOURCES.md.
struct TrainingMetricsTests {

    // Referencia común: FC reposo 50, FCmáx 190 → reserva cardíaca de 140 lpm.
    static let rest = 50.0
    static let max = 190.0

    // MARK: - TRIMP de Banister

    // TRIMP = t · HRr · 0.64 · e^(1.92·HRr) para hombres.
    // 60 min a 150 lpm → HRr = (150−50)/140 = 0.714286
    // 60 · 0.714286 · 0.64 · e^(1.371429) = 108.0954
    @Test func banisterCoincideConLaEcuacionPublicada() {
        let trimp = TrainingMetrics.banisterTRIMP(
            minutes: 60, avgHR: 150, restingHR: Self.rest, maxHR: Self.max, isMale: true
        )
        #expect(abs(trimp - 108.0954) < 0.001)
    }

    // Las mujeres usan a=0.86 y b=1.67, así que el mismo esfuerzo da otro valor.
    @Test func banisterAplicaLosCoeficientesFemeninos() {
        let hombre = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 150, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        let mujer  = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 150, restingHR: Self.rest, maxHR: Self.max, isMale: false)
        #expect(abs(mujer - 121.4991) < 0.001)
        #expect(mujer != hombre)
    }

    // Con datos imposibles devuelve 0 en vez de NaN o negativos: estos valores
    // alimentan ATL/CTL, y un NaN colado ahí envenenaría toda la serie histórica.
    @Test(arguments: [
        (0.0, 150.0, 50.0, 190.0),    // sin duración
        (-10.0, 150.0, 50.0, 190.0),  // duración negativa
        (60.0, 150.0, 190.0, 190.0),  // reserva cardíaca nula
        (60.0, 150.0, 200.0, 190.0),  // reposo por encima de la máxima
    ])
    func banisterDevuelveCeroConDatosInvalidos(minutes: Double, avgHR: Double, rest: Double, max: Double) {
        let trimp = TrainingMetrics.banisterTRIMP(minutes: minutes, avgHR: avgHR, restingHR: rest, maxHR: max, isMale: true)
        #expect(trimp == 0)
        #expect(!trimp.isNaN)
    }

    // HRr se satura en [0,1]: por debajo del reposo no hay carga negativa y por
    // encima de la FCmáx no se dispara (una lectura errónea del pulsómetro no debe
    // inflar la carga del día).
    @Test func banisterSaturaLaFraccionDeReserva() {
        let bajoReposo = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 40, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(bajoReposo == 0)

        let enMaxima = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 190, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        let porEncima = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 250, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(abs(enMaxima - porEncima) < 0.0001)
    }

    @Test func banisterCreceConDuracionEIntensidad() {
        let base = TrainingMetrics.banisterTRIMP(minutes: 30, avgHR: 140, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        let masLargo = TrainingMetrics.banisterTRIMP(minutes: 60, avgHR: 140, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        let masIntenso = TrainingMetrics.banisterTRIMP(minutes: 30, avgHR: 170, restingHR: Self.rest, maxHR: Self.max, isMale: true)
        #expect(masLargo > base)
        #expect(masIntenso > base)
        // El doble de tiempo a la misma FC es exactamente el doble de carga (es lineal en t).
        #expect(abs(masLargo - base * 2) < 0.0001)
    }

    // MARK: - TSS

    // Definición de Coggan: una hora exacta al FTP es, por construcción, 100 TSS.
    // Es la prueba que ancla toda la escala.
    @Test func unaHoraAlFTPSonCienTSS() {
        let tss = TrainingMetrics.tss(seconds: 3600, normalizedPower: 250, ftp: 250)
        #expect(abs(tss - 100) < 0.0001)
    }

    // TSS escala con el cuadrado del factor de intensidad (IF²·horas·100).
    @Test func tssEscalaConElCuadradoDeLaIntensidad() {
        let alOchentaPorCiento = TrainingMetrics.tss(seconds: 3600, normalizedPower: 200, ftp: 250)
        #expect(abs(alOchentaPorCiento - 64) < 0.0001)   // 0.8² × 100

        let mediaHora = TrainingMetrics.tss(seconds: 1800, normalizedPower: 250, ftp: 250)
        #expect(abs(mediaHora - 50) < 0.0001)
    }

    @Test(arguments: [
        (0.0, 250.0, 250.0),    // sin duración
        (3600.0, 0.0, 250.0),   // sin potencia
        (3600.0, 250.0, 0.0),   // sin FTP
    ])
    func tssDevuelveCeroConDatosInvalidos(seconds: Double, np: Double, ftp: Double) {
        let tss = TrainingMetrics.tss(seconds: seconds, normalizedPower: np, ftp: ftp)
        #expect(tss == 0)
        #expect(!tss.isNaN)
    }

    // MARK: - Esfuerzo diario

    // Curva saturante 100·(1−e^(−TRIMP/90)). Con TRIMP = K el resultado es
    // 100·(1−1/e) = 63, que es el punto que fija la escala.
    @Test(arguments: [(0.0, 0), (45.0, 39), (90.0, 63), (180.0, 86), (270.0, 95)])
    func effortScoreSigueLaCurvaSaturante(trimp: Double, esperado: Int) {
        #expect(TrainingMetrics.effortScore(dailyTRIMP: trimp) == esperado)
    }

    // Nunca llega a 100 ni se pasa: es una asíntota, no un tope recortado.
    @Test func effortScoreNoSaturaAlCien() {
        #expect(TrainingMetrics.effortScore(dailyTRIMP: 10_000) <= 100)
        #expect(TrainingMetrics.effortScore(dailyTRIMP: 0) == 0)
        #expect(TrainingMetrics.effortScore(dailyTRIMP: -50) == 0)
    }

    @Test func effortScoreEsMonotono() {
        let valores = stride(from: 10.0, through: 400.0, by: 10.0)
            .map { TrainingMetrics.effortScore(dailyTRIMP: $0) }
        #expect(zip(valores, valores.dropFirst()).allSatisfy { $0 <= $1 })
    }

    // MARK: - FC de respaldo por deporte

    // Fracción de la reserva cardíaca: reposo + frac × (máx − reposo), con 140 de reserva.
    @Test(arguments: [
        ("run", 155.0),             // 0.75
        ("ride", 141.0),            // 0.65
        ("swim", 148.0),            // 0.70
        ("weighttraining", 127.0),  // 0.55
        ("walk", 106.0),            // 0.40
        ("yoga", 92.0),             // 0.30
        ("deporte_inventado", 134.0) // 0.60 por defecto
    ])
    func fallbackAvgHRUsaLaFraccionDeCadaDeporte(sport: String, esperado: Double) {
        let hr = TrainingMetrics.fallbackAvgHR(sport: sport, restingHR: Self.rest, maxHR: Self.max)
        #expect(abs(hr - esperado) < 0.0001)
    }

    @Test func fallbackAvgHRIgnoraMayusculas() {
        let minus = TrainingMetrics.fallbackAvgHR(sport: "run", restingHR: Self.rest, maxHR: Self.max)
        let mayus = TrainingMetrics.fallbackAvgHR(sport: "Run", restingHR: Self.rest, maxHR: Self.max)
        #expect(minus == mayus)
    }

    // MARK: - Estrés a partir del HRV

    @Test func hrvBaseStressSinDatoDevuelveValorNeutro() {
        #expect(TrainingMetrics.hrvBaseStress(todaySDNN: nil, baseline: []) == 30)
    }

    // Estar en la media del baseline (z = 0) da 23, el ancla de la escala.
    @Test func hrvBaseStressEnLaMediaDaElValorAncla() {
        let baseline = [40.0, 45, 50, 55, 60, 50, 50]   // media 50
        let estres = TrainingMetrics.hrvBaseStress(todaySDNN: 50, baseline: baseline)
        #expect(abs(estres - 23.0) < 0.0001)
    }

    // Relación inversa: más HRV → menos estrés.
    @Test func hrvBaseStressBajaCuandoSubeElHRV() {
        let baseline = [40.0, 45, 50, 55, 60, 50, 50]
        let conHRVAlto = TrainingMetrics.hrvBaseStress(todaySDNN: 65, baseline: baseline)
        let conHRVBajo = TrainingMetrics.hrvBaseStress(todaySDNN: 35, baseline: baseline)
        #expect(conHRVAlto < conHRVBajo)
    }

    // Valores extremos quedan dentro de [8, 60]: un SDNN anómalo no debe pintar
    // "estrés 0" ni "estrés 100" en el dashboard.
    @Test func hrvBaseStressQuedaAcotado() {
        let baseline = [40.0, 45, 50, 55, 60, 50, 50]
        #expect(TrainingMetrics.hrvBaseStress(todaySDNN: 500, baseline: baseline) == 8)
        #expect(TrainingMetrics.hrvBaseStress(todaySDNN: 1, baseline: baseline) == 60)
    }

    // Con menos de 7 noches no hay baseline fiable: usa el mapa absoluto 70 − SDNN.
    @Test(arguments: [(40.0, 30.0), (20.0, 50.0), (76.0, 12.0)])
    func hrvBaseStressSinBaselineUsaMapaAbsoluto(sdnn: Double, esperado: Double) {
        let estres = TrainingMetrics.hrvBaseStress(todaySDNN: sdnn, baseline: [50.0, 50, 50])
        #expect(abs(estres - esperado) < 0.0001)
    }

    // MARK: - Estrés fisiológico instantáneo

    // En reposo el estrés es el tono de fondo; en FCmáx suma los 70 puntos de empuje.
    @Test func physiologicalStressParteDeLaBaseAutonomica() {
        let enReposo = TrainingMetrics.physiologicalStress(hr: 50, restingHR: Self.rest, maxHR: Self.max, hrvBase: 25)
        #expect(abs(enReposo - 25) < 0.0001)

        let aTope = TrainingMetrics.physiologicalStress(hr: 190, restingHR: Self.rest, maxHR: Self.max, hrvBase: 25)
        #expect(abs(aTope - 95) < 0.0001)
    }

    @Test func physiologicalStressQuedaEntreCeroYCien() {
        let altisimo = TrainingMetrics.physiologicalStress(hr: 250, restingHR: Self.rest, maxHR: Self.max, hrvBase: 60)
        #expect(altisimo <= 100)
        let bajisimo = TrainingMetrics.physiologicalStress(hr: 20, restingHR: Self.rest, maxHR: Self.max, hrvBase: 10)
        #expect(bajisimo >= 0)
    }

    // Sin reserva cardíaca válida devuelve la base en vez de dividir por cero.
    @Test func physiologicalStressSinReservaDevuelveLaBase() {
        let estres = TrainingMetrics.physiologicalStress(hr: 150, restingHR: 190, maxHR: 190, hrvBase: 42)
        #expect(estres == 42)
        #expect(!estres.isNaN)
    }
}
