import AppKit
import Foundation

/// The latest video frame, handed from the emulation thread to the view.
final class FrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pixels: [UInt32] = []
    private(set) var width = 0
    private(set) var height = 0
    private var sequence = 0

    func publish(_ source: [UInt32], width: Int, height: Int) {
        lock.lock()
        pixels = source
        self.width = width
        self.height = height
        sequence &+= 1
        lock.unlock()
    }

    /// Returns a CGImage of the newest frame if it is newer than `after`.
    func image(after: inout Int) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard sequence != after, width > 0, height > 0 else { return nil }
        after = sequence
        return Self.makeImage(pixels, width: width, height: height)
    }

    func currentImage() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard width > 0 else { return nil }
        return Self.makeImage(pixels, width: width, height: height)
    }

    /// mGBA's 32-bit colour is R, G, B, X in memory.
    static func makeImage(_ pixels: [UInt32], width: Int, height: Int) -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

enum SessionError: LocalizedError {
    case unsupportedROM(String)
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedROM(let path): return "mGBA does not recognise this file as a Game Boy or Game Boy Advance ROM: \(path)"
        case .startFailed(let path): return "The game could not be started: \(path)"
        }
    }
}

/// Owns the mGBA core and the thread that runs it.
final class EmulatorSession: @unchecked Sendable {
    let manifest: GameManifest
    let romURL: URL
    let dataFolder: URL
    let frames = FrameBuffer()
    let platform: Int32
    private(set) var hardware: UInt32 = 0
    private(set) var frameRate: Double = 59.7275

    private let core: OpaquePointer
    private let coreLock = NSRecursiveLock()
    private var thread: Thread?
    private let stateLock = NSLock()
    private var running = false
    private let audio: AudioOutput

    // Controls, written from the main thread.
    private var _paused = false
    private var _frameStep = false
    private var _fastForwardToggle = false
    private var _fastForwardHeld = false
    private var _rewindHeld = false
    private var _keyboardKeys: UInt32 = 0
    private var _padKeys: UInt32 = 0
    private var previousFrame: [UInt32] = []

    var onRumble: ((Float) -> Void)?

    init(manifest: GameManifest, romURL: URL, biosFolder: URL?, dataFolder: URL) throws {
        self.manifest = manifest
        self.romURL = romURL
        self.dataFolder = dataFolder
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)

        let defaults = Bundle.main.url(forResource: "defaults", withExtension: "ini", subdirectory: "Game")
        let config = dataFolder.appendingPathComponent("config.ini")
        guard let core = gbp_create(romURL.path, defaults?.path, config.path) else {
            throw SessionError.unsupportedROM(romURL.path)
        }
        self.core = core
        platform = gbp_platform(core)

