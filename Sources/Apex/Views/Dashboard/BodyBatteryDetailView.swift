import SwiftUI
import Charts

struct BodyBatteryDetailView: View {
    let score: RecoveryScore?
    let recentHourlyHR: [MetricSample]    // 7 días de FC por hora
    let restingHR: Double?
    let sleepHistory: [SleepData]
    let recoveryHistory: [MetricSample]   // score diario
    var activities: [StravaActivity] = []

    private let cal = Calendar.current

    // Días disponibles (de más antiguo a más reciente)
    private var availableDays: [Date] {
        (0...6).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
    }

    @State private var selectedPage: Int = 6  // hoy

    var body: some View {
        VStack(spacing: 0) {
            // Indicador de día
            HStack {
                Button {
                    if selectedPage > 0 { withAnimation { selectedPage -= 1 } }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(selectedPage > 0 ? .primary : .secondary)
                }

                Spacer()
                Text(availableDays[selectedPage], format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).fontWeight(.semibold)
                    .contentTransition(.numericText())
                Spacer()

                Button {
                    if selectedPage < 6 { withAnimation { selectedPage += 1 } }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(selectedPage < 6 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            // Páginas deslizables
            TabView(selection: $selectedPage) {
                ForEach(availableDays.indices, id: \.self) { i in
                    DayBatteryPage(
                        day: availableDays[i],
                        score: dayScore(for: availableDays[i]),
                        todayScore: score,
                        hourlyHR: hoursFor(day: availableDays[i]),
                        restingHR: restingHR,
                        sleep: sleepFor(day: availableDays[i]),
                        startBattery: startBattery(for: i),
                        activities: activities.filter { cal.isDate($0.startDate, inSameDayAs: availableDays[i]) }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Body Battery")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func hoursFor(day: Date) -> [MetricSample] {
        recentHourlyHR.filter { cal.isDate($0.date, inSameDayAs: day) }
    }
    private func sleepFor(day: Date) -> SleepData? {
        sleepHistory.first { cal.isDate($0.date, inSameDayAs: day) }
    }
    private func dayRecovery(for day: Date) -> Double {
        let s = recoveryHistory.first { cal.isDate($0.date, inSameDayAs: day) }
        return s?.value ?? Double(score?.value ?? 65)
    }
    private func dayScore(for day: Date) -> Int { Int(dayRecovery(for: day)) }

    // Batería al inicio del día i: usa la persistida si existe, si no simula encadenado
    private func startBattery(for index: Int) -> Double {
        let day = availableDays[index]
        // Para días históricos, intentar recuperar el valor almacenado de ese día
        if let stored = BodyBatteryStore.shared.storedValue(for: day) { return stored }
        guard index > 0 else {
            // Primer día sin historial: fallback conservador igual que BodyBatteryStore
            return min(95.0, dayRecovery(for: day) * 0.95)
        }
        let prevDay = availableDays[index - 1]
        let prev = BodyBatteryStore.shared.simulateDay(
            day: prevDay,
            recovery: dayRecovery(for: prevDay),
            hourlyHR: hoursFor(day: prevDay),
            sleep: sleepFor(day: prevDay),
            startBattery: startBattery(for: index - 1),
            restingHR: restingHR ?? 55.0
        )
        return prev.last?.value ?? min(95.0, dayRecovery(for: prevDay) * 0.95)
    }
}

// MARK: - Página de un día

private struct DayBatteryPage: View {
    let day: Date
    let score: Int
    let todayScore: RecoveryScore?
    let hourlyHR: [MetricSample]
    let restingHR: Double?
    let sleep: SleepData?
    let startBattery: Double
    var activities: [StravaActivity] = []

    private let cal = Calendar.current

    private var batteryColor: Color {
        let s = cal.isDateInToday(day) ? (todayScore?.systemColor ?? .blue) : scoreColor(score)
        return s
    }

    private func scoreColor(_ v: Int) -> Color {
        v >= 80 ? .green : v >= 60 ? .cyan : v >= 40 ? .orange : .red
    }

    private var hourlyBattery: [MetricSample] {
        if cal.isDateInToday(day) {
            // Para hoy: misma llamada que usa la card, garantiza valor idéntico
            return BodyBatteryStore.shared.hourlyBattery(
                recoveryScore: todayScore,
                sleep: sleep,
                hourlyHR: hourlyHR,
                restingHR: restingHR
            )
        }
        return BodyBatteryStore.shared.simulateDay(
            day: day,
            recovery: Double(score),
            hourlyHR: hourlyHR,
            sleep: sleep,
            startBattery: startBattery,
            restingHR: restingHR ?? 55.0
        )
    }

    private var currentBattery: Int { Int(hourlyBattery.last?.value ?? Double(score)) }

    private func activityColor(_ act: StravaActivity) -> Color {
        switch act.sportType.lowercased() {
        case "run", "trail_run", "virtualrun": return .red
        case "ride", "virtualride", "ebikeride": return .orange
        case "swim": return .cyan
        case "hike": return .green
        case "walk": return .teal
        case "weighttraining", "crossfit", "workout": return .purple
        default: return .orange
        }
    }

    @State private var selectedDate: Date? = nil

    private var selected: MetricSample? {
        guard let sel = selectedDate else { return hourlyBattery.last }
        return hourlyBattery.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // Hero del día
                HStack(spacing: 20) {
                    ZStack {
                        Circle().fill(batteryColor.opacity(0.12)).frame(width: 64, height: 64)
                        Image(systemName: "bolt.heart.fill").font(.system(size: 26))
                            .foregroundColor(batteryColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Body Battery").font(.subheadline).foregroundColor(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(currentBattery)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(batteryColor)
                                .contentTransition(.numericText())
                            Text("/ 100").font(.subheadline).foregroundColor(.secondary).offset(y: -4)
                        }
                        HStack(spacing: 6) {
                            if cal.isDateInToday(day) {
                                Text(todayScore?.label ?? "--").font(.caption).fontWeight(.medium)
                                    .foregroundColor(batteryColor)
                                Text("· Pico \(score)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Gráfica con zona de sueño
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom) {
                        if let s = selected {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.date, format: .dateTime.hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text("\(Int(s.value))")
                                        .font(.system(.title3, design: .rounded)).fontWeight(.bold)
                                        .foregroundColor(batteryColor)
                                    Text("/ 100").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            if let sl = sleep {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.fill").foregroundColor(.indigo).font(.caption2)
                                    Text(sl.sleepStart, format: .dateTime.hour().minute())
                                    Text("–")
                                    Text(sl.sleepEnd, format: .dateTime.hour().minute())
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                            ForEach(activities) { act in
                                HStack(spacing: 4) {
                                    Circle().fill(activityColor(act)).frame(width: 7, height: 7)
                                    Text(act.name).lineLimit(1)
                                    Text(act.startDate, format: .dateTime.hour().minute())
                                }
                                .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    if hourlyBattery.isEmpty {
                        Text("Sin datos de FC para este día.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 40)
                    } else {
                        Chart {
                            if let sl = sleep {
                                RectangleMark(
                                    xStart: .value("Inicio", sl.sleepStart),
                                    xEnd:   .value("Fin",   sl.sleepEnd),
                                    yStart: .value("Y0", 0), yEnd: .value("Y1", 100)
                                )
                                .foregroundStyle(Color.indigo.opacity(0.08))

                                PointMark(
                                    x: .value("Mid", sl.sleepStart.addingTimeInterval(sl.sleepEnd.timeIntervalSince(sl.sleepStart) / 2)),
                                    y: .value("Top", 94)
                                )
                                .annotation(position: .overlay) {
                                    Label("Sueño", systemImage: "moon.fill")
                                        .font(.system(size: 9)).foregroundColor(.indigo)
                                }
                            }

                            ForEach(activities) { act in
                                let actEnd = act.startDate.addingTimeInterval(Double(act.movingTime))
                                RectangleMark(
                                    xStart: .value("AStart", act.startDate),
                                    xEnd:   .value("AEnd",   actEnd),
                                    yStart: .value("Y0", 0), yEnd: .value("Y1", 100)
                                )
                                .foregroundStyle(activityColor(act).opacity(0.12))

                                PointMark(
                                    x: .value("AMid", act.startDate.addingTimeInterval(Double(act.movingTime) / 2)),
                                    y: .value("Top", 94)
                                )
                                .annotation(position: .overlay) {
                                    Label(act.sportEmoji, systemImage: "")
                                        .font(.system(size: 10))
                                        .labelStyle(.titleOnly)
                                }
                            }

                            ForEach(hourlyBattery) { s in
                                AreaMark(x: .value("H", s.date, unit: .hour), y: .value("B", s.value))
                                    .foregroundStyle(LinearGradient(
                                        colors: [batteryColor.opacity(0.25), batteryColor.opacity(0)],
                                        startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("H", s.date, unit: .hour), y: .value("B", s.value))
                                    .foregroundStyle(batteryColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(.catmullRom)
                            }

                            if let sel = selected {
                                PointMark(x: .value("H", sel.date, unit: .hour), y: .value("B", sel.value))
                                    .foregroundStyle(batteryColor).symbolSize(64)
                                RuleMark(x: .value("H", sel.date, unit: .hour))
                                    .foregroundStyle(batteryColor.opacity(0.3))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                                AxisValueLabel(format: .dateTime.hour())
                                    .font(.caption2).foregroundStyle(Color.secondary)
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                                    .foregroundStyle(Color.primary.opacity(0.07))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3]))
                                    .foregroundStyle(Color.primary.opacity(0.07))
                                AxisValueLabel().font(.caption2).foregroundStyle(Color.secondary)
                            }
                        }
                        .chartXSelection(value: $selectedDate)
                        .frame(height: 200)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Factores (solo hoy)
                if cal.isDateInToday(day), let s = todayScore {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Composición de hoy").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                        FactorBarRow(label: "Sueño", icon: "moon.fill", color: .indigo,
                                     value: s.sleepScore, weight: "30%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "HRV", icon: "waveform.path.ecg", color: .green,
                                     value: s.hrvScore, weight: "40%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "FC reposo", icon: "heart.fill", color: .red,
                                     value: s.restingHRScore, weight: "20%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Carga", icon: "figure.run", color: .orange,
                                     value: s.trainingLoadScore, weight: "10%")
                            .padding(.bottom, 8)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal).padding(.top, 12).padding(.bottom, 32)
        }
    }
}
