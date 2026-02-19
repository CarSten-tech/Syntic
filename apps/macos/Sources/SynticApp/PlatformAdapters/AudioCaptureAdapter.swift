import AVFoundation
import Foundation

enum AudioCaptureAdapterError: Error {
    case permissionDenied
    case captureAlreadyRunning
    case engineStartFailed
    case captureNotRunning
}

struct AudioCaptureResult {
    let sampleRate: Double
    let channelCount: UInt32
    let frameCount: Int
    let durationMs: UInt32
    let averagePower: Float
    let peakPower: Float
}

protocol AudioCapturing: AnyObject {
    var isCapturing: Bool { get }
    func requestPermission(_ completion: @escaping (Bool) -> Void)
    func startCapture(levelHandler: @escaping (Float) -> Void) throws
    func stopCapture() -> AudioCaptureResult?
}

final class MacOSAudioCaptureAdapter: AudioCapturing {
    private let audioEngine = AVAudioEngine()
    private let stateQueue = DispatchQueue(label: "com.syntic.audio-capture.state")

    private var internalIsCapturing = false
    private var levelHandler: ((Float) -> Void)?

    private var sampleRate: Double = 16_000
    private var channelCount: UInt32 = 1
    private var frameCount = 0
    private var weightedPowerSum = 0.0
    private var peakPower: Float = 0

    var isCapturing: Bool {
        stateQueue.sync { internalIsCapturing }
    }

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func startCapture(levelHandler: @escaping (Float) -> Void) throws {
        if isCapturing {
            throw AudioCaptureAdapterError.captureAlreadyRunning
        }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureAdapterError.permissionDenied
        }

        resetMetrics()
        self.levelHandler = levelHandler

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        stateQueue.sync {
            sampleRate = format.sampleRate
            channelCount = format.channelCount
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureAdapterError.engineStartFailed
        }

        stateQueue.sync {
            internalIsCapturing = true
        }
    }

    func stopCapture() -> AudioCaptureResult? {
        guard isCapturing else {
            return nil
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        levelHandler = nil

        return stateQueue.sync {
            internalIsCapturing = false
            let effectiveFrameCount = max(frameCount, 1)
            let averagePower = Float(weightedPowerSum / Double(effectiveFrameCount))
            let durationMs = UInt32((Double(frameCount) / sampleRate) * 1_000)

            return AudioCaptureResult(
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameCount: frameCount,
                durationMs: durationMs,
                averagePower: averagePower,
                peakPower: peakPower
            )
        }
    }

    private func resetMetrics() {
        stateQueue.sync {
            frameCount = 0
            weightedPowerSum = 0
            peakPower = 0
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard
            let channelDataPointer = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return
        }

        let sampleCount = Int(buffer.frameLength)
        let channelData = channelDataPointer[0]

        var sumSquares: Float = 0
        for index in 0 ..< sampleCount {
            let sample = channelData[index]
            sumSquares += sample * sample
        }

        let rms = sqrtf(sumSquares / Float(sampleCount))
        let normalizedLevel = max(0, min(1, (20 * log10f(max(rms, 0.000_01)) + 60) / 60))

        stateQueue.sync {
            frameCount += sampleCount
            weightedPowerSum += Double(rms) * Double(sampleCount)
            peakPower = max(peakPower, rms)
        }

        if let levelHandler {
            DispatchQueue.main.async {
                levelHandler(normalizedLevel)
            }
        }
    }
}
