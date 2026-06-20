import SwiftUI

struct MetricTile: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String
    var trend: MetricTrend?
    var higherIsBetter: Bool = true
    var samples: [MetricSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                Spacer()
                if let trend {
                    Image(systemName: trend.systemImage)
                        .font(.caption2)
                        .foregroundColor(trend.color(higherIsBetter: higherIsBetter))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !samples.isEmpty {
                TrendSparkline(samples: samples, color: color, height: 28)
            } else {
                Spacer().frame(height: 28)
            }

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
