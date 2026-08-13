import Foundation
import SwiftUI

// MARK: - Generic time series

struct MetricSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

enum MetricTrend {
    case up, down, flat

    var systemImage: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .flat: return "arrow.right"
        }
    }

    func color(higherIsBetter: Bool) -> Color {
        switch self {
        case .up: return higherIsBetter ? .green : .red
        case .down: return higherIsBetter ? .red : .green
        case .flat: return .secondary
        }
    }
}

func computeTrend(samples: [MetricSample]) -> MetricTrend {
    guard samples.count >= 14 else { return .flat }
    let sorted = samples.sorted { $0.date < $1.date }
    let mid = sorted.count / 2
    let recent = sorted.suffix(mid).map(\.value)
    let previous = sorted.prefix(mid).map(\.value)
    let recentAvg = recent.reduce(0, +) / Double(recent.count)
    let prevAvg = previous.reduce(0, +) / Double(previous.count)
    guard prevAvg > 0 else { return .flat }
    let change = (recentAvg - prevAvg) / prevAvg
    if change > 0.05 { return .up }
    if change < -0.05 { return .down }
    return .flat
}

// MARK: - Sleep

struct SleepData: Identifiable {
    let id = UUID()
    let date: Date
    let sleepStart: Date    // hora a la que se durmió
    let sleepEnd: Date      // hora a la que se despertó
    let totalSleep: TimeInterval
    let deepSleep: TimeInterval
    let remSleep: TimeInterval
    let coreSleep: TimeInterval
    let awake: TimeInterval

    // Tiempo en cama = ventana completa de la sesión (de dormirse a despertar)
    var timeInBed: TimeInterval {
        max(sleepEnd.timeIntervalSince(sleepStart), totalSleep + awake)
    }

    // Eficiencia estándar (AASM): tiempo dormido / tiempo en cama.
    // totalSleep ya excluye los despertares, por eso se divide entre timeInBed.
    var efficiency: Double {
        guard timeInBed > 0 else { return 0 }
        return min(100, totalSleep / timeInBed * 100)
    }

