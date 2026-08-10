import AVFoundation
import Foundation
import Testing
@testable import TimbreCanvas

@Test func audioImportRecognizesSupportedTypes() {
    let service = AudioImportService()

    for extensionName in ["wav", "m4a", "mp3", "aiff", "aif", "caf"] {
        #expect(service.supports(URL(fileURLWithPath: "/tmp/voice.\(extensionName)")))
    }
    #expect(!service.supports(URL(fileURLWithPath: "/tmp/voice.mov")))
}

@Test func importedWAVBecomesMono22050Hz() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appending(path: ".build/audio-import-test", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appending(path: "stereo.wav")
    let destination = directory.appending(path: "converted.wav")
    let format = try #require(
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)
    )
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    do {
        let file = try AVAudioFile(
            forWriting: source,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    try AudioImportService().convertToMonoWAV(source: source, destination: destination)
    let converted = try AVAudioFile(forReading: destination)

    #expect(converted.processingFormat.channelCount == 1)
    #expect(converted.processingFormat.sampleRate == 22_050)
    #expect(converted.length > 0)
}
