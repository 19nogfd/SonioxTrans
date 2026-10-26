import AVFoundation
import Foundation

final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    func start(onAudio: @escaping @Sendable (Data) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(16_000)
        try session.setPreferredIOBufferDuration(0.1)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw CaptureError.unsupportedFormat
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { buffer, _ in
            let ratio = 16_000 / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, state in
                if supplied {
                    state.pointee = .noDataNow
                    return nil
                }
                supplied = true
                state.pointee = .haveData
                return buffer
            }
            guard status == .haveData || status == .inputRanDry,
                  output.frameLength > 0,
                  let pointer = output.audioBufferList.pointee.mBuffers.mData else { return }
            let count = Int(output.audioBufferList.pointee.mBuffers.mDataByteSize)
            onAudio(Data(bytes: pointer, count: count))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "没有麦克风权限，请在系统设置中允许访问"
        case .unsupportedFormat: "无法转换当前麦克风的音频格式"
        }
    }
}
