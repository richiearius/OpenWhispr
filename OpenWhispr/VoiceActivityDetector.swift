import Foundation
import Accelerate

struct SpeechSegment {
    let startSample: Int
    let endSample: Int
}

class VoiceActivityDetector {
    private let sampleRate: Int = 16000
    private let frameDuration: Double = 0.020 // 20ms frames
    private let noiseWindowSeconds: Double = 2.0
    private let speechMultiplier: Float = 4.0
    private let gapMergeSeconds: Double = 0.3
    private let paddingSamples: Int // 150ms

    init() {
        paddingSamples = Int(0.150 * Double(sampleRate))
    }

    /// Process a WAV file: strip silence, write speech-only WAV, return URL.
    /// Returns nil if no speech detected or VAD not needed.
    func process(inputURL: URL) -> URL? {
        guard let samples = readPCMSamples(from: inputURL) else { return nil }
        // Always run VAD — even short clips can have silence that triggers hallucinations
        guard samples.count > sampleRate / 4 else { return nil } // Skip only for <0.25s

        let segments = detectSpeechSegments(samples: samples)
        guard !segments.isEmpty else { return nil }

        // If speech covers most of the audio (>80%), skip VAD
        let totalSpeechSamples = segments.reduce(0) { $0 + ($1.endSample - $1.startSample) }
        if Double(totalSpeechSamples) / Double(samples.count) > 0.8 {
            return nil
        }

        let speechSamples = concatenateSegments(segments: segments, samples: samples)
        guard !speechSamples.isEmpty else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur_vad_\(UUID().uuidString).wav")
        writeWAV(samples: speechSamples, to: outputURL)
        return outputURL
    }

    // MARK: - Read PCM from WAV

    private func readPCMSamples(from url: URL) -> [Float]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard data.count > 44 else { return nil }

        // Skip 44-byte WAV header, read 16-bit PCM samples
        let pcmData = data.subdata(in: 44..<data.count)
        let sampleCount = pcmData.count / 2
        guard sampleCount > 0 else { return nil }

        // Convert raw bytes to Int16 array safely
        var int16Samples = [Int16](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { rawBuf in
            let src = rawBuf.bindMemory(to: Int16.self)
            for i in 0..<min(sampleCount, src.count) {
                int16Samples[i] = src[i]
            }
        }

        // Convert Int16 → Float using vDSP
        var floatSamples = [Float](repeating: 0, count: sampleCount)
        int16Samples.withUnsafeBufferPointer { srcBuf in
            floatSamples.withUnsafeMutableBufferPointer { dstBuf in
                vDSP_vflt16(srcBuf.baseAddress!, 1, dstBuf.baseAddress!, 1, vDSP_Length(sampleCount))
            }
        }

        // Normalize to -1.0...1.0
        var scale: Float = 1.0 / 32768.0
        var normalized = [Float](repeating: 0, count: sampleCount)
        vDSP_vsmul(&floatSamples, 1, &scale, &normalized, 1, vDSP_Length(sampleCount))
        floatSamples = normalized

        return floatSamples
    }

    // MARK: - Frame-level RMS Energy

    private func calculateFrameRMS(samples: [Float]) -> [Float] {
        let frameSamples = Int(frameDuration * Double(sampleRate)) // 320 samples per 20ms frame
        let frameCount = samples.count / frameSamples
        guard frameCount > 0 else { return [] }

        var rmsValues = [Float](repeating: 0, count: frameCount)

        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for i in 0..<frameCount {
                let offset = i * frameSamples
                var sumSquares: Float = 0
                vDSP_svesq(base + offset, 1, &sumSquares, vDSP_Length(frameSamples))
                rmsValues[i] = sqrt(sumSquares / Float(frameSamples))
            }
        }

