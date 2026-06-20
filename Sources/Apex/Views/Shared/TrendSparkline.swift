import SwiftUI
import Charts

struct TrendSparkline: View {
    let samples: [MetricSample]
    var color: Color = .blue
    var height: CGFloat = 40

    var body: some View {
        if samples.count < 2 {
            Color.clear.frame(height: height)
        } else {
            Chart(samples) { sample in
                LineMark(
                    x: .value("Fecha", sample.date),
                    y: .value("Valor", sample.value)
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Fecha", sample.date),
                    y: .value("Valor", sample.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: height)
        }
    }
}
