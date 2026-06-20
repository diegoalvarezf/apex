import Foundation
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()
    @Published var isAuthorized = false
    @Published var todaySummary: DailyHealthSummary?
    @Published var sleepHistory: [SleepData] = []
    @Published var hrvHistory: [HRVData] = []
    @Published var recoveryScore: RecoveryScore?

    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .vo2Max,
            .stepCount,
            .activeEnergyBurned
        ]
        for id in quantityTypes {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }()

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
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
        async let rhr = fetchRestingHR()
        async let vo2 = fetchVO2Max()
        async let steps = fetchTodaySteps()
        async let calories = fetchTodayActiveCalories()

        let (sleepData, hrvData, rhrVal, vo2Val, stepsVal, calsVal) = await (sleep, hrv, rhr, vo2, steps, calories)

        sleepHistory = sleepData
        hrvHistory = hrvData

        let recovery = computeRecovery(sleep: sleepData.first, hrv: hrvData.first, rhr: rhrVal)
        recoveryScore = recovery

        todaySummary = DailyHealthSummary(
            date: Date(),
            sleep: sleepData.first,
            hrv: hrvData.first,
            restingHR: rhrVal,
            vo2Max: vo2Val,
            steps: stepsVal,
            activeCalories: calsVal,
            recovery: recovery
        )
    }

    private func fetchSleepLast7Days() async -> [SleepData] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let sleepData = Self.processSleepSamples(samples as? [HKCategorySample] ?? [])
                continuation.resume(returning: sleepData)
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

        return byDay.compactMap { (key, daySamples) -> SleepData? in
            guard let date = calendar.date(from: key) else { return nil }
            var deep: TimeInterval = 0
            var rem: TimeInterval = 0
            var core: TimeInterval = 0
            var awake: TimeInterval = 0

            for sample in daySamples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepDeep: deep += duration
                case .asleepREM: rem += duration
                case .asleepCore, .asleepUnspecified: core += duration
                case .awake: awake += duration
                default: break
                }
            }

            let total = deep + rem + core
            guard total > 3600 else { return nil }
            return SleepData(date: date, totalSleep: total, deepSleep: deep, remSleep: rem, coreSleep: core, awake: awake)
        }
        .sorted { $0.date > $1.date }
    }

    private func fetchHRVLast30Days() async -> [HRVData] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 30, sortDescriptors: [sort]) { _, samples, _ in
                let data = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HRVData(date: sample.startDate, sdnn: sample.quantity.doubleValue(for: .init(from: "ms")))
                }
                continuation.resume(returning: data)
            }
            store.execute(query)
        }
    }

    private func fetchRestingHR() async -> Double? {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: rhrType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                continuation.resume(returning: val)
            }
            store.execute(query)
        }
    }

    private func fetchVO2Max() async -> Double? {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: vo2Type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: val)
            }
            store.execute(query)
        }
    }

    private func fetchTodaySteps() async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
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
                let cals = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: cals)
            }
            store.execute(query)
        }
    }

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
        let trainingScore = 60  // placeholder until Strava data is integrated
        let composite = Int(Double(sleepScore) * 0.35 + Double(hrvScore) * 0.35 + Double(rhrScore) * 0.15 + Double(trainingScore) * 0.15)
        return RecoveryScore(value: composite, sleepScore: sleepScore, hrvScore: hrvScore, trainingLoadScore: trainingScore, restingHRScore: rhrScore)
    }
}
