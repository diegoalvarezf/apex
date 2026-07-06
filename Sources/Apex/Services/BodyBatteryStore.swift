import Foundation
import SwiftUI

// Implementa Body Energy igual que PeakWatch:
// - El valor al final del día se persiste y es el punto de partida del día siguiente
// - El sueño carga la batería en función del Recovery Score
// - La actividad física la depleciona de forma asimétrica (más duro cerca de 100, más lento cerca de 0)

final class BodyBatteryStore {
    static let shared = BodyBatteryStore()
    private let storageKey = "apex_body_battery_snapshots"
    private let cal = Calendar.current

    private init() {}

    // MARK: - API pública

    func hourlyBattery(
        recoveryScore: RecoveryScore?,
        sleep: SleepData?,
        hourlyHR: [MetricSample],
        restingHR: Double?
    ) -> [MetricSample] {
        let recovery = Double(recoveryScore?.value ?? 65)
        let rhr      = restingHR ?? 55.0

        let yesterday    = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: Date()))!
        let startBattery = storedValue(for: yesterday) ?? min(95.0, recovery * 0.95)

        let result = simulateDay(
            day: Date(),
            recovery: recovery,
            hourlyHR: hourlyHR,
            sleep: sleep,
            startBattery: startBattery,
            restingHR: rhr
        )

        if let last = result.last { storeValue(last.value, for: Date()) }
        return result
    }

    func currentBattery(
        recoveryScore: RecoveryScore?,
        sleep: SleepData?,
        hourlyHR: [MetricSample],
        restingHR: Double?
    ) -> Int {
        let samples = hourlyBattery(recoveryScore: recoveryScore, sleep: sleep,
                                    hourlyHR: hourlyHR, restingHR: restingHR)
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
        let maxHR     = max(Double(UserProfile.maxHR), hourlyHR.map(\.value).max() ?? Double(UserProfile.maxHR))
        let wakeHour  = sleep.map { cal.component(.hour, from: $0.sleepEnd)   } ?? 7
        let sleepHour = sleep.map { cal.component(.hour, from: $0.sleepStart) } ?? 23
        let maxHour   = cal.isDateInToday(day) ? cal.component(.hour, from: Date()) : 23

        let totalSleepH: Double = sleepHour >= wakeHour
            ? max(1.0, Double(24 - sleepHour + wakeHour))
            : max(1.0, Double(wakeHour - sleepHour))

        // PeakWatch: buen sueño carga por ENCIMA del recovery.
        // 8h → recovery+8, 7h → recovery+4, 6h → recovery+0, 5h → recovery-4
        let sleepBonus    = max(-15.0, min(15.0, (totalSleepH - 6.0) * 4.0))
        let wakeupBattery = max(startBattery, min(100.0, recovery + sleepBonus))

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
                let progress = min(1.0, hoursIntoSleep / totalSleepH)
                battery = startBattery + (wakeupBattery - startBattery) * Foundation.log10(1.0 + 9.0 * progress)
            } else {
                // PeakWatch: estrés muy bajo → apenas depleciona o incluso recarga ligeramente.
                let depletionFactor = max(0.2, battery / 100.0)
                let hourlyDelta: Double
                if let hr = hourlyHR.first(where: { cal.component(.hour, from: $0.date) == hour }) {
                    let hrr = max(0.0, min(1.0, (hr.value - restingHR) / (maxHR - restingHR)))
                    if hrr < 0.10 {
                        hourlyDelta = +0.15
                    } else if hrr < 0.25 {
                        hourlyDelta = -0.4
                    } else if hrr < 0.50 {
                        hourlyDelta = -hrr * hrr * 12.0
                    } else {
                        hourlyDelta = -hrr * hrr * 22.0
                    }
                } else {
                    hourlyDelta = -0.3
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
