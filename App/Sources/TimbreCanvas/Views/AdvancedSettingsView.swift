import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var generation: GenerationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("采样与质量", subtitle: "保持默认值通常最稳定")
            parameterSlider("Temperature", value: $generation.temperature, range: 0.1...1.5, step: 0.05)
            parameterSlider("Top-P", value: $generation.topP, range: 0.1...1.0, step: 0.05)
            integerStepper("Top-K", value: $generation.topK, range: 1...100, step: 1)
            parameterSlider("重复惩罚", value: $generation.repetitionPenalty, range: 1...20, step: 0.5)
            parameterSlider("CFG", value: $generation.cfgRate, range: 0...1.2, step: 0.05)
            integerStepper("扩散步数", value: $generation.diffusionSteps, range: 10...50, step: 5)

            Divider()
            emotionMix

            Divider()
            sectionTitle("长文本", subtitle: "控制段落切分与连接")
            integerStepper("每段文字 Token", value: $generation.maxTextTokensPerSegment, range: 40...240, step: 10)
            integerStepper("段间静音（毫秒）", value: $generation.intervalSilenceMS, range: 0...1_000, step: 25)
            integerStepper("交叉淡化（毫秒）", value: $generation.segmentOverlapMS, range: 0...500, step: 10)
            integerStepper("最大 Mel Token", value: $generation.maxMelTokens, range: 500...3_000, step: 100)

            Divider()
            Toggle("固定随机种子", isOn: fixedSeedBinding)
            if generation.seed != nil {
                HStack {
                    Text("随机种子")
                    Spacer()
                    TextField("42", value: seedBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
        }
        .font(.callout)
        .padding(.top, 12)
    }

    private var emotionMix: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("混合多种情绪", isOn: emotionMixBinding)
            if !generation.emotionWeights.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(EmotionPreset.allCases) { emotion in
                        HStack(spacing: 8) {
                            Text(emotion.displayName)
                                .frame(width: 34, alignment: .leading)
                            Slider(value: emotionWeightBinding(emotion), in: 0...1.2, step: 0.1)
                            Text(emotionWeightBinding(emotion).wrappedValue, format: .number.precision(.fractionLength(1)))
                                .font(.caption.monospacedDigit())
                                .frame(width: 24)
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func parameterSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack {
            Text(label).frame(width: 92, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(StudioDesign.accent)
            Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                .font(.caption.monospacedDigit())
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func integerStepper(
        _ label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 48, alignment: .trailing)
            }
            .fixedSize()
        }
    }

    private var fixedSeedBinding: Binding<Bool> {
        Binding(
            get: { generation.seed != nil },
            set: { generation.seed = $0 ? 42 : nil }
        )
    }

    private var seedBinding: Binding<Int> {
        Binding(
            get: { generation.seed ?? 42 },
            set: { generation.seed = $0 }
        )
    }

    private var emotionMixBinding: Binding<Bool> {
        Binding(
            get: { !generation.emotionWeights.isEmpty },
            set: { enabled in
                generation.emotionWeights = enabled ? [generation.emotion.rawValue: 1.0] : [:]
            }
        )
    }

    private func emotionWeightBinding(_ emotion: EmotionPreset) -> Binding<Double> {
        Binding(
            get: { generation.emotionWeights[emotion.rawValue, default: 0] },
            set: { value in
                if value == 0 {
                    generation.emotionWeights.removeValue(forKey: emotion.rawValue)
                    if generation.emotionWeights.isEmpty {
                        generation.emotionWeights[generation.emotion.rawValue] = 1.0
                    }
                } else {
                    generation.emotionWeights[emotion.rawValue] = value
                }
            }
        )
    }
}
