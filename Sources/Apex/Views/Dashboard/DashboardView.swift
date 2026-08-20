import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashVM: DashboardViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var stravaAuth: StravaAuthManager

    @State private var showProfile = false
    @State private var showCalendar = false

    // Alertas del día: las escribe la IA (cacheadas 1×/día). Si aún no hay o falló
    // la llamada, se usan las reglas locales como red de seguridad.
    private var displayedTips: [SmartTip] {
        dashVM.aiAlerts.isEmpty ? smartTips : dashVM.aiAlerts.map(\.asSmartTip)
    }

    private var smartTips: [SmartTip] {
        SmartTipsEngine.compute(
            recovery: healthKit.recoveryScore,
            sleep: healthKit.sleepHistory.last,
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

    // Mismo camino que la tarea en segundo plano, para que abrir la app y
    // despertarse solo produzcan exactamente lo mismo.
    private func refreshWidget() {
        DailyMetricsRecorder.recordToday(healthKit: healthKit, activities: dashVM.activities)
    }

    private func sendToWatch() {
        let activities = dashVM.activities.suffix(5).reversed().map { act -> WatchActivity in
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
            sleepHours: healthKit.sleepHistory.last.map { $0.totalSleep / 3600 } ?? 0,
            sleepScore: healthKit.sleepHistory.last?.score ?? 0,
            hrv: healthKit.hrvHistory.last?.sdnn ?? 0,
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
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCalendar) { MetricCalendarView() }
            .onChange(of: dashVM.trainingLoad) { _, load in
                if let load = load { healthKit.updateStravaTrainingLoad(load, history: dashVM.loadHistory) }
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
            // Con `id:` la tarea se repite cuando Strava termina de cargar: al abrir
            // la app llega antes aquí que las actividades, y sin repetirla las
            // alertas del día no se escribirían hasta el siguiente arranque.
            .task(id: dashVM.activitiesSettled) { await dashVM.loadAlertsIfStale(health: healthKit) }
        }
    }

    // Cabecera con la fecha y "Hoy" pulsable, que abre el calendario del mes. Se
    // hace a mano en lugar de con navigationTitle porque el título del sistema no
    // admite un botón dentro.
    private var dateHeader: some View {
        Button { showCalendar = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.month(.abbreviated).day().weekday(.wide))
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("Hoy")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dashboardContent() -> some View {
        // VStack (no Lazy): con LazyVStack el scroll se quedaba pillado al usar
        // "deslizar para recargar", porque el contenido se re-mide durante el gesto.
        VStack(spacing: 16) {
            dateHeader

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
                RecentActivitiesCard(activities: Array(dashVM.activities.suffix(3).reversed())).padding(.horizontal)
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
            sleep: healthKit.sleepHistory.last,
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
            vo2EstimatedSeries: healthKit.estimatedVO2Series,
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
            SleepCard(sleep: healthKit.latestSleep).padding(.horizontal)
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
