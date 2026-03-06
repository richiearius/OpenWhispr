import Foundation
import SwiftLlama

class TextProcessor: ObservableObject {
    enum ProcessorState: Equatable {
        case unavailable
        case ready
        case error(String)
    }

    @Published var state: ProcessorState = .unavailable

    private var llamaService: LlamaService?

    var isReady: Bool { state == .ready }

    func setup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            guard let modelURL = Bundle.main.url(forResource: "qwen3-0.6b-q4_k_m", withExtension: "gguf") else {
                print("[TextProcessor] Model file not found in bundle")
                DispatchQueue.main.async { self.state = .error("Model file not found in bundle") }
                return
            }

            print("[TextProcessor] Loading model from: \(modelURL.path)")
            let service = LlamaService(
                modelUrl: modelURL,
                config: .init(batchSize: 512, maxTokenCount: 4096, useGPU: true)
            )
            self.llamaService = service
            print("[TextProcessor] Model loaded, running warmup inference…")

            // Warmup: run a tiny inference to pre-compile Metal shaders
            // so the first real polishing doesn't have cold-start latency
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                let warmupMessages = [
                    LlamaChatMessage(role: .system, content: "You are a text processor."),
                    LlamaChatMessage(role: .user, content: "/no_think\nHello"),
                ]
                do {
                    let stream = try await service.streamCompletion(
                        of: warmupMessages,
                        samplingConfig: .init(temperature: 0.0, seed: 42)
                    )
                    for try await _ in stream {}
                } catch {
                    print("[TextProcessor] Warmup failed (non-fatal): \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait()

            DispatchQueue.main.async { self.state = .ready }
            print("[TextProcessor] Ready — Qwen3 0.6B warmed up on Metal")
        }
    }

    struct ProcessingContext {
        var tone: String = "neutral" // "casual", "neutral", "professional", "raw"
        var polishingEnabled: Bool = true
        var alwaysEnglish: Bool = false
        var userStyleDescription: String = ""
        var summarize: Bool = false
    }

    func process(_ text: String, context: ProcessingContext) async -> String {
        // Skip LLM entirely for raw tone (code editors)
        if context.tone == "raw" { return text }

        if text.split(separator: " ").count < 3 { return text }

        guard let llamaService else { return text }

        let systemPrompt = buildSystemPrompt(context: context)
        print("[TextProcessor] Processing with tone=\(context.tone), summarize=\(context.summarize)")

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

            var cleaned = stripThinkBlocks(result)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            print("[TextProcessor] Output: \(cleaned)")
            if cleaned.isEmpty { return text }

            if looksLikeConversation(cleaned, original: text) {
                print("[TextProcessor] Detected conversation, using raw text")
                return text
            }

            return cleaned
        } catch {
            print("[TextProcessor] Failed: \(error)")
            return text
        }
    }

    private func buildSystemPrompt(context: ProcessingContext) -> String {
        var parts: [String] = []

        // Base instruction
        if context.summarize {
            parts.append("You are a summarization assistant. Summarize the following dictated text into concise bullet points. Capture all key points, decisions, and action items. The summary must be shorter than the input.")
        } else {
            parts.append("You are a text processor for dictated speech. Clean and format the text while preserving the speaker's meaning.")
        }

        // Tone instruction (only if polishing/tone is enabled)
        if context.polishingEnabled && !context.summarize {
            switch context.tone {
            case "professional":
                parts.append("Tone: Professional. Use proper grammar, formal language, no slang or contractions. Suitable for emails and business communication.")
            case "casual":
                parts.append("Tone: Casual. Keep contractions, informal language, and a conversational feel. Suitable for messaging apps.")
            case "neutral":
                parts.append("Tone: Neutral. Clean and clear writing. Not too formal, not too casual.")
            default:
                break
            }
        }

        // Smart formatting (always on unless summarizing)
        if !context.summarize {
            parts.append("Formatting rules: Add proper punctuation and capitalization. When the speaker says \"new paragraph\" or \"next paragraph\", insert an actual line break — do not include the literal words. Detect lists (\"first... second...\" or \"number one... number two...\") and format as numbered/bulleted lists. Format spoken numbers and dates into written form (e.g., \"January fifteenth twenty twenty six\" → \"January 15, 2026\", \"three hundred and forty two\" → \"342\").")
        }

        // Translation
        if context.alwaysEnglish {
            parts.append("If the input text is not in English, translate it to English. If already in English, do not change it. Translation must preserve the tone and formatting rules above.")
        }

        // User style description
        if !context.userStyleDescription.isEmpty {
            parts.append("User's style preference: \(context.userStyleDescription)")
        }

        // Output instruction
        if !context.summarize {
            if !context.polishingEnabled {
                parts.append("Only apply formatting (punctuation, paragraphs, lists, numbers). Do not rephrase, rewrite, or change the speaker's words. Remove filler words (um, uh, like, you know).")
            }
            parts.append("Output only the processed text. No explanations.")
        }

        return parts.joined(separator: "\n\n")
    }

    func answerQuestion(_ question: String) async -> String {
        guard let llamaService else { return "" }

        let systemPrompt = """
You are a quick-answer assistant. Give short, helpful answers — 1 to 3 sentences max. Be direct, no filler. If you don't know, say "I don't know".

Examples:
Q: What's the capital of France?
A: Paris.

Q: What does HTTP stand for?
A: HyperText Transfer Protocol. It's the protocol browsers use to communicate with web servers.

Q: What's the difference between a stack and a queue?
A: A stack is last-in first-out (LIFO) — the last item added is the first removed. A queue is first-in first-out (FIFO) — items are processed in the order they arrive.

Q: How do I reverse a string in Python?
A: Use slicing: my_string[::-1]. This creates a new string with characters in reverse order.

Q: What year did World War 2 end?
A: 1945. Germany surrendered in May and Japan in September.

Q: What's a good way to center a div in CSS?
A: Use flexbox on the parent: display: flex; justify-content: center; align-items: center. Works both horizontally and vertically.
"""

        let messages = [
            LlamaChatMessage(role: .system, content: systemPrompt),
            LlamaChatMessage(role: .user, content: "/no_think\n\(question)"),
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
            let cleaned = stripThinkBlocks(result).trimmingCharacters(in: .whitespacesAndNewlines)
            print("[TextProcessor] Q&A: \"\(question)\" → \"\(cleaned)\"")
            return cleaned
        } catch {
            print("[TextProcessor] Q&A failed: \(error)")
            return ""
        }
    }

    private func stripThinkBlocks(_ text: String) -> String {
        var cleaned = text
        if let thinkRange = cleaned.range(of: "<think>") {
            if let endRange = cleaned.range(of: "</think>") {
                cleaned = String(cleaned[endRange.upperBound...])
            } else {
                cleaned = String(cleaned[thinkRange.upperBound...])
            }
        }
        return cleaned
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
