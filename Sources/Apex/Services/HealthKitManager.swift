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
    @Published var bodyComposition: BodyCompositionData?
    @Published var heartRateZones: [HeartRateZone] = []
    @Published var restingHRHistory: [MetricSample] = []

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .vo2Max,
            .stepCount, .activeEnergyBurned, .respiratoryRate,
            .appleSleepingWristTemperature, .timeInDaylight,
            .bodyMass, .bodyMassIndex
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
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
        async let hrv = fetchHRVLast30Days()
        async let rhr = fetchLatestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let rhrHistory = fetchQuantitySamples(.restingHeartRate, days: 30, unit: .count().unitDivided(by: .minute()))
        async let vo2 = fetchVO2MaxHistory()
        async let steps = fetchTodaySteps()
        async let calories = fetchTodayActiveCalories()
        async let respiratory = fetchRespiratoryData()
        async let wristTemp = fetchWristTempData()
        async let daylight = fetchDaylightData()
        async let body = fetchBodyComposition()

        let (sleepData, hrvData, rhrVal, rhrHist, vo2Data, stepsVal, calsVal, respData, wtData, dlData, bodyData) =
            await (sleep, hrv, rhr, rhrHistory, vo2, steps, calories, respiratory, wristTemp, daylight, body)

        sleepHistory = sleepData
        hrvHistory = hrvData
        vo2MaxData = vo2Data
        respiratoryData = respData
        wristTempData = wtData
        daylightData = dlData
        bodyComposition = bodyData
        restingHRHistory = rhrHist

        let recovery = computeRecovery(sleep: sleepData.first, hrv: hrvData.first, rhr: rhrVal)
        recoveryScore = recovery

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
        var byDay: [DateComponents: [HKCategorySample]] = [:]
        for sample in samples {
            let key = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
            byDay[key, default: []].append(sample)
        }
        return byDay.compactMap { key, daySamples -> SleepData? in
            guard let date = calendar.date(from: key) else { return nil }
            var deep: TimeInterval = 0; var rem: TimeInterval = 0
            var core: TimeInterval = 0; var awake: TimeInterval = 0
            for sample in daySamples {
                let d = sample.endDate.timeIntervalSince(sample.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepDeep: deep += d
                case .asleepREM: rem += d
                case .asleepCore, .asleepUnspecified: core += d
                case .awake: awake += d
                default: break
                }
            }
            let total = deep + rem + core
            guard total > 3600 else { return nil }
            return SleepData(date: date, totalSleep: total, deepSleep: deep, remSleep: rem, coreSleep: core, awake: awake)
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

    private func fetchHRVLast30Days() async -> [HRVData] {
        let samples = await fetchQuantitySamples(.heartRateVariabilitySDNN, days: 30, unit: HKUnit(from: "ms"))
        return samples.map { HRVData(date: $0.date, sdnn: $0.value) }.reversed()
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

    private func computeRecovery(sleep: SleepData?, hrv: HRVData?, rhr: Double?) -> RecoveryScore {
        let sleepScore = sleep.map { min($0.score, 100) } ?? 50
        let hrvScore: Int
        if let sdnn = hrv?.sdnn {
            hrvScore = min(Int(sdnn / 60.0 * 100), 100)
        } else {
            hrvScore = 50
        }
        let rhrScore: Int
        if let rhr {
            rhrScore = rhr < 50 ? 100 : rhr < 60 ? 85 : rhr < 70 ? 65 : rhr < 80 ? 40 : 20
        } else {
            rhrScore = 50
        }
        let trainingScore = 60
        let composite = Int(Double(sleepScore) * 0.35 + Double(hrvScore) * 0.35 + Double(rhrScore) * 0.15 + Double(trainingScore) * 0.15)
        return RecoveryScore(value: composite, sleepScore: sleepScore, hrvScore: hrvScore, trainingLoadScore: trainingScore, restingHRScore: rhrScore)
    }
}
