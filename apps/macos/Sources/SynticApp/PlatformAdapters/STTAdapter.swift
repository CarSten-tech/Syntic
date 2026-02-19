import Foundation
import Speech

enum STTAdapterError: Error {
    case noSpeechDetected
    case missingRecordingFile
    case speechPermissionDenied
    case recognizerUnavailable
    case recognitionFailed(String)
}

struct STTTranscriptResult {
    let provider: String
    let transcript: String
    let confidencePercent: UInt8
    let latencyMs: UInt32
}

protocol STTTranscribing {
    var providerIdentifier: String { get }
    func transcribe(
        capture: AudioCaptureResult,
        locale: String,
        completion: @escaping (Result<STTTranscriptResult, Error>) -> Void
    )
}

final class AppleSpeechRecognizerSTTAdapter: STTTranscribing {
    let providerIdentifier = "apple_speech_recognizer"
    private let fileManager: FileManager
    private let stateQueue = DispatchQueue(label: "com.syntic.apple-stt.state")
    private var activeTasks: [UUID: SFSpeechRecognitionTask] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func transcribe(
        capture: AudioCaptureResult,
        locale: String,
        completion: @escaping (Result<STTTranscriptResult, Error>) -> Void
    ) {
        guard capture.durationMs >= 250 else {
            completion(.failure(STTAdapterError.noSpeechDetected))
            return
        }

        guard let recordingFileURL = capture.recordingFileURL else {
            completion(.failure(STTAdapterError.missingRecordingFile))
            return
        }

        withSpeechAuthorization { [weak self, fileManager] authorizationStatus in
            guard let self else {
                try? fileManager.removeItem(at: recordingFileURL)
                return
            }
            guard authorizationStatus == .authorized else {
                try? fileManager.removeItem(at: recordingFileURL)
                completion(.failure(STTAdapterError.speechPermissionDenied))
                return
            }

            let completionGuardQueue = DispatchQueue(label: "com.syntic.apple-stt.completion")
            var didComplete = false
            let requestID = UUID()
            let startedAt = Date()

            func completeOnce(_ result: Result<STTTranscriptResult, Error>) {
                completionGuardQueue.sync {
                    guard !didComplete else {
                        return
                    }
                    didComplete = true
                    self.stateQueue.sync {
                        _ = self.activeTasks.removeValue(forKey: requestID)
                    }
                    try? fileManager.removeItem(at: recordingFileURL)
                    completion(result)
                }
            }

            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)) else {
                completeOnce(.failure(STTAdapterError.recognizerUnavailable))
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: recordingFileURL)
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    completeOnce(.failure(STTAdapterError.recognitionFailed(error.localizedDescription)))
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else {
                    completeOnce(.failure(STTAdapterError.noSpeechDetected))
                    return
                }

                let segments = result.bestTranscription.segments
                let confidencePercent: UInt8
                if segments.isEmpty {
                    confidencePercent = 0
                } else {
                    let confidenceSum = segments.reduce(Float(0)) { partial, segment in
                        partial + segment.confidence
                    }
                    let averageConfidence = confidenceSum / Float(segments.count)
                    let clamped = max(0, min(100, Int((averageConfidence * 100).rounded())))
                    confidencePercent = UInt8(clamped)
                }

                let latencyMsDouble = Date().timeIntervalSince(startedAt) * 1_000
                let latencyMsInt = max(0, min(Int(UInt32.max), Int(latencyMsDouble.rounded())))
                let latencyMs = UInt32(latencyMsInt)

                completeOnce(
                    .success(
                        STTTranscriptResult(
                            provider: self.providerIdentifier,
                            transcript: transcript,
                            confidencePercent: confidencePercent,
                            latencyMs: latencyMs
                        )
                    )
                )
            }
            self.stateQueue.sync {
                self.activeTasks[requestID] = task
            }
        }
    }

    private func withSpeechAuthorization(
        _ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status)
            }
            return
        }
        completion(currentStatus)
    }
}

struct CloudStubSTTAdapter: STTTranscribing {
    let providerIdentifier = "openai_whisper"

    func transcribe(
        capture: AudioCaptureResult,
        locale: String,
        completion: @escaping (Result<STTTranscriptResult, Error>) -> Void
    ) {
        let syntheticLatencyMs: UInt32 = 460

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(syntheticLatencyMs))) {
            guard capture.durationMs >= 250 else {
                completion(.failure(STTAdapterError.noSpeechDetected))
                return
            }

            let seconds = String(format: "%.1f", Double(capture.durationMs) / 1_000)
            let transcript = "[Cloud STT \(locale)] Aufnahme \(seconds)s verarbeitet"

            completion(
                .success(
                    STTTranscriptResult(
                        provider: providerIdentifier,
                        transcript: transcript,
                        confidencePercent: 88,
                        latencyMs: syntheticLatencyMs
                    )
                )
            )
        }
    }
}
