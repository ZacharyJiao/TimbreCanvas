import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct AudioImportService: Sendable {
    private let supportedExtensions = Set(["wav", "m4a", "mp3", "aiff", "aif", "caf"])

    func supports(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    @MainActor
    func chooseReferenceAudio() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择参考音频"
        panel.message = "支持 WAV、M4A、MP3、AIFF 和 CAF"
        panel.prompt = "导入音色"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func convertToMonoWAV(source: URL, destination: URL) throws {
        guard supports(source) else { throw AudioImportError.unsupportedFormat }
        let inputFile = try AVAudioFile(forReading: source)
        let inputFormat = inputFile.processingFormat
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let outputFile = try AVAudioFile(forWriting: destination, settings: fileSettings)
        let outputFormat = outputFile.processingFormat
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioImportError.converterUnavailable
        }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let inputCapacity: AVAudioFrameCount = 4_096
        let outputCapacity = AVAudioFrameCount(ceil(Double(inputCapacity) * ratio)) + 32
        var reachedEnd = false

        while !reachedEnd {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputCapacity
            ) else { throw AudioImportError.converterUnavailable }
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) {
                _, inputStatus in
                guard let inputBuffer = AVAudioPCMBuffer(
                    pcmFormat: inputFormat,
                    frameCapacity: inputCapacity
                ) else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                do {
                    try inputFile.read(into: inputBuffer, frameCount: inputCapacity)
                } catch {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                if inputBuffer.frameLength == 0 {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if let conversionError { throw conversionError }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            if status == .endOfStream
                || (status == .inputRanDry && inputFile.framePosition >= inputFile.length) {
                reachedEnd = true
            }
            if status == .error { throw AudioImportError.conversionFailed }
        }
    }
}

enum AudioImportError: LocalizedError {
    case unsupportedFormat
    case converterUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "不支持这种音频格式"
        case .converterUnavailable: "无法创建音频转换器"
        case .conversionFailed: "参考音频转换失败"
        }
    }
}
