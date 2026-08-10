import AVFoundation
import SwiftUI

struct AudioWaveformView: View {
    let audioURL: URL
    var color: Color = StudioDesign.accent
    var sampleCount = 40

    @State private var samples: [CGFloat] = []

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let centerY = size.height / 2
            let step = size.width / CGFloat(max(samples.count - 1, 1))
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * step
                let halfHeight = max(1, sample * size.height * 0.46)
                path.move(to: CGPoint(x: x, y: centerY - halfHeight))
                path.addLine(to: CGPoint(x: x, y: centerY + halfHeight))
            }
            context.stroke(path, with: .color(color), lineWidth: 1.15)
        }
        .task(id: audioURL) {
            samples = await Task.detached(priority: .utility) {
                Self.readSamples(from: audioURL, count: sampleCount)
            }.value
        }
        .accessibilityHidden(true)
    }

    nonisolated private static func readSamples(from url: URL, count: Int) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else { return [] }
        do { try file.read(into: buffer) } catch { return [] }
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return [] }
        let frameCount = Int(buffer.frameLength)
        let bucketSize = max(1, frameCount / count)
        return stride(from: 0, to: frameCount, by: bucketSize).prefix(count).map { start in
            let end = min(frameCount, start + bucketSize)
            var peak: Float = 0
            for index in start..<end { peak = max(peak, abs(channel[index])) }
            return CGFloat(min(1, peak * 1.8))
        }
    }
}
