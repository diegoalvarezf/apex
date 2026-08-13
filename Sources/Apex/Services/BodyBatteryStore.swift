import Foundation
import SwiftUI

// Body Battery (metodología Firstbeat/Garmin, ver docs/METRICS_SOURCES.md):
// - El valor del final del día es el punto de partida del día siguiente.
// - CARGA: solo durmiendo. El total de la noche = calidad × horas realmente
//   dormidas × 6.5 (noche completa de calidad ≈ +50), repartido por hora con más
//   carga al principio (el sueño profundo se concentra en la primera mitad).
// - DRENAJE: despierto la batería solo baja (estar despierto ya cuesta), y los
//   entrenos drenan según su TRIMP con curva saturante estilo EPOC.
// - El drenaje es más rápido con la batería alta y se frena cerca del suelo.
// - Acotado a 5-100, como Garmin.
//
// Firstbeat/Garmin no publican fórmulas exactas; las constantes de carga/descarga
// son calibración propia de Apex, documentada línea a línea.
final class BodyBatteryStore {
    static let shared = BodyBatteryStore()
    private let storageKey = "apex_body_battery_snapshots"
    private let cal = Calendar.current

    private init() {}

    // Memoria del último cálculo. La serie se pide desde propiedades computadas de
    // la vista (valor, color, tendencia y gráfica), así que sin esto SwiftUI rehacía
    // la simulación de 7 días —y sus escrituras a UserDefaults— varias veces por
    // repintado. La firma cambia en cuanto cambia cualquier dato de entrada.
    private var cacheSignature: String?
    private var cachedSamples: [MetricSample] = []

    // MARK: - API pública

    // Serie horaria de HOY. Encadena la simulación de los últimos 7 días con la FC
    // horaria disponible, de modo que el punto de partida de hoy sea el final real
    // de ayer (no el último valor visto al abrir la app).
    func hourlyBattery(
        recoveryScore: RecoveryScore?,
        sleepHistory: [SleepData],
        hourlyHR: [MetricSample],
        restingHR: Double?,
        recoveryHistory: [MetricSample] = [],
        activities: [StravaActivity] = [],
        hrvHistory: [MetricSample] = []
    ) -> [MetricSample] {
        var partes: [String] = []
        partes.append(String(recoveryScore?.value ?? -1))
        partes.append(String(sleepHistory.count))
        partes.append(String(hourlyHR.count))
        let ultimaHora: Double = hourlyHR.last?.date.timeIntervalSince1970 ?? 0
        partes.append(String(ultimaHora))
        // Los VALORES, no solo cuántos hay: con la misma cantidad de muestras y otra
        // FC el resultado cambia, y sin esto la caché devolvía la serie anterior.
        let sumaHR: Double = hourlyHR.reduce(0) { $0 + $1.value }
        partes.append(String(sumaHR))
        partes.append(String(restingHR ?? -1))
        partes.append(String(recoveryHistory.count))
        partes.append(String(activities.count))
        partes.append(String(hrvHistory.count))
        let hoy: Double = cal.startOfDay(for: Date()).timeIntervalSince1970
        partes.append(String(hoy))
        let firma = partes.joined(separator: "|")
        if firma == cacheSignature { return cachedSamples }

        let resultado = computeHourlyBattery(
            recoveryScore: recoveryScore, sleepHistory: sleepHistory,
            hourlyHR: hourlyHR, restingHR: restingHR,
            recoveryHistory: recoveryHistory, activities: activities,
            hrvHistory: hrvHistory)
        cacheSignature = firma
        cachedSamples = resultado
        return resultado
    }

    private func computeHourlyBattery(
        recoveryScore: RecoveryScore?,
        sleepHistory: [SleepData],
        hourlyHR: [MetricSample],
        restingHR: Double?,
        recoveryHistory: [MetricSample],
        activities: [StravaActivity],
        hrvHistory: [MetricSample]
    ) -> [MetricSample] {
        let recoveryToday = Double(recoveryScore?.value ?? 65)
        let rhr = restingHR ?? UserProfile.restingHR
        let today = cal.startOfDay(for: Date())

        func recovery(for day: Date) -> Double {
            recoveryHistory.first { cal.isDate($0.date, inSameDayAs: day) }?.value ?? recoveryToday
        }

        guard let firstDay = cal.date(byAdding: .day, value: -6, to: today) else { return [] }
        var battery = storedValue(for: cal.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay)
            ?? min(95.0, recovery(for: firstDay) * 0.95)

        for offset in 0...6 {
            guard let day = cal.date(byAdding: .day, value: offset - 6, to: today) else { continue }
            let dayHR = hourlyHR.filter { cal.isDate($0.date, inSameDayAs: day) }
            let sleep = sleepHistory.first { cal.isDate($0.date, inSameDayAs: day) }
            let dayActs = activities.filter { cal.isDate($0.startDate, inSameDayAs: day) }
            // HRV de esa noche y baseline personal previo (para modular la carga)
            let nightHRV = hrvHistory.first { cal.isDate($0.date, inSameDayAs: day) }?.value
            let baseline = hrvHistory.filter { $0.date < cal.startOfDay(for: day) }.map(\.value)

            let sim = simulateDay(
                day: day,
                hourlyHR: dayHR,
                sleep: sleep,
                startBattery: battery,
                restingHR: rhr,
                activities: dayActs,
                nightHRV: nightHRV,
                hrvBaseline: baseline
            )
            battery = sim.last?.value ?? battery
            storeValue(battery, for: day)
            if cal.isDate(day, inSameDayAs: today) { return sim }
        }
        return []
    }