    var formattedTotal: String {
        let hours = Int(totalSleep) / 3600
        let minutes = (Int(totalSleep) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    // Score de calidad del sueño 0-100 anclado a las normas de arquitectura del
    // sueño de la AASM y la National Sleep Foundation:
    //   Duración 40% — óptimo 7-9h (NSF)
    //   Profundo (N3) 20% — normal 15-20% del total; se da crédito pleno a ≥16%
    //   REM 20% — normal 20-25%; crédito pleno a ≥20%
    //   Eficiencia 20% — normal ≥85% (AASM)
    // Fuente única de score de sueño para toda la app (cards, recovery, edad).
    var score: Int {
        let hours = totalSleep / 3600
        let durationScore: Double
        switch hours {
        case 7...9:   durationScore = 1.0
        case 6..<7:   durationScore = 0.6 + (hours - 6) * 0.4      // 6→0.6, 7→1.0
        case 9..<10:  durationScore = 1.0 - (hours - 9) * 0.3      // ligera penalización por exceso
        case 5..<6:   durationScore = 0.3 + (hours - 5) * 0.3      // 5→0.3, 6→0.6
        default:      durationScore = max(0, min(0.3, hours / 5 * 0.3))
        }

        let total = max(totalSleep, 1)
        let deepScore = min(deepSleep / total / 0.16, 1.0)   // N3 ≥16%
        let remScore  = min(remSleep  / total / 0.20, 1.0)   // REM ≥20%
        let effScore  = max(0, min((efficiency - 50) / 35, 1.0))  // 50%→0, ≥85%→1

        let composite = durationScore * 0.40 + deepScore * 0.20 + remScore * 0.20 + effScore * 0.20
        return Int((composite * 100).rounded())
    }
}

// MARK: - HRV

struct HRVData: Identifiable {
    let id = UUID()
    let date: Date
    let sdnn: Double  // ms
}

// MARK: - Recovery / Body Battery

struct RecoveryScore {
    let value: Int  // 0-100
    let sleepScore: Int
    let hrvScore: Int
    let trainingLoadScore: Int
    let restingHRScore: Int

    var label: String {
        switch value {
        case 80...100: return "Excelente"
        case 60..<80: return "Buena"
        case 40..<60: return "Moderada"
        case 20..<40: return "Baja"
        default: return "Muy baja"
        }
    }

    var systemColor: Color {
        switch value {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        case 20..<40: return .orange
        default: return .red
        }
    }

    var gradientColors: [Color] {
        switch value {
        case 80...100: return [.green, .mint]
        case 60..<80: return [.cyan, .blue]
        case 40..<60: return [.yellow, .orange]
        case 20..<40: return [.orange, .red]
        default: return [.red, .pink]
        }
    }
}

// MARK: - New health metrics

struct VO2MaxData {
    let current: Double
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }

    // Fecha de la última medición. HealthKit conserva lecturas de relojes que ya no
    // usas, así que `current` puede ser de hace meses.
    var lastMeasured: Date? { samples.last?.date }

    var daysSinceMeasured: Int? {
        guard let d = lastMeasured else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day
    }

    // Un reloj que está sincronizando escribe VO2max cada pocos días, así que dos
    // semanas sin ninguna lectura significan que esa fuente dejó de alimentar Salud
    // (otro reloj, un puente desactivado…). Pasado ese plazo el valor deja de
    // tratarse como vigente y manda la estimación hecha con las carreras recientes.
    static let stalenessDays = 14
    var isStale: Bool { (daysSinceMeasured ?? .max) > Self.stalenessDays }

    // Solo el valor que sigue siendo representativo. La edad de fitness usa este:
    // si está caducado, se prefiere el estimado (etiquetado) a un dato obsoleto.
    var currentIfFresh: Double? { isStale ? nil : current }
}

struct RespiratoryData {
    let current: Double  // breaths/min
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }
}

struct WristTempData {
    let baseline: Double   // °C
    let deviation: Double  // latest - baseline
    let samples: [MetricSample]
}

struct DaylightData {
    let todayMinutes: Int
    let samples: [MetricSample]
    var trend: MetricTrend { computeTrend(samples: samples) }
}

struct BodyCompositionData {
    let weightKg: Double?
    let bmi: Double?
    let samples: [MetricSample]  // weight history
    var trend: MetricTrend { computeTrend(samples: samples) }

    static func computeBMI(weightKg: Double, heightM: Double) -> Double {
        guard heightM > 0 else { return 0 }
        return weightKg / (heightM * heightM)
    }
}

struct HeartRateZone: Identifiable {
    let id = UUID()
    let zone: Int
    let name: String
    let minBPM: Int
    let maxBPM: Int
    let timeInZone: TimeInterval

