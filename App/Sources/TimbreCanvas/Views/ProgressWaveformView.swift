import SwiftUI

struct ProgressWaveformView: View {
    let progress: Double

    private let bars: [CGFloat] = [0.32, 0.6, 0.42, 0.82, 0.54, 1, 0.68, 0.46, 0.76, 0.38, 0.58, 0.28]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(barColor(index: index))
                    .frame(width: 3, height: 22 * height)
            }
        }
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private func barColor(index: Int) -> Color {
        let completed = Int(progress * Double(bars.count))
        return index < completed ? StudioDesign.accent : .secondary.opacity(0.22)
    }
}
