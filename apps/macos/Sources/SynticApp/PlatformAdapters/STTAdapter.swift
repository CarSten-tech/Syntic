import Foundation

enum STTAdapterError: Error {
    case noSpeechDetected
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

struct LocalStubSTTAdapter: STTTranscribing {
    let providerIdentifier = "apple_speech_recognizer"

    func transcribe(
        capture: AudioCaptureResult,
        locale: String,
        completion: @escaping (Result<STTTranscriptResult, Error>) -> Void
    ) {
        let syntheticLatencyMs: UInt32 = 170

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(syntheticLatencyMs))) {
            guard capture.durationMs >= 250 else {
                completion(.failure(STTAdapterError.noSpeechDetected))
                return
            }

            let seconds = String(format: "%.1f", Double(capture.durationMs) / 1_000)
            let transcript = "[Local STT \(locale)] Aufnahme \(seconds)s verarbeitet"

            completion(
                .success(
                    STTTranscriptResult(
                        provider: providerIdentifier,
                        transcript: transcript,
                        confidencePercent: 74,
                        latencyMs: syntheticLatencyMs
                    )
                )
            )
        }
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
