import AppKit
import CoreHaptics
import GameController

/// The ten console buttons, in mGBA's bit order.
enum ConsoleButton: String, CaseIterable, Identifiable {
    case a = "A", b = "B", select = "Select", start = "Start", right = "Right", left = "Left", up = "Up", down = "Down", r = "R", l = "L"

    var id: String { rawValue }
    var bit: UInt32 {
        switch self {
        case .a: return UInt32(GBP_KEY_A.rawValue)
        case .b: return UInt32(GBP_KEY_B.rawValue)
        case .select: return UInt32(GBP_KEY_SELECT.rawValue)
        case .start: return UInt32(GBP_KEY_START.rawValue)
        case .right: return UInt32(GBP_KEY_RIGHT.rawValue)
        case .left: return UInt32(GBP_KEY_LEFT.rawValue)
        case .up: return UInt32(GBP_KEY_UP.rawValue)
        case .down: return UInt32(GBP_KEY_DOWN.rawValue)
        case .r: return UInt32(GBP_KEY_R.rawValue)
        case .l: return UInt32(GBP_KEY_L.rawValue)
        }
    }

    /// GB and GBC have no shoulder buttons.
    static func buttons(gba: Bool) -> [ConsoleButton] {
        gba ? allCases : allCases.filter { $0 != .l && $0 != .r }
    }

    /// mGBA Qt's default keyboard layout.
    var defaultKeyCode: UInt16 {
        switch self {
        case .a: return 7          // X
        case .b: return 6          // Z
        case .l: return 0          // A
        case .r: return 1          // S
        case .start: return 36     // Return
        case .select: return 51    // Delete
        case .right: return 124
        case .left: return 123
        case .up: return 126
        case .down: return 125
        }
    }

    var configKey: String { "keyboard.\(rawValue)" }
}

/// Hotkeys that are held rather than chosen from a menu.
enum HeldHotkey: String, CaseIterable, Identifiable {
    case fastForward = "Fast forward (hold)"
    case rewind = "Rewind (hold)"

    var id: String { rawValue }
    var defaultKeyCode: UInt16 { self == .fastForward ? 48 : 50 }   // Tab, `
    var configKey: String { self == .fastForward ? "keyboard.fastForward" : "keyboard.rewind" }
}

/// Keyboard and game controllers → console buttons; controller rumble.
final class InputController {
    private weak var session: EmulatorSession?
    private var keyboardBits: UInt32 = 0
    private var bindings: [UInt16: ConsoleButton] = [:]
    private var fastForwardKey: UInt16 = 48
    private var rewindKey: UInt16 = 50
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var rumbling = false

    /// While set, the next key press is reported here instead of played (used by the Controls settings).
    var captureNextKey: ((UInt16) -> Void)?

