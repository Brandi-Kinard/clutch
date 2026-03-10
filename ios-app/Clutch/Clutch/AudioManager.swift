import AVFoundation
import Foundation

/// Handles microphone capture (16 kHz PCM Int16) and audio playback.
/// Uses AVAudioEngine for both paths.
final class AudioManager {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// Called on a background thread with each captured audio buffer.
    var onAudioCaptured: ((Data) -> Void)?
    var isMuted = false

    private var isCapturing = false
    private var isPlaying = false

    // 16 kHz mono Int16
    private let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    // Playback format (PCM Int16, 24 kHz — adjust to match backend output)
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Session setup

    func configureAudioSession(bluetoothOutput: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions = bluetoothOutput
                ? [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
                : [.defaultToSpeaker]
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setPreferredSampleRate(16_000)
            try session.setActive(true)
        } catch {
            print("[AudioManager] Session setup error:", error)
        }
    }

    // MARK: - Permission

    func requestMicAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        default:
            return false
        }
    }

    // MARK: - Capture

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        engine.attach(playerNode)
        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        let inputNode = engine.inputNode
        // Install tap with device's native format, convert to 16kHz inside callback
        let hwFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processCaptureBuffer(buffer, from: hwFormat)
        }

        do {
            try engine.start()
        } catch {
            print("[AudioManager] Engine start error:", error)
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    // Runs on AVAudioEngine's internal thread — do NOT access @MainActor state here
    private func processCaptureBuffer(_ buffer: AVAudioPCMBuffer, from srcFormat: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: srcFormat, to: captureFormat) else { return }
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (16_000 / srcFormat.sampleRate))
        guard let converted = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: converted, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, let channelData = converted.int16ChannelData else { return }
        let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        if !isMuted { onAudioCaptured?(data) }
    }

    // MARK: - Playback

    func playAudio(_ data: Data) {
        guard data.count >= 2 else { return }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }

        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)
        data.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.baseAddress else { return }
            pcmBuffer.int16ChannelData![0].update(
                from: src.assumingMemoryBound(to: Int16.self),
                count: sampleCount
            )
        }

        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
        }
        // muting handled by WebSocketManager
        playerNode.scheduleBuffer(pcmBuffer) { [weak self] in
            self?.isMuted = false
        }
    }

    func stopPlayback() {
        playerNode.stop()
        isPlaying = false
    }
}
