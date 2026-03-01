import Foundation
import AVFoundation
import Accelerate

class AudioRecorder: ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0   // 0..1 normalised

    let recordingURL: URL

    init() {
        recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonotext_capture.wav")
        audioLogger.debug("Recorder initialized. Output path: \(self.recordingURL.path, privacy: .public)")
    }

    func startRecording() {
        let inputNode = audioEngine.inputNode
        let hwFormat  = inputNode.outputFormat(forBus: 0)
        audioLogger.debug("Start requested. sampleRate=\(hwFormat.sampleRate, format: .fixed(precision: 0)) channels=\(hwFormat.channelCount, privacy: .public)")

        do {
            audioFile = try AVAudioFile(forWriting: recordingURL, settings: hwFormat.settings)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buf, _ in
                guard let self else { return }
                // Write audio to file
                do {
                    try self.audioFile?.write(from: buf)
                } catch {
                    audioLogger.error("Tap write failed: \(error.localizedDescription, privacy: .public)")
                }
                // Compute level
                let lvl = Self.rmsLevel(buf)
                DispatchQueue.main.async { self.audioLevel = lvl }
            }

            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
                audioLogger.notice("Recording started")
            }
        } catch {
            audioLogger.error("Start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopRecording(completion: @escaping (URL) -> Void) {
        audioLogger.debug("Stop requested")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil

        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel  = 0
            audioLogger.notice("Recording stopped. File ready: \(self.recordingURL.lastPathComponent, privacy: .public)")
            completion(self.recordingURL)
        }
    }

    func toggleRecording(completion: @escaping (URL?) -> Void) {
        if isRecording {
            stopRecording { url in completion(url) }
        } else {
            startRecording()
            completion(nil)
        }
    }

    // MARK: - RMS level — works with both interleaved and non-interleaved buffers
    private static func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var rmsVal: Float = 0

        if let floatData = buffer.floatChannelData {
            // Non-interleaved float PCM — the common case after macOS converts it
            let channelCount = Int(buffer.format.channelCount)
            var channelRms: Float = 0
            for ch in 0..<channelCount {
                let ptr = floatData[ch]
                var sumSquares: Float = 0
                vDSP_svesq(ptr, 1, &sumSquares, vDSP_Length(frameCount))
                channelRms += sqrtf(sumSquares / Float(frameCount))
            }
            rmsVal = channelRms / Float(max(1, channelCount))
        } else if let int16Data = buffer.int16ChannelData {
            // 16-bit integer PCM (some hardware formats)
            let ptr = int16Data[0]
            var sumSquares: Float = 0
            for i in 0..<frameCount {
                let s = Float(ptr[i]) / 32768.0
                sumSquares += s * s
            }
            rmsVal = sqrtf(sumSquares / Float(frameCount))
        }

        // Map dB range -55..0 → 0..1
        let db = 20 * log10f(max(rmsVal, 1e-7))
        return max(0, min((db + 55) / 55, 1))
    }
}
