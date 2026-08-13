import SwiftUI
import Charts

// MARK: - Stress Detail

struct StressDetailView: View {
    let value: Int
    let history: [MetricSample]
    let color: Color
    let activities: [StravaActivity]
    let recentHourlyHR: [MetricSample]   // últimos 7 días
    let restingHR: Double?
    var hrvBase: Double = 30

    private let cal = Calendar.current

    private var availableDays: [Date] {
        (0...6).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
    }

    @State private var selectedPage: Int = 6

    var body: some View {
        VStack(spacing: 0) {
            // Navegación de día
            HStack {
                Button { if selectedPage > 0 { withAnimation { selectedPage -= 1 } } } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(selectedPage > 0 ? .primary : .secondary)
                }
                Spacer()
                Text(availableDays[selectedPage], format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).fontWeight(.semibold)
                    .contentTransition(.numericText())
                Spacer()
                Button { if selectedPage < 6 { withAnimation { selectedPage += 1 } } } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(selectedPage < 6 ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            TabView(selection: $selectedPage) {
                ForEach(availableDays.indices, id: \.self) { i in
                    DayStressPage(
                        day: availableDays[i],
                        todayValue: i == 6 ? value : dayStress(for: availableDays[i]),
                        hourlyHR: recentHourlyHR.filter { cal.isDate($0.date, inSameDayAs: availableDays[i]) },
                        restingHR: restingHR,
                        hrvBase: hrvBase,
                        color: color
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Estrés").navigationBarTitleDisplayMode(.inline)
    }

    private func dayStress(for day: Date) -> Int {
        let s = history.first { cal.isDate($0.date, inSameDayAs: day) }
        return Int(s?.value ?? Double(value))
    }
}

private struct DayStressPage: View {
    let day: Date
    let todayValue: Int
    let hourlyHR: [MetricSample]
    let restingHR: Double?
    var hrvBase: Double = 30
    let color: Color

    // Consejo IA con los datos reales de estrés
    private func stressAdvice() async throws -> String {
        var lines = [
            "Estrés fisiológico hoy: \(todayValue)/100.",
            "Base autonómica por HRV: \(Int(hrvBase.rounded()))/100 (más alta = HRV bajo frente a su media)."
        ]
        if let rhr = restingHR { lines.append("FC en reposo: \(Int(rhr)) bpm.") }
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        if let peak = hourlyHR.map(\.value).max() {
            lines.append("FC máxima del día: \(Int(peak)) bpm (FCmáx de referencia \(Int(maxHR))).")
        }
        let system = AIPrompts.stress
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private var stressLabel: String {
        todayValue < 30 ? "Bajo — sistema descansado"
            : todayValue < 60 ? "Moderado" : "Elevado — prioriza descanso"
    }

    private var hourlyStress: [MetricSample] {
        let rhr = restingHR ?? UserProfile.restingHR
        let maxHR = TrainingMetrics.observedMaxHR(hourlyHR: hourlyHR)
        return hourlyHR.map { s in
            let stress = TrainingMetrics.physiologicalStress(hr: s.value, restingHR: rhr, maxHR: maxHR, hrvBase: hrvBase)
            return MetricSample(date: s.date, value: stress)
        }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: todayValue, label: "Estrés", icon: "brain.head.profile",
                         color: color, subtitle: stressLabel)

                HourlyInteractiveChart(
                    samples: hourlyStress,
                    color: color,
                    unit: "",
                    higherIsBetter: false,
                    emptyText: "Sin datos de FC para este día.",
                    useBarMarks: true,
                    barColorFn: { v in v < 30 ? .green : v < 60 ? .orange : .red }
                )

                AITextCard(
                    title: "Cómo bajar tu estrés hoy",
                    subtitle: "Claude mira tu estrés, HRV y FC y te dice qué hacer hoy.",
                    cacheKey: "apex_stress_tips_\(aiDayKey(day))_\(todayValue)",
                    generate: { try await stressAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
    }
}

