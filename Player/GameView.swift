import AppKit
import QuartzCore

/// Shows the emulator's frames, keeps the picture's aspect ratio or integer scale, and passes keys to the input controller.
final class GameView: NSView {
    weak var session: EmulatorSession?
    var input: InputController?
    private let screen = CALayer()
    private var lastSequence = -1
    private var displayLink: CADisplayLink?
    private var frameSize = CGSize(width: 240, height: 160)

    var lockAspectRatio = true { didSet { needsLayout = true } }
    var integerScaling = false { didSet { needsLayout = true } }
    var bilinear = false {
        didSet { screen.magnificationFilter = bilinear ? .linear : .nearest }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        screen.magnificationFilter = .nearest
        screen.minificationFilter = .linear
        screen.contentsGravity = .resize
        screen.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(screen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplay() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let session, let image = session.frames.image(after: &lastSequence) else { return }
        let size = CGSize(width: image.width, height: image.height)
        if size != frameSize {
            frameSize = size
            needsLayout = true
        }
        screen.contents = image
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        var rect = bounds
        if lockAspectRatio || integerScaling {
            var scale = min(bounds.width / frameSize.width, bounds.height / frameSize.height)
            if integerScaling { scale = max(1, floor(scale)) }
            let size = CGSize(width: frameSize.width * scale, height: frameSize.height * scale)
            rect = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                          width: size.width, height: size.height)
        }
        screen.frame = rect.integral
        screen.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Native picture size (240×160 for GBA, 160×144 for GB, 256×224 with Super Game Boy borders).
    var nativeSize: CGSize { frameSize }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if input?.keyDown(event) != true { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if input?.keyUp(event) != true { super.keyUp(with: event) }
    }

    override func flagsChanged(with event: NSEvent) {
        input?.flagsChanged(event)
    }
}
