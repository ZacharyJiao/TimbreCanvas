import SwiftUI

struct EmotionControlsView: View {
    @Binding var emotion: EmotionPreset
    @Binding var strength: Double
    @Binding var emotionWeights: [String: Double]

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("表达方式")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(EmotionPreset.allCases) { preset in
                    Button {
                        emotion = preset
                        emotionWeights = [:]
                    } label: {
                        Label(preset.displayName, systemImage: preset.symbol)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EmotionButtonStyle(isSelected: emotion == preset))
                    .accessibilityAddTraits(emotion == preset ? .isSelected : [])
                }
            }

            HStack {
                Text("情绪强度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $strength, in: 0...1, step: 0.05)
                    .tint(StudioDesign.accent)
                Text(strength, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

private struct EmotionButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: StudioDesign.compactCornerRadius)
                        .fill(isSelected ? StudioDesign.accent : StudioDesign.paper)
                    if !isSelected {
                        PaperTexture(opacity: 0.42)
                            .clipShape(RoundedRectangle(cornerRadius: StudioDesign.compactCornerRadius))
                    }
                    RoundedRectangle(cornerRadius: StudioDesign.compactCornerRadius)
                        .strokeBorder(StudioDesign.graphite.opacity(0.16), lineWidth: 0.8)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
