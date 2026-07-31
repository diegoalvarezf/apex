import SwiftUI

struct BiologicalAgeCard: View {
    let result: BiologicalAgeResult

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(result.deltaColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: "figure.walk.motion")
                    .foregroundColor(result.deltaColor)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Edad de fitness")
                    .font(.subheadline)
                Text(result.deltaLabel)
                    .font(.caption).foregroundColor(result.deltaColor)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", result.biologicalAge))
                    .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                    .foregroundColor(result.deltaColor)
                Text("años")
                    .font(.caption).foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
