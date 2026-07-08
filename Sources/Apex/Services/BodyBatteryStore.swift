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
        recoveryHistory: [MetricSample] = []
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
            let sim = simulateDay(
                day: day,
                recovery: recovery(for: day),
                hourlyHR: dayHR,
                sleep: sleep,
                startBattery: battery,
                restingHR: rhr
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
        recoveryHistory: [MetricSample] = []
    ) -> Int {
        let samples = hourlyBattery(recoveryScore: recoveryScore, sleepHistory: sleepHistory,
                                    hourlyHR: hourlyHR, restingHR: restingHR,
                                    recoveryHistory: recoveryHistory)
        return Int(samples.last?.value ?? Double(recoveryScore?.value ?? 0))
    }

    // Simulación reutilizable para cualquier día (se usa también en el detalle histórico)
    func simulateDay(
        day: Date,
        recovery: Double,
        hourlyHR: [MetricSample],
        sleep: SleepData?,
        startBattery: Double,
        restingHR: Double
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

        // Buen sueño carga por ENCIMA del recovery; sueño corto por debajo.
        // 8h → recovery+8 · 7h → +4 · 6h → 0 · 5h → −4 (límites ±15)
        let sleepBonus    = max(-15.0, min(15.0, (sleepDurationH - 6.0) * 4.0))
        let wakeupBattery = max(0.0, min(100.0, recovery + sleepBonus))

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
                // Cerca de 100 cuesta más cargar y se descarga más rápido; cerca de 0 al revés
                let depletionFactor = max(0.2, battery / 100.0)
                let hourlyDelta: Double
                if let hr = hourlyHR.first(where: { cal.component(.hour, from: $0.date) == hour }) {
                    let hrr = max(0.0, min(1.0, (hr.value - restingHR) / (maxHR - restingHR)))
                    if hrr < 0.10 {
                        hourlyDelta = +0.15   // reposo profundo: recarga leve
                    } else if hrr < 0.25 {
                        hourlyDelta = -0.4    // vida diaria tranquila
                    } else if hrr < 0.50 {
                        hourlyDelta = -hrr * hrr * 12.0
                    } else {
                        hourlyDelta = -hrr * hrr * 22.0  // ejercicio: drenaje cuadrático
                    }
                } else {
                    hourlyDelta = -0.3        // sin datos de FC: consumo basal
                }
                battery += hourlyDelta * depletionFactor
            }

            battery = max(0.0, min(100.0, battery))
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
