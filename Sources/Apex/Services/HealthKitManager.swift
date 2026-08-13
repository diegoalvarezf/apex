import Foundation
import HealthKit
import SwiftUI

@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySummary: DailyHealthSummary?
    @Published var sleepHistory: [SleepData] = []
    @Published var hrvHistory: [HRVData] = []
    @Published var recoveryScore: RecoveryScore?
    @Published var vo2MaxData: VO2MaxData?
    @Published var respiratoryData: RespiratoryData?
    @Published var wristTempData: WristTempData?
    @Published var daylightData: DaylightData?
    @Published var bloodOxygen: Double?         // SpO2 %
    @Published var bodyComposition: BodyCompositionData?
    @Published var heartRateZones: [HeartRateZone] = []
    @Published var restingHRHistory: [MetricSample] = []
    @Published var restingHRIsDerived = false   // true si la FC reposo se estimó de la FC (sin dato nativo)
    @Published var todayFlights: Int = 0        // pisos subidos hoy
    @Published var bloodOxygenHistory: [MetricSample] = []   // SpO2 30 días
    @Published var bodyFatPercent: Double?      // % grasa corporal (báscula inteligente)
    @Published var leanBodyMassKg: Double?      // masa magra en kg
    @Published var recoveryHistory: [MetricSample] = []
    @Published var biologicalAge: BiologicalAgeResult?
    @Published var sleepAge: SleepAgeResult?
    // Muestras de FC por hora del día de hoy (para gráficas horarias)
    @Published var recentHourlyHR: [MetricSample] = []  // últimos 7 días, una muestra por hora

    // Actualizado por DashboardViewModel tras cargar actividades Strava
    private var stravaTrainingScore: Int? = nil

    // Últimas entradas guardadas para poder recomputar cuando llega el TSB de Strava
    private var lastSleep: SleepData? = nil
    private var lastHRV: HRVData? = nil
    private var lastRHR: Double? = nil
    private var lastWorkoutCals: Double = 0

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .vo2Max,
            .stepCount, .flightsClimbed, .activeEnergyBurned, .respiratoryRate,
            .appleSleepingWristTemperature, .timeInDaylight,
            .bodyMass, .bodyMassIndex, .heartRate, .oxygenSaturation,
            .bodyFatPercentage, .leanBodyMass
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        // Characteristic types for bio age
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        return types
    }()

    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let w = HKQuantityType.quantityType(forIdentifier: .bodyMass) { types.insert(w) }
        if let b = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) { types.insert(b) }
        return types
    }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            await loadAll()
            return true
        } catch {
            return false
        }
    }

    func loadAll() async {
        async let sleep = fetchSleepLast7Days()
        async let hrv = fetchHRVLast60Days()
        async let rhr = fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let rhrHistory = fetchQuantitySamples(.restingHeartRate, days: 60, unit: .count().unitDivided(by: .minute()))
        async let vo2 = fetchVO2MaxHistory()
        async let steps = fetchTodaySteps()
        async let calories = fetchTodayActiveCalories()
        async let recentWorkoutCalories = fetchRecentWorkoutCalories()
        async let respiratory = fetchRespiratoryData()
        async let wristTemp = fetchWristTempData()
        async let daylight = fetchDaylightData()
        async let body = fetchBodyComposition()
        async let hourlyHR = fetchRecentHourlyHR()
        async let spo2 = fetchLatestQuantity(.oxygenSaturation, unit: .percent())
        async let maxHR30 = fetchMaxHR30Days()
        async let rhrDerivedSeries = fetchRestingHRSeries()
        async let flights = fetchTodayFlights()
        async let spo2Hist = fetchQuantitySamples(.oxygenSaturation, days: 30, unit: .percent())
        async let bodyFat = fetchLatestQuantity(.bodyFatPercentage, unit: .percent())
        async let leanMass = fetchLatestQuantity(.leanBodyMass, unit: .gramUnit(with: .kilo))

        let (sleepData, hrvData, rhrRaw, rhrHistRaw, vo2Data, stepsVal, calsVal, respData, wtData, dlData, bodyData, workoutCals, hrByHour, spo2Val, maxHRVal, rhrSeries) =
            await (sleep, hrv, rhr, rhrHistory, vo2, steps, calories, respiratory, wristTemp, daylight, body, recentWorkoutCalories, hourlyHR, spo2, maxHR30, rhrDerivedSeries)

        // FC en reposo: la de HealthKit si existe; si no, la derivada de la FC real
        // (mediana de mínimos diarios). El baseline z-score usa el histórico real y,
        // en su defecto, la serie derivada.
        let rhrVal = rhrRaw ?? Self.median(rhrSeries.map(\.value))
        let rhrHist = rhrHistRaw.isEmpty ? rhrSeries : rhrHistRaw
        restingHRIsDerived = rhrRaw == nil && rhrVal != nil
        todayFlights = await flights
        bloodOxygenHistory = await spo2Hist.map { MetricSample(date: $0.date, value: $0.value * 100) }
        bodyFatPercent = await bodyFat.map { $0 * 100 }   // HealthKit da 0-1
        leanBodyMassKg = await leanMass

        // Persistir para las calculadoras (TRIMP, zonas, battery):
        // FCmáx observada 30 días (metodología PeakWatch), FC reposo y sexo biológico
        if let m = maxHRVal, m > 100 {
            UserDefaults.standard.set(m, forKey: "user_observed_max_hr_30d")
        }
        if let r = rhrVal, r > 20 {
            UserDefaults.standard.set(r, forKey: "user_resting_hr")
        }
        if let sx = (try? store.biologicalSex())?.biologicalSex, sx != .notSet {
            UserDefaults.standard.set(sx != .female, forKey: "user_is_male")
        }

        sleepHistory = sleepData
        hrvHistory = hrvData
        vo2MaxData = vo2Data
        respiratoryData = respData
        wristTempData = wtData
        daylightData = dlData
        bodyComposition = bodyData
        restingHRHistory = rhrHist
        recentHourlyHR = hrByHour
        bloodOxygen = spo2Val.map { $0 * 100 }  // HealthKit devuelve 0-1, convertir a %

        // Guardar inputs para poder recomputar cuando llegue el TSB de Strava
        lastSleep = sleepData.first; lastHRV = hrvData.first
        lastRHR = rhrVal; lastWorkoutCals = workoutCals

        let recovery = computeRecovery(sleep: sleepData.first, hrv: hrvData.first, rhr: rhrVal, recentWorkoutCalories: workoutCals)
        recoveryScore = recovery

        // Historial de recovery score (último dato por día)
        let calendar = Calendar.current
        var byDay: [Date: (sleep: SleepData?, hrv: HRVData?)] = [:]
        for s in sleepData {
            let day = calendar.startOfDay(for: s.date)
            byDay[day, default: (nil, nil)].sleep = s
        }
        for h in hrvData {
            let day = calendar.startOfDay(for: h.date)
            byDay[day, default: (nil, nil)].hrv = h
        }
        recoveryHistory = byDay.map { date, pair in
            let score = computeRecovery(sleep: pair.sleep, hrv: pair.hrv, rhr: rhrVal, recentWorkoutCalories: workoutCals)
            return MetricSample(date: date, value: Double(score.value))
        }.sorted { $0.date < $1.date }

        todaySummary = DailyHealthSummary(
            date: Date(),
            sleep: sleepData.first,
            hrv: hrvData.first,
            restingHR: rhrVal,
            vo2Max: vo2Data?.current,
            steps: stepsVal,
            activeCalories: calsVal,
            recovery: recovery,
            respiratoryRate: respData?.current,
            wristTempDeviation: wtData?.deviation,
            daylightMinutes: dlData?.todayMinutes,
            weightKg: bodyData?.weightKg,
            bmi: bodyData?.bmi
        )

        // Sleep age
        if let dobComps = try? store.dateOfBirthComponents(),
           let dob = Calendar.current.date(from: dobComps) {
            let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
            sleepAge = SleepAgeResult.compute(chronologicalAge: age, sleep: sleepData.first)
        }

        // Biological age — con el VO2max solo si sigue vigente (si no, se estima)
        biologicalAge = computeBiologicalAge(
            vo2Max: vo2Data?.currentIfFresh,
            restingHR: rhrVal,
            hrv: hrvData.first?.sdnn,
            sleepScore: sleepData.first?.score,
            bmi: bodyData?.bmi
        )

        // Sincronizar perfil con datos de HealthKit (mismo actor, sin await)
        UserProfileManager.shared.syncFromHealthKit(
            weightKg: bodyData?.weightKg,
            chronologicalAge: biologicalAge?.chronologicalAge
        )

        // Programar notificaciones
        await NotificationManager.shared.checkStatus()
        NotificationManager.shared.scheduleWeeklySummary()
        if let score = recoveryScore {
            // highLoadDaysStreak se actualiza con más precisión en updateStravaTrainingLoad
            NotificationManager.shared.scheduleDailyRecovery(
                recovery: score.value,
                highLoadDaysStreak: 0
            )
        }
    }

    private func computeBiologicalAge(
        vo2Max: Double?,
        restingHR: Double?,
        hrv: Double?,
        sleepScore: Int?,
        bmi: Double?,
        weeklyActiveMinutes: Double? = nil,
        runBasedVO2Max: Double? = nil
    ) -> BiologicalAgeResult? {
        guard let dobComps = try? store.dateOfBirthComponents(),
              let dob = Calendar.current.date(from: dobComps) else { return nil }
        let age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
        guard age > 0 else { return nil }

        let sexObj = try? store.biologicalSex()
        let isMale = sexObj?.biologicalSex != .female

        return BiologicalAgeResult.compute(
            chronologicalAge: age,
            isMale: isMale,
            vo2Max: vo2Max,
            restingHR: restingHR,
            hrv: hrv,
            sleepScore: sleepScore,
            bmi: bmi,
            weeklyActiveMinutes: weeklyActiveMinutes,
            maxHR: UserProfile.effectiveMaxHR,
            runBasedVO2Max: runBasedVO2Max
        )
    }

    // MARK: - Sleep

    private func fetchSleepLast7Days() async -> [SleepData] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let data = Self.processSleepSamples(samples as? [HKCategorySample] ?? [])
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    nonisolated private static func processSleepSamples(_ samples: [HKCategorySample]) -> [SleepData] {
        let calendar = Calendar.current

        // Filtrar solo muestras de sueño reales (excluir inBed que no cuenta como dormido)
        let relevant = samples.filter {
            let v = HKCategoryValueSleepAnalysis(rawValue: $0.value)
            return v == .asleepDeep || v == .asleepREM || v == .asleepCore
                || v == .asleepUnspecified || v == .awake
        }.sorted { $0.startDate < $1.startDate }

        // Agrupar en sesiones de sueño: un hueco >4h significa nueva sesión
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd = Date.distantPast
        for s in relevant {
            if current.isEmpty || s.startDate.timeIntervalSince(currentEnd) < 4 * 3600 {
                current.append(s)
                if s.endDate > currentEnd { currentEnd = s.endDate }
            } else {
                sessions.append(current)
                current = [s]
                currentEnd = s.endDate
            }
        }
        if !current.isEmpty { sessions.append(current) }

        typealias Iv = (start: Date, end: Date)
        func mergedDuration(_ ivs: [Iv]) -> TimeInterval {
            var merged: [Iv] = []
            for iv in ivs.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, iv.start <= last.end {
                    merged[merged.count - 1] = (last.start, max(last.end, iv.end))
                } else { merged.append(iv) }
            }
            return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }

        return sessions.compactMap { sess -> SleepData? in
            // Atribuir la sesión al día en que el usuario SE DESPIERTA (igual que Apple Health)
            let wakeDate   = sess.map(\.endDate).max() ?? Date()
            let sleepStart = sess.map(\.startDate).min() ?? wakeDate
            let date = calendar.startOfDay(for: wakeDate)

            // Total de sueño: fusionar intervalos para eliminar solapamientos entre fuentes
            var sleepIvs: [Iv] = []
            var deep: TimeInterval = 0, rem: TimeInterval = 0
            var core: TimeInterval = 0, awake: TimeInterval = 0

            for s in sess {
                let d = s.endDate.timeIntervalSince(s.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
                case .asleepDeep:
                    deep += d
                    sleepIvs.append((s.startDate, s.endDate))
                case .asleepREM:
                    rem += d
                    sleepIvs.append((s.startDate, s.endDate))
                case .asleepCore, .asleepUnspecified:
                    core += d
                    sleepIvs.append((s.startDate, s.endDate))
                case .awake:
                    awake += d
                default: break
                }
            }

            // Usar intervalos fusionados como total real (evita doble conteo iPhone+Watch)
            let total = mergedDuration(sleepIvs)
            guard total > 3600 else { return nil }

            return SleepData(date: date, sleepStart: sleepStart, sleepEnd: wakeDate,
                             totalSleep: total, deepSleep: deep, remSleep: rem,
                             coreSleep: core, awake: awake)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Generic quantity fetchers

    private func fetchLatestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: val)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(_ id: HKQuantityTypeIdentifier, days: Int, unit: HKUnit) async -> [MetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: days, sortDescriptors: [sort]) { _, samples, _ in
                let data = (samples as? [HKQuantitySample] ?? []).map {
                    MetricSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    // MARK: - HRV

    private func fetchHRVLast60Days() async -> [HRVData] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -60, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        // Traer todas las muestras sin límite artificial (Apple Watch graba ~8-10/noche)
        let allSamples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, s, _ in
                cont.resume(returning: (s as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }

        // Agrupar por día y promediar — igual que Apple Health y PeakWatch
        var byDay: [Date: [Double]] = [:]
        for s in allSamples {
            let day = cal.startOfDay(for: s.startDate)
            byDay[day, default: []].append(s.quantity.doubleValue(for: HKUnit(from: "ms")))
        }

        return byDay
            .map { day, values in HRVData(date: day, sdnn: values.reduce(0, +) / Double(values.count)) }
            .sorted { $0.date > $1.date }  // más reciente primero
    }

    // MARK: - VO2Max

    private func fetchVO2MaxHistory() async -> VO2MaxData? {
        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        let samples = await fetchQuantitySamples(.vo2Max, days: 90, unit: unit)
        guard let latest = samples.last else { return nil }
        return VO2MaxData(current: latest.value, samples: samples)
    }

    // MARK: - Respiratory

    private func fetchRespiratoryData() async -> RespiratoryData? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = await fetchQuantitySamples(.respiratoryRate, days: 30, unit: unit)
        guard let latest = samples.last else { return nil }
        return RespiratoryData(current: latest.value, samples: samples)
    }

    // MARK: - Wrist temperature

    private func fetchWristTempData() async -> WristTempData? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples: [MetricSample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 30, sortDescriptors: [sort]) { _, s, _ in
                let data = (s as? [HKQuantitySample] ?? []).map {
                    MetricSample(date: $0.startDate, value: $0.quantity.doubleValue(for: .degreeCelsius()))
                }
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return nil }
        let baseline = samples.map(\.value).reduce(0, +) / Double(samples.count)
        let deviation = (samples.last?.value ?? baseline) - baseline
        return WristTempData(baseline: baseline, deviation: deviation, samples: samples)
    }

    // MARK: - Daylight

    private func fetchDaylightData() async -> DaylightData? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let interval = DateComponents(day: 1)
        let anchorDate = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, _ in
                guard let results else { continuation.resume(returning: nil); return }
                var samples: [MetricSample] = []
                results.enumerateStatistics(from: start, to: Date()) { stats, _ in
                    let minutes = (stats.sumQuantity()?.doubleValue(for: .minute()) ?? 0)
                    samples.append(MetricSample(date: stats.startDate, value: minutes))
                }
                let today = Int(samples.last?.value ?? 0)
                continuation.resume(returning: DaylightData(todayMinutes: today, samples: samples))
            }
            store.execute(query)
        }
    }

    // MARK: - Body composition

    private func fetchBodyComposition() async -> BodyCompositionData? {
        let weightSamples = await fetchQuantitySamples(.bodyMass, days: 90, unit: .gramUnit(with: .kilo))
        let bmiSamples = await fetchQuantitySamples(.bodyMassIndex, days: 90, unit: .count())
        let latestWeight = weightSamples.last?.value
        let latestBMI = bmiSamples.last?.value
        guard latestWeight != nil || latestBMI != nil else { return nil }
        return BodyCompositionData(weightKg: latestWeight, bmi: latestBMI, samples: weightSamples)
    }

    // MARK: - Steps / Calories

    private func fetchTodaySteps() async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            store.execute(query)
        }
    }

    private func fetchTodayFlights() async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0))
            }
            store.execute(query)
        }
    }

    private func fetchTodayActiveCalories() async -> Double {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Write weight

    func writeWeight(_ kg: Double, heightM: Double? = nil) async {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: Date(), end: Date()
        )
        try? await store.save(sample)
        if let h = heightM, let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            let bmi = BodyCompositionData.computeBMI(weightKg: kg, heightM: h)
            let bmiSample = HKQuantitySample(
                type: bmiType,
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: Date(), end: Date()
            )
            try? await store.save(bmiSample)
        }
        await loadAll()
    }

    // MARK: - Recovery score

    private func computeRecovery(sleep: SleepData?, hrv: HRVData?, rhr: Double?, recentWorkoutCalories: Double) -> RecoveryScore {
        // ── Sleep — score único anclado a AASM/NSF (SleepData.score) ──────────
        let sleepScore = sleep?.score ?? 50

        // ── HRV — z-score contra baseline 60 días ────────────────────────────
        // PeakWatch: baseline (z=0) = ~75 pts, no 50. Al estar en tu media de 60d
        // estás "bien" recuperado. Solo bajas de 50 si estás claramente por debajo.
        let hrvScore: Int
        if let sdnn = hrv?.sdnn {
            // Baseline = últimos 60 días EXCLUYENDO hoy (hoy se compara contra tu media)
            let todayStart = Calendar.current.startOfDay(for: Date())
            let history = hrvHistory.compactMap { $0.date < todayStart ? $0.sdnn : nil }
            if history.count >= 7 {
                let mean = history.reduce(0, +) / Double(history.count)
                let variance = history.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(history.count)
                let sd = max(sqrt(variance), 1.0)
                let z = (sdnn - mean) / sd
                // Calibrado con datos reales vs PeakWatch: en tu media (z=0) ≈ 50.
                // Pendiente 17 (comprime el extremo alto, que leía ~8 pts por encima).
                // z=+1 → 67, z=+2 → 84, z=-1 → 33
                let raw = 50.0 + z * 17.0
                hrvScore = max(0, min(100, Int(raw)))
            } else {
                hrvScore = sdnn > 80 ? 80 : sdnn > 60 ? 62 : sdnn > 40 ? 48 : sdnn > 25 ? 32 : 18
            }
        } else {
            hrvScore = 65
        }

        // ── FC reposo — z-score invertido ────────────────────────────────────
        let rhrScore: Int
        if let rhr {
            // Baseline = últimos 60 días EXCLUYENDO hoy
            let todayStart = Calendar.current.startOfDay(for: Date())
            let history = restingHRHistory.filter { $0.date < todayStart }.map(\.value)
            if history.count >= 7 {
                let mean = history.reduce(0, +) / Double(history.count)
                let variance = history.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(history.count)
                let sd = max(sqrt(variance), 0.5)
                let z = (rhr - mean) / sd   // positivo = peor (FC elevada)
                // Mismo centro/pendiente que el HRV: z=0 → 50, FC baja (z<0) sube el score
                let raw = 50.0 - z * 17.0
                rhrScore = max(0, min(100, Int(raw)))
            } else {
                rhrScore = rhr < 50 ? 82 : rhr < 55 ? 68 : rhr < 62 ? 54 : rhr < 70 ? 40 : 28
            }
        } else {
            rhrScore = 65
        }

        // ── Carga de entrenamiento (10%) ─────────────────────────────────────
        // Prioridad: TSB de Strava (ATL/CTL). Fallback: calorías activas 48h.
        let trainingScore: Int
        if let ss = stravaTrainingScore {
            trainingScore = ss
        } else {
            switch recentWorkoutCalories {
            case ..<300:      trainingScore = 80
            case 300..<500:   trainingScore = 65
            case 500..<700:   trainingScore = 50
            case 700..<900:   trainingScore = 35
            default:          trainingScore = 20
            }
        }

        // ── Consistencia circadiana (ajuste sobre sleepScore) ─────────────────
        // Varianza de hora de inicio de sueño últimos 7 días (en minutos)
        let recentStarts = sleepHistory.prefix(7).map { s -> Double in
            let c = Calendar.current.dateComponents([.hour, .minute], from: s.sleepStart)
            return Double((c.hour ?? 23) * 60 + (c.minute ?? 0))
        }
        var circadianAdj = 0
        if recentStarts.count >= 3 {
            let mean = recentStarts.reduce(0, +) / Double(recentStarts.count)
            let variance = recentStarts.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(recentStarts.count)
            let stdMinutes = sqrt(variance)
            // <15 min → +5 pts, 15-30 → 0, 30-60 → -5, >60 → -10
            if stdMinutes < 15 { circadianAdj = 5 }
            else if stdMinutes > 60 { circadianAdj = -10 }
            else if stdMinutes > 30 { circadianAdj = -5 }
        }
        let adjustedSleepScore = max(0, min(100, sleepScore + circadianAdj))

        // ── Preparación por SUEÑO (por duración real, no solo calidad) ───────
        // El déficit de sueño baja la disponibilidad aunque el HRV esté alto.
        let sleepReadiness: Double
        if let h = sleep.map({ $0.totalSleep / 3600.0 }) {
            switch h {
            case ..<4.5: sleepReadiness = 25
            case ..<5.5: sleepReadiness = 40
            case ..<6.0: sleepReadiness = 52
            case ..<6.5: sleepReadiness = 63
            case ..<7.0: sleepReadiness = 74
            case ..<7.5: sleepReadiness = 86
            default:     sleepReadiness = 95
            }
        } else {
            sleepReadiness = 60
        }

        // ── Composición tipo "readiness" (Whoop / Oura / Garmin) ─────────────
        // El HRV manda (estado autonómico), pero el sueño insuficiente y la carga
        // aguda elevada bajan la disponibilidad. Ya no es HRV+RHR puro: una noche
        // corta o la sobrecarga templan el score aunque el HRV esté alto.
        let composite = Int(
            Double(hrvScore)      * 0.45 +
            Double(rhrScore)      * 0.15 +
            sleepReadiness        * 0.25 +
            Double(trainingScore) * 0.15
        )

        return RecoveryScore(
            value: max(0, min(100, composite)),
            sleepScore: adjustedSleepScore,
            hrvScore: hrvScore,
            trainingLoadScore: trainingScore,
            restingHRScore: rhrScore
        )
    }

    // Llamado por DashboardViewModel tras cargar actividades Strava
    func updateBiologicalAgeActivity(weeklyMinutes: Double, activities: [StravaActivity] = []) {
        let rhr = todaySummary?.restingHR
        // Si el reloj no escribe el VO2max en Salud (o lo que hay ya caducó), se
        // estima con las carreras: ritmo y FC dan una lectura de hoy, no de hace meses.
        let porCarreras = VO2MaxEstimator.estimate(
            from: activities,
            restingHR: rhr ?? UserProfile.restingHR,
            maxHR: UserProfile.effectiveMaxHR
        )
        biologicalAge = computeBiologicalAge(
            vo2Max: vo2MaxData?.currentIfFresh ?? todaySummary?.vo2Max,
            restingHR: rhr,
            hrv: hrvHistory.first?.sdnn,
            sleepScore: sleepHistory.first?.score,
            bmi: bodyComposition?.bmi,
            weeklyActiveMinutes: weeklyMinutes,
            runBasedVO2Max: porCarreras
        )
    }

    func updateStravaTrainingLoad(_ load: TrainingLoad) {
        stravaTrainingScore = acwrToScore(load.acwr)
        let score = computeRecovery(
            sleep: lastSleep, hrv: lastHRV,
            rhr: lastRHR, recentWorkoutCalories: lastWorkoutCals
        )
        recoveryScore = score

        // Reprogramar notificación con info de carga actualizada
        Task { @MainActor in
            await NotificationManager.shared.checkStatus()
            if let s = recoveryScore {
                // ACWR > 1.3 durante varios días consecutivos = racha de carga elevada
                let highLoadStreak = load.acwr > 1.3 ? 3 : 0
                NotificationManager.shared.scheduleDailyRecovery(
                    recovery: s.value,
                    highLoadDaysStreak: highLoadStreak
                )
            }
        }
    }

    // ACWR zones: <0.8 undertrained, 0.8-1.3 optimal, 1.3-1.5 elevated, >1.5 overreached
    // Curva continua: máximo en la zona óptima baja (0.8-1.1) y descenso progresivo
    // al acercarse al límite, para que 1.2-1.3 ya reste algo (no salte de 90 a 50).
    private func acwrToScore(_ acwr: Double) -> Int {
        switch acwr {
        case ..<0.8:     return 65  // Poco cargado — sin fatiga pero poco estímulo
        case 0.8..<1.1:  return 90  // Zona óptima
        case 1.1..<1.3:  return Int((90 - (acwr - 1.1) / 0.2 * 25).rounded())  // 90→65
        case 1.3..<1.5:  return Int((65 - (acwr - 1.3) / 0.2 * 30).rounded())  // 65→35
        default:         return 20  // Sobreentrenado — riesgo
        }
    }

    // FC por hora — últimos 7 días, una muestra por hora exacta
    private func fetchRecentHourlyHR() async -> [MetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit = HKUnit.count().unitDivided(by: .minute())
        let rawSamples: [MetricSample] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, _ in
                let samples = (results as? [HKQuantitySample]) ?? []
                let mapped = samples.map { MetricSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
                continuation.resume(returning: mapped)
            }
            self.store.execute(q)
        }
        // Agrupar por hora exacta del día
        var byHour = [Date: [Double]]()
        for s in rawSamples {
            let comps = cal.dateComponents([.year, .month, .day, .hour], from: s.date)
            if let hourDate = cal.date(from: comps) {
                byHour[hourDate, default: []].append(s.value)
            }
        }
        return byHour.map { date, vals in
            MetricSample(date: date, value: vals.reduce(0, +) / Double(vals.count))
        }.sorted { $0.date < $1.date }
    }

    // FC en reposo derivada de la FC real cuando HealthKit no expone
    // `.restingHeartRate` (algunos relojes/pipelines no lo escriben). Metodología
    // equivalente a la de Apple: mínimo de FC de cada día y mediana de esos mínimos
    // → FC en reposo estable, robusta frente a lecturas atípicas. Devuelve la serie
    // diaria (para el baseline z-score del Recovery) además del valor mediano.
    private func fetchRestingHRSeries(days: Int = 14) async -> [MetricSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))!
        let unit = HKUnit.count().unitDivided(by: .minute())
        var interval = DateComponents(); interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                options: .discreteMin, anchorDate: cal.startOfDay(for: start),
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, results, _ in
                var series: [MetricSample] = []
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let m = stat.minimumQuantity()?.doubleValue(for: unit), m > 25, m < 120 {
                        series.append(MetricSample(date: stat.startDate, value: m))
                    }
                }
                cont.resume(returning: series.sorted { $0.date < $1.date })
            }
            self.store.execute(q)
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s[s.count / 2]
    }

    // FC máxima registrada en los últimos 30 días (PeakWatch: "the highest
    // recorded heart rate over the past 30 days" como FCmáx efectiva)
    private func fetchMaxHR30Days() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .discreteMax) { _, stats, _ in
                continuation.resume(returning: stats?.maximumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchRecentWorkoutCalories() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let start = Calendar.current.date(byAdding: .hour, value: -48, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: val)
            }
            store.execute(query)
        }
    }
}
