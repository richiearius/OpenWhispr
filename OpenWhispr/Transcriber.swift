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
                // Download with progress callback
                let modelFolder = try await WhisperKit.download(
                    variant: "openai_whisper-small",
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor in
                            self.modelState = .downloading(progress: fraction)
                        }
                    }
                )

                // Init from downloaded model
                let whisper = try await WhisperKit(
                    modelFolder: modelFolder.path,
                    computeOptions: .init(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
                )
                self.whisperKit = whisper

                // Warmup: run a silent transcription to compile CoreML model
                let warmupURL = FileManager.default.temporaryDirectory.appendingPathComponent("murmur_warmup.wav")
                self.generateSilentWav(at: warmupURL, duration: 0.5)
                _ = try? await whisper.transcribe(audioPath: warmupURL.path)
                try? FileManager.default.removeItem(at: warmupURL)

                await MainActor.run { modelState = .ready }
            } catch {
                await MainActor.run { modelState = .error("Failed to load model: \(error.localizedDescription)") }
            }
        }
    }

    private func generateSilentWav(at url: URL, duration: Double) {
        let sampleRate = 16000
        let numSamples = Int(duration * Double(sampleRate))
        let dataSize = numSamples * 2

        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var fileSize = UInt32(36 + dataSize)
        header.append(Data(bytes: &fileSize, count: 4))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var fmtSize: UInt32 = 16
        header.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat: UInt16 = 1
        header.append(Data(bytes: &audioFormat, count: 2))
        var channels: UInt16 = 1
        header.append(Data(bytes: &channels, count: 2))
        var sr = UInt32(sampleRate)
        header.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(sampleRate * 2)
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = 2
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        header.append(Data(bytes: &bitsPerSample, count: 2))
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = UInt32(dataSize)
        header.append(Data(bytes: &ds, count: 4))
        header.append(Data(count: dataSize))

        try? header.write(to: url)
    }

    func transcribe(fileURL: URL) async -> String? {
        guard let whisperKit else { return nil }

        do {
            let decodingOptions = DecodingOptions(
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                usePrefillPrompt: false,
                usePrefillCache: false,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6
            )
            let results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: decodingOptions)

            // Debug: log raw results
            for (i, result) in results.enumerated() {
                print("[Transcriber] Result \(i): language=\(result.language) text=\"\(result.text.prefix(200))\"")
                for (j, seg) in result.segments.enumerated() {
                    print("[Transcriber]   Seg \(j): comp=\(seg.compressionRatio) logp=\(seg.avgLogprob) noSpeech=\(seg.noSpeechProb) temp=\(seg.temperature) text=\"\(seg.text.prefix(100))\"")
                }
            }

            let noiseTokens: Set<String> = [
                "[BLANK_AUDIO]", "[NO_SPEECH]", "(blank_audio)", "(no speech)",
                "[MUSIC PLAYING]", "[MUSIC]", "(music playing)", "(music)",
                "[SOUND]", "[NOISE]", "[SILENCE]", "[APPLAUSE]", "[LAUGHTER]",
                "(sound)", "(noise)", "(silence)", "(applause)", "(laughter)",
                "[INAUDIBLE]", "(inaudible)",
            ]
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var cleaned = noiseTokens.reduce(text) { $0.replacingOccurrences(of: $1, with: "", options: .caseInsensitive) }
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Catch remaining hallucination patterns like "[MUSIC PLAYING]" variants
            if let regex = try? NSRegularExpression(pattern: "\\[.*?\\]|\\(.*?\\)", options: .caseInsensitive) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                let stripped = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Only use stripped version if removing brackets left nothing meaningful
                if stripped.isEmpty && !cleaned.isEmpty {
                    return nil
                }
                // Remove bracket tokens but keep the rest
                cleaned = stripped
            }
            // Detect repetition hallucinations (e.g., "day." repeated, same word looping)
            if isRepetitionHallucination(cleaned) {
                print("[Transcriber] Detected repetition hallucination, discarding")
                return nil
            }

            return cleaned.isEmpty ? nil : cleaned
        } catch {
            print("Transcription failed: \(error)")
            return nil
        }
    }

    private func isRepetitionHallucination(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard words.count >= 4 else { return false }

        // Check if any single word makes up >60% of all words
        var counts: [String: Int] = [:]
        for word in words { counts[word, default: 0] += 1 }
        if let maxCount = counts.values.max(), Double(maxCount) / Double(words.count) > 0.6 {
            return true
        }

        // Check for repeated short phrases (2-3 word patterns)
        for len in 1...3 where words.count >= len * 3 {
            let pattern = Array(words.prefix(len))
            var matches = 0
            for i in stride(from: 0, to: words.count - len + 1, by: len) {
                if Array(words[i..<min(i+len, words.count)]) == pattern { matches += 1 }
            }
            if matches >= 3 && Double(matches * len) / Double(words.count) > 0.5 {
                return true
            }
        }

        return false
    }
}
