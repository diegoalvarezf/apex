import Foundation
import CoreLocation
import HealthKit

// MARK: - Sport type

enum WorkoutSportType: String, CaseIterable, Identifiable {
    case run = "Run"
    case ride = "Ride"
    case walk = "Walk"
    case hike = "Hike"
    case trailRun = "TrailRun"
    case weightTraining = "WeightTraining"
    case yoga = "Yoga"
    case swim = "Swim"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run:           return "Carrera"
        case .ride:          return "Ciclismo"
        case .walk:          return "Caminata"
        case .hike:          return "Senderismo"
        case .trailRun:      return "Trail"
        case .weightTraining: return "Pesas"
        case .yoga:          return "Yoga"
        case .swim:          return "Natación"
        }
    }

    var emoji: String {
        switch self {
        case .run:           return "🏃"
        case .ride:          return "🚴"
        case .walk:          return "🚶"
        case .hike:          return "🥾"
        case .trailRun:      return "🏔️"
        case .weightTraining: return "🏋️"
        case .yoga:          return "🧘"
        case .swim:          return "🏊"
        }
    }

    var isOutdoor: Bool {
        switch self {
        case .weightTraining, .yoga, .swim: return false
        default: return true
        }
    }

    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .run, .trailRun: return .running
        case .ride:           return .cycling
        case .walk:           return .walking
        case .hike:           return .hiking
        case .weightTraining: return .traditionalStrengthTraining
        case .yoga:           return .yoga
        case .swim:           return .swimming
        }
    }
}

// MARK: - Tracker

@MainActor
final class ActivityTracker: NSObject, ObservableObject {

    enum TrackingState { case idle, active, paused }

    @Published var state: TrackingState = .idle
    @Published var elapsedSeconds: Int = 0
    @Published var coordinates: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var currentPaceSecPerKm: Double = 0
    @Published var locationAuthorized = false

    private(set) var sport: WorkoutSportType = .run
    private var startDate = Date()
    private var pausedDuration: TimeInterval = 0
    private var pauseStart: Date?
    private var timer: Timer?
    private let locationManager = CLLocationManager()
    private var recentLocations: [CLLocation] = []
    private let store = HKHealthStore()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    func start(sport: WorkoutSportType) {
        self.sport = sport
        startDate = Date()
        elapsedSeconds = 0
        coordinates = []
        distanceMeters = 0
        currentPaceSecPerKm = 0
        recentLocations = []
        pausedDuration = 0
        state = .active

        if sport.isOutdoor { locationManager.startUpdatingLocation() }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
                self?.updatePace()
            }
        }
    }

    func pause() {
        guard state == .active else { return }
        state = .paused
        pauseStart = Date()
        locationManager.stopUpdatingLocation()
        timer?.invalidate(); timer = nil
    }

    func resume() {
        guard state == .paused else { return }
        if let ps = pauseStart { pausedDuration += Date().timeIntervalSince(ps) }
        state = .active
        if sport.isOutdoor { locationManager.startUpdatingLocation() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedSeconds += 1
                self?.updatePace()
            }
        }
    }

    func finish() async -> Bool {
        state = .idle
        locationManager.stopUpdatingLocation()
        timer?.invalidate(); timer = nil
        return await saveToHealthKit()
    }

    func cancel() {
        state = .idle
        locationManager.stopUpdatingLocation()
        timer?.invalidate(); timer = nil
    }

    private func updatePace() {
        let cutoff = Date().addingTimeInterval(-30)
        let recent = recentLocations.filter { $0.timestamp > cutoff }
        guard recent.count >= 2 else { return }
        var d: Double = 0
        for i in 1..<recent.count { d += recent[i].distance(from: recent[i - 1]) }
        let t = recent.last!.timestamp.timeIntervalSince(recent.first!.timestamp)
        guard t > 0, d > 0 else { return }
        currentPaceSecPerKm = (t / d) * 1000
    }

    private func saveToHealthKit() async -> Bool {
        var writeTypes: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) { writeTypes.insert(d) }
        if let d = HKQuantityType.quantityType(forIdentifier: .distanceCycling) { writeTypes.insert(d) }

        do { try await store.requestAuthorization(toShare: writeTypes, read: []) }
        catch { return false }

        let config = HKWorkoutConfiguration()
        config.activityType = sport.hkActivityType
        config.locationType = sport.isOutdoor ? .outdoor : .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let end = Date()

        do {
            try await builder.beginCollection(at: startDate)

            if sport.isOutdoor, distanceMeters > 0 {
                let typeID: HKQuantityTypeIdentifier = sport == .ride
                    ? .distanceCycling : .distanceWalkingRunning
                if let qType = HKQuantityType.quantityType(forIdentifier: typeID) {
                    let sample = HKQuantitySample(
                        type: qType,
                        quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                        start: startDate, end: end
                    )
                    try await builder.addSamples([sample])
                }
            }

            try await builder.endCollection(at: end)
            let _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension ActivityTracker: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard state == .active else { return }
            for loc in locations {
                guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 30 else { continue }
                if let last = recentLocations.last {
                    distanceMeters += loc.distance(from: last)
                }
                recentLocations.append(loc)
                coordinates.append(loc.coordinate)
                // Keep 5 min max for pace window
                let cutoff = Date().addingTimeInterval(-300)
                recentLocations = recentLocations.filter { $0.timestamp > cutoff }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthorized = manager.authorizationStatus == .authorizedWhenInUse ||
                                  manager.authorizationStatus == .authorizedAlways
        }
    }
}
