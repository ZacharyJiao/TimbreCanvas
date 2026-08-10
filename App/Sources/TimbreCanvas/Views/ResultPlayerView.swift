import SwiftUI

struct ResultPlayerView: View {
    let result: GenerationResult
    @ObservedObject var playback: PlaybackService
    @State private var playbackError: String?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                do {
                    try playback.toggle(url: result.outputURL)
                } catch {
                    playbackError = error.localizedDescription
                }
            } label: {
                Image(systemName: isPlayingThisResult ? "pause.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(StudioDesign.accent)
            .help(isPlayingThisResult ? "暂停" : "播放")

            VStack(alignment: .leading, spacing: 4) {
                Text(result.outputURL.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("时长 \(format(result.duration)) · 生成用时 \(format(result.generationSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            AudioWaveformView(audioURL: result.outputURL, sampleCount: 72)
                .frame(maxWidth: 260, minHeight: 30, maxHeight: 30)

            Spacer()

            Button("在 Finder 中显示", systemImage: "folder") {
                FolderSelectionService.reveal(result.outputURL)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .deckledPaperSurface()
        .alert("无法播放", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(playbackError ?? "未知错误")
        }
    }

    private var isPlayingThisResult: Bool {
        playback.isPlaying && playback.loadedURL == result.outputURL
    }

    private func format(_ interval: TimeInterval) -> String {
        if interval >= 60 {
            return String(format: "%d:%02d", Int(interval) / 60, Int(interval) % 60)
        }
        return String(format: "%.1f 秒", interval)
    }
}