    var color: Color {
        switch zone {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }

    var formattedTime: String {
        let h = Int(timeInZone) / 3600
        let m = (Int(timeInZone) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Fitness age normative data (VO2max)

// Valores normativos de VO2max por edad y sexo del HUNT Fitness Study
// (Loe, Steinshamn & Wisløff 2013, PLOS One, n=3.816 adultos sanos 20-90 años).
// Se usan los puntos medios de cada década. La "edad de fitness" es la edad a la
// que la media poblacional de VO2max iguala tu VO2max medido — mismo concepto que
// la Fitness Age de CERG/NTNU y Garmin.
enum FitnessAgeNorms {
    // (edad media de la banda, VO2max medio ml/kg/min)
    private static let male: [(Double, Double)] = [
        (25, 54.4), (35, 49.0), (45, 47.0), (55, 42.7), (65, 38.5), (75, 34.7), (85, 31.4)
    ]
    private static let female: [(Double, Double)] = [
        (25, 43.0), (35, 39.9), (45, 37.2), (55, 33.0), (65, 29.8), (75, 27.1), (85, 24.4)
    ]

    // VO2max medio esperado para una edad/sexo (interpolación lineal, extrapolación en extremos)
    static func expectedVO2max(age: Double, male isMale: Bool) -> Double {
        let t = isMale ? male : female
        if age <= t.first!.0 { return t.first!.1 }
        if age >= t.last!.0 { return t.last!.1 }
        for i in 0..<(t.count - 1) where age >= t[i].0 && age <= t[i+1].0 {
            let f = (age - t[i].0) / (t[i+1].0 - t[i].0)
            return t[i].1 + f * (t[i+1].1 - t[i].1)
        }
        return t.last!.1
    }

    // VO2max estimado a partir del cociente FCmáx/FCreposo (Uth, Sørensen, Overgaard
    // & Pedersen 2004, Eur J Appl Physiol): VO2max ≈ 15.3 · (FCmáx / FCreposo).
    // Es un método publicado, pensado justo para cuando no hay prueba de esfuerzo.
    // Se usa SOLO si HealthKit no trae un VO2max medido, y se etiqueta como estimado:
    // un cociente no mide el consumo de oxígeno, lo infiere.
    static func estimatedVO2max(maxHR: Double, restingHR: Double) -> Double? {
        // Fuera de rangos fisiológicos plausibles no se estima nada: mejor "sin dato"
        // que un número inventado.
        guard restingHR >= 30, restingHR <= 100, maxHR >= 120, maxHR <= 220, maxHR > restingHR else { return nil }
        return 15.3 * (maxHR / restingHR)
    }

    // Edad a la que la media poblacional de VO2max = tu VO2max (invierte la curva).
    static func fitnessAge(vo2Max: Double, male isMale: Bool) -> Double {
        let t = isMale ? male : female
        // Por encima de la media de 20-29 → más joven que 20; por debajo de la de 80-89 → 90
        if vo2Max >= t.first!.1 {
            // extrapolar por la pendiente del primer tramo, con suelo en 18
            let slope = (t[1].1 - t[0].1) / (t[1].0 - t[0].0)   // ml/kg/min por año (negativa)
            let age = t.first!.0 + (vo2Max - t.first!.1) / slope
            return max(18, age)
        }
        if vo2Max <= t.last!.1 { return 90 }
        for i in 0..<(t.count - 1) where vo2Max <= t[i].1 && vo2Max >= t[i+1].1 {
            let f = (vo2Max - t[i].1) / (t[i+1].1 - t[i].1)
            return t[i].0 + f * (t[i+1].0 - t[i].0)
        }
        return t.last!.0
    }
}

// MARK: - Biological Age

struct BiologicalAgeResult {
    let chronologicalAge: Int
    let biologicalAge: Double   // Double para precisión tipo PeakWatch (ej. 26.3)

    var delta: Double { biologicalAge - Double(chronologicalAge) }

    var deltaLabel: String {
        let abs = Swift.abs(delta)
        if abs < 0.5 { return "igual a tu edad real" }
        let fmt = String(format: "%.1f", abs)
        return delta < 0 ? "\(fmt) años más joven" : "\(fmt) años mayor"
    }

    var deltaColor: Color {
        if delta < -2 { return .green }
        if delta > 2  { return .red }
        return .orange
    }

    var factors: [BiologicalAgeFactor]

    struct BiologicalAgeFactor: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: Color
        let ageDelta: Double    // Double para precisión
        let valueLabel: String
        let explanation: String
    }

    static func compute(
        chronologicalAge: Int,
        isMale: Bool,
        vo2Max: Double?,
        restingHR: Double?,
        hrv: Double?,
        sleepScore: Int?,
        bmi: Double?,
        weeklyActiveMinutes: Double? = nil,
        maxHR: Double? = nil,
        runBasedVO2Max: Double? = nil
    ) -> BiologicalAgeResult {

        var factors: [BiologicalAgeFactor] = []

        // ── EDAD DE FITNESS — método publicado y validado (Nes et al. 2011, HUNT) ──
        // Definición: la edad a la que la media poblacional de VO2max iguala tu valor.
        // Es la ÚNICA "edad" a partir de wearables con respaldo científico (la usa
        // Garmin). SOLO depende del VO2max — no se mezcla con otros marcadores con
        // pesos inventados. HealthKit puede infravalorar el VO2max si no corres fuera.
        // Prioridad del VO2max: medido y vigente > estimado con tus carreras >
        // estimado por FCmáx/FCreposo. Se baja un escalón solo si el anterior falta.
        let medido = vo2Max
        let porCarreras: Double? = medido == nil ? runBasedVO2Max : nil
        let porCociente: Double? = (medido == nil && porCarreras == nil)
            ? FitnessAgeNorms.estimatedVO2max(maxHR: maxHR ?? 0, restingHR: restingHR ?? 0)
            : nil

        let age: Double
        if let v = medido ?? porCarreras ?? porCociente {
            let esEstimado = medido == nil
            age = FitnessAgeNorms.fitnessAge(vo2Max: v, male: isMale)
            let expected = FitnessAgeNorms.expectedVO2max(age: Double(chronologicalAge), male: isMale)
            factors.append(.init(
                name: esEstimado ? "VO₂Max (estimado)" : "VO₂Max",
                icon: "lungs.fill",
                color: .cyan,
                ageDelta: age - Double(chronologicalAge),
                valueLabel: String(format: esEstimado ? "~%.1f ml/kg/min estimado (media %.0f a tu edad)" : "%.1f ml/kg/min (media %.0f a tu edad)", v, expected),
                explanation: {
                    if porCarreras != nil {
                        return "No hay una medición reciente de VO₂Max en Apple Salud, así que se estima a partir de tus carreras: del ritmo y la FC media de cada rodaje se calcula el consumo de oxígeno (ecuación de carrera del ACSM) y se extrapola al esfuerzo máximo usando la equivalencia entre reserva de FC y reserva de VO₂ (Swain & Leutholtz 1997). Se toma la mediana de los últimos 90 días, descartando series, cuestas y sesiones cortas. Es la misma idea que usan Garmin y Suunto, aunque su algoritmo exacto no es público. Si hay una medición registrada en Salud, se usa esa."
                    }
                    if porCociente != nil {
                        return "No hay una medición reciente de VO₂Max en Apple Salud ni carreras suficientes para estimarlo con ritmo y FC, así que se usa el cociente FCmáx/FCreposo (Uth et al. 2004): VO₂Max ≈ 15,3 × (FCmáx/FCreposo). Es un método publicado, pero el más grueso de los tres: con unas cuantas carreras registradas la estimación mejora sola."
                    }
                    return "Tu Edad Apex es la edad a la que la media poblacional de VO₂Max iguala tu valor medido (estudio HUNT, Nes 2011, >4.600 adultos). Es el método validado que usa Garmin. Nota: las normas HUNT son de una población en forma, así que la referencia es exigente."
                }()
            ))
        } else {
            // Ni medido ni estimable: se muestra la edad real
            age = Double(chronologicalAge)
        }

        // ── Marcadores COMPLEMENTARIOS (informativos, NO entran en la edad) ────────
        // Cada uno se asocia a longevidad por separado, pero NO existe una fórmula
        // publicada que los combine con el VO2max en una sola "edad". Se muestran con
        // su valor y su influencia direccional como contexto, sin sumarse al número.
        func infoTone(_ delta: Double) -> String {
            delta < -0.5 ? "te favorece" : delta > 0.5 ? "a mejorar" : "en la media"
        }
        if let rhr = restingHR {
            factors.append(.init(name: "FC en reposo", icon: "heart.fill", color: .red,
                ageDelta: 0, valueLabel: "\(Int(rhr)) bpm · \(infoTone(rhrDelta(rhr)))",
                explanation: "Marcador complementario (no entra en la Edad Apex). Una FC en reposo baja indica un corazón eficiente; <60 bpm es propio de personas entrenadas."))
        }
        if let h = hrv {
            factors.append(.init(name: "HRV", icon: "waveform.path.ecg", color: .green,
                ageDelta: 0, valueLabel: "\(Int(h)) ms · \(infoTone(hrvDelta(h, age: chronologicalAge)))",
                explanation: "Marcador complementario (no entra en la Edad Apex). Refleja el sistema nervioso autónomo; declina con la edad y valores altos indican resiliencia."))
        }
        if let score = sleepScore {
            factors.append(.init(name: "Calidad del sueño", icon: "moon.fill", color: .indigo,
                ageDelta: 0, valueLabel: "Score \(score)/100 · \(infoTone(sleepDelta(score)))",
                explanation: "Marcador complementario (no entra en la Edad Apex). El sueño profundo repara el cuerpo; su déficit crónico acelera el envejecimiento."))
        }
        if let b = bmi {
            factors.append(.init(name: "Composición corporal", icon: "figure.stand", color: .pink,
                ageDelta: 0, valueLabel: String(format: "IMC %.1f · %@", b, infoTone(bmiDelta(b))),
                explanation: "Marcador complementario (no entra en la Edad Apex). Un IMC saludable (18.5-24.9) reduce inflamación y estrés cardiovascular."))
        }
        if let mins = weeklyActiveMinutes {
            let label = mins < 60 ? "< 1h/sem" : mins < 150 ? String(format: "%.0f min/sem", mins) : String(format: "%.0fh/sem", mins / 60)
            factors.append(.init(name: "Actividad física", icon: "figure.run", color: .orange,
                ageDelta: 0, valueLabel: "\(label) · \(infoTone(exerciseDelta(mins)))",
                explanation: "Marcador complementario (no entra en la Edad Apex). Las guías OMS recomiendan 150-300 min/semana; el ejercicio es el mayor modificador de la longevidad."))
        }

        let rounded = ((max(18.0, age)) * 10).rounded() / 10
        return BiologicalAgeResult(
            chronologicalAge: chronologicalAge,
            biologicalAge: rounded,
            factors: factors
        )
    }

    // MARK: - Delta functions (marcadores secundarios sobre la edad de fitness)

    private static func rhrDelta(_ rhr: Double) -> Double {
        switch rhr {
        case ..<45: return -4.0
        case 45..<50: return -3.0
        case 50..<55: return -2.0
        case 55..<60: return -1.0
        case 60..<65: return 0.0
        case 65..<70: return 0.5
        case 70..<75: return 1.5
        case 75..<80: return 2.5
        default: return 4.0
        }
    }

    private static func hrvDelta(_ hrv: Double, age: Int) -> Double {
        // HRV esperado declina ~0.8ms/año desde los 20
        let expected = max(20.0, 80.0 - Double(max(0, age - 20)) * 0.8)
        let d = -(hrv - expected) / 7.0
        return max(-4, min(4, d))
    }

    private static func sleepDelta(_ score: Int) -> Double {
        switch score {
        case 85...100: return -2.0
        case 70..<85:  return -1.0
        case 55..<70:  return 0.0
        case 40..<55:  return 1.0
        default:       return 2.5
        }
    }

    private static func bmiDelta(_ bmi: Double) -> Double {
        switch bmi {
        case 18.5..<21: return -2.0
        case 21..<23:   return -1.0
        case 23..<25:   return -0.5
        case 25..<27:   return 0.5
        case 27..<30:   return 1.5
        case 30..<35:   return 2.5
        default:        return 3.5
        }
    }

    // Guías OMS: 150 min/semana mínimo, 300 min óptimo
    private static func exerciseDelta(_ mins: Double) -> Double {
        switch mins {
        case ..<75:      return 1.5   // sedentario
        case 75..<150:   return 0.0   // mínimo
        case 150..<300:  return -1.0  // cumple OMS
        case 300..<450:  return -2.0  // activo
        default:         return -3.5  // muy activo / atleta
        }
    }
}

// MARK: - Sleep Age

struct SleepAgeResult {
    let chronologicalAge: Int
    let sleepAge: Int

    var delta: Int { sleepAge - chronologicalAge }

    var deltaLabel: String {
        if delta == 0 { return "igual a tu edad real" }
        let a = Swift.abs(delta)
        return delta < 0 ? "\(a) año\(a == 1 ? "" : "s") más joven" : "\(a) año\(a == 1 ? "" : "s") mayor"
    }

    var deltaColor: Color {
        if delta < -2 { return .green }
        if delta > 2  { return .red }
        return .orange
    }

    struct Factor: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let color: Color
        let ageDelta: Int
        let valueLabel: String
        let explanation: String
    }

    var factors: [Factor]

    static func compute(chronologicalAge: Int, sleep: SleepData?) -> SleepAgeResult? {
        guard let s = sleep else { return nil }
        var factors: [Factor] = []
        var total = 0

        // Duración (±5 años)
        let hours = s.totalSleep / 3600
        let durDelta: Int
        switch hours {
        case 8..<9.5: durDelta = -3
        case 7..<8:   durDelta = -1
        case 9.5...:  durDelta = 0
        case 6..<7:   durDelta = 2
        default:      durDelta = 5
        }
        total += durDelta
        factors.append(.init(name: "Duración", icon: "clock.fill", color: .indigo, ageDelta: durDelta,
            valueLabel: String(format: "%.1fh", hours),
            explanation: "El rango óptimo para adultos es 7-9h. Dormir menos de 6h cronicamente envejece el cerebro."))

        // Sueño profundo % (±4 años) — declina con la edad
        let deepPct = s.totalSleep > 0 ? s.deepSleep / s.totalSleep * 100 : 0
        let deepDelta: Int
        switch deepPct {
        case 22...: deepDelta = -3
        case 17..<22: deepDelta = -1
        case 12..<17: deepDelta = 1
        default: deepDelta = 4
        }
        total += deepDelta
        factors.append(.init(name: "Sueño profundo", icon: "moon.stars.fill", color: .purple, ageDelta: deepDelta,
            valueLabel: String(format: "%.0f%%", deepPct),
            explanation: "El sueño profundo (N3) declina con la edad. Un 20%+ indica un sistema nervioso más joven y mayor recuperación celular."))

        // REM % (±3 años)
        let remPct = s.totalSleep > 0 ? s.remSleep / s.totalSleep * 100 : 0
        let remDelta: Int
        switch remPct {
        case 22...: remDelta = -2
        case 17..<22: remDelta = -1
        case 12..<17: remDelta = 1
        default: remDelta = 3
        }
        total += remDelta
        factors.append(.init(name: "REM", icon: "brain", color: .blue, ageDelta: remDelta,
            valueLabel: String(format: "%.0f%%", remPct),
            explanation: "El sueño REM consolida la memoria y regula las emociones. Un REM bajo es típico de estrés crónico y envejecimiento acelerado."))

        // Eficiencia (±2 años)
        let effDelta: Int
        switch s.efficiency {
        case 90...: effDelta = -2
        case 80..<90: effDelta = 0
        default: effDelta = 2
        }
        total += effDelta
        factors.append(.init(name: "Eficiencia", icon: "chart.bar.fill", color: .cyan, ageDelta: effDelta,
            valueLabel: String(format: "%.0f%%", s.efficiency),
            explanation: "La eficiencia es el tiempo dormido vs tiempo en cama. Por debajo del 85% indica fragmentación del sueño, típica del envejecimiento."))

        let age = max(18, chronologicalAge + total)
        return SleepAgeResult(chronologicalAge: chronologicalAge, sleepAge: age, factors: factors)
    }
}

// MARK: - Daily summary

struct DailyHealthSummary {
    let date: Date
    let sleep: SleepData?
    let hrv: HRVData?
    let restingHR: Double?
    let vo2Max: Double?
    let steps: Int
    let activeCalories: Double
    let recovery: RecoveryScore?
    let respiratoryRate: Double?
    let wristTempDeviation: Double?
    let daylightMinutes: Int?
    let weightKg: Double?
    let bmi: Double?
}
