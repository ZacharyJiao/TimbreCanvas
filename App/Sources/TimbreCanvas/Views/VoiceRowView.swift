import SwiftUI

struct VoiceRowView: View {
    let voice: VoiceProfile

    var body: some View {
        HStack(spacing: 10) {
            AudioWaveformView(
                audioURL: voice.referenceURL,
                color: voice.isAvailable ? waveformColor : .secondary,
                sampleCount: 18
            )
            .frame(width: 38, height: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(voice.isAvailable ? "可以使用" : "需要重新提取")
                    .font(.caption)
                    .foregroundStyle(voice.isAvailable ? Color.secondary : Color.orange)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(voice.name)，\(voice.isAvailable ? "可以使用" : "需要重新提取")")
    }

    private var waveformColor: Color {
        let palette: [Color] = [
            StudioDesign.accent,
            StudioDesign.graphite.opacity(0.72),
            StudioDesign.accentSecondary.opacity(0.82),
            Color.orange.opacity(0.75),
        ]
        let stableValue = voice.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[stableValue % palette.count]
    }
}
