import SwiftUI

// MARK: - Recovery Detail

struct RecoveryDetailView: View {
    let score: RecoveryScore?
    let history: [MetricSample]
    let color: Color
    let hrvHistory: [HRVData]
    let rhrHistory: [MetricSample]
    let todayRHR: Double?

    // Consejo IA con los datos reales de recuperación
    private func recoveryAdvice() async throws -> String {
        var lines: [String] = []
        if let s = score {
            lines.append("Recuperación hoy: \(s.value)/100 (sub-puntuaciones sobre 100, NO son bpm ni ms — HRV: \(s.hrvScore)/100, FC reposo: \(s.restingHRScore)/100, sueño: \(s.sleepScore)/100, carga: \(s.trainingLoadScore)/100).")
        }
        if let hrv = hrvHistory.first { lines.append("HRV hoy: \(Int(hrv.sdnn)) ms.") }
        let hrvVals = hrvHistory.prefix(14).map(\.sdnn)
        if hrvVals.count >= 3 {
            let mean = hrvVals.reduce(0, +) / Double(hrvVals.count)
            lines.append("HRV media 14 días: \(Int(mean.rounded())) ms.")
        }
        if let rhr = todayRHR { lines.append("FC en reposo hoy: \(Int(rhr)) bpm.") }
        let rhrVals = rhrHistory.prefix(14).map(\.value)
        if rhrVals.count >= 3 {
            let mean = rhrVals.reduce(0, +) / Double(rhrVals.count)
            lines.append("FC reposo media 14 días: \(Int(mean.rounded())) bpm.")
        }
        if history.count >= 3 {
            let recent = history.suffix(7).map { String(Int($0.value)) }
            lines.append("Recuperación últimos días: \(recent.joined(separator: "→")).")
        }
        let system = AIPrompts.recovery
        return try await AIService.shared.rawCompletion(prompt: lines.joined(separator: "\n"), system: system, maxTokens: 400)
    }

    private var todayHRV: Double? { hrvHistory.first?.sdnn }
    private var hrvBaseline: Double? {
        guard hrvHistory.count >= 3 else { return nil }
        let vals = hrvHistory.map(\.sdnn)
        return vals.reduce(0, +) / Double(vals.count)
    }
    private var rhrBaseline: Double? {
        guard rhrHistory.count >= 3 else { return nil }
        let vals = rhrHistory.map(\.value)
        return vals.reduce(0, +) / Double(vals.count)
    }

    private var hrvPct: Int {
        guard let t = todayHRV, let b = hrvBaseline, b > 0 else { return 50 }
        return max(0, min(100, Int((t / b) * 100)))
    }
    private var rhrPct: Int {
        // Invertido: RHR más baja = mejor = más porcentaje
        guard let t = todayRHR, let b = rhrBaseline, b > 0 else { return 50 }
        let ratio = b / t  // >1 si FC hoy < baseline (bien)
        return max(0, min(100, Int(ratio * 100)))
    }

    private var hrvSamples: [MetricSample] {
        hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HeroCard(value: score?.value ?? 0, label: "Recuperación",
                         icon: "arrow.up.heart.fill", color: color,
                         subtitle: score?.label ?? "--")

                // HRV block
                MetricProgressBlock(
                    title: "Variabilidad FC (HRV)",
                    icon: "waveform.path.ecg", color: .green,
                    todayValue: todayHRV.map { "\(Int($0)) ms" } ?? "--",
                    baselineValue: hrvBaseline.map { "media \(Int($0)) ms" } ?? "",
                    pct: hrvPct,
                    higherBetter: true,
                    samples: hrvSamples,
                    unit: "ms"
                )

                // RHR block
                MetricProgressBlock(
                    title: "FC en reposo",
                    icon: "heart.fill", color: .red,
                    todayValue: todayRHR.map { "\(Int($0)) ppm" } ?? "--",
                    baselineValue: rhrBaseline.map { "media \(Int($0)) ppm" } ?? "",
                    pct: rhrPct,
                    higherBetter: false,
                    samples: rhrHistory.sorted { $0.date < $1.date },
                    unit: "ppm"
                )

                // Factores — pesos reales del score (HRV 70% + FC reposo 30%,
                // metodología PeakWatch). Sueño y carga se muestran como contexto:
                // alimentan Body Battery y las alertas, no este score.
                if let s = score {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Composición del score").font(.headline)
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                        FactorBarRow(label: "HRV", icon: "waveform.path.ecg", color: .green,
                                     value: s.hrvScore, weight: "70%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "FC reposo", icon: "heart.fill", color: .red,
                                     value: s.restingHRScore, weight: "30%")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Sueño", icon: "moon.fill", color: .indigo,
                                     value: s.sleepScore, weight: "contexto")
                        Divider().padding(.leading, 52)
                        FactorBarRow(label: "Carga", icon: "figure.run", color: .orange,
                                     value: s.trainingLoadScore, weight: "contexto")
                        Text("El score compara HRV y FC en reposo de hoy contra tu baseline de 60 días. Sueño y carga influyen en Body Battery, no en este número.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                AITextCard(
                    title: "Cómo mejorar tu recuperación",
                    subtitle: "Claude lee tu HRV, FC en reposo y su tendencia y te da el siguiente paso.",
                    cacheKey: "apex_recovery_tips_\(aiDayKey(Date()))_\(score?.value ?? 0)",
                    generate: { try await recoveryAdvice() }
                )
            }
            .padding(.top).padding(.bottom, 32).padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recuperación").navigationBarTitleDisplayMode(.inline)
    }
}

