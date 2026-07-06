import Foundation

struct WatchDashboardData: Codable {
    var battery: Int = 0
    var recovery: Int = 0
    var recoveryLabel: String = "--"
    var sleepHours: Double = 0
    var sleepScore: Int = 0
    var hrv: Double = 0
    var rhr: Double = 0
    var kcal: Double = 0
    var atl: Double = 0
    var ctl: Double = 0
    var tsb: Double = 0
    var recentActivities: [WatchActivity] = []
    var updatedAt: Date = Date()
}

struct WatchActivity: Codable, Identifiable {
    var id: String
    var name: String
    var emoji: String
    var durationSeconds: Int
    var distanceMeters: Double
    var date: Date
}
