import AVFoundation
import Foundation

/// Two "decks" feeding an equalizer. Each song plays on its own deck, so the next song can start
/// exactly when the current one ends (gapless) or overlap it (crossfade), even if the files differ.
@MainActor
final class AudioEngine {
    struct Item: Equatable {
        let id: Int
        let url: URL
        let start: Double
        let end: Double?
        /// Linear volume from normalization (0...1).
        let gain: Float
        let fadeIn: Double
        let fadeOut: Double
    }

    final class Deck {
        let node = AVAudioPlayerNode()
        let bus: AVAudioNodeBus
        var item: Item?
        var sampleRate: Double = 44_100
        var segmentStart: Double = 0
        var segmentEnd: Double = 0
        var generation = 0
        /// Host time this deck is set to start at (when queued as "next").
        var startHostTime: UInt64?
        var overlapIn: Double = 0
        var overlapOut: Double = 0
        var pausedPosition: Double?
        /// The file format this deck's node is connected with.
        var format: AVAudioFormat?
        /// Player sample time where the current segment began, and how many frames it has.
        /// (With gapless, several songs play back to back on one deck, so this moves forward.)
        var baseSample: AVAudioFramePosition = 0
        var currentFrames: AVAudioFramePosition = 0
        /// The next song, already scheduled on this same deck right after the current one (true gapless).
        var queued: Queued?
        init(bus: AVAudioNodeBus) { self.bus = bus }
    }

    struct Queued {
        let item: Item
        let start: Double
        let end: Double
        let frames: AVAudioFramePosition
    }

    let engine = AVAudioEngine()
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    private let mixer = AVAudioMixerNode()
    private(set) var decks = [Deck(bus: 0), Deck(bus: 1)]
    private(set) var currentIndex = 0

    var current: Deck { decks[currentIndex] }
    var other: Deck { decks[1 - currentIndex] }

    /// Called when the current song played to its end and nothing was queued after it.
    var onFinished: ((_ id: Int) -> Void)?
    /// Called when the queued next song took over (gapless or crossfade).
    var onAdvanced: (() -> Void)?

    init() {
        engine.attach(mixer)
        engine.attach(eq)
        for d in decks { engine.attach(d.node) }
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        for d in decks { engine.connect(d.node, to: mixer, fromBus: 0, toBus: d.bus, format: nil) }
        engine.prepare()
    }

    // MARK: Engine lifecycle