        // Player defaults (below the app's defaults.ini and the user's config.ini).
        let playerDefaults: [String: String] = [
            "useBios": "1", "skipBios": "0", "volume": "256", "mute": "0",
            "lockAspectRatio": "1", "lockIntegerScaling": "0", "interframeBlending": "0", "resampleVideo": "0",
            "frameskip": "0", "fastForwardRatio": "-1", "rewindEnable": "1", "rewindBufferCapacity": "600",
            "rewindBufferInterval": "1", "videoScale": "3", "pauseOnFocusLost": "0", "sgb.borders": "1",
            "idleOptimization": "detect", "allowOpposingDirections": "1", "solarLevel": "6",
            GameWindowController.borderlessKey: "0", GameWindowController.preventDisplaySleepKey: "1",
        ]
        for (key, value) in playerDefaults where gbp_config_get(core, key) == nil {
            gbp_config_set_default(core, key, value)
        }
        // The bundled BIOS files are fixed: they live in the app, not in the user's config.
        if let biosFolder {
            for (key, file) in manifest.bios {
                gbp_config_set_default(core, key, biosFolder.appendingPathComponent(file).path)
                gbp_config_unset(core, key)
            }
        }
        audio = AudioOutput(sampleRate: Double(gbp_audio_sample_rate(core)))
    }

    deinit {
        gbp_destroy(core)
    }

    // MARK: Paths

    var romBaseName: String { (manifest.romFile as NSString).deletingPathExtension }

    var defaultSaveFolder: URL { dataFolder.appendingPathComponent("saves", isDirectory: true) }

    var saveFolder: URL {
        if let path = config("savegamePath"), !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return defaultSaveFolder
    }

    var stateFolder: URL {
        if let path = config("savestatePath"), !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return dataFolder.appendingPathComponent("states", isDirectory: true)
    }

    var screenshotFolder: URL {
        if let path = config("screenshotPath"), !path.isEmpty { return URL(fileURLWithPath: path, isDirectory: true) }
        return dataFolder.appendingPathComponent("screenshots", isDirectory: true)
    }

    var saveFile: URL { saveFolder.appendingPathComponent(romBaseName + ".sav") }
    var cheatsFile: URL { dataFolder.appendingPathComponent(romBaseName + ".cheats") }
    func stateFile(slot: Int) -> URL { stateFolder.appendingPathComponent("\(romBaseName).ss\(slot)") }

    // MARK: Lifecycle

    func start() throws {
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let ok = withCore { core -> Bool in
            guard gbp_start(core, saveFile.path) else { return false }
            hardware = gbp_hardware(core)
            frameRate = gbp_frame_rate(core)
            gbp_set_light_level(core, Int32(configInt("solarLevel") ?? 6))
            if FileManager.default.fileExists(atPath: cheatsFile.path) {
                _ = gbp_cheats_load(core, cheatsFile.path)
            }
            return true
        }
        guard ok else { throw SessionError.startFailed(romURL.path) }
        applyAudioSettings()
        audio.start()
        stateLock.withLock { running = true }
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "mGBA emulation"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        stateLock.withLock { running = false }
        while thread?.isExecuting == true { usleep(1000) }
        thread = nil
        audio.stop()
        withCore { core in
            _ = gbp_config_save(core)
        }
    }

    // MARK: Controls

    var isPaused: Bool {
        get { stateLock.withLock { _paused } }
        set { stateLock.withLock { _paused = newValue } }
    }

    func frameAdvance() {
        stateLock.withLock {
            _paused = true
            _frameStep = true
        }
    }

    var fastForwardToggle: Bool {
        get { stateLock.withLock { _fastForwardToggle } }
        set { stateLock.withLock { _fastForwardToggle = newValue } }
    }

    var fastForwardHeld: Bool {
        get { stateLock.withLock { _fastForwardHeld } }
        set { stateLock.withLock { _fastForwardHeld = newValue } }
    }

    var rewindHeld: Bool {
        get { stateLock.withLock { _rewindHeld } }
        set { stateLock.withLock { _rewindHeld = newValue } }
    }

    func setKeyboardKeys(_ keys: UInt32) { stateLock.withLock { _keyboardKeys = keys } }
    func setPadKeys(_ keys: UInt32) { stateLock.withLock { _padKeys = keys } }

    func setTilt(x: Float, y: Float) {
        withCore { gbp_set_tilt($0, x, y) }
    }

    // MARK: Core access

    @discardableResult
    func withCore<T>(_ body: (OpaquePointer) throws -> T) rethrows -> T {
        coreLock.lock()
        defer { coreLock.unlock() }
        return try body(core)
    }

    func config(_ key: String) -> String? {
        withCore { core in gbp_config_get(core, key).map { String(cString: $0) } }
    }

    func configBool(_ key: String) -> Bool { (config(key).flatMap { Int($0) } ?? 0) != 0 }
    func configInt(_ key: String) -> Int? { config(key).flatMap { Int($0) } }

    /// Sets a key in the user's config.ini, saves it and applies it to the running core.
    func setConfig(_ key: String, _ value: String?) {
        withCore { core in
            if let value { gbp_config_set(core, key, value) } else { gbp_config_unset(core, key) }
            _ = gbp_config_save(core)
            gbp_config_apply(core)
        }
        applyAudioSettings()
    }

    func setConfig(_ key: String, _ value: Bool) { setConfig(key, value ? "1" : "0") }

    func applyAudioSettings() {
        let volume = Float(configInt("volume") ?? 256) / 256
        audio.volume = configBool("mute") ? 0 : min(max(volume, 0), 1)
    }

    func reset() { withCore { gbp_reset($0) } }

    func saveState(slot: Int) -> Bool {
        try? FileManager.default.createDirectory(at: stateFolder, withIntermediateDirectories: true)
        return saveState(to: stateFile(slot: slot))
    }

    func loadState(slot: Int) -> Bool { loadState(from: stateFile(slot: slot)) }

    func saveState(to url: URL) -> Bool { withCore { gbp_state_save($0, url.path) } }
    func loadState(from url: URL) -> Bool { withCore { gbp_state_load($0, url.path) } }

    func exportSave(to url: URL) -> Bool { withCore { gbp_savedata_export($0, url.path) } }
    func importSave(from url: URL) -> Bool { withCore { gbp_savedata_import($0, url.path) } }

    /// Moves the battery save to another folder (`nil` = the default) and switches the core to it.
    func changeSaveFolder(to folder: URL?) throws {
        let old = saveFile
        let target = folder ?? defaultSaveFolder
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let new = target.appendingPathComponent(romBaseName + ".sav")
        guard new.standardizedFileURL != old.standardizedFileURL else { return }
        try withCore { core in
            let fm = FileManager.default
            if fm.fileExists(atPath: new.path) {
                // A save is already there: keep it and use it (the old one stays where it was).
            } else if fm.fileExists(atPath: old.path) {
                _ = gbp_savedata_export(core, new.path)
            }
            if let folder { gbp_config_set(core, "savegamePath", folder.path) } else { gbp_config_unset(core, "savegamePath") }
            _ = gbp_config_save(core)
            guard gbp_savedata_reload(core, new.path) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: new.path])
            }
        }
    }

    func takeScreenshot() -> URL? {
        guard let image = frames.currentImage() else { return nil }
        let folder = screenshotFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var index = 0
        var url: URL
        repeat {
            url = folder.appendingPathComponent("\(romBaseName)-\(index).png")
            index += 1
        } while FileManager.default.fileExists(atPath: url.path)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    func saveCheats() {
        withCore { core in
            // No file for a game without cheats; an existing file is rewritten (also when the last cheat was removed).
            guard gbp_cheats_count(core) > 0 || FileManager.default.fileExists(atPath: cheatsFile.path) else { return }
            _ = gbp_cheats_save(core, cheatsFile.path)
        }
    }

    // MARK: Emulation thread

    private func loop() {
        let stride = Int(gbp_video_stride(core))
        var audioScratch = [Int16](repeating: 0, count: 8192 * 2)
        var nextFrame = DispatchTime.now().uptimeNanoseconds
        var wasRewinding = false

        while true {
            let (isRunning, paused, step, ff, rewinding, keys) = stateLock.withLock { () -> (Bool, Bool, Bool, Bool, Bool, UInt32) in
                let step = _frameStep
                _frameStep = false
                return (running, _paused, step, _fastForwardToggle || _fastForwardHeld, _rewindHeld, _keyboardKeys | _padKeys)
            }
            if !isRunning { break }
            if paused && !step {
                usleep(5000)
                nextFrame = DispatchTime.now().uptimeNanoseconds
                continue
            }

            let ratio = Double(configInt("fastForwardRatio") ?? -1)
            let feedsAudio = !ff && !rewinding && !step
            // Pacing: on the audio queue when the core's sound is played, otherwise on the clock.
            if feedsAudio && audio.isRunning {
                while audio.bufferedFrames > audio.targetFrames {
                    usleep(500)
                    if !stateLock.withLock({ running }) { break }
                }
                nextFrame = DispatchTime.now().uptimeNanoseconds
            } else if !(ff && ratio <= 0) {
                let rate = ff ? frameRate * max(ratio, 1) : frameRate
                let now = DispatchTime.now().uptimeNanoseconds
                if nextFrame > now { usleep(UInt32((nextFrame - now) / 1000)) }
                nextFrame = max(nextFrame, now) + UInt64(1_000_000_000 / rate)
            }

            var width: UInt32 = 0
            var height: UInt32 = 0
            var pixels: [UInt32] = []
            coreLock.lock()
            if rewinding != wasRewinding {
                gbp_set_rewinding(core, rewinding)
                wasRewinding = rewinding
            }
            if rewinding { _ = gbp_rewind_step(core) }
            gbp_set_keys(core, keys)
            gbp_run_frame(core)
            audioScratch.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                while true {
                    let read = gbp_audio_read(core, base, 8192)
                    if read == 0 { break }
                    if feedsAudio { audio.push(base, frames: read) }
                }
            }
            gbp_video_size(core, &width, &height)
            let source = gbp_video_buffer(core)
            let rumble = gbp_rumble_level(core)
            let blend = configBool("interframeBlending")
            if let source {
                let w = Int(width)
                pixels = [UInt32](repeating: 0, count: w * Int(height))
                pixels.withUnsafeMutableBufferPointer { target in
                    guard let base = target.baseAddress else { return }
                    for y in 0..<Int(height) {
                        memcpy(base + y * w, source + y * stride, w * MemoryLayout<UInt32>.size)
                    }
                }
            }
            coreLock.unlock()

            if !feedsAudio { audio.clear() }
            if blend && previousFrame.count == pixels.count {
                let raw = pixels
                pixels.withUnsafeMutableBufferPointer { current in
                    previousFrame.withUnsafeBufferPointer { previous in
                        for i in 0..<current.count {
                            current[i] = ((current[i] & 0xFEFEFEFE) >> 1) &+ ((previous[i] & 0xFEFEFEFE) >> 1)
                        }
                    }
                }
                previousFrame = raw
            } else {
                previousFrame = pixels
            }
            frames.publish(pixels, width: Int(width), height: Int(height))
            onRumble?(rumble)
        }
    }
}
