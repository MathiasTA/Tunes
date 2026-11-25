import AVFoundation
import Foundation

/// One pass over an audio file: loudness for normalization, the catchiest part for previews and Wrapped,
/// silence at the start/end for trimming, and a waveform for the trim screen.
struct AudioAnalysis: Codable, Hashable {
    /// Average loudness (RMS) in dBFS.
    var loudnessDB: Double
    /// Start of the loudest ~20 second stretch.
    var highlightStart: Double
    /// Seconds of silence at the start / end.
    var leadingSilence: Double
    var trailingSilence: Double
    var duration: Double
    /// RMS level per 0.1 s block, 0...1.
    var blocks: [Float]

    static let blockSeconds = 0.1

    static func analyze(_ url: URL) async -> AudioAnalysis? {
        await Task.detached(priority: .utility) { run(url) }.value
    }

    private static func run(_ url: URL) -> AudioAnalysis? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let rate = format.sampleRate
        let blockFrames = AVAudioFrameCount(max(1, rate * blockSeconds))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames * 20) else { return nil }
        var blocks: [Float] = []
        var sumSquares: Double = 0
        var counted: Double = 0
        var pendingSum: Float = 0
        var pendingCount: AVAudioFrameCount = 0
        let channels = Int(format.channelCount)

        while true {
            do { try file.read(into: buffer) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { break }
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<channels { let v = data[c][i]; s += v * v }
                s /= Float(channels)
                pendingSum += s
                pendingCount += 1
                if pendingCount == blockFrames {
                    let rms = sqrt(pendingSum / Float(pendingCount))
                    blocks.append(rms)
                    sumSquares += Double(pendingSum)
                    counted += Double(pendingCount)
                    pendingSum = 0
                    pendingCount = 0
                }
            }
        }
        if pendingCount > 0 {
            blocks.append(sqrt(pendingSum / Float(pendingCount)))
            sumSquares += Double(pendingSum)
            counted += Double(pendingCount)
        }
        guard !blocks.isEmpty, counted > 0 else { return nil }

        // Loudness of the audible part only, so quiet intros/outros don't skew it.
        let silenceLevel: Float = 0.003 // about -50 dBFS
        let audible = blocks.filter { $0 > silenceLevel }
        let meanSquare = audible.isEmpty ? sumSquares / counted : Double(audible.map { $0 * $0 }.reduce(0, +)) / Double(audible.count)
        let loudness = 10 * log10(max(meanSquare, 1e-10))

        let lead = Double(blocks.firstIndex(where: { $0 > silenceLevel }) ?? 0) * blockSeconds
        let trailBlocks = blocks.reversed().firstIndex(where: { $0 > silenceLevel }) ?? 0
        let trail = Double(trailBlocks) * blockSeconds

        // Loudest 20 s window (sliding sum), starting no earlier than 15% into the song.
        let window = Int(20 / blockSeconds)
        var highlight = 0.0
        if blocks.count > window {
            var sum = blocks[0..<window].reduce(0, +)
            var best = sum
            var bestIndex = 0
            let minStart = Int(Double(blocks.count) * 0.15)
            for i in 1...(blocks.count - window) {
                sum += blocks[i + window - 1] - blocks[i - 1]
                if i >= minStart && sum > best { best = sum; bestIndex = i }
            }
            highlight = Double(bestIndex) * blockSeconds
        }
        let peak = blocks.max() ?? 1
        let normalized = blocks.map { min(1, $0 / max(peak, 0.0001)) }
        return AudioAnalysis(loudnessDB: loudness, highlightStart: highlight, leadingSilence: lead,
                             trailingSilence: trail, duration: Double(file.length) / rate, blocks: normalized)
    }

    /// Waveform bars for display.
    /// Uses the average of each stretch and stretches the range between the song's quiet and loud parts,
    /// so loud, modern masters don't all come out as a flat block.
    func waveform(bars: Int) -> [Float] {
        guard !blocks.isEmpty, bars > 0 else { return [] }
        let per = max(1, blocks.count / bars)
        let raw: [Float] = stride(from: 0, to: blocks.count, by: per).prefix(bars).map { i in
            let slice = blocks[i..<min(blocks.count, i + per)]
            return slice.reduce(0, +) / Float(slice.count)
        }
        let sorted = raw.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.05)]
        let high = max(sorted.last ?? 1, low + 0.0001)
        return raw.map { v in
            let t = min(1, max(0, (v - low) / (high - low)))
            return 0.12 + 0.88 * powf(t, 1.6)
        }
    }
}
