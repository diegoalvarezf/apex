import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var stravaAuth: StravaAuthManager

    @State private var showProfile = false

    // Alertas del día: las escribe la IA (cacheadas 1×/día). Si aún no hay o falló
    // la llamada, se usan las reglas locales como red de seguridad.
    private var displayedTips: [SmartTip] {
        dashVM.aiAlerts.isEmpty ? smartTips : dashVM.aiAlerts.map(\.asSmartTip)
    }

    private var smartTips: [SmartTip] {
        SmartTipsEngine.compute(
            recovery: healthKit.recoveryScore,
            sleep: healthKit.sleepHistory.first,
            sleepHistory: healthKit.sleepHistory,
            hourlyHR: healthKit.recentHourlyHR,
            rhr: healthKit.todaySummary?.restingHR,
            rhrHistory: healthKit.restingHRHistory,
            hrvHistory: healthKit.hrvHistory,
            activities: dashVM.activities
        )
    }

    private func reloadStrava() async {
        guard let token = stravaAuth.accessToken else { return }
        await dashVM.loadActivities(token: token)
    }

    private func refreshWidget() {
        guard let score = healthKit.recoveryScore else { return }
        let battery = BodyBatteryStore.shared.currentBattery(
            recoveryScore: score,
            sleepHistory: healthKit.sleepHistory,
            hourlyHR: healthKit.recentHourlyHR,
            restingHR: healthKit.todaySummary?.restingHR,
            recoveryHistory: healthKit.recoveryHistory,
            activities: dashVM.activities,
            hrvHistory: healthKit.hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }
        )
        // Mismo cálculo de esfuerzo que el tile del dashboard (Edwards TRIMP diario)
        let rhr = healthKit.todaySummary?.restingHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: healthKit.recentHourlyHR)
        let effort = TrainingMetrics.effortScore(dailyTRIMP: TrainingMetrics.dailyEffortTRIMP(
            day: Date(), activities: dashVM.activities, hourlyHR: healthKit.recentHourlyHR,
            restingHR: rhr, maxHR: maxHR, isMale: UserProfile.isMale))
        UserProfileManager.shared.updateWidget(
            battery: battery,
            recovery: score.value,
            label: score.label,
            effort: effort,
            sleep: healthKit.sleepHistory.first?.score ?? 0
        )
    }

    private func sendToWatch() {
        let activities = dashVM.activities.prefix(5).map { act -> WatchActivity in
            let emoji: String
            switch act.sportType.lowercased() {
            case "run", "trail_run": emoji = "🏃"
            case "ride", "virtualride": emoji = "🚴"
            case "swim": emoji = "🏊"
            case "walk": emoji = "🚶"
            case "hike": emoji = "🥾"
            case "weighttraining", "workout": emoji = "🏋️"
            case "yoga": emoji = "🧘"
            default: emoji = "⚡"
            }
            return WatchActivity(
                id: String(act.id),
                name: act.name,
                emoji: emoji,
                durationSeconds: act.movingTime,
                distanceMeters: act.distance,
                date: act.startDate
            )
        }
        let dash = WatchDashboardData(
            battery: healthKit.recoveryScore?.value ?? 0,
            recovery: healthKit.recoveryScore?.value ?? 0,
            recoveryLabel: healthKit.recoveryScore?.label ?? "--",
            sleepHours: healthKit.sleepHistory.first.map { $0.totalSleep / 3600 } ?? 0,
            sleepScore: healthKit.sleepHistory.first?.score ?? 0,
            hrv: healthKit.hrvHistory.first?.sdnn ?? 0,
            rhr: healthKit.todaySummary?.restingHR ?? 0,
            kcal: healthKit.todaySummary?.activeCalories ?? 0,
            atl: dashVM.trainingLoad?.atl ?? 0,
            ctl: dashVM.trainingLoad?.ctl ?? 0,
            tsb: dashVM.trainingLoad?.tsb ?? 0,
            recentActivities: Array(activities),
            updatedAt: Date()
        )
        PhoneConnectivityManager.shared.send(dash)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                dashboardContent()
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                // En paralelo para que el spinner no se quede colgado
                async let health: Void = healthKit.loadAll()
                async let strava: Void = reloadStrava()
                _ = await (health, strava)
                // loadAlertsIfStale solo llama a la IA si las alertas NO son de hoy
                await dashVM.loadAlertsIfStale(health: healthKit)
            }
            .navigationTitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: dashVM.trainingLoad) { _, load in
                if let load = load { healthKit.updateStravaTrainingLoad(load) }
                sendToWatch()
            }
            .onChange(of: dashVM.activities.count) { _, _ in
                let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
                let recent = dashVM.activities.filter { $0.startDate >= cutoff }
                let weeklyMins = recent.reduce(0.0) { $0 + Double($1.movingTime) } / 60.0 / 4.0
                healthKit.updateBiologicalAgeActivity(weeklyMinutes: weeklyMins, activities: dashVM.activities)
                refreshWidget()
            }
            .onChange(of: healthKit.recoveryScore?.value) { _, _ in
                refreshWidget()
                sendToWatch()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showProfile = true } label: {
                        if let athlete = stravaAuth.athlete,
                           let profileURL = URL(string: athlete.profile) {
                            AsyncImage(url: profileURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Circle().fill(Color(UIColor.tertiarySystemFill))
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.title3).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileSheet()
            }
            .onAppear { refreshWidget() }
            .task { await dashVM.loadAlertsIfStale(health: healthKit) }
        }
    }

    @ViewBuilder
    private func dashboardContent() -> some View {
        // VStack (no Lazy): con LazyVStack el scroll se quedaba pillado al usar
        // "deslizar para recargar", porque el contenido se re-mide durante el gesto.
        VStack(spacing: 16) {
            if dashVM.isLoadingAlerts && dashVM.aiAlerts.isEmpty {
                AlertsLoadingBanner().padding(.horizontal)
            } else if !displayedTips.isEmpty {
                SmartTipBanner(
                    tips: displayedTips,
                    updatedAt: dashVM.aiAlertsAt,
                    isAI: !dashVM.aiAlerts.isEmpty,
                    isLoading: dashVM.isLoadingAlerts,
                    onRefresh: { Task { await dashVM.reloadAlerts(health: healthKit) } }
                ).padding(.horizontal)
            }
            metricsRow()
            sleepLink()
            if let load = dashVM.trainingLoad { trainingLoadLink(load: load) }
            quickMetrics()
            if !dashVM.activities.isEmpty {
                RecentActivitiesCard(activities: Array(dashVM.activities.prefix(3))).padding(.horizontal)
            }
            if dashVM.isLoadingActivities { ProgressView().padding() }
        }
        .padding(.top)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private func metricsRow() -> some View {
        StressRecoveryEffortRow(
            recoveryScore: healthKit.recoveryScore,
            recoveryHistory: healthKit.recoveryHistory,
            activities: dashVM.activities,
            hrvHistory: healthKit.hrvHistory,
            rhrHistory: healthKit.restingHRHistory,
            todayRHR: healthKit.todaySummary?.restingHR,
            hourlyHR: healthKit.recentHourlyHR,
            todayActiveKcal: healthKit.todaySummary?.activeCalories ?? 0,
            trainingLoad: dashVM.trainingLoad,
            sleep: healthKit.sleepHistory.first,
            sleepHistory: healthKit.sleepHistory
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private func quickMetrics() -> some View {
        QuickMetricsGrid(
            summary: healthKit.todaySummary,
            hrvHistory: healthKit.hrvHistory,
            vo2MaxData: healthKit.vo2MaxData,
            vo2Display: healthKit.displayVO2Max,
            respiratoryData: healthKit.respiratoryData,
            wristTempData: healthKit.wristTempData,
            daylightData: healthKit.daylightData,
            bloodOxygen: healthKit.bloodOxygen,
            rhrHistory: healthKit.restingHRHistory,
            bloodOxygenHistory: healthKit.bloodOxygenHistory
        )
    }

    @ViewBuilder
    private func sleepLink() -> some View {
        let h = healthKit.sleepHistory
        NavigationLink(destination: SleepDetailView(history: h)) {
            SleepCard(sleep: h.first).padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trainingLoadLink(load: TrainingLoad) -> some View {
        let acts = dashVM.activities
        let hist = dashVM.loadHistory
        NavigationLink(destination: TrainingLoadDetailView(load: load, activities: acts, loadHistory: hist)) {
            TrainingLoadCard(load: load).padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

private struct RecentActivitiesCard: View {
    let activities: [StravaActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Últimas actividades")
                    .font(.headline)
                Spacer()
                NavigationLink("Ver todas") {
                    ActivitiesView()
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                NavigationLink(destination: ActivityDetailView(activity: activity)) {
                    ActivityRowView(activity: activity)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                if index < activities.count - 1 {
                    Divider().padding(.leading, 72)
                }
            }
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