    func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do { try engine.start() } catch { print("Audio engine failed to start: \(error)") }
    }

    func pauseEngine() { engine.pause() }

    // MARK: Loading

    /// Plays `item` on the current deck from `position` (seconds into the file).
    func load(_ item: Item, from position: Double, play: Bool) throws {
        stopDeck(other)
        stopDeck(current)
        try schedule(current, item: item, from: position)
        current.overlapIn = 0
        current.overlapOut = 0
        startEngineIfNeeded()
        if play { current.node.play() } else { current.pausedPosition = current.segmentStart }
        applyVolumes()
    }

    /// Queues `item` on the other deck to start `overlap` seconds before the current one ends.
    /// Returns false if it's too early to schedule (more than `lead` seconds away).
    @discardableResult
    func prepareNext(_ item: Item, overlap: Double, lead: Double = 1.0) throws -> Bool {
        let cur = current
        guard cur.item != nil else { return false }
        if other.item == item && other.startHostTime != nil { return true }
        if let q = cur.queued { return q.item == item }

        // Gapless: put the next song on the same deck, straight after this one. The player node then plays
        // the two back to back with no gap at all, sample for sample, which keeps album transitions intact.
        if overlap == 0, cur.pausedPosition == nil, let curFormat = cur.format {
            guard cur.segmentEnd - position(of: cur) <= max(lead, 8) else { return false }
            let file = try AVAudioFile(forReading: item.url)
            let f = file.processingFormat
            if f.sampleRate == curFormat.sampleRate && f.channelCount == curFormat.channelCount {
                let remaining = cur.segmentEnd - position(of: cur)
                guard remaining <= max(lead, 8) else { return false }
                stopDeck(other)
                let total = Double(file.length) / f.sampleRate
                let end = min(item.end ?? total, total)
                let start = max(0, min(item.start, end - 0.05))
                let frames = AVAudioFramePosition(max(1, (end - start) * f.sampleRate))
                let gen = cur.generation
                let id = item.id
                cur.node.scheduleSegment(file, startingFrame: AVAudioFramePosition(start * f.sampleRate),
                                         frameCount: AVAudioFrameCount(frames), at: nil,
                                         completionCallbackType: .dataPlayedBack) { [weak self, weak cur] _ in
                    Task { @MainActor in
                        guard let self, let cur, cur.generation == gen else { return }
                        self.deckFinished(cur, id: id)
                    }
                }
                cur.queued = Queued(item: item, start: start, end: end, frames: frames)
                return true
            }
        }
        guard let nodeTime = cur.node.lastRenderTime, nodeTime.isHostTimeValid,
              let playerTime = cur.node.playerTime(forNodeTime: nodeTime) else { return false }
        let positionAtRender = cur.segmentStart + Double(max(0, playerTime.sampleTime)) / playerTime.sampleRate
        let remaining = cur.segmentEnd - positionAtRender
        let startIn = max(0, remaining - overlap)
        guard startIn <= lead else { return false }
        stopDeck(other)
        try schedule(other, item: item, from: item.start)
        let host = nodeTime.hostTime + AVAudioTime.hostTime(forSeconds: startIn)
        other.startHostTime = host
        other.overlapIn = min(overlap, remaining)
        cur.overlapOut = min(overlap, remaining)
        other.node.play(at: AVAudioTime(hostTime: host))
        return true
    }

    /// Cancels a queued next song (after skipping, seeking or changing the queue).
    func cancelNext() {
        if other.startHostTime != nil || other.item != nil {
            stopDeck(other)
            current.overlapOut = 0
        }
        // A song queued on the same deck can't be unscheduled on its own: restart the current song where it is.
        if current.queued != nil, let item = current.item {
            let pos = position(of: current)
            let wasPlaying = current.pausedPosition == nil && current.node.isPlaying
            stopDeck(current)
            try? schedule(current, item: item, from: pos)
            if wasPlaying { current.node.play() } else { current.pausedPosition = pos }
            applyVolumes()
        }
    }

    /// True once the queued deck has actually started; then it becomes the current deck.
    func promoteIfStarted() -> Bool {
        guard let start = other.startHostTime, mach_absolute_time() >= start else { return false }
        other.startHostTime = nil
        currentIndex = 1 - currentIndex
        return true
    }

    // MARK: Transport

    func pause() {
        // Cancels a queued next song, or ends a crossfade tail.
        if other.item != nil { stopDeck(other) }
        current.overlapOut = 0
        current.pausedPosition = position(of: current)
        current.node.pause()
        engine.pause()
    }

    func resume() {
        startEngineIfNeeded()
        current.pausedPosition = nil
        current.node.play()
        applyVolumes()
    }

    func seek(to seconds: Double, playing: Bool) throws {
        guard let item = current.item else { return }
        current.queued = nil // dropped by the restart below
        cancelNext()
        stopDeck(current)
        try schedule(current, item: item, from: seconds)
        current.overlapIn = 0
        startEngineIfNeeded()
        if playing { current.node.play() } else { current.pausedPosition = current.segmentStart }
        applyVolumes()
    }

    func stopAll() {
        stopDeck(other)
        stopDeck(current)
        engine.pause()
    }

    // MARK: Time

    func position(of deck: Deck) -> Double {
        if let p = deck.pausedPosition { return p }
        guard let nodeTime = deck.node.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = deck.node.playerTime(forNodeTime: nodeTime) else { return deck.segmentStart }
        let t = deck.segmentStart + Double(max(0, playerTime.sampleTime - deck.baseSample)) / playerTime.sampleRate
        return min(max(deck.segmentStart, t), deck.segmentEnd)
    }

    var currentPosition: Double { position(of: current) }

    // MARK: Volume, fades and EQ

    /// Called ~30 times a second by the player to apply fades and crossfades.
    func applyVolumes() {
        for d in decks {
            guard let item = d.item else { continue }
            let pos = position(of: d)
            var v = item.gain
            let fromStart = pos - item.start
            let toEnd = d.segmentEnd - pos
            if item.fadeIn > 0 { v *= Float(min(1, max(0, fromStart / item.fadeIn))) }
            if item.fadeOut > 0 { v *= Float(min(1, max(0, toEnd / item.fadeOut))) }
            if d.overlapIn > 0 { v *= Float(min(1, max(0, fromStart / d.overlapIn))) }
            if d.overlapOut > 0 { v *= Float(min(1, max(0, toEnd / d.overlapOut))) }
            d.node.volume = max(0, min(1, v))
        }
    }

    func setEQ(gains: [Float], enabled: Bool) {
        let freqs = EQProfile.bands
        for (i, band) in eq.bands.enumerated() where i < freqs.count {
            band.filterType = .parametric
            band.frequency = freqs[i]
            band.bandwidth = 1.0
            band.gain = i < gains.count ? gains[i] : 0
            band.bypass = false
        }
        let flat = gains.allSatisfy { $0 == 0 }
        eq.bypass = !enabled || flat
        // Leave headroom when boosting so loud songs don't clip.
        eq.globalGain = enabled ? -max(0, gains.max() ?? 0) * 0.7 : 0
    }

    // MARK: Internals

    private func schedule(_ deck: Deck, item: Item, from position: Double) throws {
        let file = try AVAudioFile(forReading: item.url)
        let format = file.processingFormat
        let rate = format.sampleRate
        let total = Double(file.length) / rate
        let end = min(item.end ?? total, total)
        let start = max(0, min(position, end - 0.05))
        // Reconnect at this file's format so files with different sample rates play correctly. Only when it
        // actually changes: rewiring the graph while music plays can cause a tiny dropout.
        if deck.format == nil || deck.format?.sampleRate != format.sampleRate || deck.format?.channelCount != format.channelCount {
            engine.disconnectNodeOutput(deck.node)
            engine.connect(deck.node, to: mixer, fromBus: 0, toBus: deck.bus, format: format)
            deck.format = format
        }
        deck.generation += 1
        let gen = deck.generation
        let frames = AVAudioFrameCount(max(0, (end - start) * rate))
        let startFrame = AVAudioFramePosition(start * rate)
        let id = item.id
        deck.node.scheduleSegment(file, startingFrame: startFrame, frameCount: max(frames, 1), at: nil,
                                  completionCallbackType: .dataPlayedBack) { [weak self, weak deck] _ in
            Task { @MainActor in
                guard let self, let deck, deck.generation == gen else { return }
                self.deckFinished(deck, id: id)
            }
        }
        deck.item = item
        deck.sampleRate = rate
        deck.segmentStart = start
        deck.segmentEnd = end
        deck.pausedPosition = nil
        deck.startHostTime = nil
        deck.baseSample = 0
        deck.currentFrames = AVAudioFramePosition(max(frames, 1))
        deck.queued = nil
    }

    private func deckFinished(_ deck: Deck, id: Int) {
        guard deck.item?.id == id else { return }
        // Gapless: the song queued on this deck is already playing. Just move the bookkeeping over.
        if let q = deck.queued {
            deck.baseSample += deck.currentFrames
            deck.currentFrames = q.frames
            deck.item = q.item
            deck.segmentStart = q.start
            deck.segmentEnd = q.end
            deck.queued = nil
            deck.overlapIn = 0
            deck.overlapOut = 0
            if deck === current { onAdvanced?() }
            return
        }
        let wasCurrent = deck === current
        deck.generation += 1
        deck.node.stop()
        deck.item = nil
        deck.overlapIn = 0
        deck.overlapOut = 0
        guard wasCurrent else { return }
        if other.item != nil && other.startHostTime != nil {
            // The next song was already queued to start right now: hand over to it.
            other.startHostTime = nil
            currentIndex = 1 - currentIndex
            onAdvanced?()
        } else {
            onFinished?(id)
        }
    }

    private func stopDeck(_ deck: Deck) {
        deck.generation += 1
        deck.node.stop()
        deck.item = nil
        deck.queued = nil
        deck.baseSample = 0
        deck.startHostTime = nil
        deck.overlapIn = 0
        deck.overlapOut = 0
        deck.pausedPosition = nil
    }
}