    init(session: EmulatorSession) {
        self.session = session
        reloadBindings()
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            if let controller = note.object as? GCController { self?.attach(controller) }
        }
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.session?.setPadKeys(0)
            self?.setupHaptics()
        }
        GCController.shouldMonitorBackgroundEvents = false
        GCController.controllers().forEach(attach)
        session.onRumble = { [weak self] level in
            DispatchQueue.main.async { self?.rumble(level) }
        }
    }

    static func keyCode(for button: ConsoleButton, in session: EmulatorSession) -> UInt16 {
        session.configInt(button.configKey).map { UInt16($0) } ?? button.defaultKeyCode
    }

    static func keyCode(for hotkey: HeldHotkey, in session: EmulatorSession) -> UInt16 {
        session.configInt(hotkey.configKey).map { UInt16($0) } ?? hotkey.defaultKeyCode
    }

    func reloadBindings() {
        guard let session else { return }
        bindings = [:]
        for button in ConsoleButton.allCases {
            bindings[Self.keyCode(for: button, in: session)] = button
        }
        fastForwardKey = Self.keyCode(for: .fastForward, in: session)
        rewindKey = Self.keyCode(for: .rewind, in: session)
    }

    // MARK: Keyboard

    func keyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        if let capture = captureNextKey {
            captureNextKey = nil
            capture(event.keyCode)
            return true
        }
        if event.isARepeat { return true }
        return setKey(event.keyCode, pressed: true)
    }

    func keyUp(_ event: NSEvent) -> Bool {
        setKey(event.keyCode, pressed: false)
    }

    func flagsChanged(_ event: NSEvent) {}

    /// Releases everything (window lost focus).
    func releaseAll() {
        keyboardBits = 0
        session?.setKeyboardKeys(0)
        session?.fastForwardHeld = false
        session?.rewindHeld = false
    }

    private func setKey(_ code: UInt16, pressed: Bool) -> Bool {
        guard let session else { return false }
        if code == fastForwardKey {
            session.fastForwardHeld = pressed
            return true
        }
        if code == rewindKey {
            session.rewindHeld = pressed
            return true
        }
        guard let button = bindings[code] else { return false }
        if pressed { keyboardBits |= button.bit } else { keyboardBits &= ~button.bit }
        session.setKeyboardKeys(keyboardBits)
        return true
    }

    // MARK: Game controllers

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self] pad, _ in self?.read(pad) }
        setupHaptics()
    }

    /// Buttons by position, as on the console: right face button = A, bottom = B.
    private func read(_ pad: GCExtendedGamepad) {
        guard let session else { return }
        var bits: UInt32 = 0
        func on(_ pressed: Bool, _ button: ConsoleButton) { if pressed { bits |= button.bit } }
        on(pad.buttonB.isPressed, .a)
        on(pad.buttonA.isPressed, .b)
        on(pad.buttonY.isPressed, .a)
        on(pad.buttonX.isPressed, .b)
        on(pad.leftShoulder.isPressed, .l)
        on(pad.rightShoulder.isPressed, .r)
        on(pad.buttonMenu.isPressed, .start)
        on(pad.buttonOptions?.isPressed ?? false, .select)
        let stick = pad.leftThumbstick
        on(pad.dpad.right.isPressed || stick.xAxis.value > 0.5, .right)
        on(pad.dpad.left.isPressed || stick.xAxis.value < -0.5, .left)
        on(pad.dpad.up.isPressed || stick.yAxis.value > 0.5, .up)
        on(pad.dpad.down.isPressed || stick.yAxis.value < -0.5, .down)
        session.setPadKeys(bits)
        session.fastForwardHeld = pad.rightTrigger.isPressed
        session.rewindHeld = pad.leftTrigger.isPressed
        if session.hardware & UInt32(GBP_HW_TILT.rawValue | GBP_HW_GYRO.rawValue) != 0 {
            session.setTilt(x: pad.rightThumbstick.xAxis.value, y: -pad.rightThumbstick.yAxis.value)
        }
    }

    // MARK: Rumble

    private func setupHaptics() {
        hapticPlayer = nil
        hapticEngine?.stop()
        hapticEngine = nil
        guard let hardware = session?.hardware, hardware & UInt32(GBP_HW_RUMBLE.rawValue) != 0,
              let haptics = GCController.controllers().first(where: { $0.haptics != nil })?.haptics,
              let engine = haptics.createEngine(withLocality: .default)
        else { return }
        do {
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            ], relativeTime: 0, duration: 100)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            hapticPlayer = try engine.makeAdvancedPlayer(with: pattern)
            hapticEngine = engine
        } catch {
            hapticEngine = nil
        }
    }

    private func rumble(_ level: Float) {
        guard let player = hapticPlayer else { return }
        let on = level > 0.05
        do {
            if on {
                let intensity = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: level, relativeTime: 0)
                if !rumbling { try player.start(atTime: CHHapticTimeImmediate) }
                try player.sendParameters([intensity], atTime: CHHapticTimeImmediate)
            } else if rumbling {
                try player.stop(atTime: CHHapticTimeImmediate)
            }
            rumbling = on
        } catch {
            rumbling = false
        }
    }
}
