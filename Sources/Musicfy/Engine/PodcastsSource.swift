import AppKit
import os

/// Apple Podcasts has no AppleScript. It does report to the system's Now Playing
/// (MediaRemote), like the media keys and Control Center see it, and that's how it's read
/// and driven here: through `NowPlayingBridge`.
///
/// Podcasts has no volume, shuffle, repeat, lyrics or queue of its own to offer, and the
/// skip buttons jump 15 s back and 30 s forward, as in Podcasts.
final class PodcastsSource: MediaSource {
    let kind = SourceKind.podcasts
    static let skipBack: Double = 15
    static let skipForward: Double = 30

    private let bridge = NowPlayingBridge()

    /// Called on the main thread when Podcasts reports a change.
    var onChange: (() -> Void)? {
        get { bridge.onChange }
        set { bridge.onChange = newValue }
    }

    func fetchState() -> Result<PlayerState?, AppleScriptRunner.Failure> {
        guard kind.isRunning else {
            bridge.stop()
            return .success(nil)
        }
        bridge.start()
        guard let info = bridge.latest, info.belongs(to: kind.bundleID) else { return .success(nil) }
        return .success(PlayerState(
            source: kind,
            isPlaying: info.playing,
            title: info.title,
            artist: info.artist,
            album: info.album,
            duration: info.duration,
            position: info.position(),
            trackID: info.identifier,
            volume: 100,
            shuffle: false,
            repeatMode: .off,
            favorited: false,
            artworkURL: nil,
            artworkTag: info.artworkTag
        ))
    }

    func fetchEmbeddedArtwork() -> NSImage? {
        guard bridge.latest?.belongs(to: kind.bundleID) == true, let data = bridge.artwork else { return nil }
        return ArtworkLoader.decode(data)
    }

    func playPause() { bridge.send("toggle") }
    func next() { skip(by: Self.skipForward) }
    func previous(currentPosition: Double) { seek(to: max(0, currentPosition - Self.skipBack)) }
    func seek(to seconds: Double) { bridge.send("seek \(MusicSource.number(max(0, seconds)))") }

    private func skip(by delta: Double) {
        guard let info = bridge.latest else { return }
        var target = info.position() + delta
        if info.duration > 0 { target = min(target, max(0, info.duration - 1)) }
        seek(to: target)
    }

    func setVolume(_ volume: Int) {}
    func setShuffle(_ on: Bool) {}
    func setRepeat(_ mode: RepeatMode) {}
    func setFavorite(_ on: Bool) {}
    func fetchQueue() -> QueueInfo? { nil }
    func playQueueItem(at index: Int) {}
}

/// Runs `/usr/bin/perl Resources/now-playing.pl Frameworks/MusicfyNowPlaying.dylib` while
/// Podcasts is open and keeps the last thing it reported. Since macOS 15.4 MediaRemote
/// only answers Apple's own binaries, and perl is one (see Helper/NowPlaying.m).
///
/// The helper pushes a line only when something changes, so an idle Podcasts costs
/// nothing. It quits by itself when Musicfy does (its stdin closes).
final class NowPlayingBridge {
    struct Info {
        var bundle: String
        var parent: String
        var playing: Bool
        var title: String
        var artist: String
        var album: String
        var duration: Double
        /// As of `readAt`.
        var position: Double
        var readAt: Date
        var identifier: String
        var artworkTag: String

        func belongs(to bundleID: String) -> Bool {
            bundle.caseInsensitiveCompare(bundleID) == .orderedSame
                || parent.caseInsensitiveCompare(bundleID) == .orderedSame
        }

        func position(at date: Date = Date()) -> Double {
            let value = position + (playing ? date.timeIntervalSince(readAt) : 0)
            return duration > 0 ? min(value, duration) : value
        }
    }

    var onChange: (() -> Void)?

    init() {
        // Writing to a helper that just died must not take Musicfy down with it.
        signal(SIGPIPE, SIG_IGN)
    }

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var _latest: Info?
    private var _artwork: Data?
    /// Don't respawn in a loop if perl can't run the helper.
    private var failures = 0
    private var lastLaunch = Date.distantPast

    var latest: Info? {
        lock.lock()
        defer { lock.unlock() }
        return _latest
    }

    var artwork: Data? {
        lock.lock()
        defer { lock.unlock() }
        return _artwork
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard process?.isRunning != true else { return }
        let wait = failures == 0 ? 0 : min(60, pow(2, Double(failures)))
        guard Date().timeIntervalSince(lastLaunch) >= wait else { return }
        guard let script = Bundle.main.url(forResource: "now-playing", withExtension: "pl"),
              let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("MusicfyNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: library.path)
        else { return }
        lastLaunch = Date()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.receive(chunk)
            }
        }
        process.terminationHandler = { [weak self] ended in
            guard let self else { return }
            self.lock.lock()
            if self.process === ended {
                self.process = nil
                self.input = nil
                if ended.terminationStatus != 0 || ended.terminationReason == .uncaughtSignal {
                    self.failures += 1
                    Log.podcasts.error("Now Playing reader ended with status \(ended.terminationStatus, privacy: .public) (failure \(self.failures, privacy: .public))")
                }
            }
            self.lock.unlock()
        }
        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
            buffer.removeAll()
        } catch {
            failures += 1
            Log.podcasts.error("Couldn't start the Now Playing reader: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        lock.lock()
        let running = process
        process = nil
        input = nil
        let hadState = _latest != nil
        _latest = nil
        _artwork = nil
        failures = 0
        lock.unlock()
        running?.terminate()
        if hadState { notify() }
    }

    func send(_ command: String) {
        lock.lock()
        let handle = input
        lock.unlock()
        guard let handle, let data = (command + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    /// Runs on the pipe's queue.
    private func receive(_ chunk: Data) {
        var lines: [Data] = []
        lock.lock()
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<newline))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        var changed = false
        for line in lines {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let message = json["error"] as? String {
                Log.podcasts.error("Now Playing reader: \(message, privacy: .public)")
                continue
            }
            apply(json)
            changed = true
        }
        if changed { notify() }
    }

    private func apply(_ json: [String: Any]) {
        let bundle = json["bundle"] as? String ?? ""
        lock.lock()
        defer { lock.unlock() }
        failures = 0
        guard !bundle.isEmpty, let title = json["title"] as? String else {
            _latest = nil
            _artwork = nil
            return
        }
        let info = Info(
            bundle: bundle,
            parent: json["parent"] as? String ?? "",
            playing: json["playing"] as? Bool ?? false,
            title: title,
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            duration: json["duration"] as? Double ?? 0,
            position: json["position"] as? Double ?? 0,
            readAt: Date(),
            identifier: json["id"] as? String ?? "",
            artworkTag: json["artworkTag"] as? String ?? ""
        )
        if let encoded = json["artwork"] as? String {
            _artwork = Data(base64Encoded: encoded)
        } else if info.artworkTag.isEmpty {
            _artwork = nil
        }
        _latest = info
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
