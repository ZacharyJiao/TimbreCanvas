import SwiftUI

struct ModelStatusView: View {
    let state: WorkerState
    let progress: Double
    let stage: String

    var body: some View {
        HStack(spacing: 8) {
            statusMark
            Text(title)
                .font(.callout.weight(.medium))
                .contentTransition(.numericText())
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(foreground.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("推理状态：\(title)")
    }

    @ViewBuilder
    private var statusMark: some View {
        if state == .loadingModel || state == .starting || state == .recovering || state == .generating {
            ProgressView(value: state == .generating ? progress : nil)
                .controlSize(.small)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: state == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var title: String {
        switch state {
        case .starting: "正在启动"
        case .loadingModel: "正在加载模型"
        case .ready: "模型已就绪"
        case .generating: stageTitle
        case .recovering: "正在恢复"
        case .unavailable: "模型不可用"
        }
    }

    private var stageTitle: String {
        switch stage {
        case "preparing": "正在准备"
        case "complete": "生成完成"
        default: "正在生成 \(Int(progress * 100))%"
        }
    }

    private var foreground: Color {
        switch state {
        case .ready: .green
        case .unavailable: .red
        default: StudioDesign.accent
        }
    }
}
