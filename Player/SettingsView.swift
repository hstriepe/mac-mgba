import AppKit
import SwiftUI

/// The game's settings: mGBA's settings dialog, reduced to what applies to one embedded game.
/// Every value is an mGBA config key in the game's `config.ini`. Not here: BIOS (bundled), library, updater, logging.
final class SettingsModel: ObservableObject {
    let session: EmulatorSession
    weak var delegate: AppDelegate?
    @Published var capturing: String?
    @Published var message: String?

    init(session: EmulatorSession, delegate: AppDelegate) {
        self.session = session
        self.delegate = delegate
    }

    var isGB: Bool { session.platform == Int32(GBP_PLATFORM_GB.rawValue) }
    var hasLightSensor: Bool { session.hardware & UInt32(GBP_HW_LIGHT_SENSOR.rawValue) != 0 }

    func bool(_ key: String) -> Binding<Bool> {
        Binding(get: { self.session.configBool(key) }, set: { self.set(key, $0 ? "1" : "0") })
    }

    func inverted(_ key: String) -> Binding<Bool> {
        Binding(get: { !self.session.configBool(key) }, set: { self.set(key, $0 ? "0" : "1") })
    }

    func int(_ key: String, _ fallback: Int) -> Binding<Int> {
        Binding(get: { self.session.configInt(key) ?? fallback }, set: { self.set(key, String($0)) })
    }

    func double(_ key: String, _ fallback: Double) -> Binding<Double> {
        Binding(get: { Double(self.session.configInt(key) ?? Int(fallback)) }, set: { self.set(key, String(Int($0))) })
    }

    func string(_ key: String, _ fallback: String) -> Binding<String> {
        Binding(get: { self.session.config(key) ?? fallback }, set: { self.set(key, $0) })
    }

    func set(_ key: String, _ value: String?) {
        objectWillChange.send()
        session.setConfig(key, value)
        delegate?.applyVideoSettings()
    }

    // MARK: Folders

    func chooseFolder(_ key: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(key, url)
    }

    func setFolder(_ key: String, _ url: URL?) {
        objectWillChange.send()
        if key == "savegamePath" {
            do {
                try session.changeSaveFolder(to: url)
                message = "The save is now in \(session.saveFolder.path)."
            } catch {
                message = "The save folder could not be changed: \(error.localizedDescription)"
            }
        } else {
            session.setConfig(key, url?.path)
        }
    }

    // MARK: Game Boy

    static let models: [(String, String?)] = [
        ("Autodetect", nil), ("Game Boy (DMG)", "DMG"), ("Super Game Boy (SGB)", "SGB"),
        ("Game Boy Color (CGB)", "CGB"), ("Game Boy Advance (AGB)", "AGB"),
    ]
    private static let modelKeys = ["gb.model", "sgb.model", "cgb.model", "cgb.hybridModel", "cgb.sgbModel"]

    /// One model for this game: mGBA keeps one per cartridge type, so all of them are set alike.
    var model: Binding<String> {
        Binding(get: { self.session.config("gb.model") ?? "" }, set: { value in
            self.objectWillChange.send()
            for key in Self.modelKeys { self.session.setConfig(key, value.isEmpty ? nil : value) }
            self.message = "The model changes when the game is reset."
        })
    }

    var palettes: [String] {
        (0..<gbp_gb_palette_count()).compactMap { gbp_gb_palette_name($0).map { String(cString: $0) } }
    }

    var palette: Binding<Int> {
        Binding(get: { self.session.configInt("gb.palettePreset") ?? -1 }, set: { index in
            self.objectWillChange.send()
            guard index >= 0 else { return }
            self.session.withCore { gbp_gb_palette_apply($0, index) }
            self.session.setConfig("gb.palettePreset", String(index))
        })
    }

    var solarLevel: Binding<Double> {
        Binding(get: { Double(self.session.withCore { gbp_light_level($0) }) }, set: { value in
            self.objectWillChange.send()
            self.session.withCore { gbp_set_light_level($0, Int32(value)) }
            self.session.setConfig("solarLevel", String(Int(value)))
        })
    }

    // MARK: Controls

    func keyName(_ button: ConsoleButton) -> String {
        KeyNames.name(InputController.keyCode(for: button, in: session))
    }

    func keyName(_ hotkey: HeldHotkey) -> String {
        KeyNames.name(InputController.keyCode(for: hotkey, in: session))
    }

    func capture(configKey: String) {
        capturing = configKey
        guard let input = delegate?.inputController else { return }
        // Keys go to the game window, so bring it forward while waiting for the key.
        NSApp.windows.first { $0.contentView is GameView }?.makeKeyAndOrderFront(nil)
        input.captureNextKey = { [weak self] code in
            guard let self else { return }
            self.capturing = nil
            if code != 53 { self.set(configKey, String(code)) }   // Esc cancels
            input.reloadBindings()
        }
    }

