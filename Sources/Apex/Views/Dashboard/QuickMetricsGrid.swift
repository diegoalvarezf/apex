import SwiftUI

struct QuickMetricsGrid: View {
    let summary: DailyHealthSummary?
    let hrvHistory: [HRVData]
    let vo2MaxData: VO2MaxData?
    let respiratoryData: RespiratoryData?
    let wristTempData: WristTempData?
    let daylightData: DaylightData?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Métricas corporales")
                .font(.headline)
                .padding(.horizontal, 2)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // FC en reposo
                NavigationLink(destination: metricDetail(
                    title: "FC en reposo",
                    icon: "heart.fill",
                    color: .red,
                    value: summary?.restingHR.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "bpm",
                    samples: [],
                    higherIsBetter: false,
                    normalRange: 40...80,
                    explanation: "La frecuencia cardíaca en reposo es un indicador clave de tu forma cardiovascular. Valores más bajos generalmente indican mejor condición física."
                )) {
                    MetricTile(
                        icon: "heart.fill", color: .red,
                        title: "FC reposo",
                        value: summary?.restingHR.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "bpm",
                        higherIsBetter: false
                    )
                }
                .buttonStyle(.plain)

                // HRV
                NavigationLink(destination: metricDetail(
                    title: "HRV",
                    icon: "waveform.path.ecg",
                    color: .green,
                    value: hrvHistory.first.map { String(format: "%.0f", $0.sdnn) } ?? "--",
                    unit: "ms",
                    samples: hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) },
                    higherIsBetter: true,
                    normalRange: 20...80,
                    explanation: "La variabilidad de la frecuencia cardíaca (HRV) mide la variación en el tiempo entre latidos. Un HRV más alto indica mejor recuperación del sistema nervioso autónomo."
                )) {
                    MetricTile(
                        icon: "waveform.path.ecg", color: .green,
                        title: "HRV",
                        value: hrvHistory.first.map { String(format: "%.0f", $0.sdnn) } ?? "--",
                        unit: "ms",
                        trend: computeTrend(samples: hrvHistory.map { MetricSample(date: $0.date, value: $0.sdnn) }),
                        higherIsBetter: true,
                        samples: hrvHistory.prefix(14).map { MetricSample(date: $0.date, value: $0.sdnn) }
                    )
                }
                .buttonStyle(.plain)

                // VO2Max
                NavigationLink(destination: metricDetail(
                    title: "VO₂Max",
                    icon: "lungs.fill",
                    color: .blue,
                    value: vo2MaxData.map { String(format: "%.1f", $0.current) } ?? summary?.vo2Max.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "ml/kg/min",
                    samples: vo2MaxData?.samples ?? [],
                    higherIsBetter: true,
                    normalRange: 35...60,
                    explanation: "El VO₂Max es la cantidad máxima de oxígeno que tu cuerpo puede utilizar durante el ejercicio intenso. Es el mejor indicador de tu capacidad aeróbica."
                )) {
                    MetricTile(
                        icon: "lungs.fill", color: .blue,
                        title: "VO₂Max",
                        value: vo2MaxData.map { String(format: "%.1f", $0.current) } ?? summary?.vo2Max.map { String(format: "%.1f", $0) } ?? "--",
                        unit: "ml/kg/min",
                        trend: vo2MaxData?.trend,
                        higherIsBetter: true,
                        samples: vo2MaxData?.samples.suffix(14).map { $0 } ?? []
                    )
                }
                .buttonStyle(.plain)

                // Frecuencia respiratoria
                NavigationLink(destination: metricDetail(
                    title: "Resp. nocturna",
                    icon: "wind",
                    color: .cyan,
                    value: respiratoryData.map { String(format: "%.0f", $0.current) } ?? summary?.respiratoryRate.map { String(format: "%.0f", $0) } ?? "--",
                    unit: "resp/min",
                    samples: respiratoryData?.samples ?? [],
                    higherIsBetter: false,
                    normalRange: 12...20,
                    explanation: "La frecuencia respiratoria nocturna es un indicador de recuperación. Valores elevados pueden indicar enfermedad, estrés o sobreentrenamiento."
                )) {
                    MetricTile(
                        icon: "wind", color: .cyan,
                        title: "Resp. nocturna",
                        value: respiratoryData.map { String(format: "%.0f", $0.current) } ?? summary?.respiratoryRate.map { String(format: "%.0f", $0) } ?? "--",
                        unit: "resp/min",
                        trend: respiratoryData?.trend,
                        higherIsBetter: false,
                        samples: respiratoryData?.samples.suffix(14).map { $0 } ?? []
                    )
                }
                .buttonStyle(.plain)

                // Temperatura muñeca
                NavigationLink(destination: metricDetail(
                    title: "Temp. muñeca",
                    icon: "thermometer.medium",
                    color: .purple,
                    value: wristTempData.map { String(format: "%+.1f°", $0.deviation) } ?? summary?.wristTempDeviation.map { String(format: "%+.1f°", $0) } ?? "--",
                    unit: "desv. °C",
                    samples: wristTempData?.samples ?? [],
                    higherIsBetter: false,
                    explanation: "La temperatura de la muñeca durante el sueño. Las desviaciones positivas persistentes pueden indicar esfuerzo o enfermedad."
                )) {
                    MetricTile(
                        icon: "thermometer.medium", color: .purple,
                        title: "Temp. muñeca",
                        value: wristTempData.map { String(format: "%+.1f°", $0.deviation) } ?? "--",
                        unit: "desv. °C",
                        samples: wristTempData?.samples.suffix(14).map { $0 } ?? []
                    )
                }
                .buttonStyle(.plain)

                // Luz diurna: solo si hay datos (la mide el Apple Watch; con otros
                // relojes no existe y quedaría un tile vacío)
                if let dl = daylightData {
                    NavigationLink(destination: metricDetail(
                        title: "Luz diurna",
                        icon: "sun.max.fill",
                        color: .yellow,
                        value: "\(dl.todayMinutes)",
                        unit: "min hoy",
                        samples: dl.samples,
                        higherIsBetter: true,
                        normalRange: 20...120,
                        explanation: "La exposición a la luz natural regula el ritmo circadiano, mejora el sueño y el estado de ánimo. Se recomiendan al menos 20-30 minutos diarios."
                    )) {
                        MetricTile(
                            icon: "sun.max.fill", color: .yellow,
                            title: "Luz diurna",
                            value: "\(dl.todayMinutes)",
                            unit: "min hoy",
                            trend: dl.trend,
                            higherIsBetter: true,
                            samples: dl.samples.suffix(14).map { $0 }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func metricDetail(
        title: String, icon: String, color: Color,
        value: String, unit: String,
        samples: [MetricSample],
        higherIsBetter: Bool = true,
        normalRange: ClosedRange<Double>? = nil,
        explanation: String = ""
    ) -> MetricDetailView {
        MetricDetailView(config: MetricConfig(
            title: title, icon: icon, color: color,
            unit: unit, value: value, samples: samples,
            higherIsBetter: higherIsBetter,
            normalRange: normalRange,
            explanation: explanation
        ))
    }
}
