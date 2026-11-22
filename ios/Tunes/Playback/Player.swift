import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// The queue, transport controls, lock screen, previews and listening stats.
@MainActor @Observable
final class Player {
    enum RepeatMode: String, Codable { case off, all, one }

    private(set) var currentID: Int?
    private(set) var isPlaying = false
    /// Seconds into the file (trims included). Use `elapsed` for display.
    private(set) var position: Double = 0
    private(set) var contextName = ""
    private(set) var contextPlaylistID: UUID?
    private(set) var context: [Int] = []
    private(set) var contextIndex = 0
    private(set) var userQueue: [Int] = []
    private(set) var shuffle = false
    private(set) var repeatMode: RepeatMode = .off
    private(set) var sleepAt: Date?
    private(set) var sleepAtEndOfSong = false
    private(set) var previewingID: Int?
    private(set) var routeName = "This iPhone"
    private(set) var outputKind: OutputKind = .phone
    var message: String?

    @ObservationIgnored private var original: [Int] = []
    @ObservationIgnored private let engine = AudioEngine()
    @ObservationIgnored private let previewPlayer = AVPlayer()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var recordID: UUID?
    @ObservationIgnored private var lastTickPosition: Double?
    @ObservationIgnored private var waitingForDownload: [Int] = []
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var current: LibraryEntry? { currentID.flatMap { AppModel.shared.library.entry($0) } }
    var currentSong: Song? { current?.song }
    var start: Double { current?.trimStart ?? 0 }
    /// Where the song stops: the trim end, else the real length of the downloaded file
    /// (YouTube uploads are often a few seconds longer or shorter than the catalog says).
    var end: Double {
        guard let e = current else { return 0 }
        return e.trimEnd ?? fileLength(e) ?? e.song.duration
    }

    @ObservationIgnored private var fileLengths: [Int: Double] = [:]

