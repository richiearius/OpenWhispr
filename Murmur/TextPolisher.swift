import Foundation
import SwiftLlama

class TextPolisher: ObservableObject {
    enum PolishState: Equatable {
        case unavailable
        case ready
        case error(String)
    }

    @Published var state: PolishState = .unavailable

    private var llamaService: LlamaService?

    var isReady: Bool { state == .ready }

    private let systemPrompt = "Fix grammar and punctuation. Remove fillers and repeated words. Output only cleaned text."

    func setup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let modelURL = Bundle.main.url(forResource: "qwen3-0.6b-q4_k_m", withExtension: "gguf") else {
                print("[Polisher] Model file not found in bundle")
                DispatchQueue.main.async { self.state = .error("Model file not found in bundle") }
                return
            }

            print("[Polisher] Loading model from: \(modelURL.path)")
            let service = LlamaService(
                modelUrl: modelURL,
                config: .init(batchSize: 512, maxTokenCount: 4096, useGPU: true)
            )
            self.llamaService = service
            DispatchQueue.main.async { self.state = .ready }
            print("[Polisher] Ready — Qwen3 0.6B loaded on Metal")
        }
    }

    func polish(_ text: String) async -> String {
        if text.split(separator: " ").count < 5 { return text }

        guard let llamaService else { return text }
        print("[Polisher] Polishing: \(text)")

        // /no_think disables Qwen3's chain-of-thought reasoning
        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: "/no_think\n\(text)"),
        ]

        do {
            let stream = try await llamaService.streamCompletion(
                of: messages,
                samplingConfig: .init(temperature: 0.0, seed: 42)
            )
            var result = ""
            for try await token in stream {
                result += token
            }

            // Strip any <think> blocks that slip through
            var cleaned = result
            if let thinkRange = cleaned.range(of: "<think>") {
                if let endRange = cleaned.range(of: "</think>") {
                    cleaned = String(cleaned[endRange.upperBound...])
                } else {
                    cleaned = String(cleaned[thinkRange.upperBound...])
                }
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            print("[Polisher] Output: \(cleaned)")
            if cleaned.isEmpty { return text }

            if looksLikeConversation(cleaned, original: text) {
                print("[Polisher] Detected conversation, using raw text")
                return text
            }

            return cleaned
        } catch {
            print("Polish failed: \(error)")
            return text
        }
    }

    private func looksLikeConversation(_ output: String, original: String) -> Bool {
        let lower = output.lowercased()

        let refusalPhrases = [
            "i can't", "i cannot", "i'm sorry", "i apologize",
            "i'm unable", "as an ai", "i'm not able",
            "i'd be happy to", "here's", "here is",
            "sure!", "of course!", "certainly!",
            "today is", "the answer", "that would be"
        ]
        for phrase in refusalPhrases {
            if lower.hasPrefix(phrase) { return true }
        }

        if output.count > original.count * 2 { return true }

        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "to", "of", "in", "on", "at", "for", "and", "or", "but", "it", "i", "you", "we", "they", "my", "your", "do", "does", "did", "what", "how", "when", "where", "who", "that", "this"]
        let inputWords = Set(original.lowercased().split(separator: " ").map(String.init)).subtracting(stopWords)
        let outputWords = Set(lower.split(separator: " ").map(String.init)).subtracting(stopWords)

        if inputWords.count >= 2 {
            let overlap = inputWords.intersection(outputWords)
            let overlapRatio = Double(overlap.count) / Double(inputWords.count)
            if overlapRatio < 0.3 { return true }
        }

        return false
    }
}