        return rmsValues
    }

    // MARK: - Adaptive Noise Floor

    private func trackNoiseFloor(rmsValues: [Float]) -> [Float] {
        let framesPerSecond = 1.0 / frameDuration
        let windowFrames = Int(noiseWindowSeconds * framesPerSecond)

        var noiseFloor = [Float](repeating: 0, count: rmsValues.count)

        for i in 0..<rmsValues.count {
            let windowStart = max(0, i - windowFrames)
            let windowSlice = Array(rmsValues[windowStart...i])
            var minVal: Float = 0
            vDSP_minv(windowSlice, 1, &minVal, vDSP_Length(windowSlice.count))
            noiseFloor[i] = max(minVal, 1e-6)
        }

        return noiseFloor
    }

    // MARK: - Speech Detection

    private func detectSpeechSegments(samples: [Float]) -> [SpeechSegment] {
        let rmsValues = calculateFrameRMS(samples: samples)
        guard !rmsValues.isEmpty else { return [] }

        let noiseFloor = trackNoiseFloor(rmsValues: rmsValues)
        let frameSamples = Int(frameDuration * Double(sampleRate))

        // Mark frames as speech
        var rawSegments: [SpeechSegment] = []
        var segStart: Int? = nil

        for i in 0..<rmsValues.count {
            let isSpeech = rmsValues[i] > noiseFloor[i] * speechMultiplier

            if isSpeech && segStart == nil {
                segStart = i * frameSamples
            } else if !isSpeech, let start = segStart {
                rawSegments.append(SpeechSegment(startSample: start, endSample: i * frameSamples))
                segStart = nil
            }
        }
        if let start = segStart {
            rawSegments.append(SpeechSegment(startSample: start, endSample: min(rmsValues.count * frameSamples, samples.count)))
        }

        guard !rawSegments.isEmpty else { return [] }

        // Merge segments with gaps < 300ms
        let gapSamples = Int(gapMergeSeconds * Double(sampleRate))
        var merged: [SpeechSegment] = [rawSegments[0]]

        for i in 1..<rawSegments.count {
            let prev = merged[merged.count - 1]
            let curr = rawSegments[i]
            if curr.startSample - prev.endSample < gapSamples {
                merged[merged.count - 1] = SpeechSegment(startSample: prev.startSample, endSample: curr.endSample)
            } else {
                merged.append(curr)
            }
        }

        // Add 150ms padding
        return merged.map { seg in
            SpeechSegment(
                startSample: max(0, seg.startSample - paddingSamples),
                endSample: min(samples.count, seg.endSample + paddingSamples)
            )
        }
    }

    // MARK: - Concatenate Speech Segments

    private func concatenateSegments(segments: [SpeechSegment], samples: [Float]) -> [Int16] {
        var output = [Int16]()
        output.reserveCapacity(segments.reduce(0) { $0 + ($1.endSample - $1.startSample) })

        for seg in segments {
            let count = seg.endSample - seg.startSample
            guard seg.startSample >= 0, seg.endSample <= samples.count, count > 0 else { continue }

            for j in seg.startSample..<seg.endSample {
                let clamped = max(-1.0, min(1.0, samples[j]))
                output.append(Int16(clamped * 32767.0))
            }
        }

        return output
    }

    // MARK: - Write WAV

    private func writeWAV(samples: [Int16], to url: URL) {
        let dataSize = samples.count * 2

        var header = Data(capacity: 44 + dataSize)
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendUInt32(&header, UInt32(36 + dataSize))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        appendUInt32(&header, 16) // fmt chunk size
        appendUInt16(&header, 1)  // PCM
        appendUInt16(&header, 1)  // mono
        appendUInt32(&header, UInt32(sampleRate))
        appendUInt32(&header, UInt32(sampleRate * 2)) // byte rate
        appendUInt16(&header, 2)  // block align
        appendUInt16(&header, 16) // bits per sample
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendUInt32(&header, UInt32(dataSize))

        // Append PCM data
        samples.withUnsafeBufferPointer { buf in
            header.append(UnsafeBufferPointer(start: UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self), count: dataSize))
        }

        try? header.write(to: url)
    }

    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}