    func currentBattery(
        recoveryScore: RecoveryScore?,
        sleepHistory: [SleepData],
        hourlyHR: [MetricSample],
        restingHR: Double?,
        recoveryHistory: [MetricSample] = [],
        activities: [StravaActivity] = [],
        hrvHistory: [MetricSample] = []
    ) -> Int {
        let samples = hourlyBattery(recoveryScore: recoveryScore, sleepHistory: sleepHistory,
                                    hourlyHR: hourlyHR, restingHR: restingHR,
                                    recoveryHistory: recoveryHistory, activities: activities,
                                    hrvHistory: hrvHistory)
        return Int(samples.last?.value ?? Double(recoveryScore?.value ?? 0))
    }

    // Convierte la carga de una sesión (TRIMP de Banister) en puntos de batería a
    // drenar. Curva saturante (estilo EPOC de Firstbeat): sesiones duras drenan mucho
    // pero con rendimientos decrecientes. ~30 TRIMP (gimnasio 50') ≈ 33 pts,
    // ~90 TRIMP (1h Z2) ≈ 55, maratón → ~65. Calibración de producto documentada.
    private func activityDrain(trimp: Double) -> Double {
        guard trimp > 0 else { return 0 }
        return 65.0 * (1.0 - Foundation.exp(-trimp / 45.0))
    }

    // Factor de recuperación autonómica de la noche a partir del HRV frente al
    // baseline personal. Firstbeat mide la recuperación nocturna con HRV, no solo
    // con la duración del sueño: dormir 8h con el HRV hundido recupera menos que
    // dormir 8h con el HRV alto. Se limita a ±25% para que MODULE la carga del
    // sueño, no la sustituya (solo tenemos un valor por noche, no latido a latido).
    func hrvRecoveryFactor(nightHRV: Double?, baseline: [Double]) -> Double {
        guard let h = nightHRV, baseline.count >= 7 else { return 1.0 }
        let mean = baseline.reduce(0, +) / Double(baseline.count)
        let variance = baseline.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(baseline.count)
        let sd = max(sqrt(variance), 7.0)
        let z = (h - mean) / sd
        return max(0.75, min(1.25, 1.0 + z * 0.12))
    }

