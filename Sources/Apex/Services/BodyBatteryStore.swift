import Foundation
import SwiftUI

// Body Battery estilo PeakWatch (doc.peakwatch.co/en/battery.html):
// - El valor del final del día es el punto de partida del día siguiente
// - El sueño carga en función del Recovery Score y de la duración real dormida
// - El estrés físico (FC sobre reposo) depleciona; estrés muy bajo recarga levemente
// - Cargar/descargar cuesta más cerca de los límites (factor asimétrico)
//
// PeakWatch no publica fórmulas exactas; las constantes de carga/descarga de este
// fichero son calibración propia de Apex documentada en cada línea.
final class BodyBatteryStore {
    static let shared = BodyBatteryStore()
    private let storageKey = "apex_body_battery_snapshots"
    private let cal = Calendar.current

    private init() {}

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
        activities: [StravaActivity] = []
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
            let sim = simulateDay(
                day: day,
                recovery: recovery(for: day),
                hourlyHR: dayHR,
                sleep: sleep,
                startBattery: battery,
                restingHR: rhr,
                activities: dayActs
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
        activities: [StravaActivity] = []
    ) -> Int {
        let samples = hourlyBattery(recoveryScore: recoveryScore, sleepHistory: sleepHistory,
                                    hourlyHR: hourlyHR, restingHR: restingHR,
                                    recoveryHistory: recoveryHistory, activities: activities)
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

    // Simulación reutilizable para cualquier día (se usa también en el detalle histórico)
    func simulateDay(
        day: Date,
        recovery: Double,
        hourlyHR: [MetricSample],
        sleep: SleepData?,
        startBattery: Double,
        restingHR: Double,
        activities: [StravaActivity] = []
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

        // Carga de sueño ADITIVA (estilo Firstbeat): una noche completa de calidad
        // (~8 h) recarga ~50 pts (≈6.5/h); el sueño corto o de baja calidad carga en
        // proporción. Se parte de la batería con la que te acostaste (drenada por el
        // día y el entreno) y se le SUMA la recarga — no se ancla al Recovery, para
        // no arrastrar su valor. Así una noche corta tras entrenar deja una batería
        // moderada, no llena.
        let sleepQuality  = max(0.4, min(1.0, Double(sleep?.score ?? 60) / 85.0))
        let sleepCharge   = sleepQuality * sleepDurationH * 6.5
        let wakeupBattery = max(0.0, min(100.0, startBattery + sleepCharge))

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
                isAsleep = hour < wakeHour
                hoursIntoSleep = Double(24 - sleepHour + hour)
            } else {
                isAsleep = hour >= sleepHour && hour < wakeHour
                hoursIntoSleep = isAsleep ? Double(hour - sleepHour) : 0
            }

            if isAsleep {
                // Curva logarítmica: carga rápida al inicio de la noche, se aplana al final
                let progress = min(1.0, hoursIntoSleep / windowH)
                battery = startBattery + (wakeupBattery - startBattery) * Foundation.log10(1.0 + 9.0 * progress)
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
