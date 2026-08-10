import SwiftUI

struct ComposerView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var voiceLibrary: VoiceLibraryStore
    @EnvironmentObject private var presets: GenerationPresetStore
    @ObservedObject var generation: GenerationStore
    @ObservedObject var playback: PlaybackService

    @State private var showsAdvanced = false
    @State private var showsRename = false
    @State private var renameText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                editor
                controls

                if let result = generation.result {
                    ResultPlayerView(result: result, playback: playback)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
        .animation(.easeInOut(duration: 0.22), value: generation.result)
        .alert("重命名音色", isPresented: $showsRename) {
            TextField("音色名称", text: $renameText)
            Button("保存") { renameSelectedVoice() }
            Button("取消", role: .cancel) {}
        }
        .alert("无法生成语音", isPresented: Binding(
            get: { generation.errorMessage != nil },
            set: { if !$0 { generation.dismissError() } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(generation.errorMessage ?? "未知错误")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(StudioDesign.accent)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(voiceLibrary.selectedVoice?.name ?? "选择一个音色")
                            .font(.title3.weight(.semibold))
                        if voiceLibrary.selectedVoice?.kind == .custom {
                            Button {
                                beginRename()
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("重命名当前音色")
                        }
                    }
                    Text(selectedVoiceSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .studioSurface()

            PresetBarView(store: presets, generation: generation)

            Spacer()

            ModelStatusView(
                state: appModel.state,
                progress: appModel.progress,
                stage: appModel.progressStage
            )
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $generation.text)
                .font(.system(size: 21, weight: .regular, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(18)
                .frame(minHeight: 235)
                .accessibilityLabel("合成文字")
            if generation.text.isEmpty {
                Text("输入想让声音说出的内容…")
                    .font(.system(size: 21, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 26)
                    .allowsHitTesting(false)
            }
            Image(systemName: "waveform.path")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(StudioDesign.accent.opacity(0.24))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .deckledPaperSurface()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 15) {
            if GenerationDraft.showsEmotionControls(for: capability) {
                EmotionControlsView(
                    emotion: $generation.emotion,
                    strength: $generation.emotionStrength,
                    emotionWeights: $generation.emotionWeights
                )
            }

            HStack(spacing: 14) {
                if capability?.supportsSpeed == true {
                    Label("语速", systemImage: "speedometer")
                        .font(.subheadline.weight(.medium))
                    Slider(value: $generation.speed, in: 0.5...2.0, step: 0.05)
                        .frame(maxWidth: 250)
                        .tint(StudioDesign.accent)
                    Text("\(generation.speed, specifier: "%.2f")×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
                Spacer()
            }

            DisclosureGroup(isExpanded: $showsAdvanced) {
                AdvancedSettingsView(generation: generation)
            } label: {
                HStack {
                    Text("高级参数")
                        .font(.subheadline.weight(.semibold))
                    Text("采样、情绪混合与长文本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(StudioDesign.graphite)

            Divider()

            HStack(spacing: 12) {
                Button {
                    if let folder = FolderSelectionService.chooseOutputDirectory(
                        current: generation.outputDirectory
                    ) {
                        generation.outputDirectory = folder
                    }
                } label: {
                    Label("输出目录  \(generation.outputDirectory.lastPathComponent)", systemImage: "folder")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help(generation.outputDirectory.path)

                Spacer()

                if generation.isGenerating {
                    ProgressWaveformView(progress: appModel.progress)
                    Button("取消生成", role: .cancel) {
                        appModel.cancelGeneration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("取消生成并重新加载模型（Esc）")
                } else {
                    Button {
                        Task {
                            await generation.generate(
                                voice: voiceLibrary.selectedVoice,
                                capability: capability,
                                appModel: appModel
                            )
                        }
                    } label: {
                        Label("生成语音", systemImage: "paperplane.fill")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(StudioDesign.accent)
                    .buttonBorderShape(.roundedRectangle(radius: StudioDesign.compactCornerRadius))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canGenerate)
                    .help("生成语音（⌘↩）")
                }
            }
        }
        .padding(16)
        .background {
            ZStack {
                StudioDesign.paper.opacity(0.72)
                PaperTexture(opacity: 0.26)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(StudioDesign.graphite.opacity(0.18)).frame(height: 1)
        }
    }

    private var capability: EngineCapability? {
        appModel.engines.first(where: { $0.engineID == "indextts2" })
    }

    private var canGenerate: Bool {
        appModel.state == .ready
            && !generation.isGenerating
            && !generation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && voiceLibrary.selectedVoice?.isAvailable == true
    }

    private var selectedVoiceSubtitle: String {
        guard let voice = voiceLibrary.selectedVoice else { return "请从左侧声音库中选择" }
        let kind = voice.kind == .builtIn ? "默认声音" : "我的声音"
        return "IndexTTS 2 · \(kind)"
    }

    private func beginRename() {
        guard let voice = voiceLibrary.selectedVoice else { return }
        renameText = voice.name
        showsRename = true
    }

    private func renameSelectedVoice() {
        guard let voice = voiceLibrary.selectedVoice else { return }
        try? voiceLibrary.rename(id: voice.id, to: renameText)
    }
}