    // Simulación reutilizable para cualquier día (se usa también en el detalle histórico)
    func simulateDay(
        day: Date,
        hourlyHR: [MetricSample],
        sleep: SleepData?,
        startBattery: Double,
        restingHR: Double,
        activities: [StravaActivity] = [],
        nightHRV: Double? = nil,
        hrvBaseline: [Double] = []
    ) -> [MetricSample] {
        let maxHR    = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        let wakeHour  = sleep.map { cal.component(.hour, from: $0.sleepEnd)   } ?? 7
        let sleepHour = sleep.map { cal.component(.hour, from: $0.sleepStart) } ?? 23
        let maxHour   = cal.isDateInToday(day) ? cal.component(.hour, from: Date()) : 23

        // Ventana en cama (horas de reloj) — solo define el tramo donde se carga
        let windowH: Double = sleepHour >= wakeHour
            ? max(1.0, Double(24 - sleepHour + wakeHour))
            : max(1.0, Double(wakeHour - sleepHour))

        // Duración REAL dormida (HealthKit), no la ventana en cama
        let sleepDurationH = sleep.map { $0.totalSleep / 3600.0 } ?? windowH

        // Carga de sueño POR HORA (estilo Firstbeat): el total de la noche es
        // calidad × horas realmente dormidas × 6.5 (noche completa de calidad ≈ +50),
        // repartido entre las horas de la ventana de sueño. Al ser por hora, una noche
        // que cruza medianoche se reparte correctamente entre los dos días naturales
        // (antes las horas previas a las 00:00 contaban como despierto y DRENABAN).
        // La calidad combina la arquitectura del sueño (score: duración, profundo,
        // eficiencia) con la recuperación autonómica real de esa noche (HRV).
        let sleepQuality = max(0.4, min(1.0, Double(sleep?.score ?? 60) / 85.0))
        let autonomic    = hrvRecoveryFactor(nightHRV: nightHRV, baseline: hrvBaseline)
        let hourlyCharge = sleepQuality * autonomic * 6.5 * (sleepDurationH / max(windowH, 1.0))

        // Drenaje por carga de entrenamiento repartido por hora (estilo EPOC de
        // Firstbeat): cada sesión drena según su TRIMP, no según el promedio de FC
        // (que se diluye en el gimnasio). En las horas cubiertas manda esto.
        let ftp = TrainingMetrics.estimateFTP(from: activities)
        var activityDrainByHour: [Int: Double] = [:]
        for act in activities {
            let load = TrainingMetrics.sessionLoad(act, ftp: ftp, restingHR: restingHR,
                                                   maxHR: maxHR, isMale: UserProfile.isMale)
            let drain = activityDrain(trimp: load)
            let startH = cal.component(.hour, from: act.startDate)
            let spanH = max(1, Int(ceil(Double(act.movingTime) / 3600.0)))
            let endH = min(23, startH + spanH - 1)
            let perHour = drain / Double(endH - startH + 1)
            for h in startH...endH { activityDrainByHour[h, default: 0] += perHour }
        }

        var battery = startBattery
        var result: [MetricSample] = []

        for hour in 0...maxHour {
            let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day

            let isAsleep: Bool
            let hoursIntoSleep: Double
            if sleepHour >= wakeHour {
                // La noche cruza medianoche: duermes tanto antes como después de las 00:00
                isAsleep = hour < wakeHour || hour >= sleepHour
                hoursIntoSleep = hour >= sleepHour
                    ? Double(hour - sleepHour)
                    : Double(24 - sleepHour + hour)
            } else {
                isAsleep = hour >= sleepHour && hour < wakeHour
                hoursIntoSleep = isAsleep ? Double(hour - sleepHour) : 0
            }

            if isAsleep {
                // Más carga al principio de la noche (sueño profundo); la media del
                // factor es 1.0, así que el total de la noche se conserva.
                let progress = min(1.0, max(0.0, hoursIntoSleep / max(windowH, 1.0)))
                battery += hourlyCharge * (1.3 - 0.6 * progress)
            } else {
                let hourlyDelta: Double
                if let actDrain = activityDrainByHour[hour] {
                    // Hora de entreno: manda la carga de la sesión (no la FC diluida)
                    hourlyDelta = -actDrain
                } else if let hr = hourlyHR.first(where: { cal.component(.hour, from: $0.date) == hour }) {
                    let hrr = max(0.0, min(1.0, (hr.value - restingHR) / (maxHR - restingHR)))
                    // Firstbeat/Garmin: DESPIERTO la batería solo BAJA — estar despierto ya
                    // tiene un coste, aunque estés sentado con FC baja. La recarga real ocurre
                    // durmiendo, no de día. (Un día sedentario no debe "recuperar" batería.)
                    if hrr < 0.12 {
                        hourlyDelta = -1.0    // en reposo pero despierto: consumo basal lento
                    } else if hrr < 0.25 {
                        hourlyDelta = -1.8    // vida diaria normal (trabajo, andar por casa)
                    } else if hrr < 0.40 {
                        hourlyDelta = -hrr * hrr * 16.0
                    } else {
                        hourlyDelta = -hrr * hrr * 38.0  // ejercicio sin registrar como actividad
                    }
                } else {
                    hourlyDelta = -0.8        // sin datos de FC: consumo basal
                }
                // El drenaje es más rápido con la batería alta y se frena cerca del suelo.
                battery += hourlyDelta * max(0.35, battery / 100.0)
            }

            // Garmin/Firstbeat acotan Body Battery en 5-100 (nunca llega a 0)
            battery = max(5.0, min(100.0, battery))
            result.append(MetricSample(date: date, value: battery))
        }

        return result
    }

    // MARK: - Persistencia

    func storedValue(for date: Date) -> Double? {
        let dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        return dict[dateKey(date)]
    }

    private func storeValue(_ value: Double, for date: Date) {
        var dict = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] ?? [:]
        dict[dateKey(date)] = value
        if let cutoff = cal.date(byAdding: .day, value: -30, to: date) {
            dict = dict.filter { k, _ in parseKey(k).map { $0 >= cutoff } ?? false }
        }
        UserDefaults.standard.set(dict, forKey: storageKey)
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func parseKey(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
