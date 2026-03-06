import Foundation
import WhisperKit

class Transcriber: ObservableObject {
    @Published var modelState: ModelState = .checking
    private var whisperKit: WhisperKit?

    enum ModelState: Equatable {
        case checking
        case notDownloaded
        case downloading(progress: Double)
        case ready
        case error(String)
    }

    var isModelReady: Bool {
        modelState == .ready
    }

    func checkAndDownload() {
        Task {
            await MainActor.run { modelState = .downloading(progress: 0) }

            do {
                let whisper = try await WhisperKit(
                    model: "base",
                    computeOptions: .init(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
                )
                self.whisperKit = whisper
                await MainActor.run { modelState = .ready }
            } catch {
                await MainActor.run { modelState = .error("Failed to load model: \(error.localizedDescription)") }
            }
        }
    }

    func transcribe(fileURL: URL) async -> String? {
        guard let whisperKit else { return nil }

        do {
            let results = try await whisperKit.transcribe(audioPath: fileURL.path)
            let noiseTokens: Set<String> = ["[BLANK_AUDIO]", "[NO_SPEECH]", "(blank_audio)", "(no speech)"]
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = noiseTokens.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            print("Transcription failed: \(error)")
            return nil
        }
    }
}