    private func fileLength(_ e: LibraryEntry) -> Double? {
        if let known = fileLengths[e.id] { return known }
        guard let f = try? AVAudioFile(forReading: e.fileURL), f.processingFormat.sampleRate > 0 else { return nil }
        let seconds = Double(f.length) / f.processingFormat.sampleRate
        fileLengths[e.id] = seconds
        return seconds
    }
    var duration: Double { max(0, end - start) }
    var elapsed: Double { max(0, position - start) }
    var hasNext: Bool { peekNextID() != nil }

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        engine.onFinished = { [weak self] _ in self?.songEnded() }
        engine.onAdvanced = { [weak self] in self?.advancedToNext() }
        observe()
        setupRemoteCommands()
    }

    // MARK: Starting playback

    /// Plays downloaded songs from a list. Songs that aren't downloaded are skipped.
    func play(_ songs: [Song], startAt index: Int = 0, context name: String, playlistID: UUID? = nil, shuffled: Bool? = nil) {
        let lib = AppModel.shared.library
        let ids = songs.map(\.id).filter { lib.isDownloaded($0) }
        guard !ids.isEmpty else {
            message = "Download songs first to play them."
            return
        }
        let wanted = songs.indices.contains(index) ? songs[index].id : ids[0]
        stopPreview()
        if let s = shuffled { shuffle = s }
        original = ids
        contextName = name
        contextPlaylistID = playlistID
        if shuffle {
            let first = (shuffled == true && index == 0) ? ids.randomElement()! : (lib.isDownloaded(wanted) ? wanted : ids[0])
            context = [first] + ids.filter { $0 != first }.shuffled()
            contextIndex = 0
        } else {
            context = ids
            contextIndex = ids.firstIndex(of: wanted) ?? 0
        }
        currentID = context[contextIndex]
        if let playlistID { AppModel.shared.playlists.markPlayed(playlistID) }
        load(play: true)
    }

    func playNext(_ song: Song) {
        guard AppModel.shared.library.isDownloaded(song.id) else { queueAfterDownload(song); return }
        userQueue.insert(song.id, at: 0)
        engine.cancelNext()
        if currentID == nil { next() }
        message = "Plays next"
    }

    func addToQueue(_ song: Song) {
        guard AppModel.shared.library.isDownloaded(song.id) else { queueAfterDownload(song); return }
        userQueue.append(song.id)
        engine.cancelNext()
        if currentID == nil { next() }
        message = "Added to queue"
    }

    private func queueAfterDownload(_ song: Song) {
        AppModel.shared.library.download(song)
        waitingForDownload.append(song.id)
        message = "Downloading, then it joins your queue"
    }

    func removeFromQueue(userIndex: Int) {
        guard userQueue.indices.contains(userIndex) else { return }
        userQueue.remove(at: userIndex)
        engine.cancelNext()
    }

    func moveUserQueue(from: IndexSet, to: Int) {
        userQueue.move(fromOffsets: from, toOffset: to)
        engine.cancelNext()
    }

    func clearUserQueue() {
        userQueue.removeAll()
        engine.cancelNext()
    }

    /// Songs coming up from the playlist/album (after the user queue).
    var upcomingContext: [Int] {
        guard contextIndex + 1 < context.count else { return repeatMode == .all ? Array(context.prefix(contextIndex)) : [] }
        return Array(context[(contextIndex + 1)...])
    }

    func moveContext(from: IndexSet, to: Int) {
        var up = upcomingContext
        up.move(fromOffsets: from, toOffset: to)
        context = Array(context.prefix(contextIndex + 1)) + up
        engine.cancelNext()
    }

    func jumpToContext(offset: Int) {
        let i = contextIndex + 1 + offset
        guard context.indices.contains(i) else { return }
        contextIndex = i
        currentID = context[i]
        load(play: true)
    }

    // MARK: Transport

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func resume() {
        guard current != nil else {
            if let first = context.first { currentID = first; load(play: true) }
            return
        }
        stopPreview()
        try? AVAudioSession.sharedInstance().setActive(true)
        if engine.current.item == nil {
            load(play: true, from: position)
            return
        }
        engine.resume()
        isPlaying = true
        lastTickPosition = nil
        if recordID == nil, let e = current { beginRecord(e) }
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        engine.pause()
        position = engine.currentPosition
        isPlaying = false
        stopTimer()
        AppModel.shared.stats.flush()
        updateNowPlaying()
        saveSession()
    }

    func next() {
        stopPreview()
        guard let id = consumeNext(manual: true) else { stopAtEnd(); return }
        currentID = id
        load(play: true)
    }

    func previous() {
        if elapsed > 3 || (contextIndex == 0 && repeatMode != .all) {
            seek(to: start)
            return
        }
        contextIndex = contextIndex > 0 ? contextIndex - 1 : max(0, context.count - 1)
        currentID = context[contextIndex]
        load(play: true)
    }

    /// `seconds` is in file time (use `start + x` for display time).
    func seek(to seconds: Double) {
        guard current != nil else { return }
        let target = min(max(start, seconds), max(start, end - 0.5))
        do {
            try engine.seek(to: target, playing: isPlaying)
            position = target
            lastTickPosition = nil
            updateNowPlaying()
        } catch {
            message = "Couldn't play this song."
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        guard let cur = currentID else { return }
        if shuffle {
            original = context
            context = [cur] + context.filter { $0 != cur }.shuffled()
            contextIndex = 0
        } else if !original.isEmpty {
            context = original
            contextIndex = original.firstIndex(of: cur) ?? 0
        }
        engine.cancelNext()
        AppModel.shared.haptic(.light)
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off)
        engine.cancelNext()
        AppModel.shared.haptic(.light)
    }

    func setSleep(minutes: Int?) {
        sleepAtEndOfSong = false
        sleepAt = minutes.map { Date.now.addingTimeInterval(Double($0) * 60) }
        if minutes != nil { engine.cancelNext() }
    }

    func setSleepAtEndOfSong() {
        sleepAt = nil
        sleepAtEndOfSong = true
        engine.cancelNext()
    }

    func stop() {
        AppModel.shared.stats.flush()
        engine.stopAll()
        stopTimer()
        isPlaying = false
        currentID = nil
        context = []
        userQueue = []
        position = 0
        recordID = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        saveSession()
    }

    /// Called when songs are deleted from the library.
    func removeSongs(_ ids: Set<Int>) {
        userQueue.removeAll { ids.contains($0) }
        if let cur = currentID, ids.contains(cur) {
            context.removeAll { ids.contains($0) }
            stop()
            return
        }
        let cur = currentID
        context.removeAll { ids.contains($0) }
        original.removeAll { ids.contains($0) }
        contextIndex = cur.flatMap { context.firstIndex(of: $0) } ?? 0
        engine.cancelNext()
    }

    /// Re-applies trims, fades, volume and source after a song was edited.
    func reloadIfCurrent(_ id: Int) {
        guard id == currentID else { return }
        load(play: isPlaying, from: max(position, start))
    }

    // MARK: Sound settings

    func applySound() {
        let p = AppModel.shared.prefs.data
        engine.setEQ(gains: p.eqProfile(outputKind).gains, enabled: p.eqEnabled)
    }

    // MARK: Previews (30-second clips from the catalog; never counted in stats)

    func togglePreview(_ song: Song) {
        if previewingID == song.id { stopPreview(); return }
        let app = AppModel.shared
        guard let url = song.previewURL else { message = "No preview for this song."; return }
        if app.network.onMobileData && !app.prefs.data.previewsOnCellular {
            message = "Previews are off on mobile data (Settings › Mobile data)."
            return
        }
        guard app.network.isOnline && !app.prefs.data.offline else { message = "You're offline."; return }
        if isPlaying { pause() }
        try? AVAudioSession.sharedInstance().setActive(true)
        previewPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        previewPlayer.play()
        previewingID = song.id
    }

    func stopPreview() {
        guard previewingID != nil else { return }
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        previewingID = nil
    }

    // MARK: Internals

    private func item(for e: LibraryEntry) -> AudioEngine.Item {
        var gain: Float = 1
        if let target = AppModel.shared.prefs.data.normalization.target, let loud = e.loudnessDB {
            gain = Float(min(1, max(0.12, pow(10, (target - loud) / 20))))
        }
        return AudioEngine.Item(id: e.id, url: e.fileURL, start: e.trimStart, end: e.trimEnd, gain: gain,
                                fadeIn: e.fadeIn, fadeOut: e.fadeOut)
    }

    private func load(play: Bool, from: Double? = nil) {
        guard let e = current else { stop(); return }
        finishRecord()
        fileLengths[e.id] = nil // the file may have been replaced since last time
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let from = from ?? e.trimStart
            try engine.load(item(for: e), from: from, play: play)
            position = from
            isPlaying = play
            lastTickPosition = nil
            if play { beginRecord(e); startTimer() } else { stopTimer() }
            updateNowPlaying()
        } catch {
            message = "Couldn't play \(e.song.title). Try re-downloading it."
            isPlaying = false
            stopTimer()
        }
    }

    private func peekNextID() -> Int? {
        if sleepAtEndOfSong { return nil }
        if repeatMode == .one { return currentID }
        if let u = userQueue.first { return u }
        if contextIndex + 1 < context.count { return context[contextIndex + 1] }
        if repeatMode == .all, let first = context.first { return first }
        return nil
    }

    private func consumeNext(manual: Bool = false) -> Int? {
        if repeatMode == .one && !manual { return currentID }
        if !userQueue.isEmpty { return userQueue.removeFirst() }
        if contextIndex + 1 < context.count { contextIndex += 1; return context[contextIndex] }
        if repeatMode == .all && !context.isEmpty { contextIndex = 0; return context[0] }
        return nil
    }

    /// The engine already switched decks (gapless or crossfade).
    private func advancedToNext() {
        finishRecord()
        currentID = consumeNext()
        guard let e = current else { stop(); return }
        position = e.trimStart
        lastTickPosition = nil
        beginRecord(e)
        updateNowPlaying()
    }

    private func songEnded() {
        if sleepAtEndOfSong {
            sleepAtEndOfSong = false
            finishRecord()
            isPlaying = false
            stopTimer()
            if let e = current { try? engine.load(item(for: e), from: e.trimStart, play: false) }
            position = start
            updateNowPlaying()
            return
        }
        if let id = consumeNext() {
            currentID = id
            load(play: true)
        } else {
            stopAtEnd()
        }
    }

    private func stopAtEnd() {
        finishRecord()
        isPlaying = false
        stopTimer()
        if !context.isEmpty {
            contextIndex = 0
            currentID = context[0]
            load(play: false)
        }
    }

    private func crossfade(from a: LibraryEntry, to b: LibraryEntry) -> Double {
        let p = AppModel.shared.prefs.data
        guard p.crossfade > 0, a.id != b.id else { return 0 }
        if p.noCrossfadeInAlbums, let x = a.song.album?.id, x == b.song.album?.id { return 0 }
        return Double(p.crossfade)
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isPlaying else { return }
        tickCount += 1
        if engine.promoteIfStarted() { advancedToNext() }
        let pos = engine.currentPosition
        if let last = lastTickPosition, let id = recordID {
            let delta = pos - last
            if delta > 0 && delta < 1.5 { AppModel.shared.stats.add(delta, to: id) }
        }
        lastTickPosition = pos
        position = pos
        engine.applyVolumes()

        if let cur = current, let nextID = peekNextID(), let nextEntry = AppModel.shared.library.entry(nextID) {
            let overlap = crossfade(from: cur, to: nextEntry)
            if !(AppModel.shared.prefs.data.gapless) && overlap == 0 {
                // Without gapless, let the song end on its own and start the next one normally.
            } else {
                _ = try? engine.prepareNext(item(for: nextEntry), overlap: overlap)
            }
        }

        if tickCount % 150 == 0 { updateNowPlaying() }
        if tickCount % 30 == 0 {
            if let s = sleepAt, s <= .now {
                sleepAt = nil
                pause()
            }
            if !waitingForDownload.isEmpty {
                let lib = AppModel.shared.library
                let ready = waitingForDownload.filter { lib.isDownloaded($0) }
                if !ready.isEmpty {
                    waitingForDownload.removeAll { ready.contains($0) }
                    userQueue.append(contentsOf: ready)
                    engine.cancelNext()
                }
            }
            if AppModel.shared.prefs.isPrivate, AppModel.shared.prefs.data.privateSkipsStats, let id = recordID {
                AppModel.shared.stats.discard(id)
                recordID = nil
            }
        }
    }

    private func beginRecord(_ e: LibraryEntry) {
        let prefs = AppModel.shared.prefs
        if prefs.isPrivate && prefs.data.privateSkipsStats { recordID = nil; return }
        recordID = AppModel.shared.stats.startPlay(e)
    }

    private func finishRecord() {
        if recordID != nil { AppModel.shared.stats.flush() }
        recordID = nil
    }

    // MARK: Lock screen & control center

    private func updateNowPlaying() {
        guard let e = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: e.song.title,
            MPMediaItemPropertyArtist: e.song.artistLine,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: min(elapsed, duration),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = e.song.album?.title { info[MPMediaItemPropertyAlbumTitle] = album }
        if let image = UIImage(contentsOfFile: e.song.localArtworkURL.path) {
            info[MPMediaItemPropertyArtwork] = Player.artwork(image)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Lock Screen, Control Center, headphones and car controls.
    /// Handlers hop to the main actor explicitly, whatever thread iOS calls them on.
    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Player) -> Void) {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                Task { @MainActor in if let self { action(self) } }
                return .success
            }
        }
        on(c.playCommand) { $0.resume() }
        on(c.pauseCommand) { $0.pause() }
        on(c.togglePlayPauseCommand) { $0.togglePlayPause() }
        on(c.nextTrackCommand) { $0.next() }
        on(c.previousTrackCommand) { $0.previous() }
        c.changePlaybackPositionCommand.isEnabled = true
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in if let self { self.seek(to: self.start + t) } }
            return .success
        }
        // Show previous / next buttons rather than "skip 15 seconds" ones.
        c.skipForwardCommand.isEnabled = false
        c.skipBackwardCommand.isEnabled = false
        c.seekForwardCommand.isEnabled = false
        c.seekBackwardCommand.isEnabled = false
    }

    // MARK: System events

    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.wasPlayingBeforeInterruption = self.isPlaying
                    self.pause()
                } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                          AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                          self.wasPlayingBeforeInterruption {
                    self.resume()
                }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateRoute()
                // Headphones unplugged / disconnected: pause like every music app does.
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self.pause() }
            }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engineConfigurationChanged() }
        })
        observers.append(nc.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            let item = note.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let item, item === self.previewPlayer.currentItem else { return }
                self.stopPreview()
            }
        })
    }

    private func engineConfigurationChanged() {
        guard current != nil else { return }
        let wasPlaying = isPlaying
        let pos = engine.currentPosition
        load(play: wasPlaying, from: pos)
    }

    func updateRoute() {
        let out = AVAudioSession.sharedInstance().currentRoute.outputs.first
        routeName = out?.portName ?? "This iPhone"
        switch out?.portType {
        case .some(.builtInSpeaker), .some(.builtInReceiver), .none:
            outputKind = .phone
            routeName = "This iPhone"
        case .some(.headphones), .some(.bluetoothA2DP), .some(.bluetoothLE), .some(.bluetoothHFP), .some(.usbAudio):
            outputKind = .headphones
        default:
            outputKind = .speakers
        }
        applySound()
    }

    // MARK: Remember where you were

    private struct Session: Codable {
        var currentID: Int?
        var context: [Int]
        var contextIndex: Int
        var contextName: String
        var position: Double
        var shuffle: Bool
        var repeatMode: RepeatMode
    }

    func saveSession() {
        let s = Session(currentID: currentID, context: context, contextIndex: contextIndex, contextName: contextName,
                        position: position, shuffle: shuffle, repeatMode: repeatMode)
        Store.save(s, "session.json")
    }

    func restoreSession() {
        guard let s = Store.load(Session.self, "session.json"), let id = s.currentID,
              AppModel.shared.library.isDownloaded(id) else { return }
        let lib = AppModel.shared.library
        context = s.context.filter { lib.isDownloaded($0) }
        contextIndex = context.firstIndex(of: id) ?? 0
        contextName = s.contextName
        shuffle = s.shuffle
        repeatMode = s.repeatMode
        original = context
        currentID = id
        load(play: false, from: s.position)
    }
}