    func resetControls() {
        for button in ConsoleButton.allCases { session.setConfig(button.configKey, nil) }
        for hotkey in HeldHotkey.allCases { session.setConfig(hotkey.configKey, nil) }
        objectWillChange.send()
        delegate?.inputController?.reloadBindings()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "folder") }
            video.tabItem { Label("Audio/Video", systemImage: "display") }
            emulation.tabItem { Label("Emulation", systemImage: "cpu") }
            if model.isGB {
                gameBoy.tabItem { Label("Game Boy", systemImage: "gamecontroller") }
            } else {
                gba.tabItem { Label("Game Boy Advance", systemImage: "gamecontroller") }
            }
            controls.tabItem { Label("Controls", systemImage: "keyboard") }
        }
        .frame(width: 560, height: 430)
        .padding()
    }

    private var general: some View {
        Form {
            Section("Folders") {
                folderRow("Battery saves", key: "savegamePath", current: model.session.saveFolder)
                folderRow("Save states", key: "savestatePath", current: model.session.stateFolder)
                folderRow("Screenshots", key: "screenshotPath", current: model.session.screenshotFolder)
            }
            Section {
                Toggle("Pause when the app is in the background", isOn: model.bool("pauseOnFocusLost"))
                Toggle("Keep the display awake while playing", isOn: model.bool(GameWindowController.preventDisplaySleepKey))
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func folderRow(_ title: String, key: String, current: URL) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(current.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack {
                    Button("Choose…") { model.chooseFolder(key) }
                    Button("Default") { model.setFolder(key, nil) }.disabled(model.session.config(key) == nil)
                    Button("Show") {
                        try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(current)
                    }
                }
            }
        }
    }

    private var video: some View {
        Form {
            Section("Audio") {
                LabeledContent("Volume") {
                    Slider(value: model.double("volume", 256), in: 0...256)
                }
                Toggle("Mute", isOn: model.bool("mute"))
            }
            Section("Video") {
                Toggle("Lock aspect ratio", isOn: model.bool("lockAspectRatio"))
                Toggle("Borderless window (floats above other windows)", isOn: model.bool(GameWindowController.borderlessKey))
                Toggle("Force integer scaling", isOn: model.bool("lockIntegerScaling"))
                Toggle("Interframe blending", isOn: model.bool("interframeBlending"))
                Toggle("Bilinear filtering", isOn: model.bool("resampleVideo"))
                Stepper("Frame skip: \(model.int("frameskip", 0).wrappedValue)", value: model.int("frameskip", 0), in: 0...10)
            }
        }
        .formStyle(.grouped)
    }

    private var emulation: some View {
        Form {
            Section {
                Toggle("Show the BIOS boot animation", isOn: model.inverted("skipBios"))
                Picker("Fast-forward speed", selection: model.int("fastForwardRatio", -1)) {
                    Text("Unbounded").tag(-1)
                    ForEach([2, 3, 4, 6, 8], id: \.self) { Text("\($0)×").tag($0) }
                }
                Picker("Idle loops", selection: model.string("idleOptimization", "detect")) {
                    Text("Run all").tag("ignore")
                    Text("Remove known").tag("remove")
                    Text("Detect and remove").tag("detect")
                }
                Toggle("Allow opposing directions (left and right at once)", isOn: model.bool("allowOpposingDirections"))
            }
            Section("Rewind") {
                Toggle("Enable rewind", isOn: model.bool("rewindEnable"))
                Stepper("Keep \(model.int("rewindBufferCapacity", 600).wrappedValue) states",
                        value: model.int("rewindBufferCapacity", 600), in: 60...6000, step: 60)
                Stepper("Every \(model.int("rewindBufferInterval", 1).wrappedValue) frame(s)",
                        value: model.int("rewindBufferInterval", 1), in: 1...30)
            }
        }
        .formStyle(.grouped)
    }

    private var gameBoy: some View {
        Form {
            Section {
                Picker("Model", selection: model.model) {
                    ForEach(SettingsModel.models, id: \.0) { Text($0.0).tag($0.1 ?? "") }
                }
                Toggle("Super Game Boy borders", isOn: model.bool("sgb.borders"))
                Picker("Colorization of Game Boy games", selection: model.int("gb.colors", 0)) {
                    Text("None").tag(0)
                    Text("Game Boy Color palettes").tag(1)
                    Text("Super Game Boy palettes").tag(2)
                    Text("Super Game Boy, else Game Boy Color").tag(3)
                }
                Picker("Palette", selection: model.palette) {
                    Text("Custom or default").tag(-1)
                    ForEach(Array(model.palettes.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                }
            }
            if let message = model.message {
                HStack {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Now") { model.session.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var gba: some View {
        Form {
            Section {
                Toggle("Game Boy Player features (rumble in supported games)", isOn: model.bool("gba.forceGbp"))
            }
            if model.hasLightSensor {
                Section("Solar sensor") {
                    LabeledContent("Sunlight") { Slider(value: model.solarLevel, in: 0...10, step: 1) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var controls: some View {
        Form {
            Section("Keyboard") {
                ForEach(ConsoleButton.buttons(gba: !model.isGB)) { button in
                    keyRow(button.rawValue, name: model.keyName(button), configKey: button.configKey)
                }
                ForEach(HeldHotkey.allCases) { hotkey in
                    keyRow(hotkey.rawValue, name: model.keyName(hotkey), configKey: hotkey.configKey)
                }
                Button("Restore Defaults") { model.resetControls() }
            }
            Section("Game controllers") {
                Text("Buttons by position as on the console: right face button A, bottom B; shoulders L and R; Menu Start, Options Select; d-pad or left stick. Right trigger fast-forwards, left trigger rewinds.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func keyRow(_ title: String, name: String, configKey: String) -> some View {
        LabeledContent(title) {
            Button(model.capturing == configKey ? "Press a key…" : name) { model.capture(configKey: configKey) }
                .frame(minWidth: 120)
        }
    }
}

enum KeyNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab",
        49: "Space", 50: "`", 51: "Delete", 53: "Esc", 76: "Enter", 117: "Forward Delete", 123: "←", 124: "→",
        125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]

    static func name(_ code: UInt16) -> String { names[code] ?? "Key \(code)" }
}
