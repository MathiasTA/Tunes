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
    /// Tempo, the time of one beat (the rest follow every 60/bpm seconds), and energy 0...1. Nil for songs
    /// analyzed before these were added (they get analyzed again).
    var bpm: Double?
    var beatOffset: Double?
    var energy: Double?
    /// Where the song winds down (for smart transitions), and its first beat after the silence at the start.
    var outroStart: Double?
    var firstBeat: Double?

    /// How calm (0) or energetic (1) the song feels, from tempo and energy.
    var mood: Double {
        let tempo = min(1, max(0, ((bpm ?? 100) - 60) / 120))
        return 0.55 * tempo + 0.45 * (energy ?? 0.5)
    }

    /// Seconds per beat.
    var beatLength: Double? { bpm.map { 60 / $0 } }

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
        // Finer energy steps (512 frames, ~12 ms) for finding the beat.
        let hop = 512
        var hops: [Float] = []
        var hopSum: Float = 0
        var hopCount = 0

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
                hopSum += s
                hopCount += 1
                if hopCount == hop { hops.append(hopSum / Float(hop)); hopSum = 0; hopCount = 0 }
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
        let duration = Double(file.length) / rate
        var result = AudioAnalysis(loudnessDB: loudness, highlightStart: highlight, leadingSilence: lead,
                                   trailingSilence: trail, duration: duration, blocks: normalized)
        let hopSeconds = Double(hop) / rate
        if let beat = Self.findBeat(hops, hopSeconds: hopSeconds) {
            result.bpm = beat.bpm
            result.beatOffset = beat.offset
            let period = 60 / beat.bpm
            let k = max(0, ceil((lead - beat.offset) / period))
            result.firstBeat = beat.offset + k * period
            let loud = min(1, max(0, (loudness + 24) / 16))
            result.energy = 0.65 * loud + 0.35 * min(1, beat.onsetDensity / 0.05)
        }
        result.outroStart = Self.findOutro(normalized, duration: duration, trailing: trail)
        return result
    }

    /// Tempo from how regularly the music's "hits" repeat (autocorrelation of energy jumps), 60–180 BPM,
    /// gently preferring tempos near 120. Then the beat position that lines up best with the hits.
    private static func findBeat(_ hops: [Float], hopSeconds: Double) -> (bpm: Double, offset: Double, onsetDensity: Double)? {
        guard hops.count > 400 else { return nil }
        var onset = [Float](repeating: 0, count: hops.count)
        var prev = log10(hops[0] + 1e-9)
        for i in 1..<hops.count {
            let cur = log10(hops[i] + 1e-9)
            onset[i] = max(0, cur - prev)
            prev = cur
        }
        // Use up to 90 s from the middle of the song.
        let window = min(onset.count, Int(90 / hopSeconds))
        let start = max(0, (onset.count - window) / 2)
        let seg = Array(onset[start..<(start + window)])
        let minLag = max(1, Int((60.0 / 180) / hopSeconds)), maxLag = Int((60.0 / 60) / hopSeconds)
        guard seg.count > maxLag * 2 else { return nil }
        var bestLag = 0
        var bestScore: Double = 0
        for lag in minLag...maxLag {
            var sum: Float = 0
            for i in 0..<(seg.count - lag) { sum += seg[i] * seg[i + lag] }
            let bpm = 60 / (Double(lag) * hopSeconds)
            let w = exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2))
            let score = Double(sum) / Double(seg.count - lag) * w
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestLag > 0, bestScore > 0 else { return nil }
        var bestPhase = 0
        var bestPhaseScore: Float = -1
        for p in 0..<bestLag {
            var sum: Float = 0
            var i = p
            while i < onset.count { sum += onset[i]; i += bestLag }
            if sum > bestPhaseScore { bestPhaseScore = sum; bestPhase = p }
        }
        let mean = Double(onset.reduce(0, +)) / Double(onset.count)
        return (60 / (Double(bestLag) * hopSeconds), Double(bestPhase) * hopSeconds, mean)
    }

    /// The last moment the song is still going strong; after it, it winds down. Never earlier than
    /// 30 seconds before the end.
    private static func findOutro(_ blocks: [Float], duration: Double, trailing: Double) -> Double? {
        guard blocks.count > 300 else { return nil }
        let audible = blocks.filter { $0 > 0.05 }.sorted()
        guard !audible.isEmpty else { return nil }
        let median = audible[audible.count / 2]
        let end = max(0, blocks.count - Int(trailing / blockSeconds))
        let span = 20 // 2 s
        var i = end - span
        let earliest = max(0, Int((duration - 30) / blockSeconds))
        while i > earliest {
            let avg = blocks[i..<(i + span)].reduce(0, +) / Float(span)
            if avg >= median * 0.6 { break }
            i -= 5
        }
        return Double(max(i + span, earliest)) * blockSeconds
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
